// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Senders} from "./sender/Senders.sol";
import {Transaction, SimulatedTransaction} from "./types.sol";
import {ITrebEvents} from "./ITrebEvents.sol";

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
contract SenderCoordinator is Script, ITrebEvents {
    using Senders for Senders.Registry;
    using Senders for Senders.Sender;

    /// @notice Whether the senders have been initialized
    bool private initialized;
    /// @notice Deployment namespace (e.g., "default", "staging", "production")
    string private namespace;
    /// @notice Whether to run in dry-run mode (no actual transactions)
    bool private dryrun;
    /// @notice Whether to suppress internal logs
    bool private quiet;

    /// @notice Thrown when sender configurations are empty
    error NoSenderInitConfigs();

    /// @notice Thrown when a requested sender ID is not found in the registry
    /// @param id The sender ID that was not found
    error SenderNotFound(string id);

    /// @notice Thrown when custom sender transactions are queued but processCustomQueue is not implemented
    error CustomQueueReceiverNotImplemented();

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
        if (!broadcastAlreadyQueued && !dryrun) {
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
        string memory _network,
        bool _dryrun,
        bool _quiet
    ) {
        Senders.initialize(_senderInitConfigs, _namespace, _network, _quiet);
        namespace = _namespace;
        dryrun = _dryrun;
        quiet = _quiet;
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
     * @return simulatedTransactions Array of executed transactions with results including status and return data
     */
    function execute(
        bytes32 _senderId,
        Transaction[] memory _transactions
    ) external returns (SimulatedTransaction[] memory simulatedTransactions) {
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
     * @return simulatedTransaction Executed transaction with results including status and return data
     */
    function execute(
        bytes32 _senderId,
        Transaction memory _transaction
    ) external returns (SimulatedTransaction memory simulatedTransaction) {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transaction);
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
        SimulatedTransaction[] memory customQueue = Senders
            .registry()
            .broadcast();
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
     * function processCustomQueue(SimulatedTransaction[] memory _customQueue) internal override {
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
        SimulatedTransaction[] memory _customQueue
    ) internal virtual {
        if (_customQueue.length > 0) {
            /// @dev override this function to implement custom queue processing
            revert CustomQueueReceiverNotImplemented();
        }
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
    ) internal view returns (Senders.Sender storage) {
        return Senders.registry().get(_name);
    }
}
