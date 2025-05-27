// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Safe} from "safe-utils/Safe.sol";
import {DeployerConfig, DeployerType, Transaction, ExecutionResult, ExecutionStatus} from "./type.sol";

/**
 * @title Executor
 * @notice Base contract for executing transactions via private key or Safe
 * @dev Provides abstraction for different execution methods
 */
abstract contract Executor is Script {
    using Safe for Safe.Client;

    error UnsupportedDeployer(string deployerType);
    error TransactionFailed(string label);

    DeployerConfig public deployerConfig;
    Safe.Client private _safe;
    Transaction[] public pendingTransactions;

    /// @notice Deployment namespace
    string public namespace;

    /// @notice Executor address
    address public executor;

    constructor() {
        namespace = vm.envOr("DEPLOYMENT_NAMESPACE", string("default"));
        _configureDeployer();
        executor = _getExecutor();
    }

    /**
     * @notice Configure the deployer based on sender configuration
     */
    function _configureDeployer() internal {
        // Get deployer type from simplified environment variable
        string memory deployerTypeStr = vm.envOr("DEPLOYER_TYPE", string("private_key"));

        if (keccak256(bytes(deployerTypeStr)) == keccak256(bytes("private_key"))) {
            deployerConfig.deployerType = DeployerType.PRIVATE_KEY;
            deployerConfig.privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployerConfig.senderAddress = vm.addr(deployerConfig.privateKey);
            vm.rememberKey(deployerConfig.privateKey);
        } else if (keccak256(bytes(deployerTypeStr)) == keccak256(bytes("ledger"))) {
            deployerConfig.deployerType = DeployerType.LEDGER;
            deployerConfig.senderAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } else if (keccak256(bytes(deployerTypeStr)) == keccak256(bytes("safe"))) {
            deployerConfig.deployerType = DeployerType.SAFE;
            deployerConfig.safeAddress = vm.envAddress("DEPLOYER_SAFE_ADDRESS");

            // Configure proposer based on type
            string memory proposerType = vm.envOr("PROPOSER_TYPE", string("private_key"));
            if (keccak256(bytes(proposerType)) == keccak256(bytes("private_key"))) {
                uint256 proposerKey = vm.envUint("PROPOSER_PRIVATE_KEY");
                vm.rememberKey(proposerKey);
                deployerConfig.senderAddress = vm.addr(proposerKey);
                deployerConfig.derivationPath = "";
            } else if (keccak256(bytes(proposerType)) == keccak256(bytes("ledger"))) {
                deployerConfig.senderAddress = vm.envAddress("PROPOSER_ADDRESS");
                deployerConfig.derivationPath = vm.envString("PROPOSER_DERIVATION_PATH");
            } else {
                revert UnsupportedDeployer(string.concat("proposer type: ", proposerType));
            }

            // Initialize Safe client
            _safe.initialize(deployerConfig.safeAddress);
        } else {
            revert UnsupportedDeployer(deployerTypeStr);
        }

        console.log("Executor:", _getExecutor());
        console.log("Executor type:", deployerConfig.deployerType == DeployerType.PRIVATE_KEY ? "PRIVATE_KEY" : "SAFE");
    }

    /**
     * @notice Get the deployer address
     * @return The address that will execute transactions
     */
    function _getExecutor() internal view returns (address) {
        if (deployerConfig.deployerType == DeployerType.SAFE) {
            return deployerConfig.safeAddress;
        } else {
            return deployerConfig.senderAddress;
        }
    }

    /**
     * @notice Get the sender address
     * @return The address that will execute transactions
     */
    function _getSenderAddress() internal view returns (address) {
        return deployerConfig.senderAddress;
    }

    /**
     * @notice Execute a single transaction
     * @param transaction The transaction to execute
     * @return ExecutionResult The result of the transaction execution
     */
    function execute(Transaction memory transaction) internal returns (ExecutionResult memory) {
        if (deployerConfig.deployerType == DeployerType.PRIVATE_KEY) {
            return executeWithPrivateKey(transaction);
        } else if (deployerConfig.deployerType == DeployerType.SAFE) {
            return queueForSafe(transaction);
        } else {
            revert UnsupportedDeployer("Unknown deployer type");
        }
    }

    /**
     * @notice Execute multiple transactions
     * @param transactions Array of transactions to execute
     */
    function execute(Transaction[] memory transactions) internal returns (ExecutionResult memory) {
        if (deployerConfig.deployerType == DeployerType.PRIVATE_KEY) {
            return executeWithPrivateKey(transactions);
        } else if (deployerConfig.deployerType == DeployerType.SAFE) {
            return queueForSafe(transactions);
        } else {
            revert UnsupportedDeployer("Unknown deployer type");
        }
    }

    /**
     * @notice Execute a transaction with a private key
     * @param transaction The transaction to execute
     * @return ExecutionResult The result of the transaction execution
     */
    function executeWithPrivateKey(Transaction memory transaction)
        internal
        returns (ExecutionResult memory)
    {
        vm.startBroadcast(deployerConfig.privateKey);
        (bool success, bytes memory returnData) = transaction.to.call(transaction.data);
        vm.stopBroadcast();
        if (!success) {
            revert TransactionFailed(transaction.label);
        } else {
            return ExecutionResult({
                status: ExecutionStatus.EXECUTED,
                returnData: returnData
            });
        }
    }

    /**
     * @notice Execute multiple transactions with a private key
     * @param transactions Array of transactions to execute
     */
    function executeWithPrivateKey(Transaction[] memory transactions) internal returns (ExecutionResult memory) {
        vm.startBroadcast(deployerConfig.privateKey);
        bytes[] memory returnData = new bytes[](transactions.length);
        for (uint256 i = 0; i < transactions.length; i++) {
            (bool _success, bytes memory data) = transactions[i].to.call(transactions[i].data);
            if (!_success) {
                revert TransactionFailed(transactions[i].label);
            }
            returnData[i] = data;
        }
        vm.stopBroadcast();

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
    function queueForSafe(Transaction memory transaction) internal returns (ExecutionResult memory) {
        pendingTransactions.push(transaction);
        console.log("Queued transaction for Safe:", transaction.label);

        bytes32 safeTxHash = _safe.proposeTransaction(
            pendingTransactions[0].to,
            pendingTransactions[0].data,
            deployerConfig.senderAddress,
            deployerConfig.derivationPath
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
    function queueForSafe(Transaction[] memory transactions) internal returns (ExecutionResult memory) {
        address[] memory targets = new address[](transactions.length);
        bytes[] memory datas = new bytes[](transactions.length);

        for (uint256 i = 0; i < transactions.length; i++) {
            targets[i] = transactions[i].to;
            datas[i] = transactions[i].data;
            console.log("  -", transactions[i].label);
        }

        bytes32 safeTxHash =
            _safe.proposeTransactions(targets, datas, deployerConfig.senderAddress, deployerConfig.derivationPath);

        return ExecutionResult({
            status: ExecutionStatus.PENDING_SAFE,
            returnData: abi.encode(safeTxHash)
        });
    }
}
