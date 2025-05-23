// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Operation.sol";

/**
 * @title CreateXDeployment  
 * @notice Base contract for deterministic deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract CreateXDeployment is Operation {
    /// @notice CreateX factory contract address
    address public constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    
    /// @notice Salt components for deterministic deployment
    string[] public saltComponents;
    
    constructor(
        string memory _contractName,
        string memory _version,
        string[] memory _saltComponents
    ) Operation(_contractName, _version) {
        saltComponents = _saltComponents;
    }
    
    /// @notice Generate deterministic salt from components
    function generateSalt() public view returns (bytes32) {
        string memory combined = "";
        for (uint i = 0; i < saltComponents.length; i++) {
            if (i > 0) combined = string.concat(combined, ".");
            combined = string.concat(combined, saltComponents[i]);
        }
        return keccak256(bytes(combined));
    }
    
    /// @notice Predict deployment address for given init code
    function predictAddress(bytes memory initCode) public view returns (address) {
        bytes32 salt = generateSalt();
        bytes32 initCodeHash = keccak256(initCode);
        
        // Use CREATE2 address calculation
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            CREATEX,
            salt,
            initCodeHash
        )))));
    }
    
    /// @notice Main deployment execution
    function run() public override {
        console2.log("=== CreateX Deployment ===");
        console2.log("Contract:", contractName);
        console2.log("Version:", label);
        
        // Get init code for address prediction
        bytes memory initCode = getInitCode();
        address predicted = predictAddress(initCode);
        
        console2.log("Predicted address:", predicted);
        
        // Check if already deployed
        address existingDeployment = getDeployed();
        if (existingDeployment != address(0)) {
            console2.log("✅ Deployment already exists at:", existingDeployment);
            return;
        }
        
        console2.log("🚀 Starting deployment...");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy using CREATE2 via CreateX-style call
        bytes32 salt = generateSalt();
        
        // Call CreateX factory to deploy
        (bool success, bytes memory returnData) = CREATEX.call(
            abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode)
        );
        
        require(success, "CreateXDeployment: Deployment failed");
        address deployed = abi.decode(returnData, (address));
        
        // Verify deployment matches prediction
        require(deployed == predicted, "CreateXDeployment: Address mismatch");
        
        vm.stopBroadcast();
        
        console2.log("✅ Deployed successfully at:", deployed);
        
        // Record deployment with enhanced metadata
        writeEnhancedDeployment(deployed, salt, initCode);
        
        console2.log("🎉 Deployment complete!");
    }
    
    /// @notice Get contract init code (constructor + args)
    /// @dev Must be implemented by child contracts
    function getInitCode() internal virtual returns (bytes memory);
    
    /// @notice Write enhanced deployment info to JSON
    function writeEnhancedDeployment(
        address deployment,
        bytes32 salt, 
        bytes memory initCode
    ) internal {
        string memory key = getLabel();
        string memory d = "__deployments__";
        
        // Parse existing deployments
        vm.serializeJson(d, chainDeployments);
        
        // Add deployment info
        vm.serializeAddress(d, string.concat(key, ".address"), deployment);
        vm.serializeString(d, string.concat(key, ".type"), "implementation");
        vm.serializeBytes32(d, string.concat(key, ".salt"), salt);
        vm.serializeBytes32(d, string.concat(key, ".initCodeHash"), keccak256(initCode));
        vm.serializeUint(d, string.concat(key, ".blockNumber"), block.number);
        vm.serializeUint(d, string.concat(key, ".timestamp"), block.timestamp);
        vm.serializeUint(d, string.concat(key, ".chainId"), block.chainid);
        
        // Add metadata
        vm.serializeString(d, string.concat(key, ".contractName"), contractName);
        vm.serializeString(d, string.concat(key, ".version"), label);
        
        // Finalize and write
        string memory newDeploymentsJson = vm.serializeString(d, string.concat(key, ".deployer"), vm.addr(deployerPrivateKey));
        
        // Ensure deployments directory exists
        vm.createDir("deployments", true);
        vm.writeJson(newDeploymentsJson, deploymentFile);
        
        console2.log("📄 Deployment recorded in:", deploymentFile);
    }
}