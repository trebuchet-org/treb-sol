// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment} from "./Deployment.sol";
import "./internal/type.sol";
import {DeploymentConfig} from "./internal/types.sol";

/**
 * @title ProxyDeployment
 * @notice Base contract for deterministic proxy deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract ProxyDeployment is Deployment {
    /// @notice Emitted when a proxy is deployed
    event ProxyDeployed(
        address indexed proxyAddress,
        address indexed implementationAddress,
        string proxyType,
        bytes initData
    );

    /// @notice Name of the contract being deployed
    string public implementationArtifactPath;

    /// @notice Implementation address
    address public implementationAddress;

    constructor(
        string memory _proxyArtifactPath,
        string memory _implementationArtifactPath,
        DeployStrategy _strategy
    ) Deployment(_proxyArtifactPath, _strategy) {
        implementationArtifactPath = _implementationArtifactPath;
        implementationAddress = vm.envAddress("IMPLEMENTATION_ADDRESS");
        require(implementationAddress != address(0), "ProxyDeployment: IMPLEMENTATION_ADDRESS is not set");
    }

    /// @notice Get the deployment label for the proxy
    function _getIdentifier() internal view override returns (string memory _identifier) {
        string memory identifier = string.concat(implementationArtifactPath, "Proxy");
        if (bytes(label).length > 0) {
            return string.concat(identifier, ":", label);
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

    /// @notice Get deployment type as string
    function _getDeploymentTypeString() internal virtual pure override returns (string memory) {
        return "PROXY";
    }

    /// @notice Log deployment type
    function _logDeploymentType() internal virtual override {
        _log("DEPLOYMENT_TYPE", "PROXY");
    }

    /// @notice Post-deployment hook to emit proxy event
    function _postDeploy(DeploymentResult memory result) internal virtual override {
        super._postDeploy(result);
        
        // Emit proxy-specific event
        address proxyAddr = result.deployed != address(0) ? result.deployed : result.predicted;
        emit ProxyDeployed(
            proxyAddr,
            implementationAddress,
            artifactPath, // proxy type (e.g., "ERC1967Proxy")
            _getProxyInitializer()
        );
    }

    /// @notice Log execution result with enhanced metadata
    function _logDeployment(DeploymentResult memory result) internal override {
        super._logDeployment(result);
        _log("DEPLOYMENT_TYPE", "PROXY");
        _log("IMPLEMENTATION_ADDRESS", vm.toString(implementationAddress));
        _log("PROXY_INITIALIZER", vm.toString(_getProxyInitializer()));
    }
}
