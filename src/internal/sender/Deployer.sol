// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {RichTransaction, Transaction} from "../types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {ICreateX} from "createx-forge/script/ICreateX.sol";

library Deployer {
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    ICreateX constant CreateX = ICreateX(CREATEX_ADDRESS);
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;

    error ContractNotFound(string what);
    error PredictedAddressMismatch(address predicted, address actual);

    event DeployingContract(string what, string label, bytes32 initCodeHash);

    event ContractDeployed(
        address indexed deployer,
        address indexed location,
        bytes32 indexed bundleId,
        bytes32 salt,
        bytes32 initCodeHash,
        bytes constructorArgs,
        string createStrategy
    );

    // *************** CREATE3 *************** //
    function deployCreate3(Senders.Sender storage sender, bytes32 salt, bytes memory bytecode, bytes memory constructorArgs) internal returns (address) {
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        address predictedAddress = sender.predictCreate3(salt);
        RichTransaction memory richTransaction = sender.execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode),
            label: "deployCreate3",
            value: 0
        }));
        address simulatedAddress = abi.decode(richTransaction.simulatedReturnData, (address));
        if (simulatedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, simulatedAddress);
        }

        emit ContractDeployed(
            sender.account,
            simulatedAddress,
            sender.bundleId,
            salt,
            keccak256(initCode),
            constructorArgs,
            "CREATE3"
        );

        return simulatedAddress;
    }

    function deployCreate3(Senders.Sender storage sender, string memory _entropy, bytes memory _bytecode, bytes memory _constructorArgs) internal returns (address) {
        return sender.deployCreate3(sender._salt(_entropy), _bytecode, _constructorArgs);
    }

    function deployCreate3(Senders.Sender storage sender, string memory _what, string memory _label, bytes memory _constructorArgs) internal returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            emit DeployingContract(_what, _label, keccak256(code));
            return sender.deployCreate3(string.concat(_what, ":", _label), code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate3(Senders.Sender storage sender, string memory _what, bytes memory _constructorArgs) internal returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return sender.deployCreate3(_what, code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate3(Senders.Sender storage sender, string memory _what) internal returns (address) {
        return sender.deployCreate3(_what, "");
    }

    function predictCreate3(Senders.Sender storage sender, bytes32 salt) internal view returns (address) {
        return CreateX.computeCreate3Address(sender._derivedSalt(salt), sender.account);
    }

    function predictCreate3(Senders.Sender storage sender, string memory _entropy) internal view returns (address) {
        return sender.predictCreate3(sender._salt(_entropy));
    }

    // *************** CREATE2 *************** //

    function deployCreate2(Senders.Sender storage sender, bytes32 salt, bytes memory bytecode, bytes memory constructorArgs) internal returns (address) {
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        bytes32 derivedSalt = sender._derivedSalt(salt);
        address predictedAddress = sender.predictCreate2(salt, initCode);
        RichTransaction memory bundleTransaction = sender.execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate2(bytes32,bytes)", derivedSalt, initCode),
            label: "deployCreate2",
            value: 0
        }));

        address simulatedAddress = abi.decode(bundleTransaction.simulatedReturnData, (address));
        if (simulatedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, simulatedAddress);
        }

        emit ContractDeployed(
            sender.account,
            simulatedAddress,
            sender.bundleId,
            salt,
            keccak256(initCode),
            constructorArgs,
            "CREATE2"
        );

        return simulatedAddress;
    }

    function deployCreate2(Senders.Sender storage sender, string memory _entropy, bytes memory _bytecode, bytes memory _constructorArgs) internal returns (address) {
        return sender.deployCreate2(sender._salt(_entropy), _bytecode, _constructorArgs);
    }

    function deployCreate2(Senders.Sender storage sender, string memory _what, string memory _label, bytes memory _constructorArgs) internal returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return sender.deployCreate2(string.concat(_what, ":", _label), code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate2(Senders.Sender storage sender, string memory _what, bytes memory _constructorArgs) internal returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return sender.deployCreate2(_what, code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate2(Senders.Sender storage sender, string memory _what) internal returns (address) {
        return sender.deployCreate2(_what, "");
    }

    function predictCreate2(Senders.Sender storage sender, bytes32 salt, bytes memory initCode) internal view returns (address) {
        return CreateX.computeCreate2Address(sender._derivedSalt(salt), keccak256(initCode));
    }

    function predictCreate2(Senders.Sender storage sender, string memory _entropy, bytes memory initCode) internal view returns (address) {
        return sender.predictCreate2(sender._salt(_entropy), initCode);
    }

    // *************** SALT HELPERS *************** //

    function _salt(Senders.Sender storage sender, string memory _entropy) internal view returns (bytes32) {
        string memory namespace = vm.envOr("NAMESPACE", string("default"));
        bytes32 entropy = keccak256(bytes(string.concat(namespace, ":", _entropy)));
        // return entropy;
        return
            bytes32(
                abi.encodePacked(
                    sender.account,
                    hex"00",
                    bytes11(uint88(uint256(entropy)))
                )
            );
    }

    function _derivedSalt(Senders.Sender storage sender, bytes32 salt) internal view returns (bytes32 derivedSalt) {
        address deployer = sender.account;

        bytes1 saltFlag = salt[20];
        address saltAddress = address(bytes20(salt));

        if (saltAddress == deployer && saltFlag == hex"00") {
            derivedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), salt));
        } else if (saltAddress == deployer && saltFlag == hex"01") {
            derivedSalt = keccak256(abi.encode(deployer, block.chainid, salt));
        } else {
            derivedSalt = keccak256(abi.encode(salt));
        }
    }
}