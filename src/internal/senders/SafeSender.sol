// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Safe} from "safe-utils/Safe.sol";

import {Sender} from "../Sender.sol";
import {Dispatcher} from "../Dispatcher.sol";

import {HardwareWalletSender} from "./HardwareWalletSender.sol";
import {Transaction, BundleStatus} from "../types.sol";

contract SafeSender is Sender, Dispatcher {
    error ProposerNotSupported(string proposerId);
    error SafeTransactionValueNotZero(string label);

    event SafeTransactionQueued(
        bytes32 indexed operationId,
        address indexed safe,
        address indexed proposer,
        bytes32 safeTxHash
    );

    Safe.Client private safe;
    Sender private immutable proposer;

    constructor(address _safe, string memory _proposerId) Sender(_safe) Dispatcher() {
        proposer = sender(_proposerId);

        Safe.SignerType signerType;
        if (proposer.isType("PrivateKey")) {
            signerType = Safe.SignerType.PrivateKey;
        } else if (proposer.isType("Ledger")) {
            signerType = Safe.SignerType.Ledger;
        } else if (proposer.isType("Trezor")) {
            signerType = Safe.SignerType.Trezor;
        } else {
            revert ProposerNotSupported(_proposerId);
        }

        bool isHardwareWallet = proposer.isType("Ledger") || proposer.isType("Trezor");

        Safe.initialize(safe, _safe, Safe.Signer({
            signer: proposer.senderAddress(),
            signerType: signerType,
            derivationPath: isHardwareWallet ? HardwareWalletSender(address(proposer)).derivationPath() : ""
        }));
    }
    
    function senderType() public pure override returns (bytes4) {
        return bytes4(keccak256("Safe"));
    }

    function _execute(Transaction[] memory _transactions) internal override returns (BundleStatus status, bytes[] memory returnData) {
        address[] memory targets = new address[](_transactions.length);
        bytes[] memory datas = new bytes[](_transactions.length);

        for (uint256 i = 0; i < _transactions.length; i++) {
            if (_transactions[i].value > 0) {
                revert SafeTransactionValueNotZero(_transactions[i].label);
            }
            targets[i] = _transactions[i].to;
            datas[i] = _transactions[i].data;
        }

        bytes32 safeTxHash = Safe.proposeTransactions(safe, targets, datas);

        emit SafeTransactionQueued(
            currentBundleId(),
            senderAddress,
            proposer.senderAddress(),
            safeTxHash
        );

        return (BundleStatus.QUEUED, new bytes[](_transactions.length));
    }
}
