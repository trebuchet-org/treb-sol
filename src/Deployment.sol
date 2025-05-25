// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {console} from "forge-std/console.sol";
import {Executor} from "./internal/Executor.sol";
import {Registry} from "./internal/Registry.sol";

enum DeployStrategy {
    CREATE2,
    CREATE3
}

enum DeploymentType {
    CONTRACT,
    PROXY,
    LIBRARY
}
/**
 * @title CreateXDeployment
 * @notice Base contract for deterministic deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract Deployment is CreateXScript, Executor, Registry {
    error DeploymentPendingSafe();
    error DeploymentAlreadyExists();
    error DeploymentFailed();
    error DeploymentAddressMismatch();

    struct DeploymentResult {
        address target;
        bytes32 salt;
        bytes initCode;
        bytes32 safeTxHash;
    }

    /// @notice Deployment strategy (CREATE2 or CREATE3)
    DeployStrategy public strategy;

    /// @notice Deployment type (IMPLEMENTATION or PROXY)
    DeploymentType public deploymentType;

    constructor(DeployStrategy _strategy, DeploymentType _deploymentType) {
        strategy = _strategy;
        deploymentType = _deploymentType;
    }

    /// @notice Get the contract bytecode
    function _getContractBytecode() internal virtual returns (bytes memory);

    /// @notice Get the constructor arguments
    function _getConstructorArgs() internal virtual view returns (bytes memory) { 
        return "";
    }

    /// @notice Get the identifier for the deployment
    function _getIdentifier() internal virtual view returns (string memory);

    /// @notice Log additional details to the console
    function _logAdditionalDetails() internal virtual view {}

    /// @notice Post-deployment setup hook
    /// @dev Override this to perform post-deployment configuration
    function _preDeploy() internal virtual {}

    /// @notice Post-deployment setup hook
    /// @dev Override this to perform post-deployment configuration
    function _postDeploy(address deployed) internal virtual {}

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

    /// @notice Main deployment execution
    function run() public virtual {
        DeploymentResult memory result = _deploy();
        _logDeployment(result.target, result.salt, result.initCode, result.safeTxHash);
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
        (bool success, bytes memory returnData) = execute(deployTx);

        if (!success) {
            revert DeploymentFailed();
        }

        address deployed;
        bytes32 safeTxHash;

        if (deployerConfig.deployerType == DeployerType.PRIVATE_KEY) {
            // For private key deployments, decode the actual deployed address
            deployed = abi.decode(returnData, (address));
            if (deployed != predicted) {
                revert DeploymentAddressMismatch();
            }
        } else {
            // For Safe deployments, we get a transaction hash and use predicted address
            safeTxHash = abi.decode(returnData, (bytes32));
            deployed = predicted;
        }

        _postDeploy(deployed);

        return DeploymentResult({
            target: deployed,
            salt: salt,
            initCode: initCode,
            safeTxHash: safeTxHash
        });
    }

    /// @notice Log execution result with enhanced metadata
    function _logDeployment(address deployment, bytes32 salt, bytes memory initCode, bytes32 safeTxHash)
        internal
        view
    {
        // Output structured data for CLI parsing
        console.log("");
        console.log("=== DEPLOYMENT_RESULT ===");
        console.log(string.concat("ADDRESS:", vm.toString(deployment)));
        console.log(string.concat("SALT:", vm.toString(salt)));
        console.log(string.concat("INIT_CODE_HASH:", vm.toString(keccak256(initCode))));
        console.log(string.concat("STRATEGY:", strategy == DeployStrategy.CREATE3 ? "CREATE3" : "CREATE2"));
        console.log(string.concat("CHAIN_ID:", vm.toString(block.chainid)));
        console.log(string.concat("BLOCK_NUMBER:", vm.toString(block.number)));
        console.log(string.concat("CONSTRUCTOR_ARGS:", vm.toString(_getConstructorArgs())));
        if (safeTxHash != bytes32(0)) {
            console.log(string.concat("SAFE_TX_HASH:", vm.toString(safeTxHash)));
        }
        _logAdditionalDetails();
        console.log("=== END_DEPLOYMENT ===");
        console.log("");
    }

    /// @notice Build salt components for deterministic deployment
    /// @dev Override this function to customize salt generation
    /// @return Array of string components used to generate the salt
    function _buildSaltComponents() internal view virtual returns (string[] memory) {
        string[] memory components = new string[](2);
        components[0] = _getIdentifier();
        components[1] = environment;
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
                combined = string.concat(combined, ".", saltComponents[i]);
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
}