// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Harness} from "../Harness.sol";
import {ITrebEvents} from "../../../internal/ITrebEvents.sol";
import {Transaction, SimulatedTransaction, SenderTypes} from "../../../internal/types.sol";

/// @title Senders (v2)
/// @notice Simplified sender registry — uses vm.broadcast() instead of vm.prank() + global queue.
/// @dev In v2, Rust routes transactions by sender type after execution. The Solidity side only needs
///      to track sender names/addresses and call vm.broadcast() for each transaction. No more
///      two-fork system, global transaction queue, or type-specific broadcast logic.
library Senders {
    using Senders for Sender;

    struct SenderInitConfig {
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
    }

    struct Registry {
        mapping(bytes32 => Sender) senders;
        mapping(bytes32 => mapping(address => address)) senderHarness;
        bytes32[] ids;
        string namespace;
        string network;
        bool quiet;
        bool initialized;
        uint256 transactionCounter;
    }

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
    }

    bytes32 private constant REGISTRY_STORAGE_SLOT = 0xec6e4b146920a90a3174833331c3e69622ec7d9a352328df6e7b536886008f0e;

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidSenderType(string name, bytes8 senderType);
    error SenderNotInitialized(string name);
    error NoSenders();
    error RegistryAlreadyInitialized();
    error CannotBroadcast(string name);
    error EmptyTransactionArray();
    error InvalidTargetAddress(uint256 index);

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
        SenderInitConfig[] memory _configs,
        string memory _namespace,
        string memory _network,
        bool _quiet
    ) internal {
        initialize(registry(), _configs, _namespace, _network, _quiet);
    }

    function initialize(
        Registry storage _registry,
        SenderInitConfig[] memory _configs,
        string memory _namespace,
        string memory _network,
        bool _quiet
    ) internal {
        if (_registry.initialized) revert RegistryAlreadyInitialized();

        _registry.namespace = _namespace;
        _registry.network = _network;
        _registry.initialized = true;
        _registry.quiet = _quiet;

        if (_configs.length == 0) revert NoSenders();

        _registry.ids = new bytes32[](_configs.length);
        unchecked {
            for (uint256 i; i < _configs.length; ++i) {
                bytes32 senderId = keccak256(abi.encodePacked(_configs[i].name));
                _registry.senders[senderId] = Sender({
                    id: senderId,
                    name: _configs[i].name,
                    account: _configs[i].account,
                    senderType: _configs[i].senderType,
                    canBroadcast: _configs[i].canBroadcast,
                    config: _configs[i].config
                });
                _registry.ids[i] = senderId;
            }
        }
        // v2: no fork creation, no type-specific initialization
    }

    function get(string memory _name) internal view returns (Sender storage) {
        return get(registry(), _name);
    }

    function get(Registry storage _registry, string memory _name) internal view returns (Sender storage) {
        Sender storage _sender = _registry.senders[keccak256(abi.encodePacked(_name))];
        if (_sender.account == address(0)) revert SenderNotInitialized(_name);
        return _sender;
    }

    function get(bytes32 _id) internal view returns (Sender storage) {
        return registry().senders[_id];
    }

    function get(Registry storage _registry, bytes32 _id) internal view returns (Sender storage) {
        return _registry.senders[_id];
    }

    function isType(Sender storage _sender, bytes8 _type) internal view returns (bool) {
        return _sender.senderType & _type == _type;
    }

    /// @notice Gets or creates a harness proxy for a sender-target pair.
    function harness(Sender storage _sender, address _target) internal returns (address) {
        Registry storage reg = registry();
        address _harness = reg.senderHarness[_sender.id][_target];
        if (_harness == address(0)) {
            _harness = address(new Harness(_target, _sender.name, _sender.id));
            reg.senderHarness[_sender.id][_target] = _harness;
        }
        return _harness;
    }

    // ── Transaction Execution (v2: vm.broadcast) ────────────────────────

    /// @notice Execute transactions through a sender using vm.broadcast().
    /// @dev In v2, transactions are broadcast directly via forge's vm.broadcast() cheatcode.
    ///      Forge captures these in BroadcastableTransactions with the `from` address set to
    ///      the sender's account. Rust routes them after execution.
    function execute(Sender storage _sender, Transaction[] memory _transactions)
        internal
        returns (SimulatedTransaction[] memory simulatedTransactions)
    {
        if (!_sender.canBroadcast) revert CannotBroadcast(_sender.name);
        if (_transactions.length == 0) revert EmptyTransactionArray();

        simulatedTransactions = new SimulatedTransaction[](_transactions.length);

        for (uint256 i = 0; i < _transactions.length; i++) {
            if (_transactions[i].to == address(0)) revert InvalidTargetAddress(i);

            bytes32 transactionId = generateTransactionId();

            // v2: use vm.broadcast instead of vm.prank + global queue
            vm.broadcast(_sender.account);
            (bool success, bytes memory returnData) =
                _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);

            if (!success) {
                assembly {
                    let dataSize := mload(returnData)
                    revert(add(returnData, 0x20), dataSize)
                }
            }

            simulatedTransactions[i] = SimulatedTransaction({
                transaction: _transactions[i],
                transactionId: transactionId,
                senderId: _sender.id,
                sender: _sender.account,
                returnData: returnData,
                gasUsed: 0 // not tracked in v2 — forge captures this
            });
        }
    }

    /// @notice Execute a single transaction through a sender.
    function execute(Sender storage _sender, Transaction memory _transaction)
        internal
        returns (SimulatedTransaction memory)
    {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = _transaction;
        return execute(_sender, transactions)[0];
    }
}
