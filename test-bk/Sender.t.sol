// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Sender} from "../src/internal/Sender.sol";
import {PrivateKeySender} from "../src/internal/senders/PrivateKeySender.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";

// Test target contract with actual functionality
contract TestTarget {
    uint256 public value;
    address public lastCaller;
    bytes public lastData;
    
    event Called(address sender, bytes data, uint256 msgValue);
    event ValueSet(uint256 newValue);
    
    function setValue(uint256 _value) external returns (uint256) {
        value = _value;
        lastCaller = msg.sender;
        emit ValueSet(_value);
        return _value;
    }
    
    function failingFunction() external pure {
        revert("This function always fails");
    }
    
    receive() external payable {
        lastCaller = msg.sender;
        emit Called(msg.sender, "", msg.value);
    }
    
    fallback() external payable {
        lastCaller = msg.sender;
        lastData = msg.data;
        emit Called(msg.sender, msg.data, msg.value);
    }
}

contract SenderTest is Test {
    PrivateKeySender sender;
    TestTarget target;
    
    uint256 constant PRIVATE_KEY = 0xabc123;
    address senderAddress;
    
    uint256 simulationForkId;
    uint256 executionForkId;
    
    function setUp() public {
        vm.setEnv("NAMESPACE", "default");
        
        // Create forks
        string memory network = vm.envOr("NETWORK", string("anvil"));
        simulationForkId = vm.createFork(network);
        executionForkId = vm.createFork(network);
        vm.selectFork(simulationForkId);
        
        // Setup sender address
        senderAddress = vm.addr(PRIVATE_KEY);
        
        // Deploy contracts
        sender = new PrivateKeySender(senderAddress, PRIVATE_KEY);
        sender.initialize(simulationForkId, executionForkId);
        target = new TestTarget();
        
        // Make target persistent across forks
        vm.makePersistent(address(target));
        vm.makePersistent(address(sender));
        
        // Deal ETH to sender for value transfers on simulation fork
        vm.deal(senderAddress, 100 ether);
        
        // Also deal ETH on execution fork
        vm.selectFork(executionForkId);
        vm.deal(senderAddress, 100 ether);
        vm.selectFork(simulationForkId);
    }
    
    function testSenderAddress() public view {
        assertEq(sender.senderAddress(), senderAddress);
    }
    
    function testExecuteSingleTransaction() public {
        // Create a transaction that actually does something
        Transaction memory txn = Transaction({
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 42),
            value: 0
        });
        
        BundleTransaction memory result = sender.execute(txn);
        
        // Verify the transaction was queued
        assertTrue(result.txId != bytes32(0));
        assertTrue(result.bundleId != bytes32(0));
        assertEq(result.simulatedReturnData, abi.encode(uint256(42)));
        
        // Check that target value is set in simulation fork
        assertEq(target.value(), 42);
        
        // Now flush to execute on execution fork
        vm.selectFork(executionForkId);
        sender.flushBundle();
        
        // Verify execution happened
        assertEq(target.value(), 42);
        assertEq(target.lastCaller(), senderAddress);
    }
    
    function testExecuteMultipleTransactions() public {
        Transaction[] memory txns = new Transaction[](3);
        txns[0] = Transaction({
            label: "setValue-100",
            to: address(target),
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 100),
            value: 0
        });
        txns[1] = Transaction({
            label: "sendEther", 
            to: address(target),
            data: "",
            value: 1 ether
        });
        txns[2] = Transaction({
            label: "setValue-200",
            to: address(target),
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 200),
            value: 0
        });
        
        BundleTransaction[] memory results = sender.execute(txns);
        
        // Verify the transactions were queued
        assertEq(results.length, 3);
        assertTrue(results[0].txId != bytes32(0));
        assertEq(results[0].simulatedReturnData, abi.encode(uint256(100)));
        assertEq(results[2].simulatedReturnData, abi.encode(uint256(200)));
        
        // Check simulation results
        assertEq(target.value(), 200); // Last setValue
        
        // Now flush to execute
        vm.selectFork(executionForkId);
        uint256 targetBalanceBeforeExec = address(target).balance;
        sender.flushBundle();
        
        // Verify execution results
        assertEq(target.value(), 200);
        assertEq(address(target).balance, targetBalanceBeforeExec + 1 ether);
    }
    
    function testBundleIdGeneration() public {
        Transaction memory txn = Transaction({
            label: "test",
            to: address(target),
            data: abi.encodeWithSelector(TestTarget.setValue.selector, 999),
            value: 0
        });
        
        // Execute transaction (simulates and queues)
        BundleTransaction memory result = sender.execute(txn);
        
        // Verify bundle transaction was created
        assertTrue(result.txId != bytes32(0));
        assertTrue(result.bundleId != bytes32(0));
        assertEq(result.transaction.label, "test");
        assertEq(result.simulatedReturnData, abi.encode(uint256(999)));
    }
    
    function testTransactionFailure() public {
        // Call a function that will revert
        Transaction memory txn = Transaction({
            label: "failing-transaction",
            to: address(target),
            data: abi.encodeWithSelector(TestTarget.failingFunction.selector),
            value: 0
        });
        
        // This should fail during simulation
        vm.expectRevert(
            abi.encodeWithSelector(Sender.TransactionFailed.selector, "failing-transaction")
        );
        sender.execute(txn);
    }
    
    function testSenderTypeFlags() public view {
        assertTrue(sender.isType("PrivateKey"));
        assertFalse(sender.isType("Safe"));
        assertFalse(sender.isType("Ledger"));
        assertFalse(sender.isType("Trezor"));
    }
}