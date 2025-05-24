// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./Executor.sol";
import "./Registry.sol";

enum DeployStrategy {
    CREATE2,
    CREATE3
}

enum DeploymentType {
    IMPLEMENTATION,
    PROXY
}

/**
 * @title CreateXDeployment
 * @notice Base contract for deterministic deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract CreateXDeployment is Executor, Registry {
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

    /// @notice Name of the contract being deployed
    string public contractName;

    /// @notice Label for this deployment
    string public deploymentLabel;

    constructor(string memory _contractName, DeploymentType _deploymentType, DeployStrategy _strategy)
        Registry()
        Executor()
    {
        contractName = _contractName;

        deploymentLabel = vm.envOr("DEPLOYMENT_LABEL", string(""));
        deploymentType = _deploymentType;
        strategy = _strategy;
        saltComponents = buildSaltComponents();
    }

    /// @notice Get the deployment label (contract name + version)
    function getIdentifier() public view returns (string memory _identifier) {
        _identifier = contractName;
        if (deploymentType == DeploymentType.PROXY) {
            _identifier = string.concat(_identifier, "Proxy");
        }
        if (bytes(deploymentLabel).length > 0) {
            _identifier = string.concat(_identifier, ":", deploymentLabel);
        }
    }

    /// @notice Check if deployment exists in registry
    function checkExistingDeployment() internal view returns (address existingAddress, bool isPending) {
        // Check if deployment exists
        address deployed = getDeployment(getIdentifier());
        if (deployed != address(0)) {
            // Check deployment status in the registry JSON
            string memory deploymentsPath = "deployments.json";
            try vm.readFile(deploymentsPath) returns (string memory json) {
                string memory statusPath = string.concat(
                    ".networks.",
                    vm.toString(block.chainid),
                    ".deployments.",
                    vm.toString(deployed),
                    ".deployment.status"
                );

                try vm.parseJsonString(json, statusPath) returns (string memory status) {
                    isPending = keccak256(bytes(status)) == keccak256(bytes("pending_safe"));
                } catch {
                    isPending = false;
                }
            } catch {
                isPending = false;
            }

            return (deployed, isPending);
        }

        return (address(0), false);
    }

    /// @notice Build salt components for deterministic deployment
    /// @dev Override this function to customize salt generation
    /// @return Array of string components used to generate the salt
    function buildSaltComponents() internal virtual returns (string[] memory) {
        string[] memory components = new string[](3);
        components[0] = getIdentifier();
        components[1] = vm.envOr("DEPLOYMENT_ENV", string("default"));
        return components;
    }

    /// @notice Generate deterministic salt from components, make it guarded.
    function generateSalt() public view returns (bytes32) {
        string memory combined = "";
        for (uint256 i = 0; i < saltComponents.length; i++) {
            if (i > 0) combined = string.concat(combined, ".");
            if (bytes(saltComponents[i]).length > 0) {
                combined = string.concat(combined, ".", saltComponents[i]);
            }
        }
        bytes32 entropy = keccak256(bytes(combined));
        // return entropy;
        return
            bytes32(
                abi.encodePacked(
                    getDeployerAddress(),
                    hex"00",
                    bytes11(uint88(uint256(entropy)))
                )
            );
    }

    /// @notice Predict deployment address
    function predictAddress() public {
        address predicted = _predictAddress(getInitCode());
        console2.log("Predicted Address:", predicted);
    }

    /// @notice Predict deployment address based on strategy
    function _predictAddress(bytes memory initCode) internal returns (address) {
        // Get the basic salt
        bytes32 salt = generateSalt();
        address deployer = getDeployerAddress();

        console2.log("Original salt:", vm.toString(salt));
        console2.log("Deployer address:", deployer);

        // Apply the same guard logic that CreateX will apply
        // Check if salt starts with deployer address (msg.sender)
        address saltAddress = address(bytes20(salt));
        bytes1 saltFlag = salt[20];
        
        bytes32 guardedSalt;
        if (saltAddress == deployer && saltFlag == hex"00") {
            // CreateX will use _efficientHash(msg.sender, salt)
            // which is keccak256(abi.encodePacked(msg.sender, salt))
            guardedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), salt));
        } else if (saltAddress == deployer && saltFlag == hex"01") {
            // Permissioned + cross-chain protection
            guardedSalt = keccak256(abi.encode(deployer, block.chainid, salt));
        } else {
            // For other patterns, CreateX hashes the salt
            guardedSalt = keccak256(abi.encode(salt));
        }
        console2.log("Guarded salt:", vm.toString(guardedSalt));

        if (strategy == DeployStrategy.CREATE3) {
            // Use the guarded salt for prediction
            return _predictCreate3Address(guardedSalt, deployer);
        } else {
            // Use the guarded salt for prediction
            return _predictCreate2Address(guardedSalt, deployer, initCode);
        }
    }

    /// @notice Predict CREATE3 address
    function _predictCreate3Address(bytes32 salt, address deployer) internal returns (address) {
        // Use CreateX's computeCreate3Address function for accurate prediction
        // This will handle the salt guarding internally
        (bool success, bytes memory result) = CREATEX.staticcall(
            abi.encodeWithSignature(
                "computeCreate3Address(bytes32,address)",
                salt,
                CREATEX // Use CreateX as the deployer since that's what will deploy
            )
        );

        if (success) {
            return abi.decode(result, (address));
        }

        // Fallback should not be needed but keep for safety
        revert("CreateXDeployment: Failed to predict CREATE3 address");
    }

    /// @notice Predict CREATE2 address
    function _predictCreate2Address(bytes32 salt, address, bytes memory initCode) internal view returns (address) {
        // Use CreateX's computeCreate2Address function for accurate prediction
        // This will handle the salt guarding internally
        bytes32 initCodeHash = keccak256(initCode);
        (bool success, bytes memory result) =
            CREATEX.staticcall(abi.encodeWithSignature("computeCreate2Address(bytes32,bytes32)", salt, initCodeHash));

        if (success) {
            return abi.decode(result, (address));
        }

        // Fallback should not be needed but keep for safety
        revert("CreateXDeployment: Failed to predict CREATE2 address");
    }

    /// @notice Main deployment execution
    function run() public virtual {
        console2.log("=== CreateX Deployment ===");
        console2.log("Contract:", contractName);
        console2.log("Type:", deploymentType == DeploymentType.IMPLEMENTATION ? "IMPLEMENTATION" : "PROXY");
        console2.log("Strategy:", strategy == DeployStrategy.CREATE3 ? "CREATE3" : "CREATE2");

        if (deploymentType == DeploymentType.PROXY) {
            console2.log("Target:", targetContract);
        }

        // Configure deployer based on environment
        string memory environment = vm.envOr("DEPLOYMENT_ENV", string("default"));
        configureDeployer(environment);

        // Get init code for address prediction
        bytes memory initCode = getInitCode();
        address predicted = _predictAddress(initCode);

        console2.log("Predicted address:", predicted);

        // Check if already deployed or pending
        console2.log("Checking for existing deployment...");
        console2.log("Environment:", environment);
        console2.log("Label:", deploymentLabel);

        (address existingDeployment, bool isPending) = checkExistingDeployment();
        if (existingDeployment != address(0)) {
            if (isPending) {
                console2.log("Deployment is pending Safe execution at:", existingDeployment);
                console2.log("Please execute the pending Safe transaction before attempting to redeploy");
            } else {
                console2.log("Deployment already exists at:", existingDeployment);
            }
            return;
        }

        console2.log("Starting deployment...");

        // Deploy using strategy-specific method with basic salt
        bytes32 salt = generateSalt();
        bytes memory deployData;

        if (strategy == DeployStrategy.CREATE3) {
            // Deploy using CreateX deployCreate3 function with basic salt
            deployData = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode);
        } else {
            // Deploy using CreateX deployCreate2 function with basic salt
            deployData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode);
        }

        // Execute deployment through Executor
        Transaction memory deployTx = Transaction(string.concat("Deploy ", contractName), CREATEX, deployData);

        (bool success, bytes memory returnData) = execute(deployTx);

        require(success, "CreateXDeployment: Deployment failed");

        address deployed;
        bytes32 safeTxHash;

        if (deployerConfig.deployerType == DeployerType.PRIVATE_KEY) {
            // For private key deployments, decode the actual deployed address
            deployed = abi.decode(returnData, (address));
            require(deployed == predicted, "CreateXDeployment: Predicted address differs from actual deployment");
            console2.log("Deployed successfully at:", deployed);
        } else {
            // For Safe deployments, we get a transaction hash and use predicted address
            safeTxHash = abi.decode(returnData, (bytes32));
            deployed = predicted;
        }

        // Log execution result with enhanced metadata
        logExecutionResult(deployed, salt, initCode, safeTxHash);

        // Execute any post-deployment setup
        postDeploy(deployed);

        console2.log("Deployment complete!");
    }

    /// @notice Post-deployment setup hook
    /// @dev Override this to perform post-deployment configuration
    function postDeploy(address deployed) internal virtual {}

    /// @notice Get contract init code (constructor + args)
    /// @notice Get contract bytecode - tries type().creationCode then falls back to artifacts
    function getContractBytecode() internal virtual returns (bytes memory) {
        // Default implementation: fallback to artifacts
        return getInitCodeFromArtifacts(contractName);
    }

    /// @notice Get constructor arguments - override in child contracts when needed
    function getConstructorArgs() internal pure virtual returns (bytes memory) {
        return "";
    }

    /// @notice Get complete init code (bytecode + constructor args)
    function getInitCode() internal virtual returns (bytes memory) {
        bytes memory bytecode = getContractBytecode();
        require(bytecode.length > 0, "Failed to load contract bytecode. Ensure contract is compiled.");
        return abi.encodePacked(bytecode, getConstructorArgs());
    }

    /// @notice Get init code from compiler artifacts (cross-version compatibility)
    function getInitCodeFromArtifacts(string memory _contractName) internal view returns (bytes memory) {
        // Try to read from out/ directory (Foundry compilation artifacts)
        string memory artifactPath = string.concat("out/", _contractName, ".sol/", _contractName, ".json");

        try vm.readFile(artifactPath) returns (string memory artifactJson) {
            // Parse the JSON to extract bytecode string
            try vm.parseJsonString(artifactJson, ".bytecode.object") returns (string memory bytecodeStr) {
                if (bytes(bytecodeStr).length > 0) {
                    // Add 0x prefix if not present
                    if (bytes(bytecodeStr).length >= 2 && bytes(bytecodeStr)[0] == "0" && bytes(bytecodeStr)[1] == "x")
                    {
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

    /// @notice Log execution result with enhanced metadata
    function logExecutionResult(address deployment, bytes32 salt, bytes memory initCode, bytes32 safeTxHash)
        internal
        view
    {
        // Output structured data for CLI parsing
        console2.log("");
        console2.log("=== DEPLOYMENT_RESULT ===");
        console2.log(string.concat("ADDRESS:", vm.toString(deployment)));
        console2.log(string.concat("SALT:", vm.toString(salt)));
        console2.log(string.concat("INIT_CODE_HASH:", vm.toString(keccak256(initCode))));
        console2.log(string.concat("CONTRACT_NAME:", contractName));
        console2.log(
            string.concat(
                "DEPLOYMENT_TYPE:", deploymentType == DeploymentType.IMPLEMENTATION ? "IMPLEMENTATION" : "PROXY"
            )
        );
        console2.log(string.concat("STRATEGY:", strategy == DeployStrategy.CREATE3 ? "CREATE3" : "CREATE2"));
        console2.log(string.concat("CHAIN_ID:", vm.toString(block.chainid)));
        console2.log(string.concat("BLOCK_NUMBER:", vm.toString(block.number)));

        if (deploymentType == DeploymentType.PROXY) {
            console2.log(string.concat("TARGET_CONTRACT:", targetContract));
        }

        // Output label if present (for both implementations and proxies)
        if (bytes(deploymentLabel).length > 0) {
            console2.log(string.concat("DEPLOYMENT_LABEL:", deploymentLabel));
        }

        if (deployerConfig.deployerType == DeployerType.SAFE && safeTxHash != bytes32(0)) {
            console2.log(string.concat("SAFE_TX_HASH:", vm.toString(safeTxHash)));
        }

        console2.log("=== END_DEPLOYMENT ===");
        console2.log("");
    }
}
