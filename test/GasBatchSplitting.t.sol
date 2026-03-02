// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {GnosisSafe} from "../src/internal/sender/GnosisSafeSender.sol";
import {SenderTypes, Transaction, SimulatedTransaction} from "../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";
import {ITrebEvents} from "../src/internal/ITrebEvents.sol";
import {Safe} from "safe-smart-account/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/proxies/SafeProxyFactory.sol";

contract MockGasTarget {
    uint256 public storedValue;

    function setValue(uint256 _value) external returns (uint256) {
        storedValue = _value;
        return _value;
    }
}

contract GasBatchSplittingTest is Test {
    MockGasTarget target;
    SendersTestHarness harness;
    Safe safeThreshold1;

    string constant PROPOSER = "proposer";
    string constant SAFE_T1 = "safe-t1";
    bytes32 constant salt = keccak256(abi.encode("gas-batch-salt"));

    function setUp() public {
        target = new MockGasTarget{salt: salt}();

        // Deploy Safe with threshold 1
        Safe safeMasterCopy = new Safe{salt: salt}();
        SafeProxyFactory factory = new SafeProxyFactory{salt: salt}();

        address[] memory owners = new address[](1);
        owners[0] = vm.addr(0x54321);

        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, payable(0)
        );

        safeThreshold1 = Safe(payable(factory.createProxyWithNonce(address(safeMasterCopy), initializer, 1)));

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);

        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: vm.addr(0x54321),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x54321)
        });

        configs[1] = Senders.SenderInitConfig({
            name: SAFE_T1,
            account: address(safeThreshold1),
            senderType: SenderTypes.GnosisSafe,
            canBroadcast: true,
            config: abi.encode(PROPOSER)
        });

        harness = new SendersTestHarness(configs);
        vm.makePersistent(address(harness));
        vm.makePersistent(address(target));

        vm.deal(vm.addr(0x54321), 10 ether);
        vm.selectFork(harness.getExecutionFork());
        vm.deal(vm.addr(0x54321), 10 ether);
        vm.selectFork(harness.getSimulationFork());
    }

    // ---- Helper to create SimulatedTransactions with controlled gasUsed ----

    function _makeSimTx(uint256 gasUsed, uint256 txId) internal view returns (SimulatedTransaction memory) {
        return SimulatedTransaction({
            transactionId: bytes32(txId),
            senderId: keccak256(abi.encodePacked(SAFE_T1)),
            sender: address(safeThreshold1),
            returnData: "",
            transaction: Transaction({
                to: address(target), data: abi.encodeWithSelector(MockGasTarget.setValue.selector, txId), value: 0
            }),
            gasUsed: gasUsed
        });
    }

    // ---- Phase 1: Gas metering tests ----

    function test_gasUsedIsRecorded() public {
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockGasTarget.setValue.selector, 42), value: 0
        });

        SimulatedTransaction memory simTx = harness.execute(SAFE_T1, txn);
        assertGt(simTx.gasUsed, 0, "gasUsed should be > 0");
    }

    function test_gasUsedRecordedForBatch() public {
        Transaction[] memory txns = new Transaction[](3);
        for (uint256 i = 0; i < 3; i++) {
            txns[i] = Transaction({
                to: address(target), data: abi.encodeWithSelector(MockGasTarget.setValue.selector, i + 1), value: 0
            });
        }

        SimulatedTransaction[] memory simTxs = harness.execute(SAFE_T1, txns);

        for (uint256 i = 0; i < simTxs.length; i++) {
            assertGt(simTxs[i].gasUsed, 0, "Each tx should have gasUsed > 0");
        }
    }

    // ---- Phase 2: Batch splitting tests using manual SimulatedTransactions ----

    function test_singleBatch_allUnderThreshold() public {
        // 3 small txs well under the gas threshold → single batch
        for (uint256 i = 0; i < 3; i++) {
            harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(100_000, i + 1));
        }

        // Expect exactly 1 SafeTransactionExecuted event
        vm.expectEmit(false, true, true, false);
        emit ITrebEvents.SafeTransactionExecuted(
            bytes32(0), address(safeThreshold1), vm.addr(0x54321), new bytes32[](3)
        );

        harness.broadcastSafeSender(SAFE_T1);
        assertEq(target.storedValue(), 3);
    }

    function test_multiBatch_splitsByGasThreshold() public {
        // block.gaslimit is typically 30M on the fork
        // threshold = 30M * 50 / 100 = 15M
        // BATCH_OVERHEAD = 100k
        //
        // 6 txs with 5M gasUsed each:
        //   Batch 1: overhead(100k) + tx1(5M) = 5.1M, + tx2(5M) = 10.1M, + tx3(5M) = 15.1M > 15M → split
        //   Batch 1 = [tx1, tx2] (10.1M)
        //   Batch 2: overhead(100k) + tx3(5M) = 5.1M, + tx4(5M) = 10.1M, + tx5(5M) = 15.1M > 15M → split
        //   Batch 2 = [tx3, tx4] (10.1M)
        //   Batch 3: overhead(100k) + tx5(5M) = 5.1M, + tx6(5M) = 10.1M
        //   Batch 3 = [tx5, tx6] (10.1M)
        //
        // Expect 3 SafeTransactionExecuted events

        for (uint256 i = 0; i < 6; i++) {
            harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(5_000_000, i + 1));
        }

        // Record logs to count events
        vm.recordLogs();
        harness.broadcastSafeSender(SAFE_T1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 executedSig = ITrebEvents.SafeTransactionExecuted.selector;

        uint256 batchCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == executedSig) {
                batchCount++;
            }
        }

        assertEq(batchCount, 3, "Should produce exactly 3 batches");
        // Last tx sets value to 6
        assertEq(target.storedValue(), 6);
    }

    function test_singleLargeTx_exceedsThreshold_stillExecutes() public {
        // A single tx with gasUsed > threshold should still go through as its own batch
        // threshold is ~15M, use 20M for the single tx
        harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(20_000_000, 42));

        vm.expectEmit(false, true, true, false);
        emit ITrebEvents.SafeTransactionExecuted(
            bytes32(0), address(safeThreshold1), vm.addr(0x54321), new bytes32[](1)
        );

        harness.broadcastSafeSender(SAFE_T1);
        assertEq(target.storedValue(), 42);
    }

    function test_mixedGas_correctBatchBoundaries() public {
        // threshold = 15M, overhead = 100k
        // tx1: 7M  → batch gas: 100k + 7M = 7.1M
        // tx2: 7M  → batch gas: 7.1M + 7M = 14.1M (under 15M)
        // tx3: 2M  → batch gas: 14.1M + 2M = 16.1M > 15M → split before tx3
        //   Batch 1 = [tx1, tx2]
        // tx3: 2M  → new batch: 100k + 2M = 2.1M
        // tx4: 2M  → batch gas: 2.1M + 2M = 4.1M
        // tx5: 2M  → batch gas: 4.1M + 2M = 6.1M
        //   Batch 2 = [tx3, tx4, tx5]
        // Expect 2 batches

        harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(7_000_000, 1));
        harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(7_000_000, 2));
        harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(2_000_000, 3));
        harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(2_000_000, 4));
        harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(2_000_000, 5));

        vm.recordLogs();
        harness.broadcastSafeSender(SAFE_T1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 executedSig = ITrebEvents.SafeTransactionExecuted.selector;

        uint256 batchCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == executedSig) {
                batchCount++;
            }
        }

        assertEq(batchCount, 2, "Should produce exactly 2 batches");
        assertEq(target.storedValue(), 5);
    }

    function test_emptyQueueDoesNotRevert() public {
        harness.broadcastSafeSender(SAFE_T1);
    }

    function test_zeroGasUsed_allInOneBatch() public {
        // If gasUsed is 0 for all txs (e.g., not metered), they should all fit in one batch
        for (uint256 i = 0; i < 10; i++) {
            harness.queueSimulatedTransaction(SAFE_T1, _makeSimTx(0, i + 1));
        }

        vm.recordLogs();
        harness.broadcastSafeSender(SAFE_T1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 executedSig = ITrebEvents.SafeTransactionExecuted.selector;

        uint256 batchCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == executedSig) {
                batchCount++;
            }
        }

        assertEq(batchCount, 1, "Zero-gas txs should all fit in one batch");
    }

    // ---- End-to-end test via normal execute flow ----

    function test_endToEnd_normalFlow() public {
        // Execute through normal flow — gasUsed will be small, all fit in one batch
        Transaction[] memory txns = new Transaction[](5);
        for (uint256 i = 0; i < 5; i++) {
            txns[i] = Transaction({
                to: address(target), data: abi.encodeWithSelector(MockGasTarget.setValue.selector, i + 1), value: 0
            });
        }

        SimulatedTransaction[] memory simTxs = harness.execute(SAFE_T1, txns);

        // Verify gas was recorded
        uint256 totalGas = 0;
        for (uint256 i = 0; i < simTxs.length; i++) {
            assertGt(simTxs[i].gasUsed, 0);
            totalGas += simTxs[i].gasUsed;
        }
        assertLt(totalGas, block.gaslimit * 50 / 100, "Total gas under threshold for single batch");

        // Broadcast via normal flow
        vm.expectEmit(false, true, true, false);
        emit ITrebEvents.SafeTransactionExecuted(
            bytes32(0), address(safeThreshold1), vm.addr(0x54321), new bytes32[](5)
        );

        harness.broadcastAll();
        assertEq(target.storedValue(), 5);
    }
}
