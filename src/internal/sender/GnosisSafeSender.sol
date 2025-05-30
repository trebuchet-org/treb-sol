// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {HardwareWallet, InMemory} from "./PrivateKeySender.sol";
import {Safe} from "safe-utils/Safe.sol";
import {RichTransaction, TransactionStatus, SenderTypes} from "../types.sol";

library GnosisSafe {
    error SafeTransactionValueNotZero(string label);
    error InvalidGnosisSafeConfig(string name);

    event SafeTransactionQueued(
        bytes32 indexed safeTxHash,
        address indexed safe,
        address indexed proposer,
        RichTransaction[] transactions
    );

    using Senders for Senders.Sender;
    using GnosisSafe for GnosisSafe.Sender;
    using Safe for Safe.Client;

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

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _gnosisSafeSender) {
        if (!_sender.isType(SenderTypes.GnosisSafe)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.GnosisSafe);
        }
        assembly {
            _gnosisSafeSender.slot := _sender.slot
        }
    }

    function initialize(Sender storage _sender) internal {
        string memory proposerName = abi.decode(_sender.config, (string));
        if (bytes(proposerName).length == 0) {
            revert InvalidGnosisSafeConfig(_sender.name);
        }

        _sender.proposerId = bytes32(keccak256(abi.encodePacked(proposerName)));

        Safe.SignerType signerType;
        string memory derivationPath;
        if (_sender.proposer().isType(SenderTypes.InMemory)) {
            signerType = Safe.SignerType.PrivateKey;
        } else if (_sender.proposer().isType(SenderTypes.Ledger)) {
            signerType = Safe.SignerType.Ledger;
            derivationPath = _sender.proposer().hardwareWallet().mnemonicDerivationPath;
        } else if (_sender.proposer().isType(SenderTypes.Trezor)) {
            signerType = Safe.SignerType.Trezor;
            derivationPath = _sender.proposer().hardwareWallet().mnemonicDerivationPath;
        } else {
            revert InvalidGnosisSafeConfig(_sender.name);
        }

        _sender.safe().initialize(_sender.account, Safe.Signer({
            signer: _sender.proposer().account,
            signerType: signerType,
            derivationPath: derivationPath
        }));
    }

    function queue(Sender storage _sender, RichTransaction memory _tx) internal {
        _sender.txQueue.push(_tx);
    }

    function broadcast(Sender storage _sender) internal {
        broadcast(_sender, false);
    }

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

        emit SafeTransactionQueued(
            safeTxHash,
            _sender.account,
            _sender.proposer().account,
            _sender.txQueue
        );

        delete _sender.txQueue;
    }

    function proposer(Sender storage _sender) internal view returns (Senders.Sender storage) {
        return Senders.get(_sender.proposerId);
    }

    function safe(Sender storage _sender) internal view returns (Safe.Client storage _safe) {
        bytes32 slot = bytes32(uint256(keccak256(abi.encodePacked("safe.Client", _sender.id))));
        assembly {
            _safe.slot := slot
        }
    }
}