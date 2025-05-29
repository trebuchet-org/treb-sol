// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Safe} from "safe-utils/Safe.sol";

import {Sender} from "./Sender.sol";
import {HardwareWalletSender} from "./HardwareWalletSender.sol";
import {Dispatcher} from "./Dispatcher.sol";

contract SafeSender is Sender, Dispatcher {
    error ProposerNotSupported(string proposerId);
    error SafeTransactionValueNotZero(string label);

    event SafeTransactionQueued(
        bytes32 indexed operationId,
        address indexed safe,
        address indexed proposer,
        bytes32 safeTxHash
    );

    Safe.Client private immutable safe;
    Sender private immutable proposer;

    constructor(address _safe, string memory _proposerId) Dispatcher() {
        isSafe = true;
        sender = _safe;
        proposer = sender(_proposerId);

        if (!proposer.isPrivateKey() && !proposer.isLedger() && !proposer.isTrezor()) {
            revert ProposerNotSupported(_proposerId);
        }

        safe.initialize(_safe, Safe.Signer({
            signer: proposer.sender,
            signerType: proposer.isPrivateKey ? Safe.SignerType.PrivateKey : proposer.isLedger ? Safe.SignerType.Ledger : Safe.SignerType.Trezor,
            derivationPath: proposer.isHardwareWallet ? HardwareWalletSender(address(proposer)).derivationPath : ""
        }));
    }

    function execute(bytes32 operationId, Transaction[] memory _transactions) public override returns (OperationResult memory result) {
        address[] memory targets = new address[](_transactions.length);
        bytes[] memory datas = new bytes[](_transactions.length);
        bytes[] memory returnDatas = new bytes[](_transactions.length);

        for (uint256 i = 0; i < _transactions.length; i++) {
            if (_transactions[i].value > 0) {
                revert SafeTransactionValueNotZero(_transactions[i].label);
            }

            // Pranking the safe address to call the transactions in order to simulate the execution of the transactions.
            vm.prank(sender);
            (bool success, bytes memory returnData) = _transactions[i].to.call(_transactions[i].data);
            if (!success) {
                revert TransactionFailed(_transactions[i].label);
            }
            returnDatas[i] = returnData;

            targets[i] = _transactions[i].to;
            datas[i] = _transactions[i].data;
        }

        bytes32 safeTxHash = safe.proposeTransactions(targets, datas);
        result.status = OperationStatus.QUEUED;
        result.returnData = abi.encode(returnDatas);

        emit SafeTransactionQueued(
            operationId,
            sender,
            proposer.sender,
            safeTxHash
        );

        emit OperationSent(
            sender,
            operationId,
            _transactions,
            result
        );
    }
}
