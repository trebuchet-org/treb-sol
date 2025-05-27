// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "./internal/Executor.sol";
import {Registry} from "./internal/Registry.sol";

import "./internal/types.sol";

/**
 * @title Deployment
 * @notice Base contract for deterministic deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract Deployment is CreateXScript, Executor, Registry {
    error DeploymentPendingSafe();
    error DeploymentAlreadyExists();
    error DeploymentFailed();
    error DeploymentAddressMismatch();
    error UnlinkedLibraries();
    error CompilationArtifactsNotFound();

    /// @notice Emitted when a deployment is completed
    event DeploymentCompleted(
        address indexed deployedAddress,
        string contractName,
        string deploymentType,
        bytes32 salt,
        bytes32 initCodeHash,
        ExecutionStatus status
    );

    /// @notice Path to the artifact file
    string public artifactPath;

    /// @notice Deployment strategy (CREATE2 or CREATE3)
    DeployStrategy public strategy;

    /// @notice Deployment configuration from CLI
    DeploymentConfig private config;

    /// @notice Log items for structured output
    struct LogItem {
        string key;
        string value;
    }

    LogItem[] public logItems;

    constructor(string memory _artifactPath, DeployStrategy _strategy) {
        artifactPath = _artifactPath;
        strategy = _strategy;
    }

    /// @notice Get the contract bytecode
    function _getContractBytecode() internal virtual returns (bytes memory) {
        try vm.getCode(artifactPath) returns (bytes memory code) {
            return code;
        } catch {
            revert UnlinkedLibraries();
        }
    }

    /// @notice Get the constructor arguments
    function _getConstructorArgs() internal virtual view returns (bytes memory) { 
        return "";
    }

    /// @notice Get the identifier for the deployment
    function _getIdentifier() internal virtual view returns (string memory) {
        return artifactPath;
    }

    /// @notice Log additional details to the console
    function _logAdditionalDetails() internal virtual view {}

    /// @notice Post-deployment setup hook
    /// @dev Override this to perform post-deployment configuration
    function _preDeploy() internal virtual {}

    /// @notice Post-deployment setup hook
    /// @dev Override this to perform post-deployment configuration
    function _postDeploy(DeploymentResult memory result) internal virtual {}

    /// @notice Get complete init code (bytecode + constructor args)
    function _getInitCode() internal virtual returns (bytes memory) {
        bytes memory bytecode = _getContractBytecode();
        require(bytecode.length > 0, "Failed to load contract bytecode. Ensure contract is compiled.");
        return abi.encodePacked(bytecode, _getConstructorArgs());
    }

    /// @notice Predict deployment address
    function predictAddress() public {
        address predicted = _predictAddress(_getInitCode());
        console.log("Predicted Address:", predicted);
    }

    /// @notice Main deployment execution with config from CLI
    function run(DeploymentConfig memory _config) public virtual withCreateX returns (DeploymentResult memory) {
        _initialize(_config);

        DeploymentResult memory result = _deploy();
        _writeLog();
        return result;
    }
    
    /// @notice Initialize from DeploymentConfig
    function _initialize(DeploymentConfig memory _config) internal virtual {
        Executor._initialize(_config.executorConfig);
        Registry._initialize(_config.namespace);
    }

    function _deploy() internal virtual returns (DeploymentResult memory) {
        // Get init code for address prediction
        console.log("Identifier:", _getIdentifier());
        bytes memory initCode = _getInitCode();
        address predicted = _predictAddress(initCode);

        (address existingDeployment, bool isPending) = checkExistingDeployment();
        if (existingDeployment != address(0)) {
            if (isPending) {
                console.log("Identical deployment is pending Safe execution at:", existingDeployment);
                console.log("Please execute the pending Safe transaction before attempting to redeploy.");
                revert DeploymentPendingSafe();
            } else {
                revert DeploymentAlreadyExists();
            }
        }

        bytes32 salt = _generateSalt();
        bytes memory deployData;

        if (strategy == DeployStrategy.CREATE3) {
            // Deploy using CreateX deployCreate3 function with basic salt
            deployData = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode);
        } else {
            // Deploy using CreateX deployCreate2 function with basic salt
            deployData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode);
        }

        // Execute deployment through Executor
        Transaction memory deployTx = Transaction(string.concat("Deploy ", _getIdentifier()), CREATEX_ADDRESS, deployData);

        _preDeploy();
        ExecutionResult memory result = execute(deployTx);

        address deployed;
        bytes32 safeTxHash;

        if (result.status == ExecutionStatus.EXECUTED) {
            // For private key and ledger deployments, decode the actual deployed address
            deployed = abi.decode(result.returnData, (address));
            if (deployed != predicted) {
                revert DeploymentAddressMismatch();
            }
        } else if (result.status == ExecutionStatus.PENDING_SAFE) {
            // For Safe deployments, we get a transaction hash and use predicted address
            safeTxHash = abi.decode(result.returnData, (bytes32));
        }

        DeploymentResult memory deploymentResult = DeploymentResult({
            deployed: deployed,
            predicted: predicted,
            status: result.status,
            salt: salt,
            initCode: initCode,
            safeTxHash: safeTxHash
        });

        _postDeploy(deploymentResult);
        _logDeployment(deploymentResult);
        
        // Emit deployment event
        emit DeploymentCompleted(
            deploymentResult.deployed != address(0) ? deploymentResult.deployed : deploymentResult.predicted,
            _getIdentifier(),
            _getDeploymentTypeString(),
            deploymentResult.salt,
            keccak256(deploymentResult.initCode),
            deploymentResult.status
        );
        
        return deploymentResult;
    }

    /// @notice Get deployment type as string
    function _getDeploymentTypeString() internal virtual pure returns (string memory) {
        return "SINGLETON";
    }

    /// @notice Log deployment type
    function _logDeploymentType() internal virtual {
        _log("DEPLOYMENT_TYPE", _getDeploymentTypeString());
    }

    /// @notice Log execution result with enhanced metadata
    function _logDeployment(DeploymentResult memory result)
        internal
        virtual
    {
        _logDeploymentType();
        _log("ADDRESS", vm.toString(result.deployed));
        _log("PREDICTED", vm.toString(result.predicted));
        _log("STATUS", toString(result.status));
        _log("SALT", vm.toString(result.salt));
        _log("INIT_CODE_HASH", vm.toString(keccak256(result.initCode)));
        _log("STRATEGY", toString(strategy));
        _log("BLOCK_NUMBER", vm.toString(block.number));
        _log("CONSTRUCTOR_ARGS", vm.toString(_getConstructorArgs()));
        if (result.status == ExecutionStatus.PENDING_SAFE) {
            _log("SAFE_TX_HASH", vm.toString(result.safeTxHash));
        }
    }

    /// @notice Build salt components for deterministic deployment
    /// @dev Override this function to customize salt generation
    /// @return Array of string components used to generate the salt
    function _buildSaltComponents() internal view virtual returns (string[] memory) {
        string [] memory components;
        if (bytes(config.label).length > 0) {
            components = new string[](3);
            components[0] = config.namespace;
            components[1] = _getIdentifier();
            components[2] = config.label;
        } else {
            components = new string[](2);
            components[0] = config.namespace;
            components[1] = _getIdentifier();
        }
        return components;
    }

    /// @notice Generate deterministic salt from components, make it guarded.
    function _generateSalt() internal view returns (bytes32) {
        string[] memory saltComponents = _buildSaltComponents();
        string memory combined = "";
        for (uint256 i = 0; i < saltComponents.length; i++) {
            if (i > 0) combined = string.concat(combined, ".");
            console.log("saltComponents[%d] %s", i, saltComponents[i]);
            if (bytes(saltComponents[i]).length > 0) {
                combined = string.concat(combined, "/", saltComponents[i]);
            }
        }
        bytes32 entropy = keccak256(bytes(combined));
        // return entropy;
        return
            bytes32(
                abi.encodePacked(
                    executor,
                    hex"00",
                    bytes11(uint88(uint256(entropy)))
                )
            );
    }

    /// @notice Predict deployment address based on strategy
    function _predictAddress(bytes memory initCode) internal view returns (address) {
        // Get the basic salt
        bytes32 salt = _generateSalt();
        address deployer = executor;

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

        if (strategy == DeployStrategy.CREATE3) {
            return CreateX.computeCreate3Address(guardedSalt);
        } else if (strategy == DeployStrategy.CREATE2) {
            return CreateX.computeCreate2Address(guardedSalt, keccak256(initCode));
        } else {
            revert("Invalid DeployStrategy");
        }
    }

    /// @notice Check if deployment exists in registry
    function checkExistingDeployment() internal view returns (address existingAddress, bool isPending) {
        // Check if deployment exists
        address deployed = getDeployment(_getIdentifier());
        if (deployed != address(0)) {
            // For now, we can't check pending status from JSON in Foundry scripts
            // The CLI will handle this check before running the script
            return (deployed, false);
        }

        return (address(0), false);
    }

    function _log(string memory key, string memory value) internal {
        logItems.push(LogItem({key: key, value: value}));
    }

    function _writeLog() internal view {
        console.log("");
        console.log("=== DEPLOYMENT_RESULT ===");
        for (uint256 i = 0; i < logItems.length; i++) {
            console.log(string.concat(logItems[i].key, ":", logItems[i].value));
        }
        console.log("=== END_DEPLOYMENT ===");
        console.log("");
    }
}