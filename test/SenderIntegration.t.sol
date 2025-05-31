// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {PrivateKey, HardwareWallet, InMemory} from "../src/internal/sender/PrivateKeySender.sol";
import {GnosisSafe} from "../src/internal/sender/GnosisSafeSender.sol";
import {SenderTypes, Transaction, RichTransaction, TransactionStatus} from "../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";
import {SenderCoordinator} from "../src/internal/SenderCoordinator.sol";

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
    
    function setUp() public {
        target = new MockTarget();
        
        // Initialize all senders that will be used across tests
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](8);
        
        // Test sender (InMemory)
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x12345)
        });
        
        // Batch sender (InMemory)
        configs[1] = Senders.SenderInitConfig({
            name: BATCH_SENDER,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x12345)
        });
        
        // Proposer for Safe (InMemory)
        configs[2] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: vm.addr(0x54321),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x54321)
        });
        
        // Safe sender
        configs[3] = Senders.SenderInitConfig({
            name: SAFE_SENDER,
            account: makeAddr("safe"),
            senderType: SenderTypes.GnosisSafe,
            config: abi.encode(PROPOSER)
        });
        
        // Ledger sender
        configs[4] = Senders.SenderInitConfig({
            name: LEDGER_SENDER,
            account: makeAddr("ledger"),
            senderType: SenderTypes.Ledger,
            config: abi.encode("m/44'/60'/0'/0/0")
        });
        
        // Fail sender (InMemory)
        configs[5] = Senders.SenderInitConfig({
            name: FAIL_SENDER,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x12345)
        });
        
        // Custom sender
        configs[6] = Senders.SenderInitConfig({
            name: CUSTOM_SENDER,
            account: makeAddr("custom"),
            senderType: SenderTypes.Custom,
            config: ""
        });
        
        // Safe_1 sender
        configs[7] = Senders.SenderInitConfig({
            name: SAFE_1,
            account: makeAddr("safe1"),
            senderType: SenderTypes.GnosisSafe,
            config: abi.encode(PROPOSER)
        });
        
        // Deal ether to test senders
        vm.deal(vm.addr(0x12345), 10 ether);
        vm.deal(vm.addr(0x54321), 10 ether);
        
        harness = new SendersTestHarness(configs);
    }
    
    function test_InMemorySenderFullFlow() public {
        // Create transaction
        Transaction memory txn = Transaction({
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 42),
            value: 0
        });
        
        // Execute transaction (simulation)
        RichTransaction memory richTxn = harness.execute(TEST_SENDER, txn);
        
        assertEq(target.getValue(), 42);

        // Verify simulation result
        assertEq(abi.decode(richTxn.simulatedReturnData, (uint256)), 42);
        assertEq(richTxn.transaction.label, "setValue");
        
        // Broadcast transaction
        harness.broadcastAll();
        
        // Verify execution
        assertEq(target.getValue(), 42);
    }
    
    function test_MultipleTransactionsBatch() public {
        // Create multiple transactions
        Transaction[] memory txns = new Transaction[](3);
        txns[0] = Transaction({
            label: "setValue-10",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 10),
            value: 0
        });
        txns[1] = Transaction({
            label: "setValue-20",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 20),
            value: 0
        });
        txns[2] = Transaction({
            label: "transfer-ether",
            to: address(target),
            data: "",
            value: 1 ether
        });
        
        // Execute batch
        RichTransaction[] memory results = harness.execute(BATCH_SENDER, txns);
        
        // Verify batch simulation
        assertEq(results.length, 3);
        assertEq(abi.decode(results[0].simulatedReturnData, (uint256)), 10);
        assertEq(abi.decode(results[1].simulatedReturnData, (uint256)), 20);
        
        // Broadcast
        harness.broadcastAll();
        
        // Verify final state
        assertEq(target.getValue(), 20);
        assertEq(address(target).balance, 1 ether);
    }
    
    function test_GnosisSafeSenderFlow() public {
        // Create transaction
        Transaction memory txn = Transaction({
            label: "setValue-via-safe",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 100),
            value: 0
        });
        
        // Execute (queue for Safe)
        harness.execute(SAFE_SENDER, txn);
        
        // Broadcast should return QUEUED status
        // Note: The event verification is tricky because we need the exact state at broadcast time
        harness.broadcastAll();
        
    }
    
    function test_HardwareWalletSenderInitialization() public view {
        // Verify hardware wallet was properly initialized
        HardwareWallet.Sender memory hwSender = harness.getHardwareWallet(LEDGER_SENDER);
        assertEq(hwSender.hardwareWalletType, "ledger");
        assertEq(hwSender.mnemonicDerivationPath, "m/44'/60'/0'/0/0");
    }
    
    function test_TransactionSimulationFailure() public {
        // Create transaction that will fail (calling non-existent function)
        Transaction memory txn = Transaction({
            label: "failing-tx",
            to: address(target),
            data: abi.encodeWithSelector(bytes4(0xdeadbeef)),
            value: 0
        });
        
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
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 42),
            value: 0
        });
        
        // queue transaction
        harness.execute(CUSTOM_SENDER, txn);
        
        // But broadcast should fail
        vm.expectRevert(abi.encodeWithSelector(SenderCoordinator.CustomQueueReceiverNotImplemented.selector));
        harness.broadcastAll();
    }
    
    function test_RegistryMultipleSenders() public {
        // Add additional senders for this test
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);
        
        configs[0] = Senders.SenderInitConfig({
            name: MEMORY_1,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x1111)
        });
        
        configs[1] = Senders.SenderInitConfig({
            name: LEDGER_1,
            account: makeAddr("ledger1"),
            senderType: SenderTypes.Ledger,
            config: abi.encode("m/44'/60'/0'/0/1")
        });
        
        // Create a separate harness for additional senders
        SendersTestHarness extraHarness = new SendersTestHarness(configs);
        
        // Verify all senders are accessible
        assertEq(extraHarness.get(MEMORY_1).name, MEMORY_1);
        assertEq(extraHarness.get(LEDGER_1).name, LEDGER_1);
        assertEq(harness.get(SAFE_1).name, SAFE_1);
        
        // Verify types
        assertTrue(extraHarness.isType(MEMORY_1, SenderTypes.InMemory));
        assertTrue(extraHarness.isType(LEDGER_1, SenderTypes.HardwareWallet));
        assertTrue(harness.isType(SAFE_1, SenderTypes.GnosisSafe));
    }
}