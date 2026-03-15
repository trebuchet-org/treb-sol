// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {Senders} from "../../src/v2/internal/sender/Senders.sol";
import {SenderCoordinator} from "../../src/v2/internal/SenderCoordinator.sol";
import {Harness} from "../../src/v2/internal/Harness.sol";
import {SenderTypes, Transaction, SimulatedTransaction} from "../../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

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

contract V2HarnessIntegrationTest is Test, CreateXScript {
    using Senders for Senders.Sender;

    SendersTestHarness harness;
    OwnableContract ownable;
    Counter counter;

    string constant SENDER_NAME = "test-sender";
    address senderAddr;

    function setUp() public withCreateX {
        uint256 privateKey = 0x1234567;
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

        harness = new SendersTestHarness(configs);

        // Deploy test contracts — v2 has no fork system so just deploy once
        vm.startPrank(senderAddr);
        ownable = new OwnableContract();
        counter = new Counter();
        vm.stopPrank();
    }

    function test_BasicHarnessCreation() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));

        assertTrue(harnessAddr != address(0));
        assertTrue(harnessAddr != address(ownable));

        // Cached
        address harnessAddr2 = harness.getHarness(SENDER_NAME, address(ownable));
        assertEq(harnessAddr, harnessAddr2);
    }

    function test_HarnessOwnableTransaction() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));
        OwnableContract(harnessAddr).setValue(42);
        assertEq(ownable.getValue(), 42);
    }

    function test_HarnessMultipleTransactions() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        Counter(harnessAddr).setNumber(10);
        Counter(harnessAddr).increment();
        Counter(harnessAddr).increment();
        assertEq(counter.number(), 12);
    }

    function test_HarnessMultipleContracts() public {
        address ownableHarness = harness.getHarness(SENDER_NAME, address(ownable));
        address counterHarness = harness.getHarness(SENDER_NAME, address(counter));

        assertTrue(ownableHarness != counterHarness);

        OwnableContract(ownableHarness).setValue(100);
        Counter(counterHarness).setNumber(200);

        assertEq(ownable.getValue(), 100);
        assertEq(counter.number(), 200);
    }

    function test_StaticCallDetection() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        Counter(harnessAddr).setNumber(50);

        uint256 num = Counter(harnessAddr).number();
        assertEq(num, 50);

        uint256 doubled = Counter(harnessAddr).doubleNumber();
        assertEq(doubled, 100);
    }

    function test_OwnershipTransferThroughHarness() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(ownable));
        address newOwner = makeAddr("newOwner");

        OwnableContract(harnessAddr).transferOwnership(newOwner);
        assertEq(ownable.owner(), newOwner);
    }

    function test_HarnessRevertHandling() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        vm.expectRevert("Counter: cannot decrement below zero");
        Counter(harnessAddr).decrement();
    }

    function test_EventsThroughHarness() public {
        address harnessAddr = harness.getHarness(SENDER_NAME, address(counter));
        vm.expectEmit(true, true, true, true);
        emit Counter.CountChanged(777);
        Counter(harnessAddr).setNumber(777);
    }

    function test_DirectExecuteThroughSenderCoordinator() public {
        bytes32 senderId = keccak256(abi.encodePacked(SENDER_NAME));
        Transaction memory txn = Transaction({
            to: address(counter),
            data: abi.encodeWithSelector(Counter.setNumber.selector, 333),
            value: 0
        });

        SimulatedTransaction memory result = harness.execute(senderId, txn);
        assertEq(counter.number(), 333);
        assertEq(result.returnData.length, 0);
    }

    function test_RevertWithDataPropagation() public {
        RevertTestContract revertContract = new RevertTestContract();
        address revertHarness = harness.getHarness(SENDER_NAME, address(revertContract));

        vm.expectRevert(abi.encodeWithSelector(RevertTestContract.CustomError.selector, 123, "custom error"));
        RevertTestContract(revertHarness).failWithCustomError();

        vm.expectRevert("require message");
        RevertTestContract(revertHarness).failWithRequire();
    }

    function test_ViewFunctionWorks() public {
        ViewTestContract viewContract = new ViewTestContract();
        address viewHarness = harness.getHarness(SENDER_NAME, address(viewContract));

        assertTrue(ViewTestContract(viewHarness).isView());
        assertEq(ViewTestContract(viewHarness).compute(10, 20), 30);
    }
}

contract RevertTestContract {
    error CustomError(uint256 code, string message);

    function failWithCustomError() public pure {
        revert CustomError(123, "custom error");
    }

    function failWithRequire() public pure {
        require(false, "require message");
    }
}

contract ViewTestContract {
    function isView() public pure returns (bool) {
        return true;
    }

    function compute(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }
}
