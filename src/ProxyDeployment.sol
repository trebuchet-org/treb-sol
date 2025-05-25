// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment} from "./Deployment.sol";
import "./internal/type.sol";

/**
 * @title ProxyDeployment
 * @notice Base contract for deterministic proxy deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract ProxyDeployment is Deployment {
    /// @notice Name of the contract being deployed
    string public implementationName;

    /// @notice Path to the implementation artifact file
    string public implementationIdentifier;

    /// @notice Label for the implementation contract
    string public implementationLabel;

    constructor(
        string memory _proxyName, 
        string memory _proxyArtifactPath,
        DeployStrategy _strategy,
        string memory _implementationName
    ) Deployment(_proxyName, _proxyArtifactPath, _strategy) {
        implementationName = _implementationName;
        implementationIdentifier = vm.envString("IMPLEMENTATION_IDENTIFIER");
        require(bytes(implementationIdentifier).length > 0, "ProxyDeployment: IMPLEMENTATION_IDENTIFIER is not set");
    }

    /// @notice Get the deployment label for the proxy
    function _getIdentifier() internal view override returns (string memory _identifier) {
        string memory identifier = string.concat(contractName, ":", implementationName);
        if (bytes(label).length > 0) {
            return string.concat(identifier, ":", label);
        }
        return identifier;
    }

    /// @notice Get constructor arguments - override in child contracts when needed
    function _getConstructorArgs() internal view virtual override returns (bytes memory) {
        return abi.encode(getDeployment(implementationIdentifier), _getProxyInitializer());
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
        _log("IMPLEMENTATION_NAME", implementationName);
        _log("IMPLEMENTATION_ADDRESS", vm.toString(getDeployment(implementationIdentifier)));
        _log("PROXY_INITIALIZER", vm.toString(_getProxyInitializer()));
    }
}
