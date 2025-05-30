// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Senders} from "../../src/internal/sender/Senders.sol";
import {PrivateKey, HardwareWallet, InMemory} from "../../src/internal/sender/PrivateKeySender.sol";
import {GnosisSafe} from "../../src/internal/sender/GnosisSafeSender.sol";
import {Transaction, RichTransaction} from "../../src/internal/types.sol";

contract SenderTestHarness {
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    using Senders for Senders.Sender;

    string public name;

    constructor(string memory _name, Senders.SenderInitConfig[] memory _configs) {
        Senders.initialize(_configs);
        name = _name;
    }

    function broadcast() public returns (bytes32) {
        return Senders.get(name).broadcast();
    }

    function execute(Transaction memory _transaction) public returns (RichTransaction memory) {
        return Senders.get(name).execute(_transaction);
    }

    function execute(Transaction[] memory _transactions) public returns (RichTransaction[] memory) {
        return Senders.get(name).execute(_transactions);
    }

    function get() public view returns (Senders.Sender memory) {
        return Senders.get(name);
    }

    function getPrivateKey() public view returns (PrivateKey.Sender memory) {
        return Senders.get(name).privateKey();
    }

    function getGnosisSafe() public view returns (GnosisSafe.Sender memory) {
        return Senders.get(name).gnosisSafe();
    }

    function getHardwareWallet() public view returns (HardwareWallet.Sender memory) {
        return Senders.get(name).hardwareWallet();
    }

    function getInMemory() public view returns (InMemory.Sender memory) {
        return Senders.get(name).inMemory();
    }
}
