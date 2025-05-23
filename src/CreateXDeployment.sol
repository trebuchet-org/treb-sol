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

    /// @notice Version or label for this deployment
    string public label;

    /// @notice Directory for deployments on this chain
    string public deploymentDir;

    /// @notice Private key for deployment (from environment)
    uint256 public deployerPrivateKey;

    constructor(string memory _contractName, DeploymentType _deploymentType, DeployStrategy _strategy) Registry() Executor() {
        contractName = _contractName;
        
        // Load label from environment (for implementations)
        if (_deploymentType == DeploymentType.IMPLEMENTATION) {
            label = vm.envOr("DEPLOYMENT_LABEL", string(""));
        } else {
            // For proxies, use PROXY_LABEL
            label = vm.envOr("PROXY_LABEL", string("main"));
        }

        // Set up deployment directory path
        string memory chainId = vm.toString(block.chainid);
        deploymentDir = string.concat("deployments/", chainId);

        // Load deployer private key
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deploymentType = _deploymentType;
        strategy = _strategy;
        saltComponents = buildSaltComponents();
    }

    /// @notice Get the deployment label (contract name + version)
    function getLabel() public view returns (string memory) {
        return string.concat(contractName, "_", label);
    }

    /// @notice Check if deployment exists in registry
    function checkExistingDeployment() internal view returns (address existingAddress, bool isPending) {
        // Build the identifier based on deployment type
        string memory identifier;
        if (deploymentType == DeploymentType.PROXY) {
            identifier = string.concat(targetContract, "Proxy");
            if (bytes(label).length > 0) {
                identifier = string.concat(identifier, ":", label);
            }
        } else {
            identifier = contractName;
            if (bytes(label).length > 0) {
                identifier = string.concat(identifier, ":", label);
            }
        }

        // Check if deployment exists
        address deployed = getDeployment(identifier);
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
        if (deploymentType == DeploymentType.IMPLEMENTATION) {
            return buildImplementationSaltComponents();
        } else {
            return buildProxySaltComponents();
        }
    }

    /// @notice Build salt components for implementation deployments
    /// @return Array with contractName, env, and initCodeHash
    function buildImplementationSaltComponents() internal virtual returns (string[] memory) {
        string memory deploymentLabel = vm.envOr("DEPLOYMENT_LABEL", string(""));

        if (bytes(deploymentLabel).length > 0) {
            // With label: contractName, env, label, initCodeHash
            string[] memory components = new string[](4);
            components[0] = contractName;
            components[1] = vm.envOr("DEPLOYMENT_ENV", string("default"));
            components[2] = deploymentLabel;
            components[3] = vm.toString(keccak256(getInitCode()));
            return components;
        } else {
            // Without label: contractName, env, initCodeHash
            string[] memory components = new string[](3);
            components[0] = contractName;
            components[1] = vm.envOr("DEPLOYMENT_ENV", string("default"));
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
        components[2] = vm.envOr("DEPLOYMENT_ENV", string("default"));
        return components;
    }

    /// @notice Generate deterministic salt from components
    function generateSalt() public view returns (bytes32) {
        string memory combined = "";
        for (uint256 i = 0; i < saltComponents.length; i++) {
            if (i > 0) combined = string.concat(combined, ".");
            combined = string.concat(combined, saltComponents[i]);
        }
        return keccak256(bytes(combined));
    }

    /// @notice Generate guarded salt for enhanced security with CreateX
    /// @dev Uses CreateX's guarded salt implementation to prevent front-running
    function generateGuardedSalt() public view returns (bytes32) {
        bytes32 baseSalt = generateSalt();
        address deployer = getDeployerAddress();
        // Create guarded salt: keccak256(deployer + baseSalt)
        // This ensures only the intended deployer can use this salt
        return keccak256(abi.encodePacked(deployer, baseSalt));
    }

    /// @notice Predict deployment address
    function predictAddress() public {
        address predicted = _predictAddress(getInitCode());
        console2.log("Address:", predicted);
    }

    /// @notice Predict deployment address based on strategy
    function _predictAddress(bytes memory initCode) internal view returns (address) {
        bytes32 salt = generateGuardedSalt();
        address actualDeployer = getDeployerAddress();

        if (strategy == DeployStrategy.CREATE3) {
            return _predictCreate3Address(salt, actualDeployer);
        } else {
            return _predictCreate2Address(salt, actualDeployer, initCode);
        }
    }

    /// @notice Predict CREATE3 address
    function _predictCreate3Address(bytes32 salt, address deployer) internal view returns (address) {
        // Use CreateX's computeCreate3Address function for accurate prediction
        (bool success, bytes memory result) =
            CREATEX.staticcall(abi.encodeWithSignature("computeCreate3Address(bytes32,address)", salt, deployer));

        if (success) {
            return abi.decode(result, (address));
        }

        // Fallback to standard CREATE3 calculation
        bytes32 proxyCodeHash = keccak256(hex"67363d3d37363d34f03d5260086018f3");
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, proxyCodeHash)))));
    }

    /// @notice Predict CREATE2 address
    function _predictCreate2Address(bytes32 salt, address, bytes memory initCode) internal view returns (address) {
        // Use CreateX's computeCreate2Address function for accurate prediction
        bytes32 initCodeHash = keccak256(initCode);
        (bool success, bytes memory result) =
            CREATEX.staticcall(abi.encodeWithSignature("computeCreate2Address(bytes32,bytes32)", salt, initCodeHash));

        if (success) {
            return abi.decode(result, (address));
        }

        // Fallback to standard CREATE2 calculation
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATEX, salt, initCodeHash)))));
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
        console2.log("Environment:", deploymentEnv);
        if (bytes(label).length > 0) {
            console2.log("Label:", label);
        }
        
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

        // Deploy using strategy-specific method with guarded salt
        bytes32 salt = generateGuardedSalt();
        bytes memory deployData;

        if (strategy == DeployStrategy.CREATE3) {
            // Deploy using CreateX deployCreate3 function with guarded salt
            deployData = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode);
        } else {
            // Deploy using CreateX deployCreate2 function with guarded salt
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
            console2.log(string.concat("PROXY_LABEL:", vm.envOr("PROXY_LABEL", string("main"))));
        }

        // Output label if present (for both implementations and proxies)
        string memory deploymentLabel = vm.envOr("DEPLOYMENT_LABEL", string(""));
        if (bytes(deploymentLabel).length > 0) {
            console2.log(string.concat("LABEL:", deploymentLabel));
        }

        if (deployerConfig.deployerType == DeployerType.SAFE && safeTxHash != bytes32(0)) {
            console2.log(string.concat("SAFE_TX_HASH:", vm.toString(safeTxHash)));
        }

        console2.log("=== END_DEPLOYMENT ===");
        console2.log("");
    }
}
