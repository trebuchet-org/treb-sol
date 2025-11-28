// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {Safe} from "safe-utils/Safe.sol";
import {SimulatedTransaction, SenderTypes} from "../types.sol";
import {ITrebEvents} from "../ITrebEvents.sol";
import {Transaction} from "../types.sol";
import {Safe as SafeContract} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/common/Enum.sol";

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
     * @notice Broadcasts all queued transactions with optional dry-run mode
     * @dev Collects all queued transactions into a batch proposal for the Safe.
     *      Validates that transactions don't include ETH transfers (currently unsupported).
     *      If the Safe has threshold 1 and we have a proposer, executes directly on-chain.
     *      Otherwise, proposes via Safe API for UI review.
     * @param _sender The Safe sender
     */
    function broadcast(Sender storage _sender) internal {
        if (_sender.txQueue.length == 0) {
            return;
        }

        address[] memory targets = new address[](_sender.txQueue.length);
        bytes[] memory datas = new bytes[](_sender.txQueue.length);

        for (uint256 i = 0; i < _sender.txQueue.length; i++) {
            if (_sender.txQueue[i].transaction.value > 0) {
                revert SafeTransactionValueNotZero(_sender.txQueue[i].transaction);
            }
            targets[i] = _sender.txQueue[i].transaction.to;
            datas[i] = _sender.txQueue[i].transaction.data;
        }

        // Check if we can execute directly (threshold = 1)
        if (isThresholdOne(_sender)) {
            // Execute directly on-chain
            _executeDirectly(_sender, targets, datas);
        } else {
            // Use Safe API for multi-sig flow
            bytes32 safeTxHash = _sender.safe().proposeTransactions(targets, datas);
            // Only emit event if not in quiet mode
            if (!Senders.registry().quiet) {
                bytes32[] memory transactionIds = new bytes32[](_sender.txQueue.length);
                for (uint256 i = 0; i < _sender.txQueue.length; i++) {
                    transactionIds[i] = _sender.txQueue[i].transactionId;
                }
                emit ITrebEvents.SafeTransactionQueued(
                    safeTxHash, _sender.account, _sender.proposer().account, transactionIds
                );
            }
        }

        delete _sender.txQueue;
    }

    /**
     * @notice Executes transactions directly on the Safe when threshold is 1
     * @dev Uses vm.broadcast to execute the Safe transaction on-chain
     * @param _sender The Safe sender
     * @param targets Array of target addresses for the transactions
     * @param datas Array of calldata for the transactions
     */
    function _executeDirectly(Sender storage _sender, address[] memory targets, bytes[] memory datas) internal {
        SafeContract safeInstance = SafeContract(payable(_sender.account));

        // Get the transaction data based on whether we have single or multiple transactions
        address to;
        uint256 value = 0;
        bytes memory data;
        Enum.Operation operation;

        if (targets.length == 1) {
            // Single transaction
            to = targets[0];
            data = datas[0];
            operation = Enum.Operation.Call;
        } else {
            // Multiple transactions - use MultiSend
            (to, data) = _sender.safe().getProposeTransactionsTargetAndData(targets, datas);
            operation = Enum.Operation.DelegateCall;
        }

        // Get the transaction hash
        uint256 nonce = safeInstance.nonce();
        bytes32 safeTxHash =
            safeInstance.getTransactionHash(to, value, data, operation, 0, 0, 0, address(0), address(0), nonce);

        // Sign the transaction with the proposer
        bytes memory signature = _sender.safe().sign(to, data, operation);

        // Execute the transaction using vm.broadcast
        // The proposer must be an owner of the Safe for this to work
        address proposerAddress = _sender.proposer().account;

        // Use vm.broadcast to execute as the proposer
        vm.broadcast(proposerAddress);
        bool success = safeInstance.execTransaction(
            to,
            value,
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

        // Emit event for tracking
        if (!Senders.registry().quiet) {
            bytes32[] memory transactionIds = new bytes32[](_sender.txQueue.length);
            for (uint256 i = 0; i < _sender.txQueue.length; i++) {
                transactionIds[i] = _sender.txQueue[i].transactionId;
            }
            emit ITrebEvents.SafeTransactionExecuted(safeTxHash, _sender.account, proposerAddress, transactionIds);
        }
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
}
