// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Senders} from "../../src/internal/sender/Senders.sol";
import {PrivateKey, HardwareWallet, InMemory} from "../../src/internal/sender/PrivateKeySender.sol";
import {GnosisSafe} from "../../src/internal/sender/GnosisSafeSender.sol";
import {Transaction, RichTransaction, SenderTypes} from "../../src/internal/types.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {Safe} from "safe-utils/Safe.sol";
import {Deployer} from "../../src/internal/sender/Deployer.sol";
import {SenderCoordinator} from "../../src/internal/SenderCoordinator.sol";

contract SendersTestHarness is SenderCoordinator {
    using Senders for Senders.Sender;
    using Senders for Senders.Registry;
    using Safe for Safe.Client;
    using GnosisSafe for GnosisSafe.Sender;
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;

    constructor(Senders.SenderInitConfig[] memory _configs) 
        SenderCoordinator(_configs, "default", false, false) 
    {
        // Also initialize Senders directly (SenderCoordinator initializes lazily)
        Senders.initialize(_configs, "default", false);
        
        // Deploy MultiSendCallOnly for testing (after initialize)
        MultiSendCallOnly multiSendCallOnly = new MultiSendCallOnly();
        
        // Setup Safe senders for testing
        for (uint256 i = 0; i < _configs.length; i++) {
            if (_configs[i].senderType == SenderTypes.GnosisSafe) {
                // Get the Safe.Client storage for this sender
                Senders.Sender storage sender = Senders.get(_configs[i].name);
                GnosisSafe.Sender storage gnosisSafeSender = GnosisSafe.cast(sender);
                Safe.Client storage safeClient = gnosisSafeSender.safe();
                safeClient.instance().urls[block.chainid] = "https://localhost";
                safeClient.instance().multiSendCallOnly[block.chainid] = multiSendCallOnly;
                
                // Mock Safe contract calls
                address safeAddress = sender.account;
                vm.mockCall(
                    safeAddress,
                    abi.encodeWithSignature("nonce()"),
                    abi.encode(uint256(0))
                );
                vm.mockCall(
                    safeAddress,
                    abi.encodeWithSignature("getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)"),
                    abi.encode(bytes32(keccak256("mock-tx-hash")))
                );
                
            }
        }
        
        // Update the snapshot to include our MultiSendCallOnly setup
        Senders.registry().snapshot = vm.snapshotState();
    }

    function broadcastAll() public {
        _broadcast();
    }

    function execute(string memory _name, Transaction memory _transaction) public returns (RichTransaction memory) {
        return Senders.get(_name).execute(_transaction);
    }

    function execute(string memory _name, Transaction[] memory _transactions) public returns (RichTransaction[] memory) {
        return Senders.get(_name).execute(_transactions);
    }

    function get(string memory _name) public view returns (Senders.Sender memory) {
        return Senders.get(_name);
    }

    function getSenderAccount(string memory _name) public view returns (address) {
        return Senders.get(_name).account;
    }

    function getPrivateKey(string memory _name) public view returns (PrivateKey.Sender memory) {
        return Senders.get(_name).privateKey();
    }

    function getGnosisSafe(string memory _name) public view returns (GnosisSafe.Sender memory) {
        return Senders.get(_name).gnosisSafe();
    }

    function getHardwareWallet(string memory _name) public view returns (HardwareWallet.Sender memory) {
        return Senders.get(_name).hardwareWallet();
    }

    function getInMemory(string memory _name) public view returns (InMemory.Sender memory) {
        return Senders.get(_name).inMemory();
    }

    function isType(string memory _name, bytes8 _senderType) public view returns (bool) {
        return Senders.get(_name).isType(_senderType);
    }

    // ************* Deployer Methods ************* //

    // Factory pattern methods only
    function deployCreate3WithArtifact(string memory _name, string memory _artifact, bytes memory _args) public returns (address) {
        // Use factory pattern: create3 -> deploy
        return Senders.get(_name).create3(_artifact).deploy(_args);
    }

    function deployCreate3WithArtifactAndLabel(string memory _name, string memory _artifact, string memory _label, bytes memory _args) public returns (address) {
        // Use factory pattern: create3 -> setLabel -> deploy
        return Senders.get(_name).create3(_artifact).setLabel(_label).deploy(_args);
    }

    function deployCreate3WithEntropy(string memory _name, string memory _entropy, bytes memory _bytecode, bytes memory _args) public returns (address) {
        // Use factory pattern: create3 with entropy -> deploy
        return Senders.get(_name).create3(_entropy, _bytecode).deploy(_args);
    }

    // ************* Prediction Methods ************* //
    
    // Mirror deployCreate3WithArtifact
    function predictCreate3WithArtifact(string memory _name, string memory _artifact, bytes memory _args) public returns (address) {
        return Senders.get(_name).create3(_artifact).predict(_args);
    }

    // Mirror deployCreate3WithArtifactAndLabel
    function predictCreate3WithArtifactAndLabel(string memory _name, string memory _artifact, string memory _label, bytes memory _args) public returns (address) {
        return Senders.get(_name).create3(_artifact).setLabel(_label).predict(_args);
    }

    // Mirror deployCreate3WithEntropy
    function predictCreate3WithEntropy(string memory _name, string memory _entropy, bytes memory _bytecode, bytes memory _args) public returns (address) {
        return Senders.get(_name).create3(_entropy, _bytecode).predict(_args);
    }

    function _salt(string memory _name, string memory _entropy) public view returns (bytes32) {
        return Senders.get(_name)._salt(_entropy);
    }
    
    function _derivedSalt(string memory _name, bytes32 _baseSalt) public view returns (bytes32) {
        return Senders.get(_name)._derivedSalt(_baseSalt);
    }

    // ************* Registry Helpers ************* //

    function setNamespace(string memory _namespace) public {
        Senders.registry().namespace = _namespace;
    }

    function getNamespace() public view returns (string memory) {
        return Senders.registry().namespace;
    }

    function setDryrun(bool _dryrun) public {
        Senders.registry().dryrun = _dryrun;
    }

    function getDryrun() public view returns (bool) {
        return Senders.registry().dryrun;
    }
    
    // ************* Harness Helpers ************* //
    
    function getHarness(string memory _name, address _target) public returns (address) {
        return Senders.get(_name).harness(_target);
    }
}
