// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../../src/v2/internal/sender/Senders.sol";
import {SenderTypes, Transaction} from "../../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

contract SendersRegistryTestHarness {
    function initialize(string[] memory _names, address[] memory _accounts) public {
        Senders.initialize(_names, _accounts, "default", "sepolia", false);
    }
}

contract V2SendersTest is Test {
    SendersTestHarness harness;

    function initialize(string[] memory _names, address[] memory _accounts) internal {
        harness = new SendersTestHarness(_names, _accounts);
    }

    function test_RevertWhen_initializeWithNoSenders() public {
        SendersRegistryTestHarness registry = new SendersRegistryTestHarness();
        vm.expectRevert(abi.encodeWithSelector(Senders.NoSenders.selector));
        registry.initialize(new string[](0), new address[](0));
    }

    function test_initialize() public {
        string[] memory names = new string[](1);
        address[] memory accounts = new address[](1);
        names[0] = "sender1";
        accounts[0] = address(0x1234);
        initialize(names, accounts);

        Senders.Sender memory s = harness.get("sender1");
        assertEq(s.name, "sender1");
        assertEq(s.account, address(0x1234));
    }

    function test_initializeMultipleSenders() public {
        string[] memory names = new string[](3);
        address[] memory accounts = new address[](3);
        names[0] = "deployer";  accounts[0] = address(0x1);
        names[1] = "safe";      accounts[1] = address(0x2);
        names[2] = "governor";  accounts[2] = address(0x3);
        initialize(names, accounts);

        assertEq(harness.getSenderAccount("deployer"), address(0x1));
        assertEq(harness.getSenderAccount("safe"), address(0x2));
        assertEq(harness.getSenderAccount("governor"), address(0x3));
    }

    function test_RevertWhen_getSenderNotInitialized() public {
        string[] memory names = new string[](1);
        address[] memory accounts = new address[](1);
        names[0] = "deployer";
        accounts[0] = address(0x1);
        initialize(names, accounts);

        vm.expectRevert(abi.encodeWithSelector(Senders.SenderNotInitialized.selector, "nonexistent"));
        harness.get("nonexistent");
    }
}
