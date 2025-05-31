// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Senders} from "./sender/Senders.sol";
import {Transaction, RichTransaction} from "./types.sol";

/**
 * @title SenderCoordinator
 * @author Trebuchet Team
 * @notice Orchestrates transaction execution across different wallet types (EOA, hardware wallets, Safe multisig)
 * @dev This contract provides a unified interface for executing transactions through various sender types.
 * It implements lazy initialization for sender configurations and automatic transaction broadcasting.
 *
 * The coordinator supports:
 * - Private key senders (EOA accounts)
 * - Hardware wallet senders (Ledger, Trezor)
 * - Safe multisig senders
 * - Custom sender types via the processCustomQueue override
 * - Safe nested broadcast handling via broadcastQueued flag
 *
 * Usage example:
 * ```solidity
 * contract MyDeployScript is SenderCoordinator {
 *     function run() public broadcast {
 *         // Get a sender by name (e.g., "default", "staging", "production")
 *         Senders.Sender storage deployer = sender("default");
 *
 *         // Execute transactions through the sender
 *         address deployed = deployer.deployCreate3("MyContract");
 *
 *         // All transactions are automatically broadcast at the end
 *     }
 * }
 * ```
 */
contract SenderCoordinator is Script {
    using Senders for Senders.Registry;
    using Senders for Senders.Sender;

    /// @notice Thrown when sender configurations are empty
    error NoSenderInitConfigs();

    /// @notice Thrown when a requested sender ID is not found in the registry
    /// @param id The sender ID that was not found
    error SenderNotFound(string id);

    /// @notice Thrown when custom sender transactions are queued but processCustomQueue is not implemented
    error CustomQueueReceiverNotImplemented();

    /**
     * @dev Internal state for lazy initialization and configuration.
     * This struct stores the raw configuration data until first use,
     * implementing a lazy initialization pattern to avoid unnecessary
     * setup costs when senders are not used.
     */
    struct DispatcherConfig {
        bool initialized; // Whether the senders have been initialized
        Senders.SenderInitConfig[] senderInitConfigs; // Sender Configurations
        string namespace; // Deployment namespace (e.g., "default", "staging", "production")
        bool dryrun; // Whether to run in dry-run mode (no actual transactions)
    }

    DispatcherConfig private config;

    /**
     * @notice Modifier that automatically broadcasts all queued transactions after function execution
     * @dev This modifier is crucial for the sender coordination pattern. It ensures that:
     * 1. All transactions queued during function execution are collected
     * 2. Transactions are broadcast in the correct order
     * 3. Custom sender types (e.g., Safe multisig) get their transactions processed
     * 4. Nested broadcast calls are handled safely - only the outermost call triggers broadcast
     *
     * The modifier uses a `broadcastQueued` flag to prevent nested broadcast issues:
     * - If no broadcast is queued, it sets the flag and will trigger broadcast at the end
     * - If a broadcast is already queued (nested call), it does nothing
     * - Only the outermost modifier call actually triggers `_broadcast()`
     *
     * Example usage:
     * ```solidity
     * function deployContracts() public broadcast {
     *     // All deployments here will be queued
     *     sender("default").deployCreate3("ContractA");
     *     sender("default").deployCreate3("ContractB");
     *     // Transactions are automatically broadcast when function ends
     * }
     * ```
     */
    modifier broadcast() {
        // Check if broadcast is already queued (nested call)
        bool broadcastAlreadyQueued = Senders.registry().broadcastQueued;
        
        // If not already queued, mark as queued
        if (!broadcastAlreadyQueued) {
            Senders.registry().broadcastQueued = true;
        }
        
        _;
        
        // Only broadcast if this was the outermost call
        if (!broadcastAlreadyQueued) {
            Senders.registry().broadcastQueued = false;
            _broadcast();
        }
    }

    /**
     * @notice Constructs a new SenderCoordinator with the given configuration
     * @param _senderInitConfigs array of SenderInitConfig structs containing sender configurations
     * @param _namespace Deployment namespace to use (e.g., "default", "staging", "production")
     * @param _dryrun Whether to run in dry-run mode without executing actual transactions
     * @dev The actual initialization is deferred until the first sender is requested (lazy initialization)
     */
    constructor(
        Senders.SenderInitConfig[] memory _senderInitConfigs,
        string memory _namespace,
        bool _dryrun
    ) {
        // Manually copy memory array to storage
        for (uint256 i = 0; i < _senderInitConfigs.length; i++) {
            config.senderInitConfigs.push(_senderInitConfigs[i]);
        }
        config.namespace = _namespace;
        config.dryrun = _dryrun;
    }

    /**
     * @notice Initializes all configured senders from the raw configuration data
     * @dev This function implements the lazy initialization pattern:
     * - Only called when the first sender is requested
     * - Decodes the raw configs and initializes all senders at once
     * - Sets the initialized flag to prevent re-initialization
     *
     * The function will revert if:
     * - rawConfigs is empty
     * - Decoding fails or results in empty array
     */
    function _initialize() internal {
        if (config.senderInitConfigs.length == 0) {
            revert NoSenderInitConfigs();
        }

        Senders.initialize(
            config.senderInitConfigs,
            config.namespace,
            config.dryrun
        );
    }

    /**
     * @notice Retrieves a sender by name, initializing the registry if needed
     * @param _name The name/ID of the sender to retrieve (e.g., "default", "staging")
     * @return The requested sender instance
     * @dev This function implements lazy initialization:
     * 1. Checks if senders have been initialized
     * 2. If not, calls _initialize() to set up all senders
     * 3. Returns the requested sender from the registry
     *
     * Example usage:
     * ```solidity
     * Senders.Sender storage deployer = sender("default");
     * address newContract = deployer.deployCreate3("MyContract");
     * ```
     */
    function sender(
        string memory _name
    ) internal returns (Senders.Sender storage) {
        if (!config.initialized) {
            _initialize();
            config.initialized = true;
        }
        return Senders.registry().get(_name);
    }

    /**
     * @notice Broadcasts all queued transactions from all senders
     * @dev This internal function is called by the broadcast modifier and:
     * 1. Calls broadcast() on the sender registry to execute standard transactions
     * 2. Receives any custom sender transactions that need external processing
     * 3. Passes custom transactions to processCustomQueue for handling
     *
     * The separation between standard and custom queues allows for:
     * - Direct execution of EOA and hardware wallet transactions
     * - Special handling for Safe multisig or other custom sender types
     */
    function _broadcast() internal {
        RichTransaction[] memory customQueue = Senders.registry().broadcast();
        processCustomQueue(customQueue);
    }

    /**
     * @notice Process custom sender transactions that require external handling
     * @dev Override this function in derived contracts to handle custom sender types.
     * This is particularly useful for:
     * - Safe multisig transactions that need to be proposed
     * - Hardware wallet transactions that need special formatting
     * - Any sender type that can't execute transactions directly
     *
     * @param _customQueue Array of transactions from custom senders that couldn't be executed directly
     *
     * Example override:
     * ```solidity
     * function processCustomQueue(RichTransaction[] memory _customQueue) internal override {
     *     for (uint i = 0; i < _customQueue.length; i++) {
     *         if (_customQueue[i].senderType == SenderType.Safe) {
     *             // Submit to Safe multisig
     *             proposeSafeTransaction(_customQueue[i]);
     *         }
     *     }
     * }
     * ```
     */
    function processCustomQueue(
        RichTransaction[] memory _customQueue
    ) internal virtual {
        if (_customQueue.length > 0) {
            /// @dev override this function to implement custom queue processing
            revert CustomQueueReceiverNotImplemented();
        }
    }

    /**
     * @notice Execute multiple transactions through a specific sender
     * @dev This function is primarily used by the harness proxy system to execute
     * transactions with proper sender context. It bypasses the broadcast modifier
     * for immediate execution, which is necessary for the harness to provide
     * seamless contract interaction. Also useful for testing and debugging.
     *
     * @param _senderId The ID of the sender to use (typically provided by harness)
     * @param _transactions Array of transactions to execute
     * @return bundleTransactions Array of executed transactions with results including status and return data
     */
    function execute(
        bytes32 _senderId,
        Transaction[] memory _transactions
    ) external returns (RichTransaction[] memory bundleTransactions) {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transactions);
    }

    /**
     * @notice Execute a single transaction through a specific sender
     * @dev This function is primarily used by the harness proxy system for
     * single transaction execution. It provides immediate execution bypassing
     * the broadcast modifier, enabling the harness to proxy individual function
     * calls with the correct sender context. Also useful for testing.
     *
     * @param _senderId The ID of the sender to use (typically provided by harness)
     * @param _transaction Transaction to execute
     * @return bundleTransaction Executed transaction with results including status and return data
     */
    function execute(
        bytes32 _senderId,
        Transaction memory _transaction
    ) external returns (RichTransaction memory bundleTransaction) {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transaction);
    }
}

