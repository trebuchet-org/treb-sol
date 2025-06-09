// SPDX-License-Identifier: MIT
// solhint-disable ordering
pragma solidity ^0.8.0;

/**
 * @title Senders
 * @notice Library providing an unified abstraction for multiple transaction execution methods.
 * @dev This library implements a modular transaction execution system that supports various sender types including
 *      private keys, hardware wallets, and Safe multisigs. It provides deterministic transaction ordering through
 *      a global queue system and handles both simulation and broadcast phases.
 *
 * ## Architecture Overview
 *
 * The Senders library is built around three main concepts:
 * 1. **Sender Abstraction**: Unified interface for different transaction execution methods
 * 2. **Global Transaction Queue**: Ordered execution queue ensuring deterministic transaction processing
 * 3. **Harness System**: Proxy contracts for secure execution context isolation
 *
 * ## Sender Types
 *
 * ### Private Key Senders
 * - **InMemory**: Ephemeral keys stored in memory (testing/development)
 * - **HardwareWallet**: Ledger/Trezor integration for production security
 * - Both support immediate transaction broadcast
 *
 * ### Safe Multisig Senders
 * - **GnosisSafe**: Safe multisig integration with transaction batching
 * - Accumulates transactions for batch execution
 * - Supports proposer patterns for multi-step workflows
 *
 * ### Custom Senders
 * - Extensible pattern for custom transaction execution logic
 * - Returns transactions for external processing
 *
 * ## Transaction Execution Flow
 *
 * 1. **Simulation Phase**: All transactions are simulated using vm.prank() to validate execution
 * 2. **Queue Management**: Transactions are added to a global queue maintaining submission order
 * 3. **Broadcast Phase**: Transactions are executed based on sender type:
 *    - Sync: Immediate broadcast (private keys)
 *    - Async: Batched execution (Safe multisig)
 *    - Custom: External processing required
 *
 * ## Global Transaction Queue System
 *
 * The library maintains a global transaction queue (`_globalQueue`) that ensures deterministic ordering:
 * - All transactions are queued in submission order regardless of sender
 * - Sync senders (private keys) execute immediately during broadcast
 * - Async senders (Safe) accumulate transactions for batch execution
 * - Queue is processed linearly during the broadcast phase
 *
 * ## Harness System
 *
 * For each sender-target pair, the library creates a Harness proxy contract that:
 * - Provides execution context isolation
 * - Enables secure cross-contract calls
 * - Maintains sender identity for access control
 * - Supports complex deployment scenarios
 *
 * ## Configuration Examples
 *
 * ```solidity
 * // Development setup with in-memory keys
 * SenderInitConfig[] memory configs = new SenderInitConfig[](1);
 * configs[0] = SenderInitConfig({
 *     name: "deployer",
 *     account: vm.addr(deployerKey),
 *     senderType: SenderTypes.InMemory,
 *     config: abi.encode(deployerKey)
 * });
 *
 * // Production setup with hardware wallet + Safe
 * configs = new SenderInitConfig[](2);
 * configs[0] = SenderInitConfig({
 *     name: "proposer",
 *     account: ledgerAddress,
 *     senderType: SenderTypes.HardwareWallet,
 *     config: abi.encode(derivationPath)
 * });
 * configs[1] = SenderInitConfig({
 *     name: "safe",
 *     account: safeAddress,
 *     senderType: SenderTypes.GnosisSafe,
 *     config: abi.encode(SafeConfig({
 *         safe: safeAddress,
 *         proposer: "proposer",
 *         threshold: 2
 *     }))
 * });
 * ```
 *
 * ## Usage Pattern
 *
 * ```solidity
 * // Initialize senders
 * Senders.initialize(configs);
 *
 * // Execute transactions
 * Sender storage deployer = Senders.get("deployer");
 * deployer.execute(Transaction({
 *     to: targetContract,
 *     value: 0,
 *     data: deploymentData,
 *     label: "Deploy MyContract"
 * }));
 *
 * // Broadcast all queued transactions
 * Senders.broadcast(Senders.registry());
 * ```
 */
import {Vm} from "forge-std/Vm.sol";
import {PrivateKey, HardwareWallet, InMemory} from "./PrivateKeySender.sol";
import {GnosisSafe} from "./GnosisSafeSender.sol";
import {Harness} from "../Harness.sol";
import {ITrebEvents} from "../ITrebEvents.sol";

import {Transaction, SimulatedTransaction, SenderTypes} from "../types.sol";

library Senders {
    using Senders for Senders.Registry;
    using Senders for Senders.Sender;
    using PrivateKey for PrivateKey.Sender;
    using HardwareWallet for HardwareWallet.Sender;
    using GnosisSafe for GnosisSafe.Sender;
    using InMemory for InMemory.Sender;

    /**
     * @notice Configuration structure for initializing a sender
     * @param name Human-readable identifier for the sender (e.g., "deployer", "proposer")
     * @param account Ethereum address associated with this sender
     * @param senderType Type identifier from SenderTypes (InMemory, HardwareWallet, GnosisSafe, Custom)
     * @param config ABI-encoded type-specific configuration data
     */
    struct SenderInitConfig {
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
    }

    /**
     * @notice Central registry managing all senders and transaction coordination
     * @dev Uses storage slots to avoid conflicts with inheriting contracts
     * @param senders Mapping of sender ID to Sender struct
     * @param senderHarness Mapping of sender ID to target address to harness proxy address
     * @param ids Array of all registered sender IDs for iteration
     * @param _globalQueue Global transaction queue maintaining submission order across all senders
     * @param namespace Current deployment namespace (default, staging, production)
     * @param snapshot VM state snapshot taken before transaction simulation
     * @param _broadcasted Flag preventing multiple broadcast calls
     * @param broadcastQueued Flag preventing nested broadcast - only outermost broadcast triggers
     * @param _transactionCounter Monotonic counter for generating unique transaction IDs
     */
    struct Registry {
        mapping(bytes32 => Sender) senders;
        mapping(bytes32 => mapping(address => address)) senderHarness;
        bytes32[] ids;
        SimulatedTransaction[] _globalQueue;
        string namespace;
        bool quiet;
        bool initialized;
        uint256 preSimulationSnapshot;
        bool broadcasted;
        bool broadcastQueued;
        uint256 transactionCounter;
    }

    /**
     * @notice Individual sender configuration and state
     * @param id Unique identifier derived from keccak256(name)
     * @param name Human-readable sender name
     * @param account Ethereum address for this sender
     * @param senderType Type bitfield indicating sender capabilities
     * @param config ABI-encoded type-specific configuration
     */
    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
    }

    /// @dev Storage slot for the Registry singleton, derived from keccak256("senders.registry")
    /// @dev This ensures the registry doesn't conflict with other storage in inherited contracts
    bytes32 private constant REGISTRY_STORAGE_SLOT = 0xec6e4b146920a90a3174833331c3e69622ec7d9a352328df6e7b536886008f0e;

    /// @dev Foundry VM interface for simulation and state management
    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    /// @notice Thrown when attempting to cast a sender to an incompatible type
    error InvalidCast(string name, bytes8 senderType, bytes8 requiredType);

    /// @notice Thrown when a sender type is not recognized or supported
    error InvalidSenderType(string name, bytes8 senderType);

    /// @notice Thrown when trying to access a sender that hasn't been initialized
    error SenderNotInitialized(string name);

    /// @notice Thrown when attempting to initialize registry with empty sender array
    error NoSenders();

    /// @notice Thrown when simulation and execution return data don't match
    error TransactionExecutionMismatch(string label, bytes returnData);

    /// @notice Thrown when attempting to broadcast a custom sender through the standard mechanism
    error CannotBroadcastCustomSender(string name);

    /// @notice Thrown when an unexpected sender type attempts to broadcast
    error UnexpectedSenderBroadcast(string name, bytes8 senderType);

    /// @notice Thrown when broadcast() is called multiple times on the same registry
    error BroadcastAlreadyCalled();

    /// @notice Thrown when execute() is called with an empty transaction array
    error EmptyTransactionArray();

    /// @notice Thrown when a transaction has an invalid (zero) target address
    error InvalidTargetAddress(uint256 index);

    /// @notice Thrown when attempting to initialize a registry that has already been initialized
    error RegistryAlreadyInitialized();

    /// @notice Thrown when attempting to broadcast a sender that cannot broadcast
    error CannotBroadcast(string name);

    /**
     * @notice Retrieves the singleton Registry instance using storage slots
     * @dev Uses assembly to access a deterministic storage slot, avoiding conflicts with inheriting contracts
     * @return _registry The global sender registry instance
     */
    function registry() internal pure returns (Registry storage _registry) {
        assembly {
            _registry.slot := REGISTRY_STORAGE_SLOT
        }
    }

    /**
     * @notice Generates a unique transaction ID for tracking and correlation
     * @dev Combines chain ID, timestamp, sender address, and an incrementing counter to ensure uniqueness
     * @return Unique transaction identifier used for event correlation and debugging
     */
    function generateTransactionId() internal returns (bytes32) {
        Registry storage _registry = registry();
        _registry.transactionCounter++;
        // solhint-disable-next-line not-rely-on-time
        return keccak256(abi.encodePacked(block.chainid, block.timestamp, msg.sender, _registry.transactionCounter));
    }

    // ************* Registry Management ************* //

    /**
     * @notice Initializes registry with sender configurations including quiet mode
     * @param _configs Array of sender configurations to register
     * @param _namespace Deployment namespace
     * @param _quiet Whether to suppress internal event logs
     */
    function initialize(SenderInitConfig[] memory _configs, string memory _namespace, bool _quiet) internal {
        initialize(registry(), _configs, _namespace, _quiet);
    }

    /**
     * @notice Initializes registry with sender configurations including quiet mode
     * @param _registry Registry storage reference
     * @param _configs Array of sender configurations to register
     * @param _namespace Deployment namespace
     * @param _quiet Whether to suppress internal event logs
     */
    function initialize(
        Registry storage _registry,
        SenderInitConfig[] memory _configs,
        string memory _namespace,
        bool _quiet
    ) internal {
        if (_registry.initialized) {
            revert RegistryAlreadyInitialized();
        }

        _registry.namespace = _namespace;
        _registry.initialized = true;
        _registry.quiet = _quiet;

        if (_configs.length == 0) {
            revert NoSenders();
        }
        _initializeSenders(_registry, _configs);
    }

    /**
     * @notice Internal helper to set up all senders in the registry
     * @dev Performs two-phase initialization:
     *      1. Register all sender configurations
     *      2. Initialize each sender's type-specific state
     * @param _registry The registry to populate
     * @param _configs Array of sender configurations
     */
    function _initializeSenders(Registry storage _registry, SenderInitConfig[] memory _configs) private {
        _registry.ids = new bytes32[](_configs.length);
        unchecked {
            for (uint256 i; i < _configs.length; ++i) {
                bytes32 senderId = keccak256(abi.encodePacked(_configs[i].name));
                _registry.senders[senderId].id = senderId;
                _registry.senders[senderId].name = _configs[i].name;
                _registry.senders[senderId].account = _configs[i].account;
                _registry.senders[senderId].senderType = _configs[i].senderType;
                _registry.senders[senderId].canBroadcast = _configs[i].canBroadcast;
                _registry.senders[senderId].config = _configs[i].config;
                _registry.ids[i] = senderId;
            }
        }

        unchecked {
            for (uint256 i; i < _registry.ids.length; ++i) {
                _registry.senders[_registry.ids[i]].initialize();
            }
        }

        _registry.preSimulationSnapshot = vm.snapshotState();
    }

    /**
     * @notice Retrieves a sender from the global registry by ID
     * @param _id Unique sender identifier
     * @return Sender storage reference
     */
    function get(bytes32 _id) internal view returns (Sender storage) {
        return get(registry(), _id);
    }

    /**
     * @notice Retrieves a sender from the global registry by name
     * @param _name Human-readable sender name
     * @return Sender storage reference
     */
    function get(string memory _name) internal view returns (Sender storage) {
        return registry().get(_name);
    }

    /**
     * @notice Retrieves a sender from a specific registry by name
     * @param _registry The registry to search in
     * @param _name Human-readable sender name
     * @return Sender storage reference
     * @dev Reverts if sender is not initialized (account == address(0))
     */
    function get(Registry storage _registry, string memory _name) internal view returns (Sender storage) {
        Sender storage sender = _registry.senders[keccak256(abi.encodePacked(_name))];
        if (sender.account == address(0)) {
            revert SenderNotInitialized(_name);
        }
        return sender;
    }

    /**
     * @notice Retrieves a sender from a specific registry by ID
     * @param _registry The registry to search in
     * @param _id Unique sender identifier
     * @return Sender storage reference
     */
    function get(Registry storage _registry, bytes32 _id) internal view returns (Sender storage) {
        return _registry.senders[_id];
    }

    // ************* Sender Operations ************* //

    /**
     * @notice Initializes a sender's type-specific state
     * @dev Dispatches to the appropriate type-specific initialization function
     * @param _sender The sender to initialize
     */
    function initialize(Sender storage _sender) internal {
        if (_sender.isType(SenderTypes.InMemory)) {
            _sender.inMemory().initialize();
        } else if (_sender.isType(SenderTypes.HardwareWallet)) {
            _sender.hardwareWallet().initialize();
        } else if (_sender.isType(SenderTypes.GnosisSafe)) {
            _sender.gnosisSafe().initialize();
        } else if (!_sender.isType(SenderTypes.Custom)) {
            revert InvalidSenderType(_sender.name, _sender.senderType);
        }
    }

    /**
     * @notice Checks if a sender matches a specific type by string name
     * @param _sender The sender to check
     * @param _type Type name to check against (e.g., "InMemory", "HardwareWallet")
     * @return True if the sender matches the specified type
     */
    function isType(Sender storage _sender, string memory _type) internal view returns (bool) {
        bytes8 typeHash = bytes8(keccak256(abi.encodePacked(_type)));
        return _sender.isType(typeHash);
    }

    /**
     * @notice Checks if a sender matches a specific type by hash
     * @param _sender The sender to check
     * @param _type Type hash to check against
     * @return True if the sender matches the specified type
     */
    function isType(Sender storage _sender, bytes8 _type) internal view returns (bool) {
        return _sender.senderType & _type == _type;
    }

    /**
     * @notice Casts a sender to a PrivateKey sender type
     * @param _sender The sender to cast
     * @return PrivateKey.Sender storage reference
     */
    function privateKey(Sender storage _sender) internal view returns (PrivateKey.Sender storage) {
        return PrivateKey.cast(_sender);
    }

    /**
     * @notice Casts a sender to a HardwareWallet sender type
     * @param _sender The sender to cast
     * @return HardwareWallet.Sender storage reference
     */
    function hardwareWallet(Sender storage _sender) internal view returns (HardwareWallet.Sender storage) {
        return HardwareWallet.cast(_sender);
    }

    /**
     * @notice Casts a sender to a GnosisSafe sender type
     * @param _sender The sender to cast
     * @return GnosisSafe.Sender storage reference
     */
    function gnosisSafe(Sender storage _sender) internal view returns (GnosisSafe.Sender storage) {
        return GnosisSafe.cast(_sender);
    }

    /**
     * @notice Casts a sender to an InMemory sender type
     * @param _sender The sender to cast
     * @return InMemory.Sender storage reference
     */
    function inMemory(Sender storage _sender) internal view returns (InMemory.Sender storage) {
        return InMemory.cast(_sender);
    }

    /**
     * @notice Gets or creates a harness proxy contract for a sender-target pair
     * @dev Harness contracts provide execution context isolation and enable secure cross-contract calls
     * @param _sender The sender requiring a harness
     * @param _target The target contract address
     * @return Address of the harness proxy contract
     */
    function harness(Sender storage _sender, address _target) internal returns (address) {
        Registry storage reg = registry();
        address _harness = reg.senderHarness[_sender.id][_target];
        if (_harness == address(0)) {
            _harness = address(new Harness(_target, _sender.name, _sender.id));
            reg.senderHarness[_sender.id][_target] = _harness;
        }
        return _harness;
    }

    // ************* Transaction Execution ************* //

    /**
     * @notice Executes an array of transactions through a sender
     * @dev Validates transaction array and target addresses, then delegates to simulate()
     * @param _sender The sender to execute transactions through
     * @param _transactions Array of transactions to execute
     * @return simulatedTransactions Array of simulated transactions with results and queue tracking
     */
    function execute(Sender storage _sender, Transaction[] memory _transactions)
        internal
        returns (SimulatedTransaction[] memory simulatedTransactions)
    {
        if (!_sender.canBroadcast) revert CannotBroadcast(_sender.name);
        if (_transactions.length == 0) revert EmptyTransactionArray();
        for (uint256 i = 0; i < _transactions.length; i++) {
            if (_transactions[i].to == address(0)) revert InvalidTargetAddress(i);
        }
        return _sender.simulate(_transactions);
    }

    /**
     * @notice Executes a single transaction through a sender
     * @dev Convenience wrapper for single transaction execution
     * @param _sender The sender to execute the transaction through
     * @param _transaction Transaction to execute
     * @return simulatedTransaction Simulated transaction with results
     */
    function execute(Sender storage _sender, Transaction memory _transaction)
        internal
        returns (SimulatedTransaction memory simulatedTransaction)
    {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = _transaction;
        SimulatedTransaction[] memory simulatedTransactions = _sender.execute(transactions);
        return simulatedTransactions[0];
    }

    /**
     * @notice Simulates transaction execution using vm.prank() and adds to global queue
     * @dev This is the core transaction processing function that:
     *      1. Generates unique transaction IDs for tracking
     *      2. Simulates execution using vm.prank() to impersonate the sender
     *      3. Emits events for successful simulation
     *      4. Creates SimulatedTransaction objects with simulation results
     *      5. Adds transactions to global queue in submission order
     * @param _sender The sender to simulate transactions for
     * @param _transactions Array of transactions to simulate
     * @return simulatedTransactions Array of simulated transactions with results
     */
    function simulate(Sender storage _sender, Transaction[] memory _transactions)
        internal
        returns (SimulatedTransaction[] memory simulatedTransactions)
    {
        Registry storage _registry = registry();
        simulatedTransactions = new SimulatedTransaction[](_transactions.length);

        for (uint256 i = 0; i < _transactions.length; i++) {
            // Generate unique transaction ID
            bytes32 transactionId = generateTransactionId();

            vm.prank(_sender.account);
            (bool success, bytes memory returnData) =
                _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);

            if (!success) {
                // Bubble up the revert reason from the failed call
                assembly {
                    let dataSize := mload(returnData)
                    revert(add(returnData, 0x20), dataSize)
                }
            }

            SimulatedTransaction memory simulatedTx = SimulatedTransaction({
                transaction: _transactions[i],
                transactionId: transactionId,
                senderId: _sender.id,
                sender: _sender.account,
                returnData: returnData
            });

            // Only emit events if not in quiet mode
            if (!registry().quiet && success) {
                emit ITrebEvents.TransactionSimulated(simulatedTx);
            }

            simulatedTransactions[i] = simulatedTx;
            // Add to global queue in order
            _registry._globalQueue.push(simulatedTx);
        }
        return simulatedTransactions;
    }

    // ************* Global Transaction Broadcasting ************* //

    /**
     * @notice Broadcasts all queued transactions maintaining their original submission order
     * @dev Implements a sophisticated broadcast mechanism that handles different sender types:
     *
     * ## Broadcast Process
     * 1. **State Management**: Captures current VM state and reverts to pre-simulation snapshot
     * 2. **Order Preservation**: Processes transactions from global queue in submission order
     * 3. **Type-Specific Handling**:
     *    - **PrivateKey/HardwareWallet**: Immediate synchronous broadcast
     *    - **GnosisSafe**: Queue for batch execution (async)
     *    - **Custom**: Collect for external processing
     * 4. **Batch Execution**: Execute accumulated async transactions as bundles
     * 5. **State Restoration**: Restore VM state and mark broadcast as complete
     *
     * ## Sender Type Processing
     *
     * ### Synchronous Senders (PrivateKey)
     * - Transactions are broadcast immediately when encountered in the queue
     * - Suitable for development and single-signer production scenarios
     * - No batching or accumulation occurs
     *
     * ### Asynchronous Senders (GnosisSafe)
     * - Transactions are accumulated into sender-specific queues
     * - After processing all transactions, each Safe executes its accumulated batch
     * - Enables efficient multi-sig workflows with reduced gas costs
     * - Supports complex proposer patterns
     *
     * ### Custom Senders
     * - Transactions are collected and returned for external processing
     * - Allows integration with custom execution environments
     * - Caller is responsible for handling these transactions
     *
     * ## Global Queue Ordering
     * The global queue ensures that regardless of sender type, transactions are processed
     * in the exact order they were submitted. This is crucial for:
     * - Deterministic deployments
     * - Contract dependency resolution
     * - State consistency across different execution contexts
     *
     * @param _registry The sender registry containing all queued transactions
     * @return customQueue Array of custom sender transactions requiring external processing
     */
    function broadcast(Registry storage _registry) internal returns (SimulatedTransaction[] memory customQueue) {
        if (_registry.broadcasted) {
            revert BroadcastAlreadyCalled();
        }

        uint256 postSimulationSnapshot = vm.snapshotState();

        customQueue = new SimulatedTransaction[](_registry._globalQueue.length);
        SimulatedTransaction[] memory txs = _registry._globalQueue;
        bytes32[] memory senderIds = _registry.ids;

        vm.revertToState(_registry.preSimulationSnapshot);
        uint256 actualCustomQueueLength = 0;

        // Process each transaction in global queue order
        for (uint256 i = 0; i < txs.length; i++) {
            SimulatedTransaction memory simulatedTx = txs[i];
            Sender storage sender = _registry.senders[simulatedTx.senderId];

            if (sender.isType(SenderTypes.PrivateKey)) {
                // Sync execution - broadcast immediately
                sender.privateKey().broadcast(simulatedTx);
            } else if (sender.isType(SenderTypes.GnosisSafe)) {
                // Async execution - accumulate for batch
                sender.gnosisSafe().queue(simulatedTx);
            } else if (sender.isType(SenderTypes.Custom)) {
                customQueue[actualCustomQueueLength] = simulatedTx;
                actualCustomQueueLength++;
            }
        }

        assembly {
            mstore(customQueue, actualCustomQueueLength)
        }

        // Now broadcast accumulated async transactions as bundles
        for (uint256 i = 0; i < senderIds.length; i++) {
            Sender storage sender = _registry.senders[senderIds[i]];
            if (sender.isType(SenderTypes.GnosisSafe)) {
                sender.gnosisSafe().broadcast();
            }
        }

        vm.revertToState(postSimulationSnapshot);
        _registry.broadcasted = true;
        return customQueue;
    }
}
