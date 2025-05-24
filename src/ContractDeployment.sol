// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Deployment, DeployStrategy, DeploymentType} from "./Deployment.sol";
import {CREATEX_ADDRESS} from "createx-forge/CreateX.d.sol";
import {getInitCodeFromArtifacts} from "./internal/utils.sol";

/**
 * @title CreateXDeployment
 * @notice Base contract for deterministic deployments using CreateX
 * @dev Provides deployment logic with comprehensive tracking and verification
 */
abstract contract ContractDeployment is Deployment {
    /// @notice Target contract for proxy deployments
    string public targetContract;

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
        _identifier = contractName;
        if (bytes(label).length > 0) {
            _identifier = string.concat(_identifier, ":", label);
        }
        return _identifier;
    }

    /// @notice Main deployment execution
    function run() public virtual {
        DeploymentResult memory result = _deploy();
        _logDeployment(result.target, result.salt, result.initCode, result.safeTxHash);
    }

    /// @notice Get constructor arguments - override in child contracts when needed
    function getConstructorArgs() internal pure virtual returns (bytes memory) {
        return "";
    }

    /// @notice Get contract bytecode - tries type().creationCode then falls back to artifacts
    function getContractBytecode() internal virtual returns (bytes memory) {
        // Default implementation: fallback to artifacts
        return getInitCodeFromArtifacts(vm, getArtifactPath());
    }

    /// @notice Get the artifact path for the contract, override in child contracts when needed
    function getArtifactPath() internal virtual view returns (string memory) {
        // Try to read from out/ directory (Foundry compilation artifacts)
        return string.concat("out/", contractName, ".sol/", contractName, ".json");
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
        console.log(string.concat("CONTRACT_NAME:", contractName));
        console.log(string.concat("DEPLOYMENT_TYPE: CONTRACT"));
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
