// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SafeSender} from "../src/internal/senders/SafeSender.sol";
import {PrivateKeySender} from "../src/internal/senders/PrivateKeySender.sol";
import {Sender} from "../src/internal/Sender.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";
import {Safe} from "safe-utils/Safe.sol";

contract SafeSenderTest is Test {
    SafeSender safeSender;
    PrivateKeySender proposer;
    address[] owners;
    address mockSafe;
    
    function setUp() public {
        // Create owners
        mockSafe = makeAddr("mockSafe");
        owners = new address[](3);
        owners[0] = makeAddr("owner1");
        owners[1] = makeAddr("owner2");
        owners[2] = makeAddr("owner3");
        
        
        // Create proposer
        (address proposerAddr, uint256 proposerKey) = makeAddrAndKey("proposer");
        proposer = new PrivateKeySender(proposerAddr, proposerKey);
        
        // Create SafeSender
        safeSender = new SafeSender(mockSafe, "proposer");
    }
    
    function testSafeSenderTypes() public {
        assertTrue(safeSender.isType("Safe"));
    }
    
    function testSafeSenderAddress() public {
        assertEq(safeSender.senderAddress(), mockSafe);
    }
    
    function testExecuteTransaction() public {
        // Create a test transaction
        address target = makeAddr("target");
        bytes memory data = abi.encodeWithSignature("test()");
        uint256 value = 1 ether;
        
        // Fund the safe
        vm.deal(mockSafe, 10 ether);
        
        // Execute transaction
        Transaction memory txn = Transaction({
            to: target,
            data: data,
            value: value,
            label: "test"
        });
        
        // This should queue the transaction in the safe
        safeSender.execute(txn);
        
        // Verify the bundle is created
        assertEq(safeSender.bundleIndex(), 1);
        BundleTransaction[] memory bundle = safeSender.getCurrentBundle();
        assertEq(bundle[0].transaction.to, target);
        assertEq(bundle[0].transaction.data, data);
        assertEq(bundle[0].transaction.value, value);
        assertEq(bundle[0].transaction.label, "test");
    }
    
    function testExecuteMultipleTransactions() public {
        // Create multiple test transactions
        address target1 = makeAddr("target1");
        address target2 = makeAddr("target2");
        
        Transaction memory txn1 = Transaction({
            label: "test1",
            to: target1,
            data: abi.encodeWithSignature("test1()"),
            value: 1 ether
        });
        
        Transaction memory txn2 = Transaction({
            label: "test2",
            to: target2,
            data: abi.encodeWithSignature("test2()"),
            value: 2 ether
        });
        
        // Fund the safe
        vm.deal(mockSafe, 10 ether);
        
        // Execute transactions
        safeSender.execute(txn1);
        safeSender.execute(txn2);
        
        // Verify both are in the same bundle
        BundleTransaction[] memory bundle = safeSender.getCurrentBundle();
        assertEq(bundle.length, 2);
    }
    
    function testProposeTransaction() public {
        // Create a test transaction
        address target = makeAddr("target");
        bytes memory data = abi.encodeWithSignature("test()");
        
        Transaction memory txn = Transaction({
            label: "propose",
            to: target,
            data: data,
            value: 0
        });
        
        // Execute to add to bundle
        safeSender.execute(txn);
        
        // Flush should propose the transaction
        safeSender.flushBundle();
        
        // Check that bundle was cleared after flush
        BundleTransaction[] memory bundle = safeSender.getCurrentBundle();
        assertEq(bundle.length, 0);
    }
}