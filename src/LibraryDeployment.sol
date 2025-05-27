// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {Executor} from "./internal/Executor.sol";
import "./internal/type.sol";
import {DeploymentConfig} from "./internal/types.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
contract LibraryDeployment is CreateXScript, Executor {
    /// @notice Emitted when a library is deployed
    event LibraryDeployed(
        address indexed libraryAddress,
        string libraryName,
        bytes32 salt
    );

    constructor() {}

    function run(DeploymentConfig memory config, string memory libraryName, string memory libraryArtifactPath) public withCreateX {
        // Initialize from config
        _initializeFromConfig(config);
        require(
            deployerConfig.deployerType == DeployerType.PRIVATE_KEY ||
            deployerConfig.deployerType == DeployerType.LEDGER,
            "LibraryDeployment: Only private key and ledger deployments are supported"
        );

        require(bytes(libraryName).length > 0, "LibraryDeployment: libraryName is not set");
        require(bytes(libraryArtifactPath).length > 0, "LibraryDeployment: libraryArtifactPath is not set");

        bytes memory libraryCode = vm.getCode(libraryArtifactPath);
        bytes32 salt = keccak256(abi.encodePacked(libraryName));

        bytes memory deployData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, libraryCode);
        Transaction memory deployTx = Transaction(string.concat("Deploy ", libraryName), CREATEX_ADDRESS, deployData);
        ExecutionResult memory result = execute(deployTx);

        address deployed = abi.decode(result.returnData, (address));
        
        // Emit library deployment event
        emit LibraryDeployed(deployed, libraryName, salt);
        
        // Only log if not broadcasting
        if (!config.broadcast) {
            console.log("=== DEPLOYMENT_RESULT ===");
            console.log("DEPLOYMENT_TYPE:LIBRARY");
            console.log("STATUS:EXECUTED");
            console.log(string.concat("LIBRARY_ADDRESS:", vm.toString(deployed)));
            console.log("=== END_DEPLOYMENT ===");
        }
    }
    
    // Legacy run method for backward compatibility
    function run() public {
        DeploymentConfig memory config = DeploymentConfig({
            projectName: vm.envOr("PROJECT_NAME", string("default")),
            namespace: vm.envOr("DEPLOYMENT_NAMESPACE", string("default")),
            label: "",
            chainId: block.chainid,
            networkName: vm.envOr("NETWORK_NAME", string("unknown")),
            sender: vm.envAddress("SENDER_ADDRESS"),
            senderType: vm.envOr("SENDER_TYPE", string("private_key")),
            registryAddress: address(0),
            broadcast: vm.envOr("BROADCAST", false),
            verify: false
        });
        
        string memory libraryName = vm.envString("LIBRARY_NAME");
        string memory libraryArtifactPath = vm.envString("LIBRARY_ARTIFACT_PATH");
        
        run(config, libraryName, libraryArtifactPath);
    }
}