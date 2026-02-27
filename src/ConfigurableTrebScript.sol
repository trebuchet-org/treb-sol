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
 *              "sepolia",               // Network
 *              "deployments.json",      // Registry file
 *              "addressbook.json",      // Addressbook file
 *              false,                   // Not dry run
 *              false,                   // Not quiet mode
 *              false                    // Not fork mode
 *          ) {}
 *
 *          function _getSenderConfigs() internal pure returns (Senders.SenderInitConfig[] memory) {
 *              // Define your sender configurations here
 *          }
 *      }
 *      ```
 */
abstract contract ConfigurableTrebScript is SenderCoordinator, Registry {
    /// @notice Whether the script is running in fork mode (against a local anvil fork)
    bool public isForkMode;

    /**
     * @notice Initializes the configurable deployment script with explicit parameters
     * @param senderInitConfigs Array of sender configurations defining available transaction senders
     * @param namespace Deployment namespace (e.g., "default", "staging", "production")
     * @param network Network name
     * @param registryFilename Path to the registry JSON file for deployment lookups
     * @param addressbookFilename Path to the addressbook JSON file
     * @param dryrun Whether to run in dry-run mode (simulate without executing transactions)
     * @param quiet Whether to suppress internal treb-cli parsing logs (reduces trace pollution)
     * @param _isForkMode Whether the script is running against a local anvil fork via treb fork mode
     * @dev This constructor provides complete control over all configuration parameters,
     *      making it suitable for use cases where environment variable configuration is not desired.
     */
    constructor(
        Senders.SenderInitConfig[] memory senderInitConfigs,
        string memory namespace,
        string memory network,
        string memory registryFilename,
        string memory addressbookFilename,
        bool dryrun,
        bool quiet,
        bool _isForkMode
    )
        Registry(namespace, registryFilename, addressbookFilename)
        SenderCoordinator(senderInitConfigs, namespace, network, dryrun, quiet)
    {
        isForkMode = _isForkMode;
    }
}
