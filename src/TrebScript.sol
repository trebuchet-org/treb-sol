// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SenderCoordinator} from "./internal/SenderCoordinator.sol";
import {Registry} from "./internal/Registry.sol";
import {Deployer} from "./internal/sender/Deployer.sol";
import {Senders} from "./internal/sender/Senders.sol";

abstract contract TrebScript is SenderCoordinator, Registry {
    constructor() Registry(
        vm.envOr("NAMESPACE", string("default")), 
        vm.envOr("DEPLOYMENTS_FILE", string(".treb/registry.json"))
    ) SenderCoordinator(
        vm.envBytes("SENDER_CONFIGS"),
        vm.envOr("NAMESPACE", string("default")),
        vm.envOr("DRYRUN", false)
    ) {}
}
