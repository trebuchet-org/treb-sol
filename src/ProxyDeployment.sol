// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment} from "./Deployment.sol";
import "./internal/types.sol";

/**
 * @title ProxyDeployment
 * @notice Base contract for deterministic proxy deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract ProxyDeployment is Deployment {
    /// @notice Name of the contract being deployed
    string public implementationArtifactPath;

    /// @notice Implementation address
    address public implementationAddress;

    ProxyDeploymentConfig private config;

    constructor(
        string memory _proxyArtifactPath,
        string memory _implementationArtifactPath,
        DeployStrategy _strategy
    ) Deployment(_proxyArtifactPath, _strategy) {
        implementationArtifactPath = _implementationArtifactPath;
    }

    function _initialize(ProxyDeploymentConfig memory _config) internal virtual {
        super._initialize(_config.deploymentConfig);
        implementationAddress = _config.implementationAddress;
        config = _config;
    }

    /// @notice Get the deployment label for the proxy
    function _getIdentifier() internal view override returns (string memory _identifier) {
        string memory identifier = string.concat(implementationArtifactPath, "Proxy");
        if (bytes(config.deploymentConfig.label).length > 0) {
            return string.concat(identifier, ":", config.deploymentConfig.label);
        }
        return identifier;
    }

    /// @notice common proxy constructor args, override in child contracts when needed
    function _getConstructorArgs() internal view virtual override returns (bytes memory) {
        return abi.encode(implementationAddress, _getProxyInitializer());
    }

    /// @notice Get proxy initializer - override in child contracts when needed
    function _getProxyInitializer() internal view virtual returns (bytes memory) {
        return "";
    }

    /// @notice Log deployment type
    function _logDeploymentType() internal virtual override {
        _log("DEPLOYMENT_TYPE", "PROXY");
    }

    /// @notice Log execution result with enhanced metadata
    function _logDeployment(DeploymentResult memory result) internal override {
        super._logDeployment(result);
        _log("DEPLOYMENT_TYPE", "PROXY");
        _log("IMPLEMENTATION_ADDRESS", vm.toString(implementationAddress));
        _log("PROXY_INITIALIZER", vm.toString(_getProxyInitializer()));
    }
}
