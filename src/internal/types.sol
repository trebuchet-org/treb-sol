// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title Deployment Types
 * @notice Common types used across the treb deployment system
 */

/**
 * @notice Configuration passed from CLI to deployment scripts
 * @dev This struct replaces environment variable usage for cleaner interface
 */
struct DeploymentConfig {
    // Deployment identification
    string projectName;        // Project name for salt generation
    string namespace;          // Deployment namespace (e.g., "default", "staging")
    string label;              // Deployment label for salt generation
    
    // Network information
    uint256 chainId;           // Chain ID for deployment
    string networkName;        // Human-readable network name
    
    // Sender configuration
    address sender;            // Transaction sender address
    string senderType;         // Type of sender (e.g., "private_key", "ledger", "safe")
    
    // Registry configuration
    address registryAddress;   // Address of the deployment registry (if exists)
    
    // Deployment flags
    bool broadcast;            // Whether to broadcast transactions
    bool verify;               // Whether to verify contracts after deployment
}

/**
 * @notice Extended deployment information for events
 */
struct DeploymentInfo {
    address deployedAddress;   // Address of deployed contract
    bytes32 salt;              // Salt used for deployment (if deterministic)
    bytes32 initCodeHash;      // Init code hash for address prediction
    string contractName;       // Name of the deployed contract
    string deploymentType;     // Type of deployment (singleton, proxy, library)
}