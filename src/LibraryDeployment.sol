// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment} from "./Deployment.sol";
import "./internal/types.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
contract LibraryDeployment is Deployment {
    LibraryDeploymentConfig private config;

    constructor() Deployment("", DeployStrategy.CREATE2) {}

    function run(LibraryDeploymentConfig memory _config) public virtual returns (DeploymentResult memory) {
        require(bytes(_config.libraryArtifactPath).length > 0, "LibraryDeployment: libraryArtifactPath is not set");

        artifactPath = _config.libraryArtifactPath;

        return Deployment.run(DeploymentConfig({
            executorConfig: _config.executorConfig,
            deploymentType: DeploymentType.LIBRARY,
            namespace: "libraries",
            label: ""
        }));
    }

}