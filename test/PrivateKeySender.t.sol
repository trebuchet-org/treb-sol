// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrivateKeySender} from "../src/internal/senders/PrivateKeySender.sol";
import {Sender} from "../src/internal/Sender.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";

contract PrivateKeySenderTest is Test {
    PrivateKeySender sender;
    address senderAddress;
    uint256 constant PRIVATE_KEY = 0xa11ce11ce11ce11ce11ce11ce11ce11ce11ce11ce11ce11ce11ce11ce11ce11c;
    
    uint256 simulationForkId;
    uint256 executionForkId;
    
    function setUp() public {
        vm.setEnv("NAMESPACE", "default");
        senderAddress = vm.addr(PRIVATE_KEY);
        
        // Create forks
        string memory network = vm.envOr("NETWORK", string("anvil"));
        simulationForkId = vm.createFork(network);
        executionForkId = vm.createFork(network);
        vm.selectFork(simulationForkId);
        
        // Fund the sender
        vm.deal(senderAddress, 100 ether);
        
        sender = new PrivateKeySender(senderAddress, PRIVATE_KEY);
        sender.initialize(simulationForkId, executionForkId);
    }
    
    function testIsPrivateKey() public {
        assertTrue(sender.isType("PrivateKey"));
        assertFalse(sender.isType("Ledger"));
        assertFalse(sender.isType("Trezor"));
        assertFalse(sender.isType("Safe"));
    }
    
    function testExecuteTransaction() public {
        // Deploy a simple contract to interact with
        MockTarget target = new MockTarget();
        
        Transaction memory txn = Transaction({
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSignature("setValue(uint256)", 42),
            value: 0
        });
        
        BundleTransaction memory result = sender.execute(txn);
        
        // Verify the transaction was executed
        assertTrue(result.txId != bytes32(0));
        
        // Verify the value was set
        assertEq(target.value(), 42);
    }
    
    function testExecuteWithValue() public {
        address payable target = payable(address(new MockTarget()));
        
        Transaction memory txn = Transaction({
            label: "sendEther",
            to: address(target),
            data: "",
            value: 1 ether
        });
        
        uint256 targetBalanceBefore = target.balance;
        
        BundleTransaction memory result = sender.execute(txn);
        
        // Verify the transaction was executed
        assertTrue(result.txId != bytes32(0));
        assertEq(target.balance, targetBalanceBefore + 1 ether);
    }
    
    function testExecuteMultipleTransactions() public {
        MockTarget target1 = new MockTarget();
        MockTarget target2 = new MockTarget();
        
        Transaction[] memory txns = new Transaction[](2);
        txns[0] = Transaction({
            label: "setValue1",
            to: address(target1),
            data: abi.encodeWithSignature("setValue(uint256)", 100),
            value: 0
        });
        txns[1] = Transaction({
            label: "setValue2",
            to: address(target2),
            data: abi.encodeWithSignature("setValue(uint256)", 200),
            value: 0
        });
        
        BundleTransaction[] memory results = sender.execute(txns);
        
        // Verify the transactions were executed
        assertEq(results.length, 2);
        assertTrue(results[0].txId != bytes32(0));
        assertTrue(results[1].txId != bytes32(0));
        assertEq(target1.value(), 100);
        assertEq(target2.value(), 200);
    }
    
    function testRevertWhen_TransactionFails() public {
        NoFallbackContract target = new NoFallbackContract();
        
        // Try to call a non-existent function
        Transaction memory txn = Transaction({
            label: "nonExistent",
            to: address(target),
            data: abi.encodeWithSignature("nonExistentFunction()"),
            value: 0
        });
        
        vm.expectRevert(abi.encodeWithSelector(Sender.TransactionFailed.selector, "nonExistent"));
        sender.execute(txn);
    }
}

// Helper contract for testing
contract MockTarget {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    receive() external payable {}
}

// Contract without fallback for testing reverts
contract NoFallbackContract {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    // No receive or fallback function
}