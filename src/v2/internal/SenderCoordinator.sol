// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Senders} from "./sender/Senders.sol";
import {Transaction, SimulatedTransaction} from "../../internal/types.sol";
import {ITrebEvents} from "../../internal/ITrebEvents.sol";

/// @title SenderCoordinator (v2)
/// @notice Same API as v1 — provides sender() and broadcast modifier.
/// @dev In v2, the broadcast modifier is a no-op because Rust handles
///      transaction routing after execution. Scripts still use the modifier
///      for API compatibility but it doesn't process a global queue.
contract SenderCoordinator is Script, ITrebEvents {
    using Senders for Senders.Registry;
    using Senders for Senders.Sender;

    error SenderNotFound(string id);

    /// @notice Modifier for API compatibility. In v2 this is a no-op — Rust
    ///         routes transactions after execution based on sender type.
    modifier broadcast() {
        _;
    }

    constructor(
        Senders.SenderInitConfig[] memory _senderInitConfigs,
        string memory _namespace,
        string memory _network,
        bool _dryrun,
        bool _quiet
    ) {
        Senders.initialize(_senderInitConfigs, _namespace, _network, _quiet);
    }

    /// @notice Execute transactions through a specific sender (used by Deployer).
    function execute(bytes32 _senderId, Transaction[] memory _transactions)
        external
        returns (SimulatedTransaction[] memory)
    {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transactions);
    }

    /// @notice Execute a single transaction through a specific sender.
    function execute(bytes32 _senderId, Transaction memory _transaction)
        external
        returns (SimulatedTransaction memory)
    {
        Senders.Sender storage _sender = Senders.registry().get(_senderId);
        return _sender.execute(_transaction);
    }

    /// @notice Retrieves a sender by name.
    function sender(string memory _name) internal view returns (Senders.Sender storage) {
        return Senders.registry().get(_name);
    }
}
