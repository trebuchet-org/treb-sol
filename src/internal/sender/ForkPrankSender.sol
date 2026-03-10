// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {ForkRpc} from "../ForkRpc.sol";
import {SimulatedTransaction, SenderTypes} from "../types.sol";

library ForkPrank {
    using Senders for Senders.Sender;

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    function initialize(Sender storage _sender) internal {
        _sender.account;
    }

    function broadcast(Sender storage _sender, SimulatedTransaction memory _tx) internal {
        vm.prank(_sender.account);
        (bool success, bytes memory returnData) =
            _tx.transaction.to.call{value: _tx.transaction.value}(_tx.transaction.data);
        if (!success) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }

        if (keccak256(returnData) != keccak256(_tx.returnData)) {
            revert Senders.TransactionExecutionMismatch(_sender.name, returnData);
        }

        ForkRpc.sendTransactionAs(_sender.account, _tx.transaction.to, _tx.transaction.data, _tx.transaction.value);
    }

    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _forkPrankSender) {
        if (!_sender.isType(SenderTypes.ForkPrank)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.ForkPrank);
        }
        assembly {
            _forkPrankSender.slot := _sender.slot
        }
    }
}
