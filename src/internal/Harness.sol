// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Sender} from "./Sender.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Transaction, BundleTransaction} from "./types.sol";

contract Harness is CommonBase {
    address private target;
    Sender private sender;

    constructor(address _target, Sender _sender) {
        target = _target;
        sender = _sender;
    }

    fallback(bytes calldata) external payable returns (bytes memory) {
        Transaction memory transaction = Transaction({
            to: target,
            value: msg.value,
            data: msg.data,
            label: string.concat("harness:", vm.toString(target), ":", vm.toString(bytes4(msg.data)))
        });

        BundleTransaction memory bundleTransaction = sender.execute(transaction);
        bytes memory returnData = bundleTransaction.simulatedReturnData;

        assembly {
            return(add(returnData, 0x20), mload(returnData))
        }
    }
}