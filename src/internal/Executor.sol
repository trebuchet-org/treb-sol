// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Safe} from "safe-utils/Safe.sol";
import "./types.sol";

/**
 * @title Executor
 * @notice Base contract for executing transactions via private key or Safe
 * @dev Provides abstraction for different execution methods
 */
abstract contract Executor is Script {
    using Safe for Safe.Client;

    error UnsupportedDeployer(string deployerType);
    error TransactionFailed(string label);

    /// @notice Emitted when a transaction is executed
    event TransactionExecuted(
        address indexed executor,
        address indexed target,
        string label,
        ExecutionStatus status
    );

    /// @notice Emitted when a Safe transaction is queued
    event SafeTransactionQueued(
        address indexed safe,
        address indexed proposer,
        bytes32 safeTxHash,
        string label,
        uint256 transactionCount
    );

    ExecutorConfig public executorConfig;
    Safe.Client private _safe;

    /// @notice Executor address
    address public executor;

    constructor() {
        executor = _getExecutor();
    }

    /**
     * @notice Initialize from ExecutorConfig
     * @param config The executor configuration
     */
    function _initialize(ExecutorConfig memory config) internal virtual {
        require(config.sender != address(0), "InvalidExecutorConfig");
        if (config.senderType == SenderType.SAFE) {
            require(config.proposer != address(0), "InvalidExecutorConfig");
            require(
                config.proposerType == SenderType.PRIVATE_KEY || 
                config.proposerType == SenderType.LEDGER, 
                "InvalidExecutorConfig"
            );
            if (config.proposerType == SenderType.PRIVATE_KEY) {
                require(config.proposerPrivateKey != 0, "InvalidExecutorConfig");
                require(config.proposer == vm.addr(config.proposerPrivateKey), "InvalidExecutorConfig");
                vm.rememberKey(config.proposerPrivateKey);
            } else {
                require(bytes(config.proposerDerivationPath).length > 0, "InvalidExecutorConfig");
            }
            _safe.initialize(config.sender);
        } else if (config.senderType == SenderType.PRIVATE_KEY) {
            require(config.senderPrivateKey != 0, "InvalidExecutorConfig");
            address expected = vm.addr(config.senderPrivateKey);
            require(expected == config.sender, "InvalidExecutorConfig");
            vm.rememberKey(config.senderPrivateKey);
        } else if (config.senderType == SenderType.LEDGER) {
            require(bytes(config.senderDerivationPath).length > 0, "InvalidExecutorConfig");
        }
        
        executorConfig = config;
        executor = _getExecutor();
    }

    /**
     * @notice Get the deployer address
     * @return The address that will execute transactions
     */
    function _getExecutor() internal view returns (address) {
        if (executorConfig.senderType == SenderType.SAFE) {
            return executorConfig.sender;
        } else {
            return executorConfig.sender;
        }
    }

    /**
     * @notice Get the sender address
     * @return The address that will execute transactions
     */
    function _getSenderAddress() internal view returns (address) {
        return executorConfig.sender;
    }

    /**
     * @notice Execute a single transaction
     * @param transaction The transaction to execute
     * @return ExecutionResult The result of the transaction execution
     */
    function execute(Transaction memory transaction) internal returns (ExecutionResult memory) {
        if (executorConfig.senderType == SenderType.PRIVATE_KEY || executorConfig.senderType == SenderType.LEDGER) {
            return broadcastFromSender(transaction);
        } else if (executorConfig.senderType == SenderType.SAFE) {
            return queueOnSafe(transaction);
        } else {
            revert UnsupportedDeployer("Unknown deployer type");
        }
    }

    /**
     * @notice Execute multiple transactions
     * @param transactions Array of transactions to execute
     */
    function execute(Transaction[] memory transactions) internal returns (ExecutionResult memory) {
        if (executorConfig.senderType == SenderType.PRIVATE_KEY || executorConfig.senderType == SenderType.LEDGER) {
            return broadcastFromSender(transactions);
        } else if (executorConfig.senderType == SenderType.SAFE) {
            return queueOnSafe(transactions);
        } else {
            revert UnsupportedDeployer("Unknown deployer type");
        }
    }

    /**
     * @notice Execute a transaction with a private key
     * @param transaction The transaction to execute
     * @return ExecutionResult The result of the transaction execution
     */
    function broadcastFromSender(Transaction memory transaction)
        internal
        returns (ExecutionResult memory)
    {
        vm.startBroadcast(executorConfig.sender);
        (bool success, bytes memory returnData) = transaction.to.call(transaction.data);
        vm.stopBroadcast();
        
        if (!success) {
            revert TransactionFailed(transaction.label);
        }
        
        // Emit event for executed transaction
        emit TransactionExecuted(
            executorConfig.sender,
            transaction.to,
            transaction.label,
            ExecutionStatus.EXECUTED
        );
        
        return ExecutionResult({
            status: ExecutionStatus.EXECUTED,
            returnData: returnData
        });
    }

    /**
     * @notice Execute multiple transactions with a private key
     * @param transactions Array of transactions to execute
     */
    function broadcastFromSender(Transaction[] memory transactions) internal returns (ExecutionResult memory) {
        vm.startBroadcast(executorConfig.sender);
        bytes[] memory returnData = new bytes[](transactions.length);
        for (uint256 i = 0; i < transactions.length; i++) {
            (bool _success, bytes memory data) = transactions[i].to.call(transactions[i].data);
            if (!_success) {
                revert TransactionFailed(transactions[i].label);
            }
            returnData[i] = data;
        }
        vm.stopBroadcast();

        for (uint256 i = 0; i < transactions.length; i++) {
            emit TransactionExecuted(
                executorConfig.sender,
                transactions[i].to,
                transactions[i].label,
                ExecutionStatus.EXECUTED
            );
        }

        return ExecutionResult({
            status: ExecutionStatus.EXECUTED,
            returnData: abi.encode(returnData)
        });
    }

    /**
     * @notice Queue a transaction for Safe execution
     * @param transaction The transaction to queue
     * @return ExecutionResult The result of the transaction execution
     */
    function queueOnSafe(Transaction memory transaction) internal returns (ExecutionResult memory) {
        console.log("Queued transaction for Safe:", transaction.label);

        bytes32 safeTxHash = _safe.proposeTransaction(
            transaction.to,
            transaction.data,
            executorConfig.proposer,
            executorConfig.proposerDerivationPath
        );
        
        // Emit event for queued Safe transaction
        emit SafeTransactionQueued(
            executorConfig.sender,
            executorConfig.proposer,
            safeTxHash,
            transaction.label,
            1
        );

        return ExecutionResult({
            status: ExecutionStatus.PENDING_SAFE,
            returnData: abi.encode(safeTxHash)
        });
    }

    /**
     * @notice Queue multiple transactions for Safe execution
     * @param transactions Array of transactions to queue
     */
    function queueOnSafe(Transaction[] memory transactions) internal returns (ExecutionResult memory) {
        address[] memory targets = new address[](transactions.length);
        bytes[] memory datas = new bytes[](transactions.length);
        string memory label = "";

        for (uint256 i = 0; i < transactions.length; i++) {
            targets[i] = transactions[i].to;
            datas[i] = transactions[i].data;
            if (i == 0) {
                label = transactions[i].label;
            } else {
                label = string.concat(label, "; ", transactions[i].label);
            }
            console.log("  -", transactions[i].label);
        }

        bytes32 safeTxHash =
            _safe.proposeTransactions(targets, datas, executorConfig.proposer, executorConfig.proposerDerivationPath);
        
        // Emit event for queued Safe transactions
        emit SafeTransactionQueued(
            executorConfig.sender,
            executorConfig.proposer,
            safeTxHash,
            label,
            transactions.length
        );

        return ExecutionResult({
            status: ExecutionStatus.PENDING_SAFE,
            returnData: abi.encode(safeTxHash)
        });
    }
}
