// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {PrivateKey, HardwareWallet, InMemory} from "../src/internal/sender/PrivateKeySender.sol";
import {GnosisSafe} from "../src/internal/sender/GnosisSafeSender.sol";
import {SenderTypes, Transaction, SimulatedTransaction} from "../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";
import {SenderCoordinator} from "../src/internal/SenderCoordinator.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {ITrebEvents} from "../src/internal/ITrebEvents.sol";

contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) external returns (uint256) {
        value = _value;
        return _value;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    receive() external payable {}
}

contract SenderIntegrationTest is Test {
    MockTarget target;
    SendersTestHarness harness;

    // Safe contracts for testing
    Safe safeThreshold1;
    Safe safeThresholdMulti;

    // Constants for sender names
    string constant TEST_SENDER = "test-sender";
    string constant BATCH_SENDER = "batch-sender";
    string constant SAFE_SENDER = "safe-sender";
    string constant PROPOSER = "proposer";
    string constant LEDGER_SENDER = "ledger-sender";
    string constant FAIL_SENDER = "fail-sender";
    string constant CUSTOM_SENDER = "custom-sender";
    string constant MEMORY_1 = "memory-1";
    string constant LEDGER_1 = "ledger-1";
    string constant SAFE_1 = "safe-1";
    string constant SAFE_THRESHOLD_1 = "safe-threshold-1";
    string constant SAFE_THRESHOLD_MULTI = "safe-threshold-multi";
    bytes32 constant salt = keccak256(abi.encode("salt"));

    function setUp() public {
        target = new MockTarget{salt: salt}();

        // Deploy Safe contracts
        Safe safeMasterCopy = new Safe{salt: salt}();
        SafeProxyFactory factory = new SafeProxyFactory{salt: salt}();

        // Deploy Safe with threshold 1
        address[] memory owners1 = new address[](1);
        owners1[0] = vm.addr(0x54321); // proposer address

        bytes memory initializer1 = abi.encodeWithSelector(
            Safe.setup.selector,
            owners1,
            1, // threshold = 1
            address(0), // to
            "", // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            payable(0) // paymentReceiver
        );

        safeThreshold1 = Safe(payable(factory.createProxyWithNonce(address(safeMasterCopy), initializer1, 1)));

        // Deploy Safe with threshold 2
        address[] memory owners2 = new address[](2);
        owners2[0] = vm.addr(0x54321); // proposer address
        owners2[1] = vm.addr(0x67890); // second owner

        bytes memory initializer2 = abi.encodeWithSelector(
            Safe.setup.selector,
            owners2,
            2, // threshold = 2
            address(0), // to
            "", // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            payable(0) // paymentReceiver
        );

        safeThresholdMulti = Safe(payable(factory.createProxyWithNonce(address(safeMasterCopy), initializer2, 2)));

        // Initialize all senders that will be used across tests
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](10);

        // Test sender (InMemory)
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x12345)
        });

        // Batch sender (InMemory)
        configs[1] = Senders.SenderInitConfig({
            name: BATCH_SENDER,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x12345)
        });

        // Proposer for Safe (InMemory)
        configs[2] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: vm.addr(0x54321),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x54321)
        });

        // Safe sender
        configs[3] = Senders.SenderInitConfig({
            name: SAFE_SENDER,
            account: makeAddr("safe"),
            senderType: SenderTypes.GnosisSafe,
            canBroadcast: true,
            config: abi.encode(PROPOSER)
        });

        // Ledger sender
        configs[4] = Senders.SenderInitConfig({
            name: LEDGER_SENDER,
            account: makeAddr("ledger"),
            senderType: SenderTypes.Ledger,
            canBroadcast: false,
            config: abi.encode("m/44'/60'/0'/0/0")
        });

        // Fail sender (InMemory)
        configs[5] = Senders.SenderInitConfig({
            name: FAIL_SENDER,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x12345)
        });

        // Custom sender
        configs[6] = Senders.SenderInitConfig({
            name: CUSTOM_SENDER,
            account: makeAddr("custom"),
            senderType: SenderTypes.Custom,
            canBroadcast: true,
            config: ""
        });

        // Safe_1 sender
        configs[7] = Senders.SenderInitConfig({
            name: SAFE_1,
            account: makeAddr("safe1"),
            senderType: SenderTypes.GnosisSafe,
            canBroadcast: true,
            config: abi.encode(PROPOSER)
        });

        // Safe with threshold 1
        configs[8] = Senders.SenderInitConfig({
            name: SAFE_THRESHOLD_1,
            account: address(safeThreshold1),
            senderType: SenderTypes.GnosisSafe,
            canBroadcast: true,
            config: abi.encode(PROPOSER)
        });

        // Safe with threshold multi
        configs[9] = Senders.SenderInitConfig({
            name: SAFE_THRESHOLD_MULTI,
            account: address(safeThresholdMulti),
            senderType: SenderTypes.GnosisSafe,
            canBroadcast: true,
            config: abi.encode(PROPOSER)
        });

        harness = new SendersTestHarness(configs);
        vm.makePersistent(address(harness));

        vm.deal(vm.addr(0x12345), 10 ether);
        vm.deal(vm.addr(0x54321), 10 ether);
        vm.selectFork(harness.getExecutionFork());
        vm.deal(vm.addr(0x12345), 10 ether);
        vm.deal(vm.addr(0x54321), 10 ether);
        vm.selectFork(harness.getSimulationFork());
    }

    function test_InMemorySenderFullFlow() public {
        // Create transaction
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 42), value: 0
        });

        // Execute transaction (simulation)
        SimulatedTransaction memory simulatedTxn = harness.execute(TEST_SENDER, txn);

        assertEq(target.getValue(), 42);

        // Verify simulation result
        assertEq(abi.decode(simulatedTxn.returnData, (uint256)), 42);
        // Label field removed from Transaction struct

        // Broadcast transaction
        harness.broadcastAll();

        // Verify execution
        assertEq(target.getValue(), 42);
    }

    function test_MultipleTransactionsBatch() public {
        // Create multiple transactions
        Transaction[] memory txns = new Transaction[](3);
        txns[0] = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 10), value: 0
        });
        txns[1] = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 20), value: 0
        });
        txns[2] = Transaction({to: address(target), data: "", value: 1 ether});

        // Execute batch
        SimulatedTransaction[] memory results = harness.execute(BATCH_SENDER, txns);

        // Verify batch simulation
        assertEq(results.length, 3);
        assertEq(abi.decode(results[0].returnData, (uint256)), 10);
        assertEq(abi.decode(results[1].returnData, (uint256)), 20);

        // Broadcast
        harness.broadcastAll();

        // Verify final state
        assertEq(target.getValue(), 20);
        assertEq(address(target).balance, 1 ether);
    }

    function test_GnosisSafeSenderFlow_Threshold1() public {
        // Create transaction
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 100), value: 0
        });

        // Execute (queue for Safe)
        harness.execute(SAFE_THRESHOLD_1, txn);

        // For threshold 1, should execute directly
        vm.expectEmit(false, true, true, false);
        emit ITrebEvents.SafeTransactionExecuted(
            bytes32(0), // We don't know the exact hash
            address(safeThreshold1),
            vm.addr(0x54321),
            new bytes32[](1)
        );

        harness.broadcastAll();

        // Verify the transaction was executed
        assertEq(target.getValue(), 100);
    }

    function test_GnosisSafeSenderFlow_ThresholdMulti() public {
        // Create transaction
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 200), value: 0
        });

        // Execute (queue for Safe)
        harness.execute(SAFE_THRESHOLD_MULTI, txn);

        // For threshold > 1, should try to propose via API and fail
        vm.expectRevert(abi.encodeWithSignature("ProposeTransactionFailed(uint256,string)", 0, ""));
        harness.broadcastAll();

        // Verify the transaction was NOT executed
        assertEq(target.getValue(), 0);
    }

    function test_HardwareWalletSenderInitialization() public view {
        // Verify hardware wallet was properly initialized
        HardwareWallet.Sender memory hwSender = harness.getHardwareWallet(LEDGER_SENDER);
        assertEq(hwSender.hardwareWalletType, "ledger");
        assertEq(hwSender.mnemonicDerivationPath, "m/44'/60'/0'/0/0");
    }

    function test_TransactionSimulationFailure() public {
        // Create transaction that will fail (calling non-existent function)
        Transaction memory txn =
            Transaction({to: address(target), data: abi.encodeWithSelector(bytes4(0xdeadbeef)), value: 0});

        // Expect TransactionSimulated and TransactionFailed events
        // Note: We can't predict the transaction ID here, so we'll skip event verification
        // The important part is that the execute fails

        // Execute should revert with the actual error (function does not exist)
        vm.expectRevert();
        harness.execute(FAIL_SENDER, txn);
    }

    function test_CustomSenderType() public {
        // Create transaction
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 42), value: 0
        });

        // queue transaction
        harness.execute(CUSTOM_SENDER, txn);

        // But broadcast should fail
        vm.expectRevert(abi.encodeWithSelector(SenderCoordinator.CustomQueueReceiverNotImplemented.selector));
        harness.broadcastAll();
    }
}
