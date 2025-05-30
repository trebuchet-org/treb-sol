// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Senders} from "./sender/Senders.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Transaction, RichTransaction} from "./types.sol";

contract Harness is CommonBase {
    using Senders for Senders.Sender;

    address private target;
    string private sender;

    constructor(address _target, string memory _sender) {
        target = _target;
        sender = _sender;
    }

    fallback(bytes calldata) external payable returns (bytes memory) {
        Transaction memory transaction = Transaction({
            to: target,
            value: msg.value,
            data: msg.data,
            label: string.concat(sender, ":harness:", vm.toString(target), ":", vm.toString(bytes4(msg.data)))
        });

        RichTransaction memory richTransaction = Senders.get(sender).execute(transaction);
        bytes memory returnData = richTransaction.simulatedReturnData;

        assembly {
            return(add(returnData, 0x20), mload(returnData))
        }
    }
}