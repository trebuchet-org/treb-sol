// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CommonBase} from "forge-std/Base.sol";
import {Senders} from "./sender/Senders.sol";

/// @title Harness (v2)
/// @notice Proxy contract for sender-scoped contract interactions.
/// @dev Intercepts all calls to the target and wraps them in
///      vm.startBroadcast(sender) / vm.stopBroadcast().  Using startBroadcast
///      (rather than single-shot broadcast) lets forge handle both state-changing
///      calls and view/pure staticcalls transparently.
///      The harness must be marked with vm.allowCheatcodes() at creation time.
contract Harness is CommonBase {
    using Senders for Senders.Sender;

    address private _target;
    Senders.Sender private _sender;

    constructor(address target_, Senders.Sender sender_, string memory senderName_) {
        _target = target_;
        _sender = sender_;
        vm.label(address(this), string.concat("Harness[", senderName_, "]"));
    }

    receive() external payable {}

    fallback(bytes calldata) external payable returns (bytes memory) {
        _sender.startBroadcast();
        (bool success, bytes memory returnData) = _target.call{value: msg.value}(msg.data);
        _sender.stopBroadcast();
        if (!success) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
        assembly {
            return(add(returnData, 0x20), mload(returnData))
        }
    }
}
