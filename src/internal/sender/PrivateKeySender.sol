// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {RichTransaction, TransactionStatus, SenderTypes} from "../types.sol";

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

    event TransactionBroadcast(
        bytes32 indexed transactionId,
        address indexed sender,
        address indexed to,
        uint256 value,
        bytes data,
        string label,
        bytes returnData
    );

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _privateKeySender) {
        if (!_sender.isType(SenderTypes.PrivateKey)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.PrivateKey);
        }
        assembly {
            _privateKeySender.slot := _sender.slot
        }
    }

    function broadcast(Sender storage _sender, RichTransaction memory _tx) internal {
        broadcast(_sender, _tx, false);
    }

    function broadcast(Sender storage _sender, RichTransaction memory _tx, bool dryrun) internal {
        bytes memory returnData = _tx.executedReturnData;
        
        if (!dryrun) {
            vm.startBroadcast(_sender.account);
            (bool _success, bytes memory _returnData) = _tx.transaction.to.call{value: _tx.transaction.value}(_tx.transaction.data);
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

        emit TransactionBroadcast(
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

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _inMemorySender) {
        if (!_sender.isType(SenderTypes.InMemory)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.InMemory);
        }
        assembly {
            _inMemorySender.slot := _sender.slot
        }
    }

    function initialize(Sender storage _sender) internal {
        _sender.privateKey = abi.decode(_sender.config, (uint256));
        if (_sender.privateKey == 0) {
            revert InvalidPrivateKey(_sender.name);
        }
        vm.rememberKey(_sender.privateKey);
    }
}

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

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _hardwareWalletSender) {
        if (!_sender.isType(SenderTypes.HardwareWallet)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.HardwareWallet);
        }
        assembly {
            _hardwareWalletSender.slot := _sender.slot
        }
    }

    function base(Sender storage _sender) internal pure returns (Senders.Sender storage _baseSender) {
        assembly {
            _baseSender.slot := _sender.slot
        }
    }

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
