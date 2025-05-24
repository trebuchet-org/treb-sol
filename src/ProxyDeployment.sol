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
        _identifier = implementationName;
        if (bytes(implementationLabel).length > 0) {
            _identifier = string.concat(_identifier, ":", implementationLabel);
        }
        return _identifier;
    }

    /// @notice Main deployment execution
    function run() public virtual {
        DeploymentResult memory result = _deploy();
        _logDeployment(result.target, result.salt, result.initCode, result.safeTxHash);
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
    function _logDeployment(address deployment, bytes32 salt, bytes memory initCode, bytes32 safeTxHash)
        internal
        view
    {
        // Output structured data for CLI parsing
        console.log("");
        console.log("=== DEPLOYMENT_RESULT ===");
        console.log(string.concat("ADDRESS:", vm.toString(deployment)));
        console.log(string.concat("SALT:", vm.toString(salt)));
        console.log(string.concat("INIT_CODE_HASH:", vm.toString(keccak256(initCode))));
        console.log(string.concat("CONTRACT_NAME:", proxyName));
        console.log(string.concat("DEPLOYMENT_TYPE: PROXY"));
        console.log(string.concat("STRATEGY:", strategy == DeployStrategy.CREATE3 ? "CREATE3" : "CREATE2"));
        console.log(string.concat("CHAIN_ID:", vm.toString(block.chainid)));
        console.log(string.concat("BLOCK_NUMBER:", vm.toString(block.number)));
        if (bytes(label).length > 0) {
            console.log(string.concat("DEPLOYMENT_LABEL:", label));
        }
        if (safeTxHash != bytes32(0)) {
            console.log(string.concat("SAFE_TX_HASH:", vm.toString(safeTxHash)));
        }
        console.log("=== END_DEPLOYMENT ===");
        console.log("");
    }
}
