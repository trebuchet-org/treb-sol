// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {RichTransaction, BundleStatus, SenderTypes} from "../types.sol";

library PrivateKey {
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    using Senders for Senders.Sender;

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
        RichTransaction[] queue;
        bytes32 bundleId;
        bool broadcasted;
    }

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _privateKeySender) {
        if (!_sender.isType(SenderTypes.PrivateKey)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.PrivateKey);
        }
        assembly {
            _privateKeySender.slot := _sender.slot
        }
    }

    function broadcast(Sender storage _sender) internal returns (BundleStatus status) {
        vm.startBroadcast(_sender.account);
        for (uint256 i = 0; i < _sender.queue.length; i++) {
            (bool _success, bytes memory data) = _sender.queue[i].transaction.to.call{value: _sender.queue[i].transaction.value}(_sender.queue[i].transaction.data);
            if (!_success) {
                revert Senders.TransactionFailed(_sender.queue[i].transaction.label);
            }
            _sender.queue[i].executedReturnData = data;
        }
        vm.stopBroadcast();
        return BundleStatus.EXECUTED;
    }
}


library InMemory {
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    using Senders for Senders.Sender;

    error InvalidPrivateKey(string name);

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
        RichTransaction[] queue;
        bytes32 bundleId;
        bool broadcasted;
        // Private key specific fields:
        uint256 privateKey;
    }

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

    error InvalidHardwareWalletConfig(string name);

    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
        RichTransaction[] queue;
        bytes32 bundleId;
        bool broadcasted;
        // Hardware wallet specific fields:
        string hardwareWalletType;
        string mnemonicDerivationPath;
    }

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _hardwareWalletSender) {
        if (!_sender.isType(SenderTypes.HardwareWallet)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.HardwareWallet);
        }
        assembly {
            _hardwareWalletSender.slot := _sender.slot
        }
    }

    function base(Sender storage _sender) internal view returns (Senders.Sender storage _baseSender) {
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
