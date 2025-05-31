// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title Registry
 * @author treb
 * @notice On-chain registry for looking up deployment addresses across different environments and chains
 * @dev This contract provides a simple interface for querying deployment addresses from a JSON registry file.
 *      It's designed to work seamlessly with the treb deployment system, allowing contracts to discover
 *      addresses of their dependencies without hardcoding them.
 *
 *      The registry reads from a JSON file (typically `.treb/registry.json`) that contains deployment
 *      information organized by chain ID, environment/namespace, and contract identifier.
 *
 *      Registry JSON Format:
 *      ```json
 *      {
 *        "1337": {                    // Chain ID
 *          "default": {               // Environment/namespace
 *            "Counter": "0x123...",   // Contract identifier -> address
 *            "Counter:V2": "0x456...",
 *            "CounterProxy#abc123": "0x789..."
 *          },
 *          "staging": {
 *            "Counter": "0xabc..."
 *          }
 *        },
 *        "11155111": {                // Sepolia chain ID
 *          "production": {
 *            "Counter": "0xdef..."
 *          }
 *        }
 *      }
 *      ```
 *
 *      Example usage in deployment scripts:
 *      ```solidity
 *      Registry registry = new Registry("default", ".treb/registry.json");
 *
 *      // Look up in current namespace and chain
 *      address counter = registry.lookup("Counter");
 *
 *      // Look up in specific environment
 *      address stagingCounter = registry.lookup("Counter", "staging");
 *
 *      // Look up in specific environment and chain
 *      address mainnetCounter = registry.lookup("Counter", "production", "1");
 *      ```
 */
contract Registry is Script {
    /// @notice The loaded registry JSON content
    string private registryJSON;

    /// @notice The default namespace/environment for lookups
    string private namespace;

    /// @notice The current chain ID as a string
    string private chainId;

    /**
     * @notice Initializes the registry with a namespace and registry file path
     * @param _namespace The default namespace to use for lookups (e.g., "default", "staging", "production")
     * @param _registryJSONFile Path to the registry JSON file (typically ".treb/registry.json")
     * @dev If the registry file cannot be loaded, the contract will initialize with an empty registry
     *      and lookups will return address(0). This allows deployment scripts to continue even if
     *      the registry is not yet populated.
     */
    constructor(string memory _namespace, string memory _registryJSONFile) {
        chainId = vm.toString(block.chainid);
        namespace = _namespace;
        try vm.readFile(_registryJSONFile) returns (string memory _registryJSON) {
            registryJSON = _registryJSON;
        } catch {
            console.log("Registry: failed to load registry from", _registryJSONFile);
            registryJSON = "{}";
        }
    }

    /**
     * @notice Look up a deployment address using the current namespace and chain
     * @param _identifier The contract identifier to look up
     * @return The deployment address, or address(0) if not found
     * @dev This is the most common lookup method, using the namespace and chain ID from construction.
     *
     *      Contract identifiers can take several forms:
     *      - Simple name: "Counter"
     *      - Name with label: "Counter:V2"
     *      - Name with hash suffix: "CounterProxy#d241asf"
     *
     *      Example:
     *      ```solidity
     *      address counterAddr = registry.lookup("Counter");
     *      require(counterAddr != address(0), "Counter not deployed");
     *      ```
     */
    function lookup(string memory _identifier) public view returns (address) {
        return lookup(_identifier, namespace, chainId);
    }

    /**
     * @notice Look up a deployment address in a specific environment
     * @param _identifier The contract identifier to look up
     * @param _env The environment/namespace to search in (e.g., "default", "staging", "production")
     * @return The deployment address, or address(0) if not found
     * @dev Use this when you need to reference deployments from a different environment than the current one.
     *
     *      Example:
     *      ```solidity
     *      // Get the production version while deploying to staging
     *      address prodCounter = registry.lookup("Counter", "production");
     *      ```
     */
    function lookup(string memory _identifier, string memory _env) public view returns (address) {
        return lookup(_identifier, _env, chainId);
    }

    /**
     * @notice Look up a deployment address with full specification of environment and chain
     * @param _identifier The contract identifier to look up
     * @param _env The environment/namespace to search in
     * @param _chainId The chain ID to search in (as a string, e.g., "1" for mainnet, "11155111" for Sepolia)
     * @return The deployment address, or address(0) if not found
     * @dev This is the most flexible lookup method, allowing cross-chain and cross-environment lookups.
     *
     *      The lookup path in the JSON is: `.<chainId>.<env>.<identifier>`
     *
     *      Fallback behavior:
     *      - If the exact path is not found, returns address(0)
     *      - Logs the failed lookup for debugging
     *      - Does not throw, allowing scripts to handle missing deployments gracefully
     *
     *      Example:
     *      ```solidity
     *      // Reference a mainnet deployment while on testnet
     *      address mainnetToken = registry.lookup("Token", "production", "1");
     *
     *      // Check if a deployment exists before using it
     *      address maybeDeploy = registry.lookup("OptionalDep", "staging", "11155111");
     *      if (maybeDeploy != address(0)) {
     *          // Use the deployment
     *      }
     *      ```
     */
    function lookup(string memory _identifier, string memory _env, string memory _chainId)
        public
        view
        returns (address)
    {
        try vm.parseJsonAddress(registryJSON, string.concat(".", _chainId, ".", _env, ".", _identifier)) returns (
            address result
        ) {
            return result;
        } catch {
            console.log("Registry: lookup failed for", _chainId, _env, _identifier);
            return address(0);
        }
    }
}
