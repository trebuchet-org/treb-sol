// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {Safe} from "safe-utils/Safe.sol";
import {SimulatedTransaction, SenderTypes} from "../types.sol";
import {ITrebEvents} from "../ITrebEvents.sol";
import {Transaction} from "../types.sol";
import {Safe as SafeContract} from "safe-smart-account/Safe.sol";
import {Enum} from "safe-smart-account/common/Enum.sol";

/**
 * @title GnosisSafe
 * @author Trebuchet Team
 * @notice Library for managing Safe multisig transactions within the Trebuchet sender system
 * @dev This library provides integration with Gnosis Safe (now Safe) multisigs, enabling:
 *      - Transaction queueing for batch execution
 *      - Support for various proposer types (private key, hardware wallets)
 *      - Automatic transaction batching for gas efficiency
 *      - Integration with Safe's proposer/signer patterns
 *
 * The library handles the complexities of Safe transaction creation, including:
 * - Collecting multiple transactions into efficient batches
 * - Managing proposer authentication (EOA, Ledger, Trezor)
 * - Generating Safe transaction hashes for tracking
 * - Ensuring value transfers are handled correctly (currently restricted)
 */
library GnosisSafe {
    using Senders for Senders.Sender;
    using GnosisSafe for GnosisSafe.Sender;
    using Safe for Safe.Client;

    /**
     * @dev Sender structure for Safe multisig integration
     * @param id Unique identifier for the sender
     * @param name Human-readable name for the sender
     * @param account Safe multisig contract address
     * @param senderType Type identifier (must be GnosisSafe)
     * @param config Encoded configuration containing proposer name
     * @param proposerId ID of the proposer sender who will submit transactions
     * @param txQueue Queue of transactions to be batched and proposed
     */
    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
        // Gnosis safe specific fields:
        bytes32 proposerId;
        SimulatedTransaction[] txQueue;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    /// @dev Fixed gas overhead per batch for MultiSend encoding + Safe.execTransaction wrapper
    uint256 private constant BATCH_OVERHEAD = 100_000;

    error SafeTransactionValueNotZero(Transaction transaction);
    error InvalidGnosisSafeConfig(string name);

    /**
     * @notice Initializes a Safe sender with its proposer configuration
     * @dev Sets up the Safe client with the appropriate proposer signer.
     *      The proposer can be an InMemory key, Ledger, or Trezor hardware wallet.
     *      The Safe client is configured to use the proposer for transaction submission.
     * @param _sender The Safe sender to initialize
     */
    function initialize(Sender storage _sender) internal {
        string memory proposerName = abi.decode(_sender.config, (string));
        if (bytes(proposerName).length == 0) {
            revert InvalidGnosisSafeConfig(_sender.name);
        }

        _sender.proposerId = bytes32(keccak256(abi.encodePacked(proposerName)));

        Safe.SignerType signerType;
        string memory derivationPath;
        uint256 privateKey;
        if (_sender.proposer().isType(SenderTypes.InMemory)) {
            signerType = Safe.SignerType.PrivateKey;
            privateKey = _sender.proposer().inMemory().privateKey;
        } else if (_sender.proposer().isType(SenderTypes.Ledger)) {
            signerType = Safe.SignerType.Ledger;
            derivationPath = _sender.proposer().hardwareWallet().mnemonicDerivationPath;
        } else if (_sender.proposer().isType(SenderTypes.Trezor)) {
            signerType = Safe.SignerType.Trezor;
            derivationPath = _sender.proposer().hardwareWallet().mnemonicDerivationPath;
        } else {
            revert InvalidGnosisSafeConfig(_sender.name);
        }

        _sender.safe()
            .initialize(
                _sender.account,
                Safe.Signer({
                signer: _sender.proposer().account,
                signerType: signerType,
                derivationPath: derivationPath,
                privateKey: privateKey
            })
            );
    }

    /**
     * @notice Queues a transaction for batch execution
     * @dev Adds the transaction to the sender's queue. Transactions are
     *      accumulated until broadcast() is called, enabling efficient batching.
     * @param _sender The Safe sender
     * @param _tx The transaction to queue
     */
    function queue(Sender storage _sender, SimulatedTransaction memory _tx) internal {
        _sender.txQueue.push(_tx);
    }

    /**
     * @notice Broadcasts all queued transactions with gas-aware batch splitting
     * @dev Splits queued transactions into multiple batches if their cumulative gas
     *      would exceed 50% of the block gas limit. Each batch is broadcast separately
     *      with sequential Safe nonces managed in-memory.
     * @param _sender The Safe sender
     */
    function broadcast(Sender storage _sender) internal {
        if (_sender.txQueue.length == 0) {
            return;
        }

        uint256 gasThreshold = block.gaslimit * 50 / 100;
        uint256 nonce = SafeContract(payable(_sender.account)).nonce();

        uint256 batchStart = 0;
        uint256 batchGas = BATCH_OVERHEAD;

        for (uint256 i = 0; i < _sender.txQueue.length; i++) {
            uint256 txGas = _sender.txQueue[i].gasUsed;

            // If adding this tx would exceed threshold, broadcast current batch first
            // (but only if current batch is non-empty)
            if (batchGas + txGas > gasThreshold && i > batchStart) {
                _broadcastBatch(_sender, batchStart, i, nonce);
                nonce++;
                batchStart = i;
                batchGas = BATCH_OVERHEAD;
            }

            batchGas += txGas;
        }

        // Broadcast remaining batch
        _broadcastBatch(_sender, batchStart, _sender.txQueue.length, nonce);

        delete _sender.txQueue;
    }

    /**
     * @notice Broadcasts a slice of the transaction queue as a single Safe batch
     * @dev Handles both threshold-1 (direct execution) and multi-sig (API proposal) paths.
     *      Validates no value transfers and emits appropriate events per batch.
     * @param _sender The Safe sender
     * @param startIdx Start index (inclusive) in txQueue
     * @param endIdx End index (exclusive) in txQueue
     * @param nonce Safe nonce to use for this batch
     */
    function _broadcastBatch(Sender storage _sender, uint256 startIdx, uint256 endIdx, uint256 nonce) internal {
        uint256 batchLen = endIdx - startIdx;
        address[] memory targets = new address[](batchLen);
        bytes[] memory datas = new bytes[](batchLen);
        bytes32[] memory transactionIds = new bytes32[](batchLen);

        for (uint256 i = 0; i < batchLen; i++) {
            SimulatedTransaction storage stx = _sender.txQueue[startIdx + i];
            if (stx.transaction.value > 0) {
                revert SafeTransactionValueNotZero(stx.transaction);
            }
            targets[i] = stx.transaction.to;
            datas[i] = stx.transaction.data;
            transactionIds[i] = stx.transactionId;
        }

        if (isThresholdOne(_sender)) {
            bytes32 safeTxHash = _executeDirectly(_sender, targets, datas, nonce);
            if (!Senders.registry().quiet) {
                emit ITrebEvents.SafeTransactionExecuted(
                    safeTxHash, _sender.account, _sender.proposer().account, transactionIds
                );
            }
        } else {
            bytes32 safeTxHash = _sender.safe().proposeTransactions(targets, datas, nonce);
            if (!Senders.registry().quiet) {
                emit ITrebEvents.SafeTransactionQueued(
                    safeTxHash, _sender.account, _sender.proposer().account, transactionIds
                );
            }
        }
    }

    /**
     * @notice Executes transactions directly on the Safe when threshold is 1
     * @dev Uses vm.broadcast to execute the Safe transaction on-chain.
     *      The nonce is managed by the caller to support sequential batches.
     * @param _sender The Safe sender
     * @param targets Array of target addresses for the transactions
     * @param datas Array of calldata for the transactions
     * @param nonce Safe nonce to use for signing and hash computation
     * @return safeTxHash The hash of the executed Safe transaction
     */
    function _executeDirectly(Sender storage _sender, address[] memory targets, bytes[] memory datas, uint256 nonce)
        internal
        returns (bytes32 safeTxHash)
    {
        // Resolve to/data/operation based on single vs multi transaction
        address to;
        bytes memory data;
        Enum.Operation operation;

        if (targets.length == 1) {
            to = targets[0];
            data = datas[0];
            operation = Enum.Operation.Call;
        } else {
            (to, data) = _sender.safe().getProposeTransactionsTargetAndData(targets, datas);
            operation = Enum.Operation.DelegateCall;
        }

        safeTxHash = _sender.safe().getSafeTxHash(to, 0, data, operation, nonce);

        // Sign with explicit nonce and execute
        bytes memory signature = _sender.safe().sign(to, data, operation, nonce);
        _execSafeTransaction(_sender, to, data, operation, signature);
    }

    /**
     * @notice Checks if the Safe has threshold of 1
     * @param _sender The Safe sender
     * @return True if the Safe has threshold of 1
     */
    function isThresholdOne(Sender storage _sender) internal view returns (bool) {
        SafeContract safeInstance = SafeContract(payable(_sender.account));
        return safeInstance.getThreshold() == 1;
    }

    /**
     * @notice Retrieves the proposer sender for this Safe
     * @dev The proposer is responsible for submitting transactions to the Safe
     * @param _sender The Safe sender
     * @return The proposer sender instance
     */
    function proposer(Sender storage _sender) internal view returns (Senders.Sender storage) {
        return Senders.get(_sender.proposerId);
    }

    /**
     * @notice Retrieves the Safe client for transaction management
     * @dev Returns a Safe.Client instance for interacting with the Safe contract
     * @param _sender The Safe sender
     * @return _safe The Safe client storage reference
     */
    function safe(Sender storage _sender) internal view returns (Safe.Client storage _safe) {
        bytes32 slot = bytes32(uint256(keccak256(abi.encodePacked("safe.Client", _sender.account))));
        assembly {
            _safe.slot := slot
        }
    }

    /**
     * @notice Casts a generic Sender to a GnosisSafe.Sender
     * @dev Validates that the sender is of GnosisSafe type before casting
     * @param _sender The generic sender to cast
     * @return _gnosisSafeSender The casted GnosisSafe sender
     */
    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _gnosisSafeSender) {
        if (!_sender.isType(SenderTypes.GnosisSafe)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.GnosisSafe);
        }
        assembly {
            _gnosisSafeSender.slot := _sender.slot
        }
    }

    /**
     * @notice Low-level Safe execTransaction call via vm.broadcast
     * @dev Extracted to reduce stack depth in _executeDirectly
     */
    function _execSafeTransaction(
        Sender storage _sender,
        address to,
        bytes memory data,
        Enum.Operation operation,
        bytes memory signature
    ) private {
        vm.broadcast(_sender.proposer().account);
        bool success = SafeContract(payable(_sender.account))
            .execTransaction(
                to,
                0, // value
                data,
                operation,
                0, // safeTxGas
                0, // baseGas
                0, // gasPrice
                address(0), // gasToken
                payable(0), // refundReceiver
                signature
            );
        require(success, "Safe transaction execution failed");
    }
}
