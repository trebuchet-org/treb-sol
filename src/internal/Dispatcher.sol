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
        _;
        _broadcast();
    }

    bool private initialized;
    bytes private rawConfigs;
    string private namespace;
    bool private dryrun;

    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun) {
        rawConfigs = _rawConfigs;
        namespace = _namespace;
        dryrun = _dryrun;
    }

    function _initialize() internal {
        if (rawConfigs.length == 0) {
            revert InvalidSenderConfigs();
        }
        Senders.SenderInitConfig[] memory configs = abi.decode(rawConfigs, (Senders.SenderInitConfig[]));
        if (configs.length == 0) {
            revert InvalidSenderConfigs();
        }

        Senders.initialize(configs, namespace, dryrun);
    }

    function sender(string memory _name) internal returns (Senders.Sender storage) {
        if (!initialized) {
            _initialize();
            initialized = true;
        }
        return Senders.registry().get(_name);
    }

    function _broadcast() internal {
        if (Senders.registry().dryrun) {
            return;
        }

        Senders.registry().broadcast();
    }
}