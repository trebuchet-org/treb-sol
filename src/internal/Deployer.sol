// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {Sender} from "./Sender.sol";
import {Transaction, BundleTransaction} from "./types.sol";

contract Deployer is CreateXScript {
    error ContractNotFound(string what);
    error PredictedAddressMismatch(address predicted, address actual);

    event ContractDeployed(
        address indexed deployer,
        address indexed location,
        bytes32 indexed txId,
        bytes32 bundleId,
        bytes32 salt,
        bytes32 initCodeHash,
        bytes constructorArgs,
        string createStrategy
    );

    Sender private immutable sender;
    string private namespace;

    constructor(Sender _sender) withCreateX() {
        namespace = vm.envOr("NAMESPACE", string("default"));
        sender = _sender;
    }

    // Hook for testing - can be overridden to disable prediction checks
    function _checkPrediction() internal virtual view returns (bool) {
        return true;
    }

    // *************** CREATE3 *************** //
    function deployCreate3(bytes32 salt, bytes memory bytecode, bytes memory constructorArgs) public returns (address) {
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        address predictedAddress = predictCreate3(salt);
        BundleTransaction memory transaction = sender.execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode),
            label: "deployCreate3",
            value: 0
        }));
        address simulatedAddress = abi.decode(transaction.simulatedReturnData, (address));
        if (_checkPrediction() && simulatedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, simulatedAddress);
        }

        emit ContractDeployed(
            sender.senderAddress(),
            simulatedAddress,
            transaction.txId,
            transaction.bundleId,
            salt,
            keccak256(initCode),
            constructorArgs,
            "CREATE3"
        );

        return simulatedAddress;
    }

    function deployCreate3(string memory _entropy, bytes memory _bytecode, bytes memory _constructorArgs) public returns (address) {
        return deployCreate3(_salt(string.concat(namespace, ":", _entropy)), _bytecode, _constructorArgs);
    }

    function deployCreate3(string memory _what, string memory _label, bytes memory _constructorArgs) public returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return deployCreate3(string.concat(_what, ":", _label), code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate3(string memory _what, bytes memory _constructorArgs) public returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return deployCreate3(_what, code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate3(string memory _what) public returns (address) {
        return deployCreate3(_what, "");
    }

    function predictCreate3(bytes32 salt) public view returns (address) {
        return CreateX.computeCreate3Address(_derivedSalt(salt), sender.senderAddress());
    }

    // *************** CREATE2 *************** //

    function deployCreate2(bytes32 salt, bytes memory bytecode, bytes memory constructorArgs) public returns (address) {
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        bytes32 derivedSalt = _derivedSalt(salt);
        address predictedAddress = predictCreate2(salt, initCode);
        BundleTransaction memory bundleTransaction = sender.execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate2(bytes32,bytes)", derivedSalt, initCode),
            label: "deployCreate2",
            value: 0
        }));

        address simulatedAddress = abi.decode(bundleTransaction.simulatedReturnData, (address));
        if (_checkPrediction() && simulatedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, simulatedAddress);
        }

        emit ContractDeployed(
            sender.senderAddress(),
            simulatedAddress,
            bundleTransaction.txId,
            bundleTransaction.bundleId,
            salt,
            keccak256(initCode),
            constructorArgs,
            "CREATE2"
        );

        return simulatedAddress;
    }

    function deployCreate2(string memory _entropy, bytes memory _bytecode, bytes memory _constructorArgs) public returns (address) {
        return deployCreate2(_salt(_entropy), _bytecode, _constructorArgs);
    }

    function deployCreate2(string memory _what, string memory _label, bytes memory _constructorArgs) public returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return deployCreate2(string.concat(_what, ":", _label), code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate2(string memory _what, bytes memory _constructorArgs) public returns (address) {
        try vm.getCode(_what) returns (bytes memory code) {
            return deployCreate2(_what, code, _constructorArgs);
        } catch {
            revert ContractNotFound(_what);
        }
    }

    function deployCreate2(string memory _what) public returns (address) {
        return deployCreate2(_what, "");
    }

    function predictCreate2(bytes32 salt, bytes memory initCode) public view returns (address) {
        return CreateX.computeCreate2Address(_derivedSalt(salt), keccak256(initCode), sender.senderAddress());
    }


    // *************** SALT HELPERS *************** //

    function _salt(string memory _entropy) internal view returns (bytes32) {
        bytes32 entropy = keccak256(bytes(string.concat(namespace, ":", _entropy)));
        // return entropy;
        return
            bytes32(
                abi.encodePacked(
                    sender.senderAddress(),
                    hex"00",
                    bytes11(uint88(uint256(entropy)))
                )
            );
    }

    function _derivedSalt(bytes32 salt) internal view returns (bytes32 derivedSalt) {
        address deployer = sender.senderAddress();

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