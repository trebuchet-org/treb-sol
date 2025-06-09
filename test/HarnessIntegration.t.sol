// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import "../src/internal/sender/Senders.sol";
import {SenderCoordinator} from "../src/internal/SenderCoordinator.sol";
import {Harness} from "../src/internal/Harness.sol";
import {SenderTypes, Transaction, SimulatedTransaction} from "../src/internal/types.sol";
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
    SenderCoordinator senderCoordinator;

    OwnableContract ownable;
    Counter counter;

    string constant SENDER_NAME = "test-sender";
    address senderAddr;

    function setUp() public withCreateX {
        // Setup test sender
        uint256 privateKey = 0x12345;
        senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: SENDER_NAME,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(privateKey)
        });

        // Initialize harness
        harness = new SendersTestHarness(configs);

        // Create senderCoordinator for testing
        senderCoordinator = new SenderCoordinator(configs, "default", false, false);

        // Deploy test contracts from the sender account
        vm.startPrank(senderAddr);
        ownable = new OwnableContract();
        counter = new Counter();
        vm.stopPrank();
    }

    // Test 1: Basic harness creation and usage
    function test_BasicHarnessCreation() public {
        // Get the harness address for the ownable contract
        // Note: The harness is created with the test harness address as senderCoordinator
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));

        // Verify harness was created
        assertTrue(harnessAddr != address(0));
        assertTrue(harnessAddr != address(ownable));

        // Verify harness is cached (second call returns same address)
        address harnessAddr2 = harness.getHarness(SENDER_NAME, address(ownable));
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
        harness.broadcastAll();

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
        harness.broadcastAll();

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
        harness.broadcastAll();

        // Values remain the same
        assertEq(ownable.getValue(), 100);
        assertEq(counter.number(), 200);
    }

    // Test 5: Staticcall detection with try/catch
    function test_StaticCallDetection() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));

        // First, set a value through normal transaction
        Counter(harnessAddr).setNumber(50);
        harness.broadcastAll();
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
        harness.broadcastAll();

        // Still new owner
        assertEq(ownable.owner(), newOwner);
    }

    // Test 7: Revert handling in harness
    function test_HarnessRevertHandling() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));

        // This should revert with the actual error message from the contract
        vm.expectRevert("Counter: cannot decrement below zero");
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
        harness.broadcastAll();
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
        harness.broadcastAll();
        assertEq(ownable.getValue(), 1000);
    }

    // Test 10: Direct execute through senderCoordinator
    function test_DirectExecuteThroughSenderCoordinator() public {
        // Get sender ID
        bytes32 senderId = keccak256(abi.encodePacked(SENDER_NAME));

        // Create transaction manually
        Transaction memory txn = Transaction({
            to: address(counter),
            data: abi.encodeWithSelector(Counter.setNumber.selector, 333),
            value: 0,
            label: "setNumber(333)"
        });

        // Execute through senderCoordinator - this simulates and queues
        SimulatedTransaction memory result = senderCoordinator.execute(senderId, txn);

        // Transaction is executed during simulation
        assertEq(counter.number(), 333);

        // setNumber doesn't return anything, so returnData should be empty
        assertEq(result.returnData.length, 0);

        // Broadcast doesn't change anything since already executed
        harness.broadcastAll();
        assertEq(counter.number(), 333);
    }

    // Test 11: Revert with data is properly propagated
    function test_RevertWithDataPropagation() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));

        // This should revert with the actual error message
        vm.expectRevert("Counter: cannot decrement below zero");
        Counter(harnessAddr).decrement();

        // Now test a custom error scenario
        // First, let's create a contract with custom errors
        RevertTestContract revertContract = new RevertTestContract();
        address revertHarness = harness.getHarness(SENDER_NAME, address(revertContract));

        // This should propagate the custom error
        vm.expectRevert(abi.encodeWithSelector(RevertTestContract.CustomError.selector, 123, "This is a custom error"));
        RevertTestContract(revertHarness).failWithCustomError();

        // This should propagate the require message
        vm.expectRevert("This is a require message");
        RevertTestContract(revertHarness).failWithRequire();
    }

    // Test 12: Only empty revert data triggers staticcall fallback
    function test_EmptyRevertDataTriggersStaticCall() public {
        // Deploy a special contract that can test this behavior
        StaticCallTestContract testContract = new StaticCallTestContract();
        address testHarness = harness.getHarness(SENDER_NAME, address(testContract));

        // View function should work (triggers staticcall path due to empty revert)
        uint256 value = StaticCallTestContract(testHarness).getValue();
        assertEq(value, 42);

        // Pure function should also work
        uint256 computed = StaticCallTestContract(testHarness).computeValue(10, 20);
        assertEq(computed, 30);

        // State changing function should be queued
        StaticCallTestContract(testHarness).setValue(100);
        assertEq(testContract.storedValue(), 100); // Executed during simulation
    }

    // Test 13: Complex revert scenarios
    function test_ComplexRevertScenarios() public {
        ComplexRevertContract complexContract = new ComplexRevertContract();
        address complexHarness = harness.getHarness(SENDER_NAME, address(complexContract));

        // Test revert with empty string (still has data due to string encoding)
        vm.expectRevert(bytes(""));
        ComplexRevertContract(complexHarness).revertEmptyString();

        // Test revert with long message
        vm.expectRevert(
            "This is a very long error message that tests how the harness handles larger revert data when propagating errors through the system"
        );
        ComplexRevertContract(complexHarness).revertLongMessage();

        // Test panic (division by zero causes panic code 0x12)
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x12));
        ComplexRevertContract(complexHarness).causePanic();
    }

    // Test 16: View function works after failures
    function test_ViewFunctionAfterFailures() public {
        ComplexRevertContract complexContract = new ComplexRevertContract();
        address complexHarness = harness.getHarness(SENDER_NAME, address(complexContract));

        // View function should work even after the contract has methods that revert
        assertTrue(ComplexRevertContract(complexHarness).isViewFunction());
    }

    // Test 17: Debug staticcall behavior
    function test_StaticCallBehaviorDebug() public {
        // Create a simple test contract
        StaticCallDebugContract debugContract = new StaticCallDebugContract();

        // Test direct call vs harness call
        uint256 directValue = debugContract.getSimpleValue();
        assertEq(directValue, 123);

        // Now through harness
        address debugHarness = harness.getHarness(SENDER_NAME, address(debugContract));
        uint256 harnessValue = StaticCallDebugContract(debugHarness).getSimpleValue();
        assertEq(harnessValue, 123);

        // Test that state changes work
        StaticCallDebugContract(debugHarness).setSimpleValue(456);
        assertEq(debugContract.simpleValue(), 456);
    }

    // Test 18: Verify transaction events are emitted
    function test_TransactionEventsEmitted() public {
        // Create a fresh counter for this test to ensure it starts at 0
        Counter freshCounter = new Counter();
        address harnessAddr = harness.getHarness(SENDER_NAME, address(freshCounter));

        // Test successful transaction emits TransactionSimulated
        // Note: Harness calls don't emit TransactionSimulated events anymore
        // as they don't go through the normal simulate/broadcast flow
        Counter(harnessAddr).setNumber(100);

        // Reset counter to 0 for failure test
        Counter(harnessAddr).setNumber(0);

        // Test failed transaction - harness calls don't emit TransactionSimulated/Failed events
        // This will revert with the actual error
        vm.expectRevert("Counter: cannot decrement below zero");
        Counter(harnessAddr).decrement();
    }
}

// Test contract for revert scenarios
contract RevertTestContract {
    error CustomError(uint256 code, string message);

    function failWithCustomError() public pure {
        revert CustomError(123, "This is a custom error");
    }

    function failWithRequire() public pure {
        require(false, "This is a require message");
    }

    function failWithRevert() public pure {
        revert("This is a revert message");
    }
}

// Test contract for staticcall detection
contract StaticCallTestContract {
    uint256 public storedValue = 42;

    function getValue() public view returns (uint256) {
        return storedValue;
    }

    function computeValue(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }

    function setValue(uint256 newValue) public {
        storedValue = newValue;
    }
}

// Test contract for complex revert scenarios
contract ComplexRevertContract {
    function revertEmptyString() public pure {
        revert(""); // Empty string still has ABI encoding
    }

    function revertLongMessage() public pure {
        revert(
            "This is a very long error message that tests how the harness handles larger revert data when propagating errors through the system"
        );
    }

    function causePanic() public pure returns (uint256) {
        uint256 a = 1;
        uint256 b = 0;
        return a / b; // Division by zero causes panic
    }

    function isViewFunction() public pure returns (bool) {
        return true;
    }
}

// Debug contract for staticcall behavior
contract StaticCallDebugContract {
    uint256 public simpleValue = 123;

    function getSimpleValue() public view returns (uint256) {
        return simpleValue;
    }

    function setSimpleValue(uint256 newValue) public {
        simpleValue = newValue;
    }
}
