// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {Safe} from "safe-utils/Safe.sol";
import {PrivateKey, HardwareWallet, InMemory} from "./PrivateKeySender.sol";
import {GnosisSafe} from "./GnosisSafeSender.sol";
import {Deployer} from "./Deployer.sol";
import {Harness} from "../Harness.sol";

import "../types.sol";

library Senders {
    // keccak256("senders.registry")
    bytes32 constant REGISTRY_STORAGE_SLOT = 0xec6e4b146920a90a3174833331c3e69622ec7d9a352328df6e7b536886008f0e;
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidCast(string name, bytes8 senderType, bytes8 requiredType);
    error InvalidSenderType(string name, bytes8 senderType);
    error NoSenders();
    error TransactionExecutionMismatch(string label, bytes returnData);
    error CannotBroadcastCustomSender(string name);
    error UnexpectedSenderBroadcast(string name, bytes8 senderType);
    error BroadcastAlreadyCalled();

    using Senders for Senders.Registry;
    using Senders for Senders.Sender;
    using PrivateKey for PrivateKey.Sender;
    using HardwareWallet for HardwareWallet.Sender;
    using GnosisSafe for GnosisSafe.Sender;
    using InMemory for InMemory.Sender;

    event BundleSent(
        address indexed sender,
        bytes32 indexed bundleId,
        BundleStatus status,
        RichTransaction[] transactions
    );

    event TransactionFailed(
        bytes32 indexed bundleId,
        address indexed to,
        uint256 value,
        bytes data,
        string label
    );

    event TransactionSimulated(
        bytes32 indexed bundleId,
        address indexed to,
        uint256 value,
        bytes data,
        string label
    );

    struct SenderInitConfig {
        string name;
        address account;
        bytes8 senderType;
        bytes config;
    }

    struct Registry {
        mapping(bytes32 => Sender) senders;
        mapping(bytes32 => mapping(address => address)) senderHarness;
        bytes32[] ids;
        uint256 snapshot;
        bool broadcasted;
        string namespace;
        bool dryrun;
    }

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
        RichTransaction[] queue;
        bytes32 bundleId;
        bool broadcasted;
    }

    function registry() internal pure returns (Registry storage _registry) {
        assembly {
            _registry.slot := REGISTRY_STORAGE_SLOT
        }
    }

    // ************* Registry ************* //

    function reset() internal {
        Registry storage _registry = registry();
        // Clear all senders
        for (uint256 i = 0; i < _registry.ids.length; i++) {
            delete _registry.senders[_registry.ids[i]];
        }
        // Clear the registry
        delete _registry.ids;
        _registry.snapshot = 0;
        _registry.broadcasted = false;
        _registry.namespace = "";
        _registry.dryrun = false;
    }

    function initialize(Registry storage _registry, SenderInitConfig[] memory _configs) internal {
        _registry.namespace = vm.envOr("NAMESPACE", string("default"));
        _registry.dryrun = vm.envOr("DRYRUN", false);

        if (_configs.length == 0) {
            revert NoSenders();
        }
        _initializeSenders(_registry, _configs);
    }

    function initialize(SenderInitConfig[] memory _configs) internal {
        initialize(registry(), _configs);
    }

    function initialize(SenderInitConfig[] memory _configs, string memory _namespace, bool _dryrun) internal {
        initialize(registry(), _configs, _namespace, _dryrun);
    }

    function get(bytes32 _id) internal view returns (Sender storage) {
        return get(registry(), _id);
    }

    function get(string memory _name) internal view returns (Sender storage) {
        return registry().get(_name);
    }

    function get(Registry storage _registry, string memory _name) internal view returns (Sender storage) {
        return _registry.senders[keccak256(abi.encodePacked(_name))];
    }

    function get(Registry storage _registry, bytes32 _id) internal view returns (Sender storage) {
        return _registry.senders[_id];
    }



    function initialize(Registry storage _registry, SenderInitConfig[] memory _configs, string memory _namespace, bool _dryrun) internal {
        _registry.namespace = _namespace;
        _registry.dryrun = _dryrun;

        if (_configs.length == 0) {
            revert NoSenders();
        }
        _initializeSenders(_registry, _configs);
    }

    function _initializeSenders(Registry storage _registry, SenderInitConfig[] memory _configs) private {

        for (uint256 i = 0; i < _configs.length; i++) {
            bytes32 senderId = keccak256(abi.encodePacked(_configs[i].name));
            _registry.senders[senderId].id = senderId;
            _registry.senders[senderId].name = _configs[i].name;
            _registry.senders[senderId].account = _configs[i].account;
            _registry.senders[senderId].senderType = _configs[i].senderType;
            _registry.senders[senderId].config = _configs[i].config;
            _registry.senders[senderId].bundleId = keccak256(abi.encodePacked(block.chainid, block.timestamp, senderId));
            _registry.ids.push(senderId);
        }

        for (uint256 i = 0; i < _registry.ids.length; i++) {
            _registry.senders[_registry.ids[i]].initialize();
        }

        _registry.snapshot = vm.snapshotState();
    }

    function broadcast(Registry storage _registry) internal {
        console.log("Broadcasting registry");
        if (_registry.broadcasted) {
            revert BroadcastAlreadyCalled();
        }

        for (uint256 i = 0; i < _registry.ids.length; i++) {
            Sender storage sender = _registry.senders[_registry.ids[i]];
            console.log("Broadcasting sender", sender.name);
            console.log("Queue length", sender.queue.length);
            if (sender.queue.length > 0) {
                sender.broadcast();
            }
        }
        _registry.broadcasted = true;
    }

    // ************* Sender ************* //

    function initialize(Sender storage _sender) internal {
        if (_sender.isType(SenderTypes.InMemory)) {
            _sender.inMemory().initialize();
        } else if (_sender.isType(SenderTypes.HardwareWallet)) {
            _sender.hardwareWallet().initialize();
        } else if (_sender.isType(SenderTypes.GnosisSafe)) {
            _sender.gnosisSafe().initialize();
        } else if (!_sender.isType(SenderTypes.Custom)) {
            revert InvalidSenderType(_sender.name, _sender.senderType);
        }
    }

    function isType(Sender storage _sender, string memory _type) internal view returns (bool) {
        bytes8 typeHash = bytes8(keccak256(abi.encodePacked(_type)));
        return _sender.isType(typeHash);
    }

    function isType(Sender storage _sender, bytes8 _type) internal view returns (bool) {
        return _sender.senderType & _type == _type;
    }

    function privateKey(Sender storage _sender) internal view returns (PrivateKey.Sender storage) {
        return PrivateKey.cast(_sender);
    }

    function hardwareWallet(Sender storage _sender) internal view returns (HardwareWallet.Sender storage) {
        return HardwareWallet.cast(_sender);
    }

    function gnosisSafe(Sender storage _sender) internal view returns (GnosisSafe.Sender storage) {
        return GnosisSafe.cast(_sender);
    }

    function inMemory(Sender storage _sender) internal view returns (InMemory.Sender storage) {
        return InMemory.cast(_sender);
    }

    function harness(Sender storage _sender, address _target) internal returns (address) {
        Registry storage reg = registry();
        address _harness = reg.senderHarness[_sender.id][_target];
        if (_harness == address(0)) {
            _harness = address(new Harness(_target, _sender.name, _sender.id, address(this)));
            reg.senderHarness[_sender.id][_target] = _harness;
        }
        return _harness;
    }

    function execute(Sender storage _sender, Transaction[] memory _transactions) internal returns (RichTransaction[] memory bundleTransactions) {
        bundleTransactions = _sender.simulate(_transactions);
        for (uint256 i = 0; i < bundleTransactions.length; i++) {
            _sender.queue.push(bundleTransactions[i]);
        }
        console.log("Queue length", _sender.queue.length);
        _persistSender(_sender);
        return bundleTransactions;
    }
    
    function _persistSender(Sender storage _sender) internal {
        registry().senders[_sender.id] = _sender;
    }

    function execute(Sender storage _sender, Transaction memory _transaction) internal returns (RichTransaction memory bundleTransaction) {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = _transaction;
        RichTransaction[] memory bundleTransactions = _sender.execute(transactions);
        return bundleTransactions[0];
    }

    function simulate(Sender storage _sender, Transaction[] memory _transactions) internal returns (RichTransaction[] memory bundleTransactions) {
        bundleTransactions = new RichTransaction[](_transactions.length);
        for (uint256 i = 0; i < _transactions.length; i++) {
            vm.prank(_sender.account);
            (bool success, bytes memory returnData) = _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);
            emit TransactionSimulated( _sender.bundleId, _transactions[i].to, _transactions[i].value, _transactions[i].data, _transactions[i].label);
            if (!success) {
                emit TransactionFailed( _sender.bundleId, _transactions[i].to, _transactions[i].value, _transactions[i].data, _transactions[i].label);
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
            bundleTransactions[i] = RichTransaction({
                transaction: _transactions[i],
                simulatedReturnData: returnData,
                executedReturnData: new bytes(0)
            });
        }
        return bundleTransactions;
    }

    function broadcast(Sender storage _sender) internal returns (bytes32 bundleId) {
        if (_sender.broadcasted) {
            revert BroadcastAlreadyCalled();
        }
        if (_sender.isType(SenderTypes.Custom)) {
            revert CannotBroadcastCustomSender(_sender.name);
        }

        if (registry().dryrun) {
            return _sender.bundleId;
        }
        if (_sender.queue.length == 0) {
            return _sender.bundleId;
        }

        uint256 snap = vm.snapshotState();
        RichTransaction[] memory queue = _sender.queue;

        vm.revertToState(registry().snapshot);

        BundleStatus status;
        if (_sender.isType(SenderTypes.PrivateKey)) {
            (status, queue) = _sender.privateKey().broadcast(queue);
        } else if (_sender.isType(SenderTypes.GnosisSafe)) {
            (status, queue) = _sender.gnosisSafe().broadcast(queue);
        } else {
            revert UnexpectedSenderBroadcast(_sender.name, _sender.senderType);
        }

        emit BundleSent(
            _sender.account,
            _sender.bundleId,
            status,
            queue
        );

        vm.revertToState(snap);

        _sender.broadcasted = true;
        return _sender.bundleId;
    }
}
