// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript, CREATEX_ADDRESS} from "createx-forge/script/CreateXScript.sol";
import {Registry} from "./Registry.sol";
import {Transaction, OperationResult} from "./types.sol";

abstract contract Deployer is CreateXScript, Registry {
    error ContractNotFound(string what);
    error PredictedAddressMismatch(address predicted, address actual);

    function execute(Transaction memory _transaction) public virtual returns (OperationResult memory result);

    function getSender() internal virtual pure returns (address);

    // *************** CREATE3 *************** //
    function deployCreate3(bytes32 salt, bytes memory initCode) public returns (address) {
        address predictedAddress = predictCreate3(salt);
        OperationResult memory result = execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode),
            label: "deployCreate3",
            value: 0
        }));
        address actualAddress = abi.decode(result.returnData[0], (address));
        if (actualAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, actualAddress);
        }
        return abi.decode(result.returnData[0], (address));
    }

    function deployCreate3(string memory _entropy, bytes memory _bytecode, bytes memory _constructorArgs) public returns (address) {
        return deployCreate3(_salt(string.concat(namespace, ":", _entropy)), abi.encode(_bytecode, _constructorArgs));
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
        return CreateX.computeCreate3Address(_derivedSalt(salt));
    }

    // *************** CREATE2 *************** //

    function deployCreate2(bytes32 salt, bytes memory initCode) public returns (address) {
        address predictedAddress = predictCreate2(salt, initCode);
        OperationResult memory result = execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode),
            label: "deployCreate3",
            value: 0
        }));

        address actualAddress = abi.decode(result.returnData[0], (address));
        if (actualAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, actualAddress);
        }
    }

    function deployCreate2(string memory _entropy, bytes memory _bytecode, bytes memory _constructorArgs) public returns (address) {
        return deployCreate2(_salt(string.concat(namespace, ":", _entropy)), abi.encode(_bytecode, _constructorArgs));
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
        return CreateX.computeCreate2Address(_derivedSalt(salt), keccak256(initCode));
    }


    // *************** SALT HELPERS *************** //

    function _salt(string memory _entropy) internal pure returns (bytes32) {
        bytes32 entropy = keccak256(bytes(_entropy));
        // return entropy;
        return
            bytes32(
                abi.encodePacked(
                    getSender(),
                    hex"00",
                    bytes11(uint88(uint256(entropy)))
                )
            );
    }

    function _derivedSalt(bytes32 salt) internal view returns (bytes32 derivedSalt) {
        address deployer = getSender();

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