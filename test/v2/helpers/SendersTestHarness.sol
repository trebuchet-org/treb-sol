// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "../../../src/v2/internal/sender/Senders.sol";
import {Transaction, SimulatedTransaction, SenderTypes} from "../../../src/internal/types.sol";
import {Deployer} from "../../../src/v2/internal/sender/Deployer.sol";
import {SenderCoordinator} from "../../../src/v2/internal/SenderCoordinator.sol";

/// @dev v2 test harness — simplified since v2 has no type-specific senders,
///      no fork management, and no global queue broadcast.
contract SendersTestHarness is SenderCoordinator {
    using Senders for Senders.Sender;
    using Senders for Senders.Registry;
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;

    constructor(Senders.SenderInitConfig[] memory _configs)
        SenderCoordinator(_configs, "default", "sepolia", false, false)
    {}

    function execute(string memory _name, Transaction memory _transaction)
        public
        returns (SimulatedTransaction memory)
    {
        return Senders.get(_name).execute(_transaction);
    }

    function execute(string memory _name, Transaction[] memory _transactions)
        public
        returns (SimulatedTransaction[] memory)
    {
        return Senders.get(_name).execute(_transactions);
    }

    function get(string memory _name) public view returns (Senders.Sender memory) {
        return Senders.get(_name);
    }

    function getSenderAccount(string memory _name) public view returns (address) {
        return Senders.get(_name).account;
    }

    function isType(string memory _name, bytes8 _senderType) public view returns (bool) {
        return Senders.get(_name).isType(_senderType);
    }

    // ── Deployer Methods ────────────────────────────────────────────────

    function deployCreate3WithArtifact(string memory _name, string memory _artifact, bytes memory _args)
        public
        returns (address)
    {
        return Senders.get(_name).create3(_artifact).deploy(_args);
    }

    function deployCreate3WithArtifactAndLabel(
        string memory _name,
        string memory _artifact,
        string memory _label,
        bytes memory _args
    ) public returns (address) {
        return Senders.get(_name).create3(_artifact).setLabel(_label).deploy(_args);
    }

    function deployCreate3WithEntropy(
        string memory _name,
        string memory _entropy,
        bytes memory _bytecode,
        bytes memory _args
    ) public returns (address) {
        return Senders.get(_name).create3(_entropy, _bytecode).deploy(_args);
    }

    function predictCreate3WithArtifact(string memory _name, string memory _artifact, bytes memory _args)
        public
        returns (address)
    {
        return Senders.get(_name).create3(_artifact).predict(_args);
    }

    function predictCreate3WithArtifactAndLabel(
        string memory _name,
        string memory _artifact,
        string memory _label,
        bytes memory _args
    ) public returns (address) {
        return Senders.get(_name).create3(_artifact).setLabel(_label).predict(_args);
    }

    function predictCreate3WithEntropy(
        string memory _name,
        string memory _entropy,
        bytes memory _bytecode,
        bytes memory _args
    ) public returns (address) {
        return Senders.get(_name).create3(_entropy, _bytecode).predict(_args);
    }

    function deployCreate2WithArtifact(string memory _name, string memory _artifact, bytes memory _args)
        public
        returns (address)
    {
        return Senders.get(_name).create2(_artifact).deploy(_args);
    }

    function deployCreate2WithArtifactAndLabel(
        string memory _name,
        string memory _artifact,
        string memory _label,
        bytes memory _args
    ) public returns (address) {
        return Senders.get(_name).create2(_artifact).setLabel(_label).deploy(_args);
    }

    function predictCreate2WithArtifact(string memory _name, string memory _artifact, bytes memory _args)
        public
        returns (address)
    {
        return Senders.get(_name).create2(_artifact).predict(_args);
    }

    function _salt(string memory _name, string memory _entropy) public view returns (bytes32) {
        return Senders.get(_name)._salt(_entropy);
    }

    function _derivedSalt(string memory _name, bytes32 _baseSalt) public view returns (bytes32) {
        return Senders.get(_name)._derivedSalt(_baseSalt);
    }

    // ── Registry Helpers ────────────────────────────────────────────────

    function setNamespace(string memory _namespace) public {
        Senders.registry().namespace = _namespace;
    }

    function getNamespace() public view returns (string memory) {
        return Senders.registry().namespace;
    }

    // ── Harness Helpers ─────────────────────────────────────────────────

    function getHarness(string memory _name, address _target) public returns (address) {
        return Senders.get(_name).harness(_target);
    }
}
