// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SenderCoordinator} from "./internal/SenderCoordinator.sol";
import {Registry} from "./internal/Registry.sol";
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
 *              false,                   // Not dry run
 *              false                    // Not quiet mode
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
     * @param network Network name
     * @param registryFilename Path to the registry JSON file for deployment lookups
     * @param dryrun Whether to run in dry-run mode (simulate without executing transactions)
     * @param quiet Whether to suppress internal treb-cli parsing logs (reduces trace pollution)
     * @dev This constructor provides complete control over all configuration parameters,
     *      making it suitable for use cases where environment variable configuration is not desired.
     */
    constructor(
        Senders.SenderInitConfig[] memory senderInitConfigs,
        string memory namespace,
        string memory network,
        string memory registryFilename,
        bool dryrun,
        bool quiet
    ) Registry(namespace, registryFilename) SenderCoordinator(senderInitConfigs, namespace, network, dryrun, quiet) {}
}
