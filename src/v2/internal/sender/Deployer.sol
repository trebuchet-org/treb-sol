// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Sender} from "../../Sender.sol";
import {Senders} from "./Senders.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {ICreateX} from "createx-forge/script/ICreateX.sol";
import {ITrebEvents} from "../../../internal/ITrebEvents.sol";

/// @title Deployer (v2)
/// @notice Builder API for deterministic CREATE2/CREATE3 deployments via CreateX.
/// @dev Each deploy() call does vm.broadcast(sender) + direct CreateX call.
///      No intermediate Transaction/execute() layer — forge captures the
///      broadcast and Rust routes by sender address after execution.
library Deployer {
    using Deployer for Sender;
    using Deployer for Deployment;

    enum CreateStrategy {
        CREATE3,
        CREATE2
    }

    struct Deployment {
        Sender sender;
        CreateStrategy strategy;
        bytes bytecode;
        string label;
        string entropy;
        string artifact;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    ICreateX private constant CREATEX = ICreateX(CREATEX_ADDRESS);

    bytes32 private constant NO_BYTECODE_HASH =
        keccak256("vm.getCode: no bytecode for contract; is it abstract or unlinked?");
    bytes32 private constant NO_ARTIFACT_HASH = keccak256("vm.getCode: no matching artifact found");

    error ContractNotFound(string what);
    error BytecodeMissing(string what);
    error PredictedAddressMismatch(address predicted, address actual);
    error EntropyAlreadySet();
    error LabelAlreadySet();
    error InvalidCreateStrategy(CreateStrategy strategy);
    error EntropyOrArtifactRequired();

    modifier verify(Deployment storage deployment) {
        if (bytes(deployment.entropy).length == 0) {
            if (bytes(deployment.artifact).length == 0) revert EntropyOrArtifactRequired();
            deployment.entropy = string.concat(Senders.registry().namespace, "/", deployment.artifact);
            if (bytes(deployment.label).length > 0) {
                deployment.entropy = string.concat(deployment.entropy, ":", deployment.label);
            }
        }
        _;
    }

    // ── Deployment Builder ──────────────────────────────────────────────

    function _deploy(Sender s, bytes memory bytecode) internal returns (Deployment storage deployment) {
        bytes32 deploymentSlot =
            keccak256(abi.encode(Sender.unwrap(s), bytecode, Senders.registry().transactionCounter));
        assembly {
            deployment.slot := deploymentSlot
        }
        delete deployment.strategy;
        delete deployment.bytecode;
        delete deployment.label;
        delete deployment.entropy;
        delete deployment.artifact;

        deployment.sender = s;
        deployment.bytecode = bytecode;
    }

    function setLabel(Deployment storage deployment, string memory _label) internal returns (Deployment storage) {
        if (bytes(deployment.entropy).length > 0) revert EntropyAlreadySet();
        deployment.label = _label;
        return deployment;
    }

    function setEntropy(Deployment storage deployment, string memory _entropy) internal returns (Deployment storage) {
        if (bytes(deployment.label).length > 0) revert LabelAlreadySet();
        deployment.entropy = _entropy;
        return deployment;
    }

    function deploy(Deployment storage deployment) internal returns (address) {
        return deployment.deploy("");
    }

    function deploy(Deployment storage deployment, bytes memory _constructorArgs)
        internal
        verify(deployment)
        returns (address)
    {
        bytes32 salt = _salt(deployment.sender, deployment.entropy);
        address predictedAddress = deployment.predict(_constructorArgs);
        bytes memory initCode = abi.encodePacked(deployment.bytecode, _constructorArgs);

        // Collision check — idempotent deployments
        if (predictedAddress.code.length > 0) {
            if (!Senders.registry().quiet) {
                ITrebEvents.DeploymentDetails memory details = ITrebEvents.DeploymentDetails({
                    artifact: deployment.artifact,
                    label: deployment.label,
                    entropy: deployment.entropy,
                    salt: salt,
                    bytecodeHash: keccak256(deployment.bytecode),
                    initCodeHash: keccak256(initCode),
                    constructorArgs: _constructorArgs,
                    createStrategy: deployment.strategy == CreateStrategy.CREATE3 ? "CREATE3" : "CREATE2"
                });
                emit ITrebEvents.DeploymentCollision(predictedAddress, details);
            }
            return predictedAddress;
        }

        // Deploy via CreateX with vm.broadcast
        bytes32 transactionId = Senders.generateTransactionId();
        deployment.sender.broadcast();
        address deployedAddress;
        if (deployment.strategy == CreateStrategy.CREATE3) {
            deployedAddress = CREATEX.deployCreate3(salt, initCode);
        } else if (deployment.strategy == CreateStrategy.CREATE2) {
            deployedAddress = CREATEX.deployCreate2(salt, initCode);
        } else {
            revert InvalidCreateStrategy(deployment.strategy);
        }

        if (deployedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, deployedAddress);
        }

        // Emit ContractDeployed for Rust-side deployment tracking
        if (!Senders.registry().quiet) {
            ITrebEvents.DeploymentDetails memory details = ITrebEvents.DeploymentDetails({
                artifact: deployment.artifact,
                label: deployment.label,
                entropy: deployment.entropy,
                salt: salt,
                bytecodeHash: keccak256(deployment.bytecode),
                initCodeHash: keccak256(initCode),
                constructorArgs: _constructorArgs,
                createStrategy: deployment.strategy == CreateStrategy.CREATE3 ? "CREATE3" : "CREATE2"
            });
            emit ITrebEvents.ContractDeployed(deployment.sender.addr(), deployedAddress, transactionId, details);
        }

        return deployedAddress;
    }

    // ── Prediction ──────────────────────────────────────────────────────

    function predict(Deployment storage deployment) internal returns (address) {
        return deployment.predict("");
    }

    function predict(Deployment storage deployment, bytes memory _constructorArgs)
        internal
        verify(deployment)
        returns (address)
    {
        bytes32 salt = _salt(deployment.sender, deployment.entropy);
        salt = _derivedSalt(deployment.sender, salt);

        if (deployment.strategy == CreateStrategy.CREATE3) {
            return CREATEX.computeCreate3Address(salt);
        } else if (deployment.strategy == CreateStrategy.CREATE2) {
            bytes memory initCode = abi.encodePacked(deployment.bytecode, _constructorArgs);
            return CREATEX.computeCreate2Address(salt, keccak256(initCode));
        } else {
            revert InvalidCreateStrategy(deployment.strategy);
        }
    }

    // ── CREATE3 ─────────────────────────────────────────────────────────

    function create3(Sender s, string memory _entropy, bytes memory bytecode)
        internal
        returns (Deployment storage deployment)
    {
        deployment = _deploy(s, bytecode);
        deployment.artifact = "<user-provided-bytecode>";
        deployment.entropy = _entropy;
        deployment.strategy = CreateStrategy.CREATE3;
    }

    function create3(Sender s, string memory _artifact) internal returns (Deployment storage deployment) {
        try vm.getCode(_artifact) returns (bytes memory code) {
            deployment = _deploy(s, code);
            deployment.artifact = _artifact;
            deployment.strategy = CreateStrategy.CREATE3;
        } catch Error(string memory reason) {
            bytes32 reasonHash = keccak256(bytes(reason));
            if (reasonHash == NO_BYTECODE_HASH) revert BytecodeMissing(_artifact);
            revert ContractNotFound(_artifact);
        } catch (bytes memory lowLevelData) {
            if (lowLevelData.length >= 68) {
                assembly {
                    lowLevelData := add(lowLevelData, 0x04)
                }
                string memory revertReason = abi.decode(lowLevelData, (string));
                if (keccak256(bytes(revertReason)) == NO_BYTECODE_HASH) revert BytecodeMissing(_artifact);
            }
            revert ContractNotFound(_artifact);
        }
    }

    // ── CREATE2 ─────────────────────────────────────────────────────────

    function create2(Sender s, string memory _entropy, bytes memory bytecode)
        internal
        returns (Deployment storage deployment)
    {
        deployment = _deploy(s, bytecode);
        deployment.artifact = "<user-provided-bytecode>";
        deployment.entropy = _entropy;
        deployment.strategy = CreateStrategy.CREATE2;
    }

    function create2(Sender s, string memory _artifact) internal returns (Deployment storage deployment) {
        try vm.getCode(_artifact) returns (bytes memory code) {
            deployment = _deploy(s, code);
            deployment.artifact = _artifact;
            deployment.strategy = CreateStrategy.CREATE2;
        } catch Error(string memory reason) {
            bytes32 reasonHash = keccak256(bytes(reason));
            if (reasonHash == NO_BYTECODE_HASH) revert BytecodeMissing(_artifact);
            revert ContractNotFound(_artifact);
        } catch (bytes memory lowLevelData) {
            if (lowLevelData.length >= 68) {
                assembly {
                    lowLevelData := add(lowLevelData, 0x04)
                }
                string memory revertReason = abi.decode(lowLevelData, (string));
                if (keccak256(bytes(revertReason)) == NO_BYTECODE_HASH) revert BytecodeMissing(_artifact);
            }
            revert ContractNotFound(_artifact);
        }
    }

    // ── Salt Helpers ────────────────────────────────────────────────────

    function _salt(Sender s, string memory _entropy) internal pure returns (bytes32) {
        bytes11 entropy = bytes11(keccak256(bytes(_entropy)));
        return bytes32(abi.encodePacked(Sender.unwrap(s), hex"00", entropy));
    }

    function _derivedSalt(Sender s, bytes32 salt) internal view returns (bytes32 derivedSalt) {
        address deployer = Sender.unwrap(s);
        bytes1 saltFlag = salt[20];
        address saltAddress = address(bytes20(salt));

        if (saltAddress == deployer && saltFlag == hex"00") {
            derivedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), salt));
        } else if (saltAddress == deployer && saltFlag == hex"01") {
            derivedSalt = keccak256(abi.encode(deployer, block.chainid, salt));
        } else {
            derivedSalt = keccak256(abi.encode(salt));
        }
    }
}
