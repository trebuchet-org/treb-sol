// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployment, DeployStrategy, DeploymentType} from "./Deployment.sol";
import {console} from "forge-std/console.sol";

/**
 * @title LibraryDeployment
 * @notice Base contract for deploying libraries with deterministic addresses
 * @dev Libraries are deployed globally (no environment) for cross-chain consistency
 */
abstract contract LibraryDeployment is Deployment {
    /// @notice Name of the library being deployed
    string public libraryName;

    constructor(string memory _libraryName) 
        Deployment(DeployStrategy.CREATE2, DeploymentType.LIBRARY) 
    {
        libraryName = _libraryName;
    }

    /// @notice Get the library name
    function _getIdentifier() internal override view returns (string memory) {
        // Libraries use just their name as identifier (no environment)
        return libraryName;
    }

    /// @notice Get library bytecode using vm.getCode
    function _getContractBytecode() internal virtual override returns (bytes memory) {
        // Use vm.getCode to get the library's creation code
        return vm.getCode(libraryName);
    }

    /// @notice Build salt components for deterministic deployment
    /// @dev Libraries use only the library name for global consistency
    function _buildSaltComponents() internal override view returns (string[] memory) {
        string[] memory components = new string[](1);
        components[0] = libraryName;
        return components;
    }

    /// @notice Log additional details to the console
    function _logAdditionalDetails() internal override view {
        console.log(string.concat("LIBRARY_NAME:", libraryName));
        console.log("DEPLOYMENT_TYPE: LIBRARY");
        // Libraries are global, no environment
        console.log("ENVIRONMENT: global");
    }
}