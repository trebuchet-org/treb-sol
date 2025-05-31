// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SenderCoordinator} from "./internal/SenderCoordinator.sol";
import {Registry} from "./internal/Registry.sol";
import {Deployer} from "./internal/sender/Deployer.sol";
import {Senders} from "./internal/sender/Senders.sol";

/**
 * @title ConfigurableTrebScript
 * @author Trebuchet
 * @notice Configurable base contract for deployment scripts that don't rely on environment variables
 * @dev This contract provides the same functionality as TrebScript but allows manual configuration
 *      of all parameters, making it suitable for use outside of treb-cli or in environments where
 *      you want explicit control over sender configurations and registry settings.
 *
 *      Unlike TrebScript which reads from environment variables, ConfigurableTrebScript requires
 *      all configuration to be passed explicitly through constructor parameters. This makes it
 *      ideal for:
 *      - Standalone usage without treb-cli
 *      - Testing environments with custom configurations
 *      - Integration with other deployment frameworks
 *      - Scenarios where environment variables are not desired
 *
 *      Example usage:
 *      ```solidity
 *      contract MyDeployment is ConfigurableTrebScript {
 *          constructor() ConfigurableTrebScript(
 *              _getSenderConfigs(),     // Custom sender configuration
 *              "production",            // Namespace
 *              "deployments.json",      // Registry file
 *              false                    // Not dry run
 *          ) {}
 *
 *          function _getSenderConfigs() internal pure returns (Senders.SenderInitConfig[] memory) {
 *              // Define your sender configurations here
 *          }
 *      }
 *      ```
 */
abstract contract ConfigurableTrebScript is SenderCoordinator, Registry {
    /**
     * @notice Initializes the configurable deployment script with explicit parameters
     * @param senderInitConfigs Array of sender configurations defining available transaction senders
     * @param namespace Deployment namespace (e.g., "default", "staging", "production")
     * @param registryFilename Path to the registry JSON file for deployment lookups
     * @param dryrun Whether to run in dry-run mode (simulate without executing transactions)
     * @dev This constructor provides complete control over all configuration parameters,
     *      making it suitable for use cases where environment variable configuration is not desired.
     */
    constructor(
        Senders.SenderInitConfig[] memory senderInitConfigs,
        string memory namespace,
        string memory registryFilename,
        bool dryrun
    )
        Registry(namespace, registryFilename)
        SenderCoordinator(senderInitConfigs, namespace, dryrun)
    {}
}

/**
 * @title TrebScript
 * @author Trebuchet
 * @notice Base contract for all Trebuchet deployment scripts, providing unified access to sender coordination and registry lookups
 * @dev Extends SenderCoordinator for multi-sig and hardware wallet support, and Registry for deployment address lookups.
 *      Deployment scripts should inherit from this contract to gain access to coordinated transaction execution
 *      and the ability to reference previously deployed contracts through the registry.
 */
abstract contract TrebScript is ConfigurableTrebScript {
    /**
     * @notice Initializes the base deployment script with sender coordination and registry capabilities
     * @dev Reads configuration from environment variables:
     *      - NAMESPACE: Deployment namespace (default: "default")
     *      - DEPLOYMENTS_FILE: Path to registry JSON file (default: ".treb/registry.json")
     *      - SENDER_CONFIGS: ABI-encoded sender configurations for multi-sig/hardware wallet support
     *      - DRYRUN: Whether to execute in dry-run mode (default: false)
     */
    constructor()
        ConfigurableTrebScript(
            abi.decode(
                vm.envBytes("SENDER_CONFIGS"),
                (Senders.SenderInitConfig[])
            ),
            vm.envOr("NAMESPACE", string("default")),
            vm.envOr("REGISTRY_FILE", string(".treb/registry.json")),
            vm.envOr("DRYRUN", false)
        )
    {}
}
