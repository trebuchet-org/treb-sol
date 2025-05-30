// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {PrivateKey, HardwareWallet, InMemory} from "../src/internal/sender/PrivateKeySender.sol";
import {GnosisSafe} from "../src/internal/sender/GnosisSafeSender.sol";
import {SenderTypes, Transaction, RichTransaction, BundleStatus} from "../src/internal/types.sol";
import {SenderTestHarness} from "./helpers/SenderTestHarness.sol";

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
    using Senders for Senders.Sender;
    using Senders for Senders.Registry;
    
    MockTarget target;
    uint256 simulationForkId;
    uint256 executionForkId;
    
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
        // Create forks for testing first
        string memory rpcUrl = vm.envOr("NETWORK", string("http://localhost:8545"));
        simulationForkId = vm.createFork(rpcUrl);
        executionForkId = vm.createFork(rpcUrl);
        
        // Deploy target on simulation fork
        vm.selectFork(simulationForkId);
        target = new MockTarget();
        
        // Deploy same target on execution fork at same address
        vm.selectFork(executionForkId);
        vm.etch(address(target), address(target).code);
        
        // Go back to simulation fork
        vm.selectFork(simulationForkId);
    }
    
    function test_InMemorySenderFullFlow() public {
        // Setup InMemory sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        
        // Deal ether on both forks
        vm.selectFork(simulationForkId);
        vm.deal(senderAddr, 10 ether);
        vm.selectFork(executionForkId);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        // Create harness on simulation fork
        vm.selectFork(simulationForkId);
        SenderTestHarness harness = new SenderTestHarness(TEST_SENDER, configs);
        
        // Create transaction
        Transaction memory txn = Transaction({
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 42),
            value: 0
        });
        
        // Execute transaction (simulation)
        RichTransaction memory richTxn = harness.execute(txn);
        
        // Verify simulation result
        assertEq(abi.decode(richTxn.simulatedReturnData, (uint256)), 42);
        assertEq(richTxn.transaction.label, "setValue");
        
        // Make harness persistent across forks
        vm.makePersistent(address(harness));
        
        // Broadcast transaction
        vm.selectFork(executionForkId);
        bytes32 bundleId = harness.broadcast();
        
        // Verify execution
        assertEq(target.getValue(), 42);
        assertTrue(bundleId != bytes32(0));
    }
    
    function test_MultipleTransactionsBatch() public {
        // Setup sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        
        // Deal funds on both forks
        vm.selectFork(simulationForkId);
        vm.deal(senderAddr, 10 ether);
        vm.selectFork(executionForkId);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: BATCH_SENDER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        // Create harness
        vm.selectFork(simulationForkId);
        SenderTestHarness harness = new SenderTestHarness(BATCH_SENDER, configs);
        
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
        RichTransaction[] memory results = harness.execute(txns);
        
        // Verify batch simulation
        assertEq(results.length, 3);
        assertEq(abi.decode(results[0].simulatedReturnData, (uint256)), 10);
        assertEq(abi.decode(results[1].simulatedReturnData, (uint256)), 20);
        
        // Make harness persistent
        vm.makePersistent(address(harness));
        
        // Broadcast
        vm.selectFork(executionForkId);
        harness.broadcast();
        
        // Verify final state
        assertEq(target.getValue(), 20);
        assertEq(address(target).balance, 1 ether);
    }
    
    function test_GnosisSafeSenderFlow() public {
        // Skip this test for now - it requires mocking HTTP calls to Safe API
        // and setting up MultiSendCallOnly contract on local chain
        vm.skip(true);
        
        // Setup proposer
        uint256 proposerKey = 0x54321;
        address proposerAddr = vm.addr(proposerKey);
        
        // Setup Safe (mock)
        address safeAddr = makeAddr("safe");
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);
        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: proposerAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(proposerKey)
        });
        configs[1] = Senders.SenderInitConfig({
            name: SAFE_SENDER,
            account: safeAddr,
            senderType: SenderTypes.GnosisSafe,
            config: abi.encode(PROPOSER)
        });
        
        Senders.initialize(configs);
        
        // Create transaction
        Transaction memory txn = Transaction({
            label: "setValue-via-safe",
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 100),
            value: 0
        });
        
        // Execute (queue for Safe)
        vm.selectFork(simulationForkId);
        Senders.Sender storage safeSender = Senders.registry().get(SAFE_SENDER);
        safeSender.execute(txn);
        
        // Broadcast should return QUEUED status
        vm.selectFork(executionForkId);
        vm.expectEmit(true, true, false, true);
        emit Senders.BundleSent(safeAddr, safeSender.bundleId, BundleStatus.QUEUED, safeSender.queue);
        bytes32 bundleId = safeSender.broadcast();
        
        assertTrue(bundleId != bytes32(0));
    }
    
    function test_HardwareWalletSenderInitialization() public {
        address ledgerAddr = makeAddr("ledger");
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: LEDGER_SENDER,
            account: ledgerAddr,
            senderType: SenderTypes.Ledger,
            config: abi.encode("m/44'/60'/0'/0/0")
        });
        
        Senders.initialize(configs);
        
        // Verify hardware wallet was properly initialized
        HardwareWallet.Sender memory hwSender = Senders.registry().get(LEDGER_SENDER).hardwareWallet();
        assertEq(hwSender.hardwareWalletType, "ledger");
        assertEq(hwSender.mnemonicDerivationPath, "m/44'/60'/0'/0/0");
    }
    
    function test_TransactionSimulationFailure() public {
        // Setup sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: FAIL_SENDER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        // Create harness for this test
        vm.selectFork(simulationForkId);
        SenderTestHarness harness = new SenderTestHarness(FAIL_SENDER, configs);
        
        // Create transaction that will fail (calling non-existent function)
        Transaction memory txn = Transaction({
            label: "failing-tx",
            to: address(target),
            data: abi.encodeWithSelector(bytes4(0xdeadbeef)),
            value: 0
        });
        
        // Execute should revert
        vm.expectRevert(abi.encodeWithSelector(Senders.TransactionFailed.selector, "failing-tx"));
        harness.execute(txn);
    }
    
    function test_CustomSenderType() public {
        // Custom sender types should be allowed but not broadcastable
        address customAddr = makeAddr("custom");
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: CUSTOM_SENDER,
            account: customAddr,
            senderType: SenderTypes.Custom,
            config: ""
        });
        
        // Create harness
        vm.selectFork(simulationForkId);
        SenderTestHarness harness = new SenderTestHarness(CUSTOM_SENDER, configs);
        
        // But broadcast should fail
        vm.selectFork(executionForkId);
        vm.expectRevert(abi.encodeWithSelector(Senders.CannotBroadcastCustomSender.selector, CUSTOM_SENDER));
        harness.broadcast();
    }
    
    function test_RegistryMultipleSenders() public {
        // Test registry with multiple senders of different types
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](4);
        
        configs[0] = Senders.SenderInitConfig({
            name: MEMORY_1,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x1111)
        });
        
        configs[1] = Senders.SenderInitConfig({
            name: LEDGER_1,
            account: makeAddr("ledger"),
            senderType: SenderTypes.Ledger,
            config: abi.encode("m/44'/60'/0'/0/0")
        });
        
        configs[2] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: vm.addr(0x2222),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x2222)
        });
        
        configs[3] = Senders.SenderInitConfig({
            name: SAFE_1,
            account: makeAddr("safe"),
            senderType: SenderTypes.GnosisSafe,
            config: abi.encode(PROPOSER)
        });
        
        Senders.initialize(configs);
        
        // Verify all senders are accessible
        assertEq(Senders.registry().get(MEMORY_1).name, MEMORY_1);
        assertEq(Senders.registry().get(LEDGER_1).name, LEDGER_1);
        assertEq(Senders.registry().get(SAFE_1).name, SAFE_1);
        
        // Verify types
        assertTrue(Senders.registry().get(MEMORY_1).isType(SenderTypes.InMemory));
        assertTrue(Senders.registry().get(LEDGER_1).isType(SenderTypes.HardwareWallet));
        assertTrue(Senders.registry().get(SAFE_1).isType(SenderTypes.GnosisSafe));
    }
}