// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Sender} from "../../Sender.sol";
import {Harness} from "../Harness.sol";

/// @title Senders (v2)
/// @notice Sender registry — maps names to Sender (UDVT over address).
/// @dev Stores sender name/address pairs at a fixed storage slot so every
///      contract in the inheritance tree shares one registry without constructor
///      plumbing. The Sender UDVT carries only the address; names are kept in
///      a side-mapping for labelling / diagnostics.
library Senders {
    struct Registry {
        mapping(bytes32 => Sender) senders;
        mapping(bytes32 => string) names;
        mapping(bytes32 => address) harnesses;
        bytes32[] ids;
        string namespace;
        string network;
        bool quiet;
        bool initialized;
        uint256 transactionCounter;
    }

    bytes32 private constant REGISTRY_STORAGE_SLOT = 0xec6e4b146920a90a3174833331c3e69622ec7d9a352328df6e7b536886008f0e;

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error SenderNotInitialized(string name);
    error NoSenders();
    error RegistryAlreadyInitialized();

    function registry() internal pure returns (Registry storage _registry) {
        assembly {
            _registry.slot := REGISTRY_STORAGE_SLOT
        }
    }

    function generateTransactionId() internal returns (bytes32) {
        Registry storage _registry = registry();
        _registry.transactionCounter++;
        return bytes32(_registry.transactionCounter);
    }

    // ── Registry Management ─────────────────────────────────────────────

    function initialize(
        string[] memory _names,
        address[] memory _accounts,
        string memory _namespace,
        string memory _network,
        bool _quiet
    ) internal {
        Registry storage _registry = registry();
        if (_registry.initialized) revert RegistryAlreadyInitialized();

        _registry.namespace = _namespace;
        _registry.network = _network;
        _registry.initialized = true;
        _registry.quiet = _quiet;

        if (_names.length == 0) revert NoSenders();

        _registry.ids = new bytes32[](_names.length);
        unchecked {
            for (uint256 i; i < _names.length; ++i) {
                bytes32 senderId = keccak256(abi.encodePacked(_names[i]));
                _registry.senders[senderId] = Sender.wrap(_accounts[i]);
                _registry.names[senderId] = _names[i];
                _registry.ids[i] = senderId;
            }
        }
    }

    // ── Lookup ──────────────────────────────────────────────────────────

    function get(string memory _name) internal view returns (Sender) {
        Registry storage _registry = registry();
        bytes32 id = keccak256(abi.encodePacked(_name));
        Sender _sender = _registry.senders[id];
        if (Sender.unwrap(_sender) == address(0)) revert SenderNotInitialized(_name);
        return _sender;
    }

    function get(bytes32 _id) internal view returns (Sender) {
        return registry().senders[_id];
    }

    function name(Sender _sender) internal view returns (string memory) {
        Registry storage _registry = registry();
        for (uint256 i; i < _registry.ids.length; ++i) {
            if (Sender.unwrap(_registry.senders[_registry.ids[i]]) == Sender.unwrap(_sender)) {
                return _registry.names[_registry.ids[i]];
            }
        }
        return "";
    }

    // ── Harness ─────────────────────────────────────────────────────────

    /// @notice Gets or creates a harness proxy for a sender-target pair.
    /// @dev The harness is allowed to call vm cheatcodes so it can broadcast
    ///      transactions from the sender's address.
    function harness(Sender _sender, address _target) internal returns (address) {
        Registry storage reg = registry();
        bytes32 key = keccak256(abi.encodePacked(Sender.unwrap(_sender), _target));
        address _harness = reg.harnesses[key];
        if (_harness == address(0)) {
            string memory senderName = name(_sender);
            _harness = address(new Harness(_target, _sender, senderName));
            vm.allowCheatcodes(_harness);
            reg.harnesses[key] = _harness;
        }
        return _harness;
    }
}
