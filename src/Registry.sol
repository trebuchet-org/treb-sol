// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

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
     * @param identifier Contract identifier (e.g., "Counter", "Counter:v2", "CounterProxy")
     * @return The deployment address, or address(0) if not found
     */
    function getDeployment(string memory identifier) public view returns (address) {
        string memory fqId = _getFullyQualifiedId(identifier);
        console2.log("Registry lookup for:", fqId);
        address result = deployments[fqId];
        if (result != address(0)) {
            console2.log("Found deployment at:", result);
        } else {
            console2.log("No deployment found");
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
            console2.log("Loading deployments from chain:", chainId);

            if (vm.keyExists(json, deploymentsPath)) {
                string[] memory addresses = vm.parseJsonKeys(json, deploymentsPath);
                console2.log("Found", addresses.length, "deployments");

                for (uint256 i = 0; i < addresses.length; i++) {
                    string memory addr = addresses[i];
                    string memory path = string.concat(deploymentsPath, ".", addr);
                    address parsedAddr = vm.parseAddress(addr);

                    if (
                        vm.keyExists(json, string.concat(path, ".contract_name"))
                            && vm.keyExists(json, string.concat(path, ".environment"))
                    ) {
                        string memory contractName = vm.parseJsonString(json, string.concat(path, ".contract_name"));
                        string memory environment = vm.parseJsonString(json, string.concat(path, ".environment"));
                        string memory deployType = vm.parseJsonString(json, string.concat(path, ".type"));

                        string memory baseIdentifier = contractName;

                        if (keccak256(bytes(deployType)) == keccak256(bytes("proxy"))) {
                            baseIdentifier = string.concat(contractName, "Proxy");
                        }

                        if (vm.keyExists(json, string.concat(path, ".label"))) {
                            string memory label = vm.parseJsonString(json, string.concat(path, ".label"));
                            if (bytes(label).length > 0) {
                                baseIdentifier = string.concat(baseIdentifier, ":", label);
                            }
                        }

                        if (
                            vm.keyExists(json, string.concat(path, ".deployment"))
                                && vm.keyExists(json, string.concat(path, ".deployment", ".status"))
                        ) {
                            string memory status = vm.parseJsonString(json, string.concat(path, ".deployment.status"));
                            bytes32 statusHash = keccak256(bytes(status));
                            if (statusHash == keccak256("pending_safe")) {
                                deploymentStatus[parsedAddr] = DeploymentStatus.PENDING_SAFE;
                            } else if (statusHash == keccak256("deployed")) {
                                deploymentStatus[parsedAddr] = DeploymentStatus.DEPLOYED;
                            } else {
                                console2.log("[WARN] Could not get deployment status, assuming DEPLOYED");
                                deploymentStatus[parsedAddr] = DeploymentStatus.DEPLOYED;
                            }
                        } else {
                            console2.log("[WARN] Could not get deployment status, assuming DEPLOYED");
                            deploymentStatus[parsedAddr] = DeploymentStatus.DEPLOYED;
                        }

                        string memory fqId = string.concat(vm.toString(chainId), "/", environment, "/", baseIdentifier);

                        console2.log("Storing deployment:", fqId);
                        console2.log("  Address:", addr);

                        deployments[fqId] = parsedAddr;
                    }
                }
            }
        } catch {
            console2.log("Warning: Could not load deployments from", DEPLOYMENTS_FILE);
        }
    }

    /**
     * @dev Convert simple identifier to fully qualified identifier
     */
    function _getFullyQualifiedId(string memory identifier) private view returns (string memory) {
        return string.concat(vm.toString(chainId), "/", deploymentEnv, "/", identifier);
    }
}
