// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TrebScript} from "./TrebScript.sol";
import {Deployer} from "./internal/sender/Deployer.sol";
import {Senders} from "./internal/sender/Senders.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
contract LibraryDeployment is TrebScript {
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;

    string private artifactPath;
    string private deployer;

    constructor() {
        artifactPath = vm.envString("LIBRARY_ARTIFACT_PATH");
        deployer = vm.envString("DEPLOYER");
    }

    function run() public broadcast returns (address) {
        return sender(deployer).create2(artifactPath).deploy();
    }
}
