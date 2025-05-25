// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum DeployStrategy {
    CREATE2,
    CREATE3
}

enum DeploymentType {
    SINGLETON,
    PROXY,
    LIBRARY
}

struct DeploymentResult {
    address deployed;
    address predicted;
    ExecutionStatus status;
    bytes32 salt;
    bytes initCode;
    bytes32 safeTxHash;
}

enum DeployerType {
    PRIVATE_KEY,
    SAFE,
    LEDGER
}

struct Transaction {
    string label;
    address to;
    bytes data;
}

struct DeployerConfig {
    DeployerType deployerType;
    address safeAddress;
    uint256 privateKey;
    address senderAddress;
    string derivationPath;
}

enum ExecutionStatus {
    PENDING_SAFE,
    EXECUTED
}

struct ExecutionResult {
    ExecutionStatus status;
    bytes returnData;
}

function toString(ExecutionStatus executionStatus) pure returns (string memory) {
    if (executionStatus == ExecutionStatus.PENDING_SAFE) {
        return "PENDING_SAFE";
    } else if (executionStatus == ExecutionStatus.EXECUTED) {
        return "EXECUTED";
    }
    return "UNKNOWN";
}

function toString(DeploymentType deploymentType) pure returns (string memory) {
    if (deploymentType == DeploymentType.SINGLETON) {
        return "SINGLETON";
    } else if (deploymentType == DeploymentType.PROXY) {
        return "PROXY";
    } else if (deploymentType == DeploymentType.LIBRARY) {
        return "LIBRARY";
    }
    return "UNKNOWN";
}

function toString(DeployStrategy deployStrategy) pure returns (string memory) {
    if (deployStrategy == DeployStrategy.CREATE2) {
        return "CREATE2";
    } else if (deployStrategy == DeployStrategy.CREATE3) {
        return "CREATE3";
    }
    return "UNKNOWN";
}
