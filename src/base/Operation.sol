// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

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
    
    /// @notice Path to the deployments file
    string public deploymentFile;
    
    /// @notice JSON object containing all deployments for the current chain
    string public chainDeployments;
    
    /// @notice Private key for deployment (from environment)
    uint256 public deployerPrivateKey;

    constructor(string memory _contractName, string memory _label) {
        contractName = _contractName;
        label = _label;
        
        // Set up deployment file path
        string memory chainId = vm.toString(block.chainid);
        deploymentFile = string.concat("deployments/", chainId, ".json");
        
        // Load existing deployments or create empty object
        try vm.readFile(deploymentFile) returns (string memory existing) {
            chainDeployments = existing;
        } catch {
            chainDeployments = "{}";
        }
        
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
        try vm.parseJsonAddress(chainDeployments, string.concat(".", key, ".address")) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    /// @notice Main execution function - must be implemented by child contracts
    function run() public virtual;
}