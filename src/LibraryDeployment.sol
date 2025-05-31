// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TrebScript, Deployer, Senders} from "./TrebScript.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
contract LibraryDeployment is TrebScript {
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;

    error MissingLibraryArtifactPath();
    
    string private constant LIBRARY_DEPLOYER = "libraries";
    string private artifactPath;

    constructor() {
        artifactPath = vm.envOr("LIBRARY_ARTIFACT_PATH", string(""));
        if (bytes(artifactPath).length == 0) {
            revert MissingLibraryArtifactPath();
        }
    }

    function run() public broadcast returns (address) {
        return sender(LIBRARY_DEPLOYER).create2(artifactPath).deploy();
    }
}