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

enum DeployerType {
    PRIVATE_KEY,
    SAFE,
    LEDGER
}

enum SenderType {
    PRIVATE_KEY,
    SAFE,
    LEDGER
}

enum ExecutionStatus {
    PENDING_SAFE,
    EXECUTED
}

struct Transaction {
    string label;
    address to;
    bytes data;
}

struct ExecutionResult {
    ExecutionStatus status;
    bytes returnData;
}

struct DeploymentResult {
    address deployed;
    address predicted;
    bytes32 salt;
    bytes initCode;
    bytes32 safeTxHash;
    bytes constructorArgs;
    // Converted from enum to string
    string status;
    string strategy;
    string deploymentType;
}


struct LibraryDeploymentConfig {
    ExecutorConfig executorConfig;
    string libraryArtifactPath;
}

struct ProxyDeploymentConfig {
    address implementationAddress;
    DeploymentConfig deploymentConfig;
}

struct DeploymentConfig {
    string namespace;
    string label;
    DeploymentType deploymentType;
    ExecutorConfig executorConfig;
}

struct ExecutorConfig {
    address sender;
    SenderType senderType;
    // senderType == PRIVATE_KEY
    uint256 senderPrivateKey;
    // senderType == LEDGER
    string senderDerivationPath;
    // senderType == SAFE
    SenderType proposerType;
    address proposer;
    // senderType == SAFE & proposerType == PRIVATE_KEY
    uint256 proposerPrivateKey;
    // senderType == SAFE & proposerType == LEDGER
    string proposerDerivationPath;
    // senderType == SAFE & proposerType == SAFE => will revert
}

function toString(DeployStrategy strategy) pure returns (string memory) {
    if (strategy == DeployStrategy.CREATE2) {
        return "CREATE2";
    } else if (strategy == DeployStrategy.CREATE3) {
        return "CREATE3";
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

function toString(ExecutionStatus status) pure returns (string memory) {
    if (status == ExecutionStatus.PENDING_SAFE) {
        return "PENDING_SAFE";
    } else if (status == ExecutionStatus.EXECUTED) {
        return "EXECUTED";
    }
    return "UNKNOWN";
}   