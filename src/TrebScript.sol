// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Dispatcher} from "./internal/Dispatcher.sol";
import {Registry} from "./internal/Registry.sol";
import {Deployer} from "./internal/sender/Deployer.sol";
import {Senders} from "./internal/sender/Senders.sol";

abstract contract TrebScript is Dispatcher, Registry {
    constructor() Registry(
        vm.envOr("NAMESPACE", string("default")), 
        vm.envOr("DEPLOYMENTS_FILE", string("deployments.json"))
    ) Dispatcher(
        vm.envBytes("SENDER_CONFIGS"),
        vm.envOr("NAMESPACE", string("default")),
        vm.envOr("DRYRUN", false)
    ) {}
}
