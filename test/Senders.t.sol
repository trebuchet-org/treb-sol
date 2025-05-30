// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {PrivateKey, HardwareWallet, InMemory} from "../src/internal/sender/PrivateKeySender.sol";
import {GnosisSafe} from "../src/internal/sender/GnosisSafeSender.sol";
import {SenderTypes} from "../src/internal/types.sol";
import {SenderTestHarness} from "./helpers/SenderTestHarness.sol";

contract SendersRegistryTestHarness {
    function initialize(Senders.SenderInitConfig[] memory _configs) public {
        Senders.initialize(_configs);
    }
}

contract SendersTest is Test {
    mapping(string => SenderTestHarness) public senders;

    function initialize(Senders.SenderInitConfig[] memory _configs) public {
        for (uint256 i = 0; i < _configs.length; i++) {
            SenderTestHarness sender = new SenderTestHarness(_configs[i].name, _configs);
            senders[_configs[i].name] = sender;
        }
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
            config: abi.encode(0x1234)
        });
        initialize(configs);

        InMemory.Sender memory sender = senders["sender1"].getInMemory();

        assertEq(sender.name, "sender1");
        assertEq(sender.account, address(0x1234));
        assertEq(sender.senderType, SenderTypes.InMemory);
        assertEq(sender.config, abi.encode(0x1234));
        assertEq(sender.privateKey, 0x1234);
    }

    function test_RevertWhen_getPrivateKeyWithInvalidSenderType() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "sender1",
            account: address(0x1234),
            senderType: SenderTypes.Ledger,
            config: abi.encode("derivation-path")
        });
        initialize(configs);

        vm.expectRevert(abi.encodeWithSelector(Senders.InvalidCast.selector, "sender1", SenderTypes.Ledger, SenderTypes.InMemory));
        senders["sender1"].getInMemory();
    }
}