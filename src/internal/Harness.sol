// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Senders} from "./sender/Senders.sol";
import {console} from "forge-std/console.sol";
import {Dispatcher} from "./Dispatcher.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Transaction, RichTransaction} from "./types.sol";

contract Harness is CommonBase {
    using Senders for Senders.Sender;

    address private target;
    bytes32 private senderId;
    Dispatcher private dispatcher;

    constructor(address _target, string memory _sender, bytes32 _senderId, address _dispatcher) {
        target = _target;
        senderId = _senderId;
        dispatcher = Dispatcher(_dispatcher);
        vm.label(address(this), string.concat("Harness[",_sender, "]"));
    }

    fallback(bytes calldata) external payable returns (bytes memory) {
        Transaction memory transaction = Transaction({
            to: target,
            value: msg.value,
            data: msg.data,
            label: ""
        });

        try dispatcher.execute(senderId, transaction) returns (RichTransaction memory richTransaction) {
            bytes memory returnData = richTransaction.simulatedReturnData;
            assembly {
                return(add(returnData, 0x20), mload(returnData))
            }
        } catch (bytes memory errorData) {
            if (errorData.length > 0) {
                assembly {
                    revert(add(errorData, 0x20), mload(errorData))
                }
            }

            (bool success, bytes memory returnData) = target.staticcall(msg.data);
            if (success) {
                assembly {
                    return(add(returnData, 0x20), mload(returnData))
                }
            } else {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }

    }
}