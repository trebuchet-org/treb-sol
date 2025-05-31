// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title Registry
 * @notice Onchain registry for deployment addresses across environments
 * @dev Reads deployment information from deployments.json to provide address lookups
 */
contract Registry is Script {
    string private registryJSON;
    string private namespace;
    string private chainId;

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
     * @notice Get deployment address by identifier
     * @param _identifier Contract identifier (e.g., "Counter", "Counter:V2", "CounterProxy#d241asf")
     * @return The deployment address, or address(0) if not found
     */
    function lookup(
        string memory _identifier
    ) public view returns (address) {
        return lookup(_identifier, namespace, chainId);
    }

    /**
     * @notice Get deployment address by identifier with explicit environment
     * @param _identifier Contract identifier (e.g., "Counter", "Counter:V2", "CounterProxy#d241asf")
     * @param _env Environment/namespace (e.g., "anvil", "staging")
     * @return The deployment address, or address(0) if not found
     */
    function lookup(
        string memory _identifier,
        string memory _env
    ) public view returns (address) {
        return lookup(_identifier, _env, chainId);
    }

    /**
     * @notice Get deployment address by identifier with explicit environment and chain
     * @param _identifier Contract identifier (e.g., "Counter", "Counter:V2", "CounterProxy#d241asf")
     * @param _env Environment/namespace (e.g., "anvil", "staging")
     * @param _chainId Chain ID (e.g., "1337")
     * @return The deployment address, or address(0) if not found
     */
    function lookup(
        string memory _identifier,
        string memory _env,
        string memory _chainId
    ) public view returns (address) {
        try vm.parseJsonAddress(registryJSON, string.concat(".", _chainId, ".", _env, ".", _identifier)) returns (address result) {
            return result;
        } catch {
            console.log("Registry: lookup failed for", _chainId, _env, _identifier);
            return address(0);
        }
    }
}
