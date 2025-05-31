// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {RichTransaction, TransactionStatus, SenderTypes} from "../types.sol";
import {ITrebEvents} from "../ITrebEvents.sol";

/**
 * @title PrivateKey
 * @author Trebuchet Team
 * @notice Library for managing private key-based transaction execution
 * @dev This library provides functionality for executing transactions using private keys,
 *      typically used for EOA (Externally Owned Account) deployments and testing.
 *      It supports both immediate transaction broadcasting and dry-run modes.
 *
 * Key features:
 * - Direct transaction execution using vm.broadcast
 * - Support for dry-run mode to simulate without actual execution
 * - Event emission for transaction tracking
 * - Integration with Foundry's cheatcode system
 */
library PrivateKey {
    using Senders for Senders.Sender;

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    /**
     * @notice Casts a generic Sender to a PrivateKey.Sender
     * @dev Validates that the sender is of PrivateKey type before casting
     * @param _sender The generic sender to cast
     * @return _privateKeySender The casted PrivateKey sender
     */
    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _privateKeySender) {
        if (!_sender.isType(SenderTypes.PrivateKey)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.PrivateKey);
        }
        assembly {
            _privateKeySender.slot := _sender.slot
        }
    }

    /**
     * @notice Broadcasts a transaction using the sender's private key
     * @dev Delegates to the overloaded broadcast function with dryrun=false
     * @param _sender The private key sender
     * @param _tx The transaction to broadcast
     */
    function broadcast(Sender storage _sender, RichTransaction memory _tx) internal {
        broadcast(_sender, _tx, false);
    }

    /**
     * @notice Broadcasts a transaction with optional dry-run mode
     * @dev Uses Foundry's vm.broadcast to execute the transaction on-chain.
     *      In dry-run mode, marks the transaction as executed without broadcasting.
     * @param _sender The private key sender
     * @param _tx The transaction to broadcast
     * @param dryrun If true, simulates execution without actual broadcasting
     */
    function broadcast(Sender storage _sender, RichTransaction memory _tx, bool dryrun) internal {
        bytes memory returnData = _tx.executedReturnData;

        if (!dryrun) {
            vm.startBroadcast(_sender.account);
            (bool _success, bytes memory _returnData) =
                _tx.transaction.to.call{value: _tx.transaction.value}(_tx.transaction.data);
            if (!_success) {
                assembly {
                    revert(add(_returnData, 0x20), mload(_returnData))
                }
            }
            returnData = _returnData;
            _tx.executedReturnData = returnData;
            _tx.status = TransactionStatus.EXECUTED;
            vm.stopBroadcast();
        } else {
            // In dryrun mode, mark as executed without actually broadcasting
            _tx.status = TransactionStatus.EXECUTED;
        }

        // Only emit event if not in quiet mode
        if (!Senders.registry().quiet) {
            emit ITrebEvents.TransactionBroadcast(
                _tx.transactionId,
                _sender.account,
                _tx.transaction.to,
                _tx.transaction.value,
                _tx.transaction.data,
                _tx.transaction.label,
                returnData
            );
        }
    }
}

/**
 * @title InMemory
 * @author Trebuchet Team
 * @notice Library for managing in-memory private key senders
 * @dev This library handles senders that use private keys stored in memory,
 *      typically used for development and testing environments where keys
 *      are provided via environment variables or configuration.
 *
 * Security considerations:
 * - Private keys are stored in contract storage during execution
 * - Only suitable for development/testing or when using ephemeral keys
 * - Keys are validated to ensure they are non-zero
 * - Integrates with Foundry's vm.rememberKey for key management
 */
library InMemory {
    using Senders for Senders.Sender;

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
        // Private key specific fields:
        uint256 privateKey;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidPrivateKey(string name);

    /**
     * @notice Casts a generic Sender to an InMemory.Sender
     * @dev Validates that the sender is of InMemory type before casting
     * @param _sender The generic sender to cast
     * @return _inMemorySender The casted InMemory sender
     */
    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _inMemorySender) {
        if (!_sender.isType(SenderTypes.InMemory)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.InMemory);
        }
        assembly {
            _inMemorySender.slot := _sender.slot
        }
    }

    /**
     * @notice Initializes an InMemory sender with its private key
     * @dev Decodes the private key from config, validates it's non-zero,
     *      and registers it with Foundry's key management system
     * @param _sender The InMemory sender to initialize
     */
    function initialize(Sender storage _sender) internal {
        _sender.privateKey = abi.decode(_sender.config, (uint256));
        if (_sender.privateKey == 0) {
            revert InvalidPrivateKey(_sender.name);
        }
        vm.rememberKey(_sender.privateKey);
    }
}

/**
 * @title HardwareWallet
 * @author Trebuchet Team
 * @notice Library for managing hardware wallet senders (Ledger, Trezor)
 * @dev This library provides support for hardware wallet integration,
 *      enabling secure transaction signing through hardware devices.
 *      It supports both Ledger and Trezor wallets with BIP44 derivation paths.
 *
 * Key features:
 * - Support for Ledger and Trezor hardware wallets
 * - BIP44 hierarchical deterministic (HD) derivation path support
 * - Type validation to ensure correct wallet configuration
 * - Integration with the broader Trebuchet sender system
 *
 * Security benefits:
 * - Private keys never leave the hardware device
 * - User confirmation required on device for each transaction
 * - Suitable for production deployments requiring high security
 */
library HardwareWallet {
    using Senders for Senders.Sender;
    using HardwareWallet for HardwareWallet.Sender;

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
        // Hardware wallet specific fields:
        string hardwareWalletType;
        string mnemonicDerivationPath;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidHardwareWalletConfig(string name);

    /**
     * @notice Casts a generic Sender to a HardwareWallet.Sender
     * @dev Validates that the sender is of HardwareWallet type before casting
     * @param _sender The generic sender to cast
     * @return _hardwareWalletSender The casted HardwareWallet sender
     */
    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _hardwareWalletSender) {
        if (!_sender.isType(SenderTypes.HardwareWallet)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.HardwareWallet);
        }
        assembly {
            _hardwareWalletSender.slot := _sender.slot
        }
    }

    /**
     * @notice Returns the base Senders.Sender from a HardwareWallet.Sender
     * @dev Used internally to access base sender functionality
     * @param _sender The hardware wallet sender
     * @return _baseSender The base sender storage reference
     */
    function base(Sender storage _sender) internal pure returns (Senders.Sender storage _baseSender) {
        assembly {
            _baseSender.slot := _sender.slot
        }
    }

    /**
     * @notice Initializes a hardware wallet sender
     * @dev Decodes the derivation path from config and determines the wallet type
     *      (Ledger or Trezor) based on the sender's type flags. Validates that
     *      the derivation path is non-empty.
     * @param _sender The hardware wallet sender to initialize
     */
    function initialize(Sender storage _sender) internal {
        _sender.mnemonicDerivationPath = abi.decode(_sender.config, (string));
        if (_sender.base().isType(SenderTypes.Ledger)) {
            _sender.hardwareWalletType = "ledger";
        } else if (_sender.base().isType(SenderTypes.Trezor)) {
            _sender.hardwareWalletType = "trezor";
        } else {
            revert InvalidHardwareWalletConfig(_sender.name);
        }

        if (bytes(_sender.mnemonicDerivationPath).length == 0) {
            revert InvalidHardwareWalletConfig(_sender.name);
        }
    }
}
