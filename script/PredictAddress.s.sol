// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

/**
 * @title PredictAddress
 * @notice Script for predicting deployment addresses before actual deployment
 * @dev Used by fdeploy CLI to predict addresses for planning and verification
 */
contract PredictAddress is Script {
    /// @notice CreateX factory address
    address public constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    
    /// @notice Predict address for a contract deployment
    /// @param contractName Name of the contract to deploy
    /// @param environment Deployment environment (staging/prod)
    function predict(string memory contractName, string memory environment) public view {
        console2.log("=== Address Prediction ===");
        console2.log("Contract:", contractName);
        console2.log("Environment:", environment);
        
        // Get version from environment or default
        string memory version = vm.envOr("CONTRACT_VERSION", string("v0.1.0"));
        
        // Build salt components
        string memory saltString = string.concat(contractName, ".", version, ".", environment);
        bytes32 salt = keccak256(bytes(saltString));
        
        console2.log("Salt components:", saltString);
        console2.log("Generated salt:");
        console2.logBytes32(salt);
        
        // Get the actual deployer address (wallet that calls the script)
        address actualDeployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        
        console2.log("Using deployer address:", actualDeployer);
        
        // Predict address using CREATE3 (only depends on salt and deployer)
        // Use CreateX's computeCreate3Address function for accurate prediction
        (bool success, bytes memory result) = CREATEX.staticcall(
            abi.encodeWithSignature("computeCreate3Address(bytes32,address)", salt, actualDeployer)
        );
        
        address predicted;
        if (success) {
            predicted = abi.decode(result, (address));
        } else {
            // Fallback to standard CREATE3 calculation
            bytes32 proxyCodeHash = keccak256(hex"67363d3d37363d34f03d5260086018f3");
            predicted = address(uint160(uint(keccak256(abi.encodePacked(
                bytes1(0xff),
                actualDeployer,
                salt,
                proxyCodeHash
            )))));
        }
        
        console2.log("Predicted address:", predicted);
        console2.log("Chain ID:", block.chainid);
        
        // Output structured data for CLI parsing
        console2.log("=== PREDICTION_RESULT ===");
        console2.log("ADDRESS:", vm.toString(predicted));
        console2.log("SALT:", vm.toString(salt));
        console2.log("SALT_STRING:", saltString);
        console2.log("=== END_PREDICTION ===");
    }
    
    /// @notice Main script entry point
    function run() public {
        // Default prediction with environment variables
        string memory contractName = vm.envOr("CONTRACT_NAME", string("DefaultContract"));
        string memory environment = vm.envOr("DEPLOYMENT_ENV", string("staging"));
        
        predict(contractName, environment);
    }
}