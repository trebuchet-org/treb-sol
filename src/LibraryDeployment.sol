// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {Executor} from "./internal/Executor.sol";
import "./internal/types.sol";

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

    LibraryDeploymentConfig private config;

    constructor() {}

    function run(LibraryDeploymentConfig memory _config) public withCreateX {
        _initialize(_config);
        require(bytes(config.libraryName).length > 0, "LibraryDeployment: libraryName is not set");
        require(bytes(config.libraryArtifactPath).length > 0, "LibraryDeployment: libraryArtifactPath is not set");

        bytes memory libraryCode = vm.getCode(config.libraryArtifactPath);
        bytes32 salt = keccak256(abi.encodePacked(config.libraryName));

        bytes memory deployData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, libraryCode);
        Transaction memory deployTx = Transaction(string.concat("Deploy ", config.libraryName), CREATEX_ADDRESS, deployData);
        ExecutionResult memory result = execute(deployTx);

        address deployed = abi.decode(result.returnData, (address));
        
        // Emit library deployment event
        emit LibraryDeployed(deployed, config.libraryName, salt);
        
        // Only log if not broadcasting
        console.log("=== DEPLOYMENT_RESULT ===");
        console.log("DEPLOYMENT_TYPE:LIBRARY");
        console.log("STATUS:EXECUTED");
        console.log(string.concat("LIBRARY_ADDRESS:", vm.toString(deployed)));
        console.log("=== END_DEPLOYMENT ===");
    }

    function _initialize(LibraryDeploymentConfig memory _config) internal virtual {
        super._initialize(_config.executorConfig);
        config = _config;
    }
}