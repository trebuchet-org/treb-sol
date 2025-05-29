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

    mapping(string => address) private deployments;

    constructor() {
        chainId = block.chainid;
        string memory defaultNamespace = "default";
        namespace = vm.envOr("NAMESPACE", defaultNamespace);
        deploymentsFile = vm.envOr("DEPLOYMENTS_FILE", string("deployments.json"));
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
        console.log("Registry lookup for:", fqId);
        address result = deployments[fqId];
        if (result != address(0)) {
            console.log("Found deployment at:", result);
        } else {
            console.log("No deployment found");
        }
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
                        if (deployments[shortId] != address(0)) {
                            console.log(
                                "Warning: Short ID already exists for",
                                shortId,
                                "at",
                                deployments[shortId]
                            );
                            deployments[shortId] = address(0);
                        } else {
                            deployments[shortId] = parsedAddr;
                        }
                    } catch {
                        console.log("Warning: Could not parse sid for", addr);
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
