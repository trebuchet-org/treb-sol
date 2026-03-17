// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

type Sender is address;

using SenderLib for Sender global;

/// @title SenderLib
/// @notice Methods attached to the Sender user-defined value type.
/// @dev Sender is a thin wrapper around address. broadcast()/startBroadcast()
///      delegate directly to forge's vm cheatcodes so the sender address appears
///      as `from` in BroadcastableTransactions for Rust-side routing.
library SenderLib {
    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    /// @notice Unwrap to a plain address (e.g. for vm.label, abi.encode, comparisons).
    function addr(Sender s) internal pure returns (address) {
        return Sender.unwrap(s);
    }

    /// @notice Broadcast the next transaction from this sender.
    function broadcast(Sender s) internal {
        vm.broadcast(Sender.unwrap(s));
    }

    /// @notice Start a broadcast scope — all subsequent calls are from this sender.
    function startBroadcast(Sender s) internal {
        vm.startBroadcast(Sender.unwrap(s));
    }

    /// @notice Stop the active broadcast scope.
    function stopBroadcast(Sender) internal {
        vm.stopBroadcast();
    }
}
