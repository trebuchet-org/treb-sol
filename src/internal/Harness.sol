// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Senders} from "./sender/Senders.sol";
import {SenderCoordinator} from "./SenderCoordinator.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Transaction, SimulatedTransaction} from "./types.sol";

contract Harness is CommonBase {
    using Senders for Senders.Sender;

    address private target;
    bytes32 private senderId;
    SenderCoordinator private senderCoordinator;

    constructor(address _target, string memory _sender, bytes32 _senderId) {
        target = _target;
        senderId = _senderId;
        senderCoordinator = SenderCoordinator(msg.sender);
        vm.label(address(this), string.concat("Harness[", _sender, "]"));
    }

    /**
     * @dev Fallback function that intercepts all calls to the harness.
     *
     * The harness serves two purposes:
     * 1. For state-changing calls: Queue transactions through the sender coordinator for batched execution
     * 2. For view/pure calls: Forward directly as staticcalls to get immediate results
     *
     * Staticcall detection mechanism:
     * - When this harness is called via staticcall (e.g., for view functions), the senderCoordinator.execute
     *   will fail because vm.prank attempts to modify state, which is not allowed in staticcall context
     * - This specific failure mode results in an empty revert (no error data)
     * - We detect this empty revert and fall back to forwarding the call as a staticcall
     *
     * Error handling:
     * - Empty revert data (length 0) → Indicates staticcall context, forward as staticcall
     * - Non-empty revert data → Real error (TransactionFailed, require, custom error), propagate it
     *
     * This approach ensures:
     * - View/pure functions work transparently through the harness
     * - Actual transaction failures are properly propagated with their error messages
     * - State-changing calls are queued for batch execution via the dispatcher
     */
    fallback(bytes calldata) external payable returns (bytes memory) {
        Transaction memory transaction =
            Transaction({to: target, value: msg.value, data: msg.data});

        // Try to execute through senderCoordinator (for state-changing calls)
        try senderCoordinator.execute(senderId, transaction) returns (SimulatedTransaction memory simulatedTx) {
            // Success: This was a state-changing call that was queued
            // Return the simulated return data
            bytes memory returnData = simulatedTx.returnData;
            assembly {
                return(add(returnData, 0x20), mload(returnData))
            }
        } catch (bytes memory errorData) {
            // If we have error data, this is a real revert that should be propagated
            // This includes TransactionFailed errors, require statements, custom errors, etc.
            if (errorData.length > 0) {
                assembly {
                    revert(add(errorData, 0x20), mload(errorData))
                }
            }

            // Empty revert data (length 0) indicates this might be a staticcall
            // The senderCoordinator.execute reverted because it detected staticcall context
            // Now try to forward as a staticcall to get the view function result
            (bool success, bytes memory returnData) = target.staticcall(msg.data);
            if (success) {
                assembly {
                    return(add(returnData, 0x20), mload(returnData))
                }
            } else {
                // The staticcall also failed - propagate the error
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }
}
