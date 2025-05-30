// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import "../src/internal/sender/Senders.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Harness} from "../src/internal/Harness.sol";
import {SenderTypes, Transaction, RichTransaction} from "../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

// Simple ownable contract for testing
contract OwnableContract {
    address public owner;
    uint256 public value;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ValueSet(uint256 newValue);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    function setValue(uint256 newValue) public onlyOwner {
        value = newValue;
        emit ValueSet(newValue);
    }
    
    function getValue() public view returns (uint256) {
        return value;
    }
}

// Counter contract with both state-changing and view functions
contract Counter {
    uint256 private count;
    
    event CountChanged(uint256 newCount);
    
    function increment() public {
        count += 1;
        emit CountChanged(count);
    }
    
    function decrement() public {
        require(count > 0, "Counter: cannot decrement below zero");
        count -= 1;
        emit CountChanged(count);
    }
    
    function setNumber(uint256 newNumber) public {
        count = newNumber;
        emit CountChanged(count);
    }
    
    function number() public view returns (uint256) {
        return count;
    }
    
    function doubleNumber() public view returns (uint256) {
        return count * 2;
    }
}

contract HarnessIntegrationTest is Test, CreateXScript {
    using Senders for Senders.Sender;
    
    SendersTestHarness harness;
    TestableDispatcher dispatcher;
    
    OwnableContract ownable;
    Counter counter;
    
    string constant SENDER_NAME = "test-sender";
    address senderAddr;
    
    function setUp() public withCreateX {
        // Reset registry
        Senders.reset();
        
        // Setup test sender
        uint256 privateKey = 0x12345;
        senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: SENDER_NAME,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        // Initialize harness
        harness = new SendersTestHarness(configs);
        
        // Create dispatcher for testing
        bytes memory encodedConfigs = abi.encode(configs);
        dispatcher = new TestableDispatcher(encodedConfigs, "default", false);
        
        // Deploy test contracts from the sender account
        vm.startPrank(senderAddr);
        ownable = new OwnableContract();
        counter = new Counter();
        vm.stopPrank();
    }
    
    // Test 1: Basic harness creation and usage
    function test_BasicHarnessCreation() public {
        // Get the harness address for the ownable contract
        // Note: The harness is created with the test harness address as dispatcher
        address harnessAddr = Senders.get(SENDER_NAME).harness(address(ownable));
        
        // Verify harness was created
        assertTrue(harnessAddr != address(0));
        assertTrue(harnessAddr != address(ownable));
        
        // Verify harness is cached (second call returns same address)
        address harnessAddr2 = Senders.get(SENDER_NAME).harness(address(ownable));
        assertEq(harnessAddr, harnessAddr2);
    }
    
    // Test 2: Harness with ownable contract - simulation and queue
    function test_HarnessOwnableTransaction() public {
        // Get harness for the ownable contract
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));
        
        // Call setValue through the harness
        uint256 newValue = 42;
        OwnableContract(harnessAddr).setValue(newValue);
        
        // The transaction is executed during simulation, so value is updated
        assertEq(ownable.getValue(), newValue);
        
        // Broadcast doesn't change anything since already executed
        harness.broadcastSender(SENDER_NAME);
        
        // Value remains the same
        assertEq(ownable.getValue(), newValue);
    }
    
    // Test 3: Multiple transactions through harness
    function test_HarnessMultipleTransactions() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        
        // Execute multiple transactions through harness
        Counter(harnessAddr).setNumber(10);
        Counter(harnessAddr).increment();
        Counter(harnessAddr).increment();
        
        // Counter is updated during simulation
        assertEq(counter.number(), 12);
        
        // Broadcast doesn't change anything since already executed
        harness.broadcastSender(SENDER_NAME);
        
        // Counter remains 12
        assertEq(counter.number(), 12);
    }
    
    // Test 4: Harness with different contracts for same sender
    function test_HarnessMultipleContracts() public {
        // Get harnesses for both contracts
        address ownableHarness = harness.getHarness(SENDER_NAME, address(ownable));
        address counterHarness = harness.getHarness(SENDER_NAME, address(counter));
        
        // Should be different addresses
        assertTrue(ownableHarness != counterHarness);
        
        // Execute transactions for both
        OwnableContract(ownableHarness).setValue(100);
        Counter(counterHarness).setNumber(200);
        
        // Values are already updated
        assertEq(ownable.getValue(), 100);
        assertEq(counter.number(), 200);
        
        // Broadcast doesn't change anything
        harness.broadcastSender(SENDER_NAME);
        
        // Values remain the same
        assertEq(ownable.getValue(), 100);
        assertEq(counter.number(), 200);
    }
    
    // Test 5: Staticcall detection with try/catch
    function test_StaticCallDetection() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        
        // First, set a value through normal transaction
        Counter(harnessAddr).setNumber(50);
        harness.broadcastSender(SENDER_NAME);
        assertEq(counter.number(), 50);
        
        // Now test view function through harness
        // This should work differently as it's a staticcall
        uint256 num = Counter(harnessAddr).number();
        assertEq(num, 50); // Should return the actual value
        
        // Test another view function
        uint256 doubled = Counter(harnessAddr).doubleNumber();
        assertEq(doubled, 100); // Should return 50 * 2
    }
    
    // Test 6: Ownership transfer through harness
    function test_OwnershipTransferThroughHarness() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));
        address newOwner = makeAddr("newOwner");
        
        // Transfer ownership through harness
        OwnableContract(harnessAddr).transferOwnership(newOwner);
        
        // Ownership is immediately transferred during simulation
        assertEq(ownable.owner(), newOwner);
        
        // Broadcast doesn't change anything
        harness.broadcastSender(SENDER_NAME);
        
        // Still new owner
        assertEq(ownable.owner(), newOwner);
    }
    
    // Test 7: Revert handling in harness
    function test_HarnessRevertHandling() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        
        // This should revert during simulation with TransactionFailed error
        vm.expectRevert(abi.encodeWithSelector(Senders.TransactionFailed.selector, ""));
        Counter(harnessAddr).decrement();
    }
    
    // Test 8: Events through harness
    function test_EventsThroughHarness() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        
        // Event is emitted during execution through harness
        vm.expectEmit(true, true, true, true);
        emit Counter.CountChanged(777);
        
        Counter(harnessAddr).setNumber(777);
        
        // Broadcast doesn't emit again
        harness.broadcastSender(SENDER_NAME);
    }
    
    // Test 9: Complex staticcall scenario
    function test_ComplexStaticCallScenario() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));
        
        // Set a value first
        OwnableContract(harnessAddr).setValue(999);
        
        // Value is immediately updated
        assertEq(ownable.getValue(), 999);
        
        // View function through harness works immediately
        uint256 retrievedValue = OwnableContract(harnessAddr).getValue();
        assertEq(retrievedValue, 999);
        
        // Execute another state-changing transaction
        OwnableContract(harnessAddr).setValue(1000);
        
        // Value is immediately updated again
        assertEq(ownable.getValue(), 1000);
        
        // View returns new value
        assertEq(OwnableContract(harnessAddr).getValue(), 1000);
        
        // Broadcast doesn't change anything
        harness.broadcastSender(SENDER_NAME);
        assertEq(ownable.getValue(), 1000);
    }
    
    // Test 10: Direct execute through dispatcher
    function test_DirectExecuteThroughDispatcher() public {
        // Get sender ID
        bytes32 senderId = keccak256(abi.encodePacked(SENDER_NAME));
        
        // Create transaction manually
        Transaction memory txn = Transaction({
            to: address(counter),
            data: abi.encodeWithSelector(Counter.setNumber.selector, 333),
            value: 0,
            label: "setNumber(333)"
        });
        
        // Execute through dispatcher - this simulates and queues
        RichTransaction memory result = dispatcher.execute(senderId, txn);
        
        // Transaction is executed during simulation
        assertEq(counter.number(), 333);
        
        // setNumber doesn't return anything, so simulatedReturnData should be empty
        assertEq(result.simulatedReturnData.length, 0);
        
        // Broadcast doesn't change anything since already executed
        harness.broadcastSender(SENDER_NAME);
        assertEq(counter.number(), 333);
    }
}

// Testable dispatcher that exposes execute functions
contract TestableDispatcher is Dispatcher {
    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun) 
        Dispatcher(_rawConfigs, _namespace, _dryrun) {}
}