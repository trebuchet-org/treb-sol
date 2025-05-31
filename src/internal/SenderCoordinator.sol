// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Senders} from "./sender/Senders.sol";
import {Deployer} from "./sender/Deployer.sol";
import {Transaction, RichTransaction} from "./types.sol";

contract SenderCoordinator is Script {
    error InvalidSenderConfigs();
    error SenderNotFound(string id);
    error CustomQueueReceiverNotImplemented();

    using Senders for Senders.Registry;
    using Senders for Senders.Sender;

    /// @notice Modifier that automatically broadcasts transactions after function execution
    /// @dev Used to ensure all queued transactions are broadcast at the end of execution
    modifier broadcast() {
        _;
        _broadcast();
    }

    /// @dev Internal state for lazy initialization and configuration
    struct DispatcherConfig {
        bool initialized;
        bytes rawConfigs;
        string namespace;
        bool dryrun;
    }
    
    DispatcherConfig private config;

    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun) {
        config.rawConfigs = _rawConfigs;
        config.namespace = _namespace;
        config.dryrun = _dryrun;
    }

    function _initialize() internal {
        if (config.rawConfigs.length == 0) {
            revert InvalidSenderConfigs();
        }
        Senders.SenderInitConfig[] memory configs = abi.decode(config.rawConfigs, (Senders.SenderInitConfig[]));
        if (configs.length == 0) {
            revert InvalidSenderConfigs();
        }

        Senders.initialize(configs, config.namespace, config.dryrun);
    }

    function sender(string memory _name) internal returns (Senders.Sender storage) {
        if (!config.initialized) {
            _initialize();
            config.initialized = true;
        }
        return Senders.registry().get(_name);
    }

    function _broadcast() internal {
        RichTransaction[] memory customQueue = Senders.registry().broadcast();
        processCustomQueue(customQueue);
    }

    /// @notice Process custom sender transactions that require external handling
    /// @dev Override this function in derived contracts to handle custom sender types
    /// @param _customQueue Array of transactions from custom senders
    function processCustomQueue(RichTransaction[] memory _customQueue) internal virtual {
        if (_customQueue.length > 0) {
            /// @dev override this function to implement custom queue processing
            revert CustomQueueReceiverNotImplemented();
        }
    }

    /// @notice Execute multiple transactions through a specific sender
    /// @dev This function is meant for testing and debugging purposes
    /// @param _senderId The ID of the sender to use
    /// @param _transactions Array of transactions to execute
    /// @return bundleTransactions Array of executed transactions with results
    function execute(bytes32 _senderId, Transaction[] memory _transactions) external returns (RichTransaction[] memory bundleTransactions) {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transactions);
    }

    /// @notice Execute a single transaction through a specific sender
    /// @dev This function is meant for testing and debugging purposes
    /// @param _senderId The ID of the sender to use
    /// @param _transaction Transaction to execute
    /// @return bundleTransaction Executed transaction with results
    function execute(bytes32 _senderId, Transaction memory _transaction) external returns (RichTransaction memory bundleTransaction) {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transaction);
    }
}