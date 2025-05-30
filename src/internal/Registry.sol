// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title Registry
 * @notice Onchain registry for deployment addresses across environments
 * @dev Reads deployment information from deployments.json to provide address lookups
 */
contract Registry is Script {
    string public deploymentsFile;
    string public namespace;
    uint256 public chainId;

    /// @dev Maps deployment identifiers to contract addresses
    /// @dev Key format: "{chainId}/{namespace}/{identifier}" or "{identifier}"
    mapping(string => address) private deployments;

    constructor(string memory _namespace, string memory _deploymentsFile) {
        chainId = block.chainid;
        namespace = _namespace;
        deploymentsFile = _deploymentsFile;
        _loadDeployments();
    }

    /**
     * @notice Get deployment address by identifier
     * @param identifier Contract identifier (e.g., "Counter", "Counter:V2", "CounterProxy")
     * @return The deployment address, or address(0) if not found
     */
    function getDeployment(
        string memory identifier
    ) public view returns (address) {
        string memory fqId = _getFullyQualifiedId(identifier);
        address result = deployments[fqId];
        return result;
    }

    /**
     * @notice Get deployment address with explicit environment
     * @param identifier Contract identifier
     * @param environment Deployment environment
     * @return The deployment address, or address(0) if not found
     */
    function getDeploymentByEnv(
        string memory identifier,
        string memory environment
    ) public view returns (address) {
        string memory fqId = string.concat(
            vm.toString(chainId),
            "/",
            environment,
            "/",
            identifier
        );
        return deployments[fqId];
    }

    /**
     * @notice Check if a deployment exists
     * @param identifier Contract identifier
     * @return True if deployment exists
     */
    function hasDeployment(
        string memory identifier
    ) public view returns (bool) {
        return getDeployment(identifier) != address(0);
    }

    /**
     * @notice Get the fully qualified identifier for a contract
     * @param identifier Simple identifier
     * @return Fully qualified identifier in format: {chainId}/{env}/{identifier}
     */
    function getFullyQualifiedId(
        string memory identifier
    ) public view returns (string memory) {
        return _getFullyQualifiedId(identifier);
    }

    /**
     * @dev Load deployments from JSON file into memory
     * @dev Parses deployments.json and populates the deployments mapping with:
     *      - Fully qualified IDs (fqid): {chainId}/{namespace}/{identifier}
     *      - Short IDs (sid): {identifier} (only if not already taken)
     */
    function _loadDeployments() private {
        try vm.readFile(deploymentsFile) returns (string memory json) {
            string memory deploymentsPath = string.concat(
                ".networks.",
                vm.toString(chainId),
                ".deployments"
            );

            if (vm.keyExistsJson(json, deploymentsPath)) {
                string[] memory addresses = vm.parseJsonKeys(
                    json,
                    deploymentsPath
                );

                for (uint256 i = 0; i < addresses.length; i++) {
                    string memory addr = addresses[i];
                    string memory path = string.concat(
                        deploymentsPath,
                        ".",
                        addr
                    );
                    address parsedAddr = vm.parseAddress(addr);

                    try
                        vm.parseJsonString(json, string.concat(path, ".fqid"))
                    returns (string memory fqId) {
                        deployments[fqId] = parsedAddr;
                    } catch {
                        console.log("Warning: Could not parse fqid for", addr);
                    }

                    try
                        vm.parseJsonString(json, string.concat(path, ".sid"))
                    returns (string memory shortId) {
                        // Only register short ID if it's not already taken
                        // This prevents conflicts when multiple contracts have the same short ID
                        if (deployments[shortId] == address(0)) {
                            deployments[shortId] = parsedAddr;
                        }
                        // Note: We silently skip duplicate short IDs rather than logging warnings
                        // to avoid cluttering output in normal operation
                    } catch {
                        // Short ID is optional, so we don't log warnings for missing values
                    }
                }
            }
        } catch {
            console.log(
                "Warning: Could not load deployments from",
                deploymentsFile
            );
        }
    }

    /**
     * @dev Convert simple identifier to fully qualified identifier
     */
    function _getFullyQualifiedId(
        string memory identifier
    ) private view returns (string memory) {
        return
            string.concat(
                vm.toString(chainId),
                "/",
                namespace,
                "/",
                identifier
            );
    }
}
