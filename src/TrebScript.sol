// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConfigurableTrebScript} from "./ConfigurableTrebScript.sol";
import {Senders} from "./internal/sender/Senders.sol";

/**
 * @title TrebScript
 * @author Trebuchet
 * @notice Base contract for all Treb deployment scripts, providing access to sender coordination and registry lookups
 * @dev Deployment scripts should inherit from this contract to gain access to coordinated transaction execution
 *      and the ability to reference previously deployed contracts through the registry.
 *
 *      This contract reads configuration from environment variables, making it suitable for use with treb-cli.
 *      For standalone usage without environment variables, use ConfigurableTrebScript instead.
 *
 *      Key capabilities:
 *      - Multi-sender coordination (EOA, hardware wallets, Safe multisig)
 *      - Deterministic deployments via CreateX integration
 *      - Cross-environment contract lookups through registry
 *      - Automatic transaction broadcasting and batching
 *
 *      Environment variables used:
 *      - SENDER_CONFIGS: ABI-encoded sender configurations for multi-sig/hardware wallet support
 *      - NAMESPACE: Deployment namespace (default: "default")
 *      - REGISTRY_FILE: Registry file path (default: ".treb/registry.json")
 *      - DRYRUN: Whether to execute in dry-run mode (default: false)
 *      - QUIET: Whether to suppress internal treb-cli parsing logs (default: false)
 */
abstract contract TrebScript is ConfigurableTrebScript {
    /**
     * @notice Initializes TrebScript by reading configuration from environment variables
     * @dev This constructor automatically reads all necessary configuration from environment variables,
     *      making it suitable for use with treb-cli which manages the environment setup.
     *
     *      Environment variables read:
     *      - SENDER_CONFIGS: ABI-encoded sender configurations for multi-sig/hardware wallet support
     *      - NAMESPACE: Deployment namespace (default: "default")
     *      - REGISTRY_FILE: Registry file path (default: ".treb/registry.json")
     *      - DRYRUN: Whether to execute in dry-run mode (default: false)
     *      - QUIET: Whether to suppress internal treb-cli parsing logs (default: false)
     */
    constructor()
        ConfigurableTrebScript(
            abi.decode(vm.envBytes("SENDER_CONFIGS"), (Senders.SenderInitConfig[])),
            vm.envOr("NAMESPACE", string("default")),
            vm.envString("NETWORK"),
            vm.envOr("REGISTRY_FILE", string(".treb/registry.json")),
            vm.envOr("DRYRUN", false),
            vm.envOr("QUIET", false)
        )
    {}
}
