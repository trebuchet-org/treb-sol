// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RichTransaction} from "./types.sol";
import {Deployer} from "./sender/Deployer.sol";

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
    // *************** TRANSACTION LIFECYCLE EVENTS *************** //

    /**
     * @notice Emitted when we start broadcasting transactions
     */
    event BroadcastStarted();

    /**
     * @notice Emitted when a transaction simulation fails during execution
     * @param transactionId Unique identifier for the failed transaction
     * @param sender Address of the sender that attempted the transaction
     * @param to Target contract address
     * @param value Ether value sent with the transaction
     * @param data Transaction calldata
     * @param label Human-readable transaction description
     */
    event TransactionFailed(
        bytes32 indexed transactionId,
        address indexed sender,
        address indexed to,
        uint256 value,
        bytes data,
        string label
    );

    /**
     * @notice Emitted when a transaction is successfully simulated
     * @param transactionId Unique identifier for the transaction
     * @param sender Address of the sender executing the transaction
     * @param to Target contract address
     * @param value Ether value sent with the transaction
     * @param data Transaction calldata
     * @param label Human-readable transaction description
     * @param returnData Return data from the successful simulation
     */
    event TransactionSimulated(
        bytes32 indexed transactionId,
        address indexed sender,
        address indexed to,
        uint256 value,
        bytes data,
        string label,
        bytes returnData
    );

    /**
     * @notice Emitted when a transaction is broadcast via PrivateKey sender
     * @param transactionId Unique identifier for the transaction
     * @param sender Address of the sender executing the transaction
     * @param to Target contract address
     * @param value Ether value sent with the transaction
     * @param data Transaction calldata
     * @param label Human-readable transaction description
     * @param returnData Return data from the execution
     */
    event TransactionBroadcast(
        bytes32 indexed transactionId,
        address indexed sender,
        address indexed to,
        uint256 value,
        bytes data,
        string label,
        bytes returnData
    );

    // *************** DEPLOYMENT EVENTS *************** //

    /**
     * @notice Emitted when a contract deployment is initiated
     * @param what The artifact path or contract name being deployed
     * @param label Optional label for deployment categorization
     * @param initCodeHash Hash of the initialization code (bytecode + constructor args)
     */
    event DeployingContract(string what, string label, bytes32 initCodeHash);

    /**
     * @notice Emitted when a contract is successfully deployed
     * @param deployer The address that initiated the deployment
     * @param location The deployed contract address
     * @param transactionId Unique identifier for the deployment transaction
     * @param deployment Comprehensive deployment details
     */
    event ContractDeployed(
        address indexed deployer,
        address indexed location,
        bytes32 indexed transactionId,
        Deployer.EventDeployment deployment
    );

    // *************** MULTISIG EVENTS *************** //

    /**
     * @notice Emitted when transactions are queued for Safe multisig execution
     * @param safeTxHash Hash of the Safe transaction
     * @param safe Address of the Safe multisig contract
     * @param proposer Address of the proposer who queued the transaction
     * @param transactions Array of transactions queued for execution
     */
    event SafeTransactionQueued(
        bytes32 indexed safeTxHash, address indexed safe, address indexed proposer, RichTransaction[] transactions
    );
}
