// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {TrebScript} from "./TrebScript.sol";
import {Deployer} from "./internal/Deployer.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
contract LibraryDeployment is TrebScript {
    string private constant LIBRARY_DEPLOYER = "libraries";
    string private artifactPath;

    constructor() {
        artifactPath = vm.envString("LIBRARY_ARTIFACT_PATH");
        if (bytes(artifactPath).length == 0) {
            revert("LIBRARY_ARTIFACT_PATH is not set");
        }
    }

    function run() public virtual flush returns (address) {
        Deployer deployer = sender(LIBRARY_DEPLOYER).deployer();
        return deployer.deployCreate3(artifactPath);
    }
}