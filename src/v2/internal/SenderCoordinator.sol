// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Senders} from "./sender/Senders.sol";

/// @title SenderCoordinator (v2)
/// @notice Initializes senders from encoded config and provides sender() lookup.
/// @dev In v2, there is no execute() — the Sender UDVT carries broadcast methods
///      directly (sender.broadcast(), sender.startBroadcast()), and the Deployer
///      library calls vm.broadcast before each CreateX deployment. The Harness
///      also broadcasts directly instead of delegating back here.
contract SenderCoordinator is Script {
    error SenderNotFound(string id);

    /// @notice Modifier for API compatibility. In v2 this is a no-op — Rust
    ///         routes transactions after execution based on sender type.
    modifier broadcast() {
        _;
    }

    constructor(
        bytes memory _senderConfigs,
        string memory _namespace,
        string memory _network,
        bool _dryrun,
        bool _quiet
    ) {
        (string[] memory names, address[] memory accounts) =
            abi.decode(_senderConfigs, (string[], address[]));
        Senders.initialize(names, accounts, _namespace, _network, _quiet);
    }

    /// @notice Retrieves a sender by name.
    function sender(string memory _name) internal view returns (Senders.Sender) {
        return Senders.get(_name);
    }
}
