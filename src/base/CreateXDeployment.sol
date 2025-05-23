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
    
    /// @notice Predict deployment address for given init code (CREATE3)
    function predictAddress(bytes memory initCode) public view returns (address) {
        bytes32 salt = generateSalt();
        
        // Use CreateX's computeCreate3Address function for accurate prediction
        // CREATE3 only depends on salt and deployer, not init code
        (bool success, bytes memory result) = CREATEX.staticcall(
            abi.encodeWithSignature("computeCreate3Address(bytes32,address)", salt, address(this))
        );
        
        if (success) {
            return abi.decode(result, (address));
        }
        
        // Fallback to standard CREATE3 calculation if CreateX call fails
        // CREATE3: keccak256(0xff || deployer || salt || keccak256(proxy_init_code))
        bytes32 proxyCodeHash = keccak256(hex"67363d3d37363d34f03d5260086018f3");
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            proxyCodeHash
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
            console2.log("Deployment already exists at:", existingDeployment);
            return;
        }
        
        console2.log("Starting deployment...");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy using CREATE3 via CreateX
        bytes32 salt = generateSalt();
        
        // Deploy using CreateX deployCreate3 function
        bytes memory deployData = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode);
        (bool success, bytes memory returnData) = CREATEX.call(deployData);
        
        require(success, "CreateXDeployment: Deployment failed");
        address deployed = abi.decode(returnData, (address));
        
        // Log prediction vs actual for debugging
        if (deployed != predicted) {
            console2.log("Warning: Predicted address differs from actual deployment");
            console2.log("Predicted:", predicted);
            console2.log("Actual:", deployed);
        }
        
        vm.stopBroadcast();
        
        console2.log("Deployed successfully at:", deployed);
        
        // Record deployment with enhanced metadata
        writeEnhancedDeployment(deployed, salt, initCode);
        
        console2.log("Deployment complete!");
    }
    
    /// @notice Get contract init code (constructor + args)
    /// @dev Must be implemented by child contracts
    function getInitCode() internal virtual returns (bytes memory);
    
    /// @notice Write enhanced deployment info to individual JSON file
    function writeEnhancedDeployment(
        address deployment,
        bytes32 salt, 
        bytes memory initCode
    ) internal {
        string memory key = getLabel();
        string memory deploymentObject = "deployment";
        
        // Build deployment artifact as nested object
        vm.serializeAddress(deploymentObject, "address", deployment);
        vm.serializeString(deploymentObject, "type", "implementation");
        vm.serializeBytes32(deploymentObject, "salt", salt);
        vm.serializeBytes32(deploymentObject, "initCodeHash", keccak256(initCode));
        vm.serializeUint(deploymentObject, "blockNumber", block.number);
        vm.serializeUint(deploymentObject, "timestamp", block.timestamp);
        vm.serializeUint(deploymentObject, "chainId", block.chainid);
        vm.serializeString(deploymentObject, "contractName", contractName);
        vm.serializeString(deploymentObject, "version", label);
        string memory deploymentJson = vm.serializeAddress(deploymentObject, "deployer", vm.addr(deployerPrivateKey));
        
        // Create chain-specific directory
        string memory chainId = vm.toString(block.chainid);
        string memory chainDir = string.concat("deployments/", chainId);
        vm.createDir(chainDir, true);
        
        // Write individual deployment file
        string memory artifactFile = string.concat(chainDir, "/", key, ".json");
        vm.writeJson(deploymentJson, artifactFile);
        
        console2.log("Deployment recorded in:", artifactFile);
    }
}