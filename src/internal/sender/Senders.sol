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
    /// @dev Storage slot for the Registry singleton, derived from keccak256("senders.registry")
    /// @dev This ensures the registry doesn't conflict with other storage in inherited contracts
    bytes32 constant REGISTRY_STORAGE_SLOT = 0xec6e4b146920a90a3174833331c3e69622ec7d9a352328df6e7b536886008f0e;
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidCast(string name, bytes8 senderType, bytes8 requiredType);
    error InvalidSenderType(string name, bytes8 senderType);
    error SenderNotInitialized(string name);
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

    event TransactionFailed(
        bytes32 indexed transactionId,
        address indexed sender,
        address indexed to,
        uint256 value,
        bytes data,
        string label
    );

    event TransactionSimulated(
        bytes32 indexed transactionId,
        address indexed sender,
        address indexed to,
        uint256 value,
        bytes data,
        string label,
        bytes returnData
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
        RichTransaction[] _globalQueue;

        string namespace;
        bool dryrun;

        uint256 snapshot;
        bool _broadcasted;
        uint256 _transactionCounter;
    }

    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bytes config;
    }

    function registry() internal pure returns (Registry storage _registry) {
        assembly {
            _registry.slot := REGISTRY_STORAGE_SLOT
        }
    }

    /// @notice Generates a unique transaction ID for tracking
    /// @dev Combines chain ID, timestamp, and an incrementing counter to ensure uniqueness
    /// @return Unique transaction identifier
    function generateTransactionId() internal returns (bytes32) {
        Registry storage _registry = registry();
        _registry._transactionCounter++;
        return keccak256(abi.encodePacked(
            block.chainid, 
            block.timestamp, 
            msg.sender,
            _registry._transactionCounter
        ));
    }

    // ************* Registry ************* //

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
        Sender storage sender = _registry.senders[keccak256(abi.encodePacked(_name))];
        if (sender.account == address(0)) {
            revert SenderNotInitialized(_name);
        }
        return sender;
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
        _registry.ids = new bytes32[](_configs.length);
        unchecked {
            for (uint256 i; i < _configs.length; ++i) {
            bytes32 senderId = keccak256(abi.encodePacked(_configs[i].name));
            _registry.senders[senderId].id = senderId;
            _registry.senders[senderId].name = _configs[i].name;
            _registry.senders[senderId].account = _configs[i].account;
            _registry.senders[senderId].senderType = _configs[i].senderType;
            _registry.senders[senderId].config = _configs[i].config;
            _registry.ids[i] = senderId;
            }
        }
        
        unchecked {
            for (uint256 i; i < _registry.ids.length; ++i) {
                _registry.senders[_registry.ids[i]].initialize();
            }
        }

        _registry.snapshot = vm.snapshotState();
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

    // ************* Sender Execute ************* //

    function execute(Sender storage _sender, Transaction[] memory _transactions) internal returns (RichTransaction[] memory bundleTransactions) {
        require(_transactions.length > 0, "Empty transaction array");
        for (uint256 i = 0; i < _transactions.length; i++) {
            require(_transactions[i].to != address(0), "Invalid target address");
            require(bytes(_transactions[i].label).length > 0, "Transaction label required");
        }
        return _sender.simulate(_transactions);
    }
    
    function execute(Sender storage _sender, Transaction memory _transaction) internal returns (RichTransaction memory bundleTransaction) {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = _transaction;
        RichTransaction[] memory bundleTransactions = _sender.execute(transactions);
        return bundleTransactions[0];
    }

    function simulate(Sender storage _sender, Transaction[] memory _transactions) internal returns (RichTransaction[] memory bundleTransactions) {
        Registry storage _registry = registry();
        bundleTransactions = new RichTransaction[](_transactions.length);
        
        for (uint256 i = 0; i < _transactions.length; i++) {
            // Generate unique transaction ID
            bytes32 transactionId = generateTransactionId();
            
            vm.prank(_sender.account);
            (bool success, bytes memory returnData) = _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);
            emit TransactionSimulated(
                transactionId,
                _sender.account,
                _transactions[i].to,
                _transactions[i].value,
                _transactions[i].data,
                _transactions[i].label,
                returnData
            );
            if (!success) {
                emit TransactionFailed(
                    transactionId,
                    _sender.account,
                    _transactions[i].to,
                    _transactions[i].value,
                    _transactions[i].data,
                    _transactions[i].label
                );
                // Bubble up the revert reason from the failed call
                assembly {
                    let dataSize := mload(returnData)
                    revert(add(returnData, 0x20), dataSize)
                }
            }
            
            RichTransaction memory richTx = RichTransaction({
                transaction: _transactions[i],
                transactionId: transactionId,
                senderId: _sender.id,
                status: TransactionStatus.PENDING,
                simulatedReturnData: returnData,
                executedReturnData: new bytes(0)
            });
            
            bundleTransactions[i] = richTx;
            // Add to global queue in order
            _registry._globalQueue.push(richTx);
        }
        return bundleTransactions;
    }

    // ************* Registry Broadcast ************* //

    /// @notice Broadcasts all queued transactions in the order they were submitted
    /// @dev Processes transactions differently based on sender type:
    ///      - PrivateKey: Immediate broadcast
    ///      - GnosisSafe: Batched for multi-sig execution
    ///      - Custom: Returned for external processing
    /// @param _registry The sender registry containing all queued transactions
    /// @return customQueue Array of custom sender transactions requiring external processing
    function broadcast(Registry storage _registry) internal returns (RichTransaction[] memory customQueue) {
        if (_registry._broadcasted) {
            revert BroadcastAlreadyCalled();
        }

        if (_registry.dryrun) {
            _registry._broadcasted = true;
            return new RichTransaction[](0);
        }


        uint256 snap = vm.snapshotState();

        customQueue = new RichTransaction[](_registry._globalQueue.length);
        RichTransaction[] memory txs = _registry._globalQueue;
        bytes32[] memory senderIds = _registry.ids;

        vm.revertToState(_registry.snapshot);
        uint256 actualCustomQueueLength = 0;

        // Process each transaction in global queue order
        for (uint256 i = 0; i < txs.length; i++) {
            RichTransaction memory richTx = txs[i];
            Sender storage sender = _registry.senders[richTx.senderId];

            if (sender.isType(SenderTypes.PrivateKey)) {
                // Sync execution - broadcast immediately
                sender.privateKey().broadcast(richTx);
            } else if (sender.isType(SenderTypes.GnosisSafe)) {
                // Async execution - accumulate for batch
                sender.gnosisSafe().queue(richTx);
            } else if (sender.isType(SenderTypes.Custom)) {
                customQueue[actualCustomQueueLength] = richTx;
                actualCustomQueueLength++;
            }
        }

        assembly {
            mstore(customQueue, actualCustomQueueLength)
        }

        // Now broadcast accumulated async transactions as bundles
        for (uint256 i = 0; i < senderIds.length; i++) {
            Sender storage sender = _registry.senders[senderIds[i]];
            if (sender.isType(SenderTypes.GnosisSafe)) {
                sender.gnosisSafe().broadcast();
            }
        }

        vm.revertToState(snap);
        _registry._broadcasted = true;
        return customQueue;
    }
}
