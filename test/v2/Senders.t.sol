// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../../src/v2/internal/sender/Senders.sol";
import {SenderTypes, Transaction} from "../../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

contract SendersRegistryTestHarness {
    function initialize(Senders.SenderInitConfig[] memory _configs) public {
        Senders.initialize(_configs, "default", "sepolia", false);
    }
}

contract V2SendersTest is Test {
    SendersTestHarness harness;

    function initialize(Senders.SenderInitConfig[] memory _configs) public {
        harness = new SendersTestHarness(_configs);
    }

    function test_RevertWhen_initializeWithNoSenders() public {
        SendersRegistryTestHarness registry = new SendersRegistryTestHarness();
        vm.expectRevert(abi.encodeWithSelector(Senders.NoSenders.selector));
        registry.initialize(new Senders.SenderInitConfig[](0));
    }

    function test_initialize() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "sender1",
            account: address(0x1234),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x1234)
        });
        initialize(configs);

        Senders.Sender memory s = harness.get("sender1");
        assertEq(s.name, "sender1");
        assertEq(s.account, address(0x1234));
        assertEq(s.senderType, SenderTypes.InMemory);
        assertEq(s.config, abi.encode(0x1234));
    }

    function test_initializeMultipleSenders() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](3);
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: address(0x1),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x1)
        });
        configs[1] = Senders.SenderInitConfig({
            name: "safe",
            account: address(0x2),
            senderType: SenderTypes.GnosisSafe,
            canBroadcast: true,
            config: ""
        });
        configs[2] = Senders.SenderInitConfig({
            name: "governor",
            account: address(0x3),
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: ""
        });
        initialize(configs);

        assertEq(harness.getSenderAccount("deployer"), address(0x1));
        assertEq(harness.getSenderAccount("safe"), address(0x2));
        assertEq(harness.getSenderAccount("governor"), address(0x3));

        assertTrue(harness.isType("deployer", SenderTypes.InMemory));
        assertTrue(harness.isType("safe", SenderTypes.GnosisSafe));
        assertTrue(harness.isType("governor", SenderTypes.OZGovernor));
    }

    function test_RevertWhen_executeWithoutBroadcastCapability() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "readOnly",
            account: address(0x1234),
            senderType: SenderTypes.Ledger,
            canBroadcast: false,
            config: abi.encode("m/44'/60'/0'/0/0")
        });
        initialize(configs);

        vm.expectRevert(abi.encodeWithSelector(Senders.CannotBroadcast.selector, "readOnly"));
        harness.execute(string("readOnly"), Transaction({to: address(0x1234), value: 0, data: ""}));
    }

    function test_RevertWhen_getSenderNotInitialized() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: address(0x1),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x1)
        });
        initialize(configs);

        vm.expectRevert(abi.encodeWithSelector(Senders.SenderNotInitialized.selector, "nonexistent"));
        harness.get("nonexistent");
    }
}
