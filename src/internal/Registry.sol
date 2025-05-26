// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

enum DeploymentStatus {
    PENDING_SAFE,
    DEPLOYED
}

/**
 * @title Registry
 * @notice Onchain registry for deployment addresses across environments
 * @dev Reads deployment information from deployments.json to provide address lookups
 */
contract Registry is Script {
    string public constant DEPLOYMENTS_FILE = "deployments.json";

    string public deploymentEnv;
    uint256 public chainId;

    mapping(string => address) private deployments;
    mapping(address => DeploymentStatus) private deploymentStatus;

    constructor() {
        deploymentEnv = vm.envOr("DEPLOYMENT_ENV", string("default"));
        chainId = block.chainid;

        _loadDeployments();
    }

    /**
     * @notice Get deployment address by identifier
     * @param identifier Contract identifier (e.g., "Counter", "Counter:V2", "CounterProxy")
     * @return The deployment address, or address(0) if not found
     */
    function getDeployment(string memory identifier) public view returns (address) {
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
    function getDeploymentByEnv(string memory identifier, string memory environment) public view returns (address) {
        string memory fqId = string.concat(vm.toString(chainId), "/", environment, "/", identifier);
        return deployments[fqId];
    }

    /**
     * @notice Check if a deployment exists
     * @param identifier Contract identifier
     * @return True if deployment exists
     */
    function hasDeployment(string memory identifier) public view returns (bool) {
        return getDeployment(identifier) != address(0);
    }

    /**
     * @notice Get the fully qualified identifier for a contract
     * @param identifier Simple identifier
     * @return Fully qualified identifier in format: {chainId}/{env}/{identifier}
     */
    function getFullyQualifiedId(string memory identifier) public view returns (string memory) {
        return _getFullyQualifiedId(identifier);
    }

    function getDeploymentStatus(address target) internal view returns (DeploymentStatus) {
        return deploymentStatus[target];
    }

    /**
     * @dev Load deployments from JSON file into memory
     */
    function _loadDeployments() private {
        try vm.readFile(DEPLOYMENTS_FILE) returns (string memory json) {
            string memory deploymentsPath = string.concat(".networks.", vm.toString(chainId), ".deployments");

            if (vm.keyExists(json, deploymentsPath)) {
                string[] memory addresses = vm.parseJsonKeys(json, deploymentsPath);

                for (uint256 i = 0; i < addresses.length; i++) {
                    string memory addr = addresses[i];
                    string memory path = string.concat(deploymentsPath, ".", addr);
                    address parsedAddr = vm.parseAddress(addr);

                    try vm.parseJsonString(json, string.concat(path, ".fqid")) returns (string memory fqId) {
                        deployments[fqId] = parsedAddr;
                    } catch {
                        console.log("Warning: Could not parse fqid for", addr);
                    }

                    try vm.parseJsonString(json, string.concat(path, ".sid")) returns (string memory shortId) {
                        if (deployments[shortId] != address(0)) {
                            console.log("Warning: Short ID already exists for", shortId, "at", deployments[shortId]);
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
            console.log("Warning: Could not load deployments from", DEPLOYMENTS_FILE);
        }
    }

    /**
     * @dev Convert simple identifier to fully qualified identifier
     */
    function _getFullyQualifiedId(string memory identifier) private view returns (string memory) {
        return string.concat(vm.toString(chainId), "/", deploymentEnv, "/", identifier);
    }
}
