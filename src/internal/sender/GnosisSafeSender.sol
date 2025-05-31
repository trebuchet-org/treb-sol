// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Senders} from "./Senders.sol";
import {HardwareWallet} from "./PrivateKeySender.sol";
import {Safe} from "safe-utils/Safe.sol";
import {RichTransaction, TransactionStatus, SenderTypes} from "../types.sol";
import {console} from "forge-std/console.sol";
import {ITrebEvents} from "../ITrebEvents.sol";

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

    error SafeTransactionValueNotZero(string label);
    error InvalidGnosisSafeConfig(string name);

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
        bytes config;
        // Gnosis safe specific fields:
        bytes32 proposerId;
        RichTransaction[] txQueue;
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

        _sender.safe().initialize(
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
    function queue(Sender storage _sender, RichTransaction memory _tx) internal {
        _sender.txQueue.push(_tx);
    }

    /**
     * @notice Broadcasts all queued transactions as a Safe batch
     * @dev Delegates to the overloaded broadcast function using the global dryrun setting
     * @param _sender The Safe sender
     */
    function broadcast(Sender storage _sender) internal {
        broadcast(_sender, Senders.registry().dryrun);
    }

    /**
     * @notice Broadcasts all queued transactions with optional dry-run mode
     * @dev Collects all queued transactions into a batch proposal for the Safe.
     *      Validates that transactions don't include ETH transfers (currently unsupported).
     *      In dry-run mode, generates a mock transaction hash without actual submission.
     * @param _sender The Safe sender
     * @param dryrun If true, simulates the batch proposal without submission
     */
    function broadcast(Sender storage _sender, bool dryrun) internal {
        if (_sender.txQueue.length == 0) {
            return;
        }

        address[] memory targets = new address[](_sender.txQueue.length);
        bytes[] memory datas = new bytes[](_sender.txQueue.length);

        for (uint256 i = 0; i < _sender.txQueue.length; i++) {
            if (_sender.txQueue[i].transaction.value > 0) {
                revert SafeTransactionValueNotZero(_sender.txQueue[i].transaction.label);
            }
            targets[i] = _sender.txQueue[i].transaction.to;
            datas[i] = _sender.txQueue[i].transaction.data;
            _sender.txQueue[i].status = TransactionStatus.QUEUED;
        }

        bytes32 safeTxHash;
        if (!dryrun) {
            safeTxHash = _sender.safe().proposeTransactions(targets, datas);
        } else {
            // In dryrun mode, generate a mock transaction hash
            safeTxHash = keccak256(abi.encode(targets, datas, block.timestamp));
        }

        // Only emit event if not in quiet mode
        if (!Senders.registry().quiet) {
            emit ITrebEvents.SafeTransactionQueued(safeTxHash, _sender.account, _sender.proposer().account, _sender.txQueue);
        }

        delete _sender.txQueue;
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
}
