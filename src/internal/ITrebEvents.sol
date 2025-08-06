// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SimulatedTransaction} from "./types.sol";

/**
 * @title ITrebEvents
 * @notice Centralized interface for all Trebuchet internal events
 * @dev This interface consolidates all event definitions used throughout the Trebuchet library
 *      to ensure they appear properly in ABIs and provide a single source of truth for event signatures.
 *
 *      All internal contracts that emit events should reference this interface rather than
 *      defining events inline. This enables better tooling integration and ABI generation.
 */
interface ITrebEvents {
    /**
     * @notice Event data structure for deployment tracking
     * @dev Emitted in ContractDeployed event for comprehensive deployment auditing
     */
    struct DeploymentDetails {
        string artifact;
        string label;
        string entropy;
        bytes32 salt;
        bytes32 bytecodeHash;
        bytes32 initCodeHash;
        bytes constructorArgs;
        string createStrategy;
    }

    /**
     * @notice Emitted when a transaction is successfully simulated
     * @param simulatedTx Simulated transaction details
     */
    event TransactionSimulated(SimulatedTransaction simulatedTx);

    /**
     * @notice Emitted when a contract is successfully deployed
     * @param deployer The address that initiated the deployment
     * @param location The deployed contract address
     * @param transactionId Unique identifier for the deployment transaction
     * @param deployment Comprehensive deployment details
     */
    event ContractDeployed(
        address indexed deployer, address indexed location, bytes32 indexed transactionId, DeploymentDetails deployment
    );

    /**
     * @notice Emitted when transactions are queued for Safe multisig execution
     * @param safeTxHash Hash of the Safe transaction
     * @param safe Address of the Safe multisig contract
     * @param proposer Address of the proposer who queued the transaction
     * @param transactionIds Array of transaction IDs queued for execution
     */
    event SafeTransactionQueued(
        bytes32 indexed safeTxHash, address indexed safe, address indexed proposer, bytes32[] transactionIds
    );

    /**
     * @notice Emitted when transactions are executed directly on a threshold-1 Safe
     * @param safeTxHash Hash of the Safe transaction
     * @param safe Address of the Safe multisig contract
     * @param executor Address of the executor who performed the transaction
     * @param transactionIds Array of transaction IDs executed
     */
    event SafeTransactionExecuted(
        bytes32 indexed safeTxHash, address indexed safe, address indexed executor, bytes32[] transactionIds
    );

    /**
     * @notice Emitted when a deployment collision is detected and skipped
     * @param existingContract The address where the contract already exists
     * @param deploymentDetails The deployment details that would have been used
     * @dev This event is emitted when a contract already exists at the predicted address
     *      and the deployment is skipped to avoid reverting the entire transaction batch
     */
    event DeploymentCollision(address indexed existingContract, DeploymentDetails deploymentDetails);
}
