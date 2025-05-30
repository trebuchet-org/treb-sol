// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Senders} from "./sender/Senders.sol";
import {Deployer} from "./sender/Deployer.sol";

contract Dispatcher is Script {
    error InvalidSenderConfigs();
    error SenderNotFound(string id);

    using Senders for Senders.Registry;
    using Senders for Senders.Sender;

    modifier broadcast() {
        uint256 snap = vm.snapshot();
        _;
        vm.revertTo(snap);
        _broadcast();
    }

    bool private initialized;

    function _initialize() internal {
        Senders.SenderInitConfig[] memory configs;
        try vm.envBytes("SENDER_CONFIGS") returns (bytes memory rawConfigs) {
            configs = abi.decode(rawConfigs, (Senders.SenderInitConfig[]));
        } catch {
            revert InvalidSenderConfigs();
        }
        Senders.registry().initialize(configs);
    }

    function sender(string memory _name) internal returns (Senders.Sender storage) {
        if (!initialized) {
            _initialize();
            initialized = true;
        }
        return Senders.registry().get(_name);
    }

    function _broadcast() internal {
        if (vm.envOr("DRYRUN", false) == true) {
            return;
        }

        Senders.registry().broadcast();
    }
}