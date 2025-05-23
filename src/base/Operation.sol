// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

enum DeployStrategy {
    CREATE2,
    CREATE3
}

enum DeploymentType {
    IMPLEMENTATION,
    PROXY
}

/**
 * @title Operation
 * @notice Base contract for all deployment operations
 * @dev Provides common functionality for deployment scripts
 */
abstract contract Operation is Script {
    /// @notice Name of the contract being deployed
    string public contractName;
    
    /// @notice Version or label for this deployment
    string public label;
    
    /// @notice Directory for deployments on this chain
    string public deploymentDir;
    
    /// @notice Private key for deployment (from environment)
    uint256 public deployerPrivateKey;

    constructor(string memory _contractName, string memory _label) {
        contractName = _contractName;
        label = _label;
        
        // Set up deployment directory path
        string memory chainId = vm.toString(block.chainid);
        deploymentDir = string.concat("deployments/", chainId);
        
        // Load deployer private key
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    /// @notice Get the deployment label (contract name + version)
    function getLabel() public view returns (string memory) {
        return string.concat(contractName, "_", label);
    }

    /// @notice Check if contract is already deployed
    function getDeployed() public view returns (address) {
        string memory key = getLabel();
        string memory artifactFile = string.concat(deploymentDir, "/", key, ".json");
        
        try vm.readFile(artifactFile) returns (string memory deploymentJson) {
            try vm.parseJsonAddress(deploymentJson, ".address") returns (address addr) {
                return addr;
            } catch {
                return address(0);
            }
        } catch {
            return address(0);
        }
    }

    /// @notice Main execution function - must be implemented by child contracts
    function run() public virtual;
}