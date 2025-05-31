// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SenderCoordinator} from "./internal/SenderCoordinator.sol";
import {Registry} from "./internal/Registry.sol";
import {Deployer} from "./internal/sender/Deployer.sol";
import {Senders} from "./internal/sender/Senders.sol";

/**
 * @title TrebScript
 * @author Trebuchet
 * @notice Base contract for all Trebuchet deployment scripts, providing unified access to sender coordination and registry lookups
 * @dev Extends SenderCoordinator for multi-sig and hardware wallet support, and Registry for deployment address lookups.
 *      Deployment scripts should inherit from this contract to gain access to coordinated transaction execution
 *      and the ability to reference previously deployed contracts through the registry.
 */
abstract contract TrebScript is SenderCoordinator, Registry {
    /**
     * @notice Initializes the base deployment script with sender coordination and registry capabilities
     * @dev Reads configuration from environment variables:
     *      - NAMESPACE: Deployment namespace (default: "default")
     *      - DEPLOYMENTS_FILE: Path to registry JSON file (default: ".treb/registry.json")
     *      - SENDER_CONFIGS: ABI-encoded sender configurations for multi-sig/hardware wallet support
     *      - DRYRUN: Whether to execute in dry-run mode (default: false)
     */
    constructor() Registry(
        vm.envOr("NAMESPACE", string("default")), 
        vm.envOr("DEPLOYMENTS_FILE", string(".treb/registry.json"))
    ) SenderCoordinator(
        vm.envBytes("SENDER_CONFIGS"),
        vm.envOr("NAMESPACE", string("default")),
        vm.envOr("DRYRUN", false)
    ) {}
}
