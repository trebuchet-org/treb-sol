// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {Executor} from "./internal/Executor.sol";
import "./internal/type.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
abstract contract LibraryDeployment is CreateXScript, Executor {
    constructor() {}

    function run() public {
        require(
            deployerConfig.deployerType == DeployerType.PRIVATE_KEY ||
            deployerConfig.deployerType == DeployerType.LEDGER,
            "LibraryDeployment: Only private key and ledger deployments are supported"
        );

        string memory libraryName = vm.envString("LIBRARY_NAME");
        string memory libraryArtifactPath = vm.envString("LIBRARY_ARTIFACT_PATH");

        require(bytes(libraryName).length > 0, "LibraryDeployment: LIBRARY_NAME is not set");
        require(bytes(libraryArtifactPath).length > 0, "LibraryDeployment: LIBRARY_ARTIFACT_PATH is not set");

        bytes memory libraryCode = vm.getCode(libraryArtifactPath);
        bytes32 salt = keccak256(abi.encodePacked(libraryName));

        bytes memory deployData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, libraryCode);
        Transaction memory deployTx = Transaction(string.concat("Deploy ", libraryName), CREATEX_ADDRESS, deployData);
        ExecutionResult memory result = execute(deployTx);

        address deployed = abi.decode(result.returnData, (address));
        console.log("=== DEPLOYMENT_RESULT ===");
        console.log("DEPLOYMENT_TYPE:LIBRARY");
        console.log(string.concat("LIBRARY_ADDRESS:", vm.toString(deployed)));
        console.log("=== END_DEPLOYMENT ===");
    }
}