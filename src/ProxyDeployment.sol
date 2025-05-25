// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment, DeployStrategy, DeploymentType} from "./Deployment.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";

import {getInitCodeFromArtifacts} from "./internal/utils.sol";

/**
 * @title ProxyDeployment
 * @notice Base contract for deterministic proxy deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract ProxyDeployment is Deployment {
    /// @notice Name of the contract being deployed
    string public implementationName;

    /// @notice Label for the implementation contract
    string public implementationLabel;

    /// @notice Name of the proxy contract
    string public proxyName;

    /// @notice Label for the proxy contract
    string public proxyLabel;

    /// @notice Label for this deployment
    string public label;

    constructor(string memory _implementationName, DeployStrategy _strategy)
        Deployment(_strategy, DeploymentType.CONTRACT)
    {
        implementationName = _implementationName;
        implementationLabel = vm.envOr("IMPLEMENTATION_LABEL", string(""));
        proxyName = string.concat(implementationName, "Proxy");
        proxyLabel = vm.envOr("DEPLOYMENT_LABEL", string(""));
        strategy = _strategy;
    }

    /// @notice Get the deployment label for the proxy
    function _getIdentifier() internal view override returns (string memory _identifier) {
        if (bytes(proxyLabel).length > 0) {
            return string.concat(proxyName, ":", proxyLabel);
        }
        return proxyName;
    }

    function _getImplementationIdentifier() internal virtual view returns (string memory _identifier) {
        if (bytes(implementationLabel).length > 0) {
            return string.concat(implementationName, ":", implementationLabel);
        }
        return implementationName;
    }

    /// @notice Get constructor arguments - override in child contracts when needed
    function _getConstructorArgs() internal view virtual override returns (bytes memory) {
        return abi.encode(getDeployment(_getImplementationIdentifier()), _getProxyInitializer());
    }

    /// @notice Get proxy initializer - override in child contracts when needed
    function _getProxyInitializer() internal view virtual returns (bytes memory) {
        return "";
    }

    /// @notice Get contract bytecode - tries type().creationCode then falls back to artifacts
    function _getContractBytecode() internal virtual override returns (bytes memory) {
        // Default implementation: fallback to artifacts
        return getInitCodeFromArtifacts(vm, getArtifactPath());
    }

    /// @notice Get the artifact path for the contract, override in child contracts when needed
    function getArtifactPath() internal virtual view returns (string memory) {
        // Try to read from out/ directory (Foundry compilation artifacts)
        return string.concat("out/", proxyName, ".sol/", proxyName, ".json");
    }

    /// @notice Log execution result with enhanced metadata
    function _logAdditionalDetails() internal override view {
        // Output structured data for CLI parsing
        console.log(string.concat("CONTRACT_NAME:", proxyName));
        console.log(string.concat("DEPLOYMENT_TYPE: PROXY"));
        if (bytes(label).length > 0) {
            console.log(string.concat("DEPLOYMENT_LABEL:", label));
        }
        console.log(string.concat("IMPLEMENTATION_NAME:", implementationName));
        if (bytes(implementationLabel).length > 0) {
            console.log(string.concat("IMPLEMENTATION_LABEL:", implementationLabel));
        }
    }
}
