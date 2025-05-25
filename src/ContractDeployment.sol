// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment, DeployStrategy, DeploymentType} from "./Deployment.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {getInitCodeFromArtifacts} from "./internal/utils.sol";

/**
 * @title CreateXDeployment
 * @notice Base contract for deterministic deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract ContractDeployment is Deployment {
    error UnlinkedLibraries();
    error CompilationArtifactsNotFound();

    /// @notice Name of the contract being deployed
    string public contractName;

    /// @notice Label for this deployment
    string public label;

    constructor(string memory _contractName, DeployStrategy _strategy)
        Deployment(_strategy, DeploymentType.CONTRACT)
    {
        contractName = _contractName;
        label = vm.envOr("DEPLOYMENT_LABEL", string(""));
        strategy = _strategy;
    }

    /// @notice Get the deployment label (contract name + version)
    function _getIdentifier() internal override view returns (string memory _identifier) {
        if (bytes(label).length > 0) {
            return string.concat(contractName, ":", label);
        }
        return contractName;
    }

    /// @notice Get constructor arguments - override in child contracts when needed
    function _getConstructorArgs() internal virtual override view returns (bytes memory) {
        return "";
    }

    /// @notice Get contract bytecode - tries type().creationCode then falls back to artifacts
    function _getContractBytecode() internal virtual override returns (bytes memory) {
        // Default implementation: fallback to artifacts
        try vm.getCode(contractName) returns (bytes memory code) {
            return code;
        } catch {
            try vm.readFile(getArtifactPath()) returns (string memory artifactJson) {
                revert UnlinkedLibraries();
            } catch {
                revert CompilationArtifactsNotFound();
            }
        }
    }

    /// @notice Get the artifact path for the contract, override in child contracts when needed
    function getArtifactPath() internal virtual view returns (string memory) {
        // Try to read from out/ directory (Foundry compilation artifacts)
        return string.concat("out/", contractName, ".sol/", contractName, ".json");
    }

    /// @notice Log additional details to the console
    function _logAdditionalDetails() internal override view {
        console.log(string.concat("CONTRACT_NAME:", contractName));
        if (bytes(label).length > 0) {
            console.log(string.concat("DEPLOYMENT_LABEL:", label));
        }
    }

}
