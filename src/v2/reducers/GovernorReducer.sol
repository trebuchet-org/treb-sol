// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

/// @title GovernorReducer
/// @notice Built-in Solidity reducer for OZ Governor sender routing.
/// @dev This script is executed by Rust when a Governor sender's transactions
///      need to be wrapped in a governance proposal. It reads pending transactions
///      from environment variables (set by Rust), builds a Governor.propose() call,
///      and broadcasts it from the proposer address.
///
///      The output BroadcastableTransactions (one propose() call) are fed back
///      through route_all() for recursive routing — if the proposer is a Safe,
///      the propose tx will flow through Safe routing.
///
///      Environment variables (set by Rust):
///      - TREB_REDUCER_ADDRESS: The governance contract address (governor, DAO, custom)
///      - TREB_REDUCER_PROPOSER: The address that will call propose()
///      - TREB_REDUCER_PENDING_TXS: ABI-encoded (address[], uint256[], bytes[]) of pending txs
///      - TREB_REDUCER_DESCRIPTION: Optional human-readable description
///      - TREB_REDUCER_TIMELOCK: Timelock address (empty string if none)
///      - TREB_REDUCER_CHAIN_ID: Chain ID
contract GovernorReducer is Script {
    /// @notice IGovernor.propose selector for interface-level calls.
    /// @dev We use a low-level call with the propose selector to avoid
    ///      importing the full IGovernor interface (which varies across versions).
    bytes4 private constant PROPOSE_SELECTOR = 0x7d5e81e2;

    function run() public {
        address governor = vm.envAddress("TREB_REDUCER_ADDRESS");
        address proposer = vm.envAddress("TREB_REDUCER_PROPOSER");
        bytes memory pendingTxs = vm.envBytes("TREB_REDUCER_PENDING_TXS");
        string memory description = vm.envOr("TREB_REDUCER_DESCRIPTION", string(""));

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = abi.decode(pendingTxs, (address[], uint256[], bytes[]));

        // Build the propose() calldata
        bytes memory proposeCalldata = abi.encodeWithSelector(
            PROPOSE_SELECTOR,
            targets,
            values,
            calldatas,
            description
        );

        // Broadcast from the proposer — Rust will route this based on
        // the proposer's sender type (Wallet, Safe, etc.)
        vm.broadcast(proposer);
        (bool success, ) = governor.call(proposeCalldata);
        require(success, "Governor.propose() failed");
    }
}
