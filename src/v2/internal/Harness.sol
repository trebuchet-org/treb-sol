// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Senders} from "./sender/Senders.sol";
import {SenderCoordinator} from "./SenderCoordinator.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Transaction, SimulatedTransaction} from "../../internal/types.sol";

/// @title Harness (v2)
/// @notice Proxy contract for sender-isolated execution context.
/// @dev Same API as v1 Harness. Intercepts calls and routes them through
///      the SenderCoordinator for proper sender-scoped execution.
///      In v2 the underlying execute() uses vm.broadcast() instead of vm.prank().
contract Harness is CommonBase {
    using Senders for Senders.Sender;

    bytes32 public lastTransactionId;
    address private target;
    bytes32 private senderId;
    SenderCoordinator private senderCoordinator;

    constructor(address _target, string memory _sender, bytes32 _senderId) {
        target = _target;
        senderId = _senderId;
        senderCoordinator = SenderCoordinator(msg.sender);
        vm.label(address(this), string.concat("Harness[", _sender, "]"));
    }

    receive() external payable {}

    /// @dev Fallback intercepts all calls. State-changing calls go through
    ///      senderCoordinator.execute(); view/pure calls fall back to staticcall.
    fallback(bytes calldata) external payable returns (bytes memory) {
        Transaction memory transaction = Transaction({to: target, value: msg.value, data: msg.data});

        try senderCoordinator.execute(senderId, transaction) returns (SimulatedTransaction memory simulatedTx) {
            bytes memory returnData = simulatedTx.returnData;
            lastTransactionId = simulatedTx.transactionId;
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
