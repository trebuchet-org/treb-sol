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
    
    /// @notice Deployment strategy (CREATE2 or CREATE3)
    DeployStrategy public strategy;
    
    /// @notice Deployment type (IMPLEMENTATION or PROXY)
    DeploymentType public deploymentType;
    
    /// @notice Target contract for proxy deployments
    string public targetContract;
    
    constructor(
        string memory _contractName,
        DeploymentType _deploymentType,
        DeployStrategy _strategy
    ) Operation(_contractName, "") {
        deploymentType = _deploymentType;
        strategy = _strategy;
        saltComponents = buildSaltComponents();
    }
    
    /// @notice Build salt components for deterministic deployment
    /// @dev Override this function to customize salt generation
    /// @return Array of string components used to generate the salt
    function buildSaltComponents() internal virtual returns (string[] memory) {
        if (deploymentType == DeploymentType.IMPLEMENTATION) {
            return buildImplementationSaltComponents();
        } else {
            return buildProxySaltComponents();
        }
    }
    
    /// @notice Build salt components for implementation deployments
    /// @return Array with contractName, env, and initCodeHash
    function buildImplementationSaltComponents() internal virtual returns (string[] memory) {
        string memory label = vm.envOr("DEPLOYMENT_LABEL", string(""));
        
        if (bytes(label).length > 0) {
            // With label: contractName, env, label, initCodeHash
            string[] memory components = new string[](4);
            components[0] = contractName;
            components[1] = vm.envOr("DEPLOYMENT_ENV", string("staging"));
            components[2] = label;
            components[3] = vm.toString(keccak256(getInitCode()));
            return components;
        } else {
            // Without label: contractName, env, initCodeHash
            string[] memory components = new string[](3);
            components[0] = contractName;
            components[1] = vm.envOr("DEPLOYMENT_ENV", string("staging"));
            components[2] = vm.toString(keccak256(getInitCode()));
            return components;
        }
    }
    
    /// @notice Build salt components for proxy deployments
    /// @return Array with targetContract, label, and env
    function buildProxySaltComponents() internal view virtual returns (string[] memory) {
        string[] memory components = new string[](3);
        components[0] = targetContract;
        components[1] = vm.envOr("PROXY_LABEL", string("main"));
        components[2] = vm.envOr("DEPLOYMENT_ENV", string("staging"));
        return components;
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
    
    /// @notice Generate guarded salt for enhanced security with CreateX
    /// @dev Uses CreateX's guarded salt implementation to prevent front-running
    function generateGuardedSalt() public view returns (bytes32) {
        bytes32 baseSalt = generateSalt();
        address deployer = vm.addr(deployerPrivateKey);
        
        // Create guarded salt: keccak256(deployer + baseSalt)
        // This ensures only the intended deployer can use this salt
        return keccak256(abi.encodePacked(deployer, baseSalt));
    }
    
    /// @notice Predict deployment address based on strategy
    function predictAddress(bytes memory initCode) public view returns (address) {
        bytes32 salt = generateGuardedSalt();
        address actualDeployer = vm.addr(deployerPrivateKey);
        
        if (strategy == DeployStrategy.CREATE3) {
            return _predictCreate3Address(salt, actualDeployer);
        } else {
            return _predictCreate2Address(salt, actualDeployer, initCode);
        }
    }
    
    /// @notice Get deployed address for a specific contract and environment
    /// @dev Used by proxy deployments to reference implementation contracts
    function getDeployedAddress(string memory _contractName, string memory _env) internal view returns (address) {
        string memory key = string.concat(_contractName, "_", _env);
        string memory artifactFile = string.concat(deploymentDir, "/", key, ".json");
        
        try vm.readFile(artifactFile) returns (string memory deploymentJson) {
            try vm.parseJsonAddress(deploymentJson, ".address") returns (address addr) {
                return addr;
            } catch {
                revert(string.concat("Failed to parse address from deployment file: ", artifactFile));
            }
        } catch {
            revert(string.concat("Deployment file not found: ", artifactFile, ". Deploy ", _contractName, " first."));
        }
    }
    
    /// @notice Predict CREATE3 address
    function _predictCreate3Address(bytes32 salt, address deployer) internal view returns (address) {
        // Use CreateX's computeCreate3Address function for accurate prediction
        (bool success, bytes memory result) = CREATEX.staticcall(
            abi.encodeWithSignature("computeCreate3Address(bytes32,address)", salt, deployer)
        );
        
        if (success) {
            return abi.decode(result, (address));
        }
        
        // Fallback to standard CREATE3 calculation
        bytes32 proxyCodeHash = keccak256(hex"67363d3d37363d34f03d5260086018f3");
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            proxyCodeHash
        )))));
    }
    
    /// @notice Predict CREATE2 address  
    function _predictCreate2Address(bytes32 salt, address, bytes memory initCode) internal view returns (address) {
        // Use CreateX's computeCreate2Address function for accurate prediction
        bytes32 initCodeHash = keccak256(initCode);
        (bool success, bytes memory result) = CREATEX.staticcall(
            abi.encodeWithSignature("computeCreate2Address(bytes32,bytes32)", salt, initCodeHash)
        );
        
        if (success) {
            return abi.decode(result, (address));
        }
        
        // Fallback to standard CREATE2 calculation
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
        console2.log("Type:", deploymentType == DeploymentType.IMPLEMENTATION ? "IMPLEMENTATION" : "PROXY");
        console2.log("Strategy:", strategy == DeployStrategy.CREATE3 ? "CREATE3" : "CREATE2");
        
        if (deploymentType == DeploymentType.PROXY) {
            console2.log("Target:", targetContract);
        }
        
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
        
        // Deploy using strategy-specific method with guarded salt
        bytes32 salt = generateGuardedSalt();
        bytes memory deployData;
        
        if (strategy == DeployStrategy.CREATE3) {
            // Deploy using CreateX deployCreate3 function with guarded salt
            deployData = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", 
                salt, initCode);
        } else {
            // Deploy using CreateX deployCreate2 function with guarded salt  
            deployData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", 
                salt, initCode);
        }
        
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
    
    /// @notice Get init code from compiler artifacts (cross-version compatibility)
    function getInitCodeFromArtifacts(string memory contractName) internal view returns (bytes memory) {
        // Try to read from out/ directory (Foundry compilation artifacts)
        string memory artifactPath = string.concat("out/", contractName, ".sol/", contractName, ".json");
        
        try vm.readFile(artifactPath) returns (string memory artifactJson) {
            // Parse the JSON to extract bytecode string
            try vm.parseJsonString(artifactJson, ".bytecode.object") returns (string memory bytecodeStr) {
                if (bytes(bytecodeStr).length > 0) {
                    // Add 0x prefix if not present
                    if (bytes(bytecodeStr).length >= 2 && bytes(bytecodeStr)[0] == "0" && bytes(bytecodeStr)[1] == "x") {
                        return vm.parseBytes(bytecodeStr);
                    } else {
                        return vm.parseBytes(string.concat("0x", bytecodeStr));
                    }
                }
            } catch {
                console2.log("Failed to parse bytecode from artifact");
            }
        } catch {
            console2.log("Warning: Could not read artifact for", contractName);
        }
        
        return "";
    }
    
    /// @notice Write enhanced deployment info to individual JSON file
    function writeEnhancedDeployment(
        address deployment,
        bytes32 salt, 
        bytes memory initCode
    ) internal {
        string memory key = getLabel();
        string memory deploymentObject = "deployment";
        
        // Build deployment artifact for debugging (optional)
        if (vm.envOr("WRITE_DEPLOYMENT_ARTIFACTS", false)) {
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
            
            console2.log("Deployment artifact written to:", artifactFile);
        }
        
        // Output structured data for CLI parsing
        console2.log("");
        console2.log("=== DEPLOYMENT_RESULT ===");
        console2.log(string.concat("ADDRESS:", vm.toString(deployment)));
        console2.log(string.concat("SALT:", vm.toString(salt)));
        console2.log(string.concat("INIT_CODE_HASH:", vm.toString(keccak256(initCode))));
        console2.log(string.concat("CONTRACT_NAME:", contractName));
        console2.log(string.concat("DEPLOYMENT_TYPE:", deploymentType == DeploymentType.IMPLEMENTATION ? "IMPLEMENTATION" : "PROXY"));
        console2.log(string.concat("STRATEGY:", strategy == DeployStrategy.CREATE3 ? "CREATE3" : "CREATE2"));
        console2.log(string.concat("CHAIN_ID:", vm.toString(block.chainid)));
        console2.log(string.concat("BLOCK_NUMBER:", vm.toString(block.number)));
        
        if (deploymentType == DeploymentType.PROXY) {
            console2.log(string.concat("TARGET_CONTRACT:", targetContract));
            console2.log(string.concat("PROXY_LABEL:", vm.envOr("PROXY_LABEL", string("main"))));
        }
        
        // Output label if present (for both implementations and proxies)
        string memory deploymentLabel = vm.envOr("DEPLOYMENT_LABEL", string(""));
        if (bytes(deploymentLabel).length > 0) {
            console2.log(string.concat("LABEL:", deploymentLabel));
        }
        
        console2.log("=== END_DEPLOYMENT ===");
        console2.log("");
    }
}