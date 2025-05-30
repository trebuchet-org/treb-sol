// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {Senders} from "./Senders.sol";
import {RichTransaction, Transaction} from "../types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {ICreateX} from "createx-forge/script/ICreateX.sol";

library Deployer {
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    ICreateX constant CreateX = ICreateX(CREATEX_ADDRESS);
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;
    using Deployer for Deployment;

    error ContractNotFound(string what);
    error PredictedAddressMismatch(address predicted, address actual);
    error EntropyAlreadySet();
    error LabelAlreadySet();
    error ConstructorArgsAlreadySet();
    error InvalidCreateStrategy(CreateStrategy strategy);

    event DeployingContract(string what, string label, bytes32 initCodeHash);

    enum CreateStrategy {
        CREATE3,
        CREATE2
    }

    struct Deployment {
        Senders.Sender sender;
        CreateStrategy strategy;
        bytes bytecode;
        string label;
        string entropy;
        string artifact;
    }

    event ContractDeployed(
        address indexed deployer,
        address indexed location,
        bytes32 indexed bundleId,
        bytes32 salt,
        bytes32 bytecodeHash,
        bytes32 initCodeHash,
        bytes constructorArgs,
        string createStrategy
    );

    // *************** DEPLOYMENT *************** //

    function _deploy(Senders.Sender storage sender, bytes memory bytecode) internal returns (Deployment storage deployment) {
        bytes32 deploymentSlot = keccak256(abi.encode(sender.account, bytecode, sender.queue.length));
        assembly {
            deployment.slot := deploymentSlot
        }
        deployment.sender = sender;
        deployment.bytecode = bytecode;
    }

    function setLabel(Deployment storage deployment, string memory _label) internal returns (Deployment storage) {
        if (bytes(deployment.entropy).length > 0) {
            revert EntropyAlreadySet();
        }
        deployment.label = _label;
        return deployment;
    }

    function setEntropy(Deployment storage deployment, string memory _entropy) internal returns (Deployment storage) {
        if (bytes(deployment.label).length > 0) {
            revert LabelAlreadySet();
        }
        deployment.entropy = _entropy;
        return deployment;
    }

    function deploy(Deployment storage deployment) internal returns (address) {
        return deployment.deploy("");
    }

    function deploy(Deployment storage deployment, bytes memory _constructorArgs) internal returns (address) {
        if (bytes(deployment.entropy).length == 0) {
            deployment.entropy = string.concat(deployment.artifact, ":", deployment.label);
        }
        if (deployment.strategy == CreateStrategy.CREATE3) {
            return deployment.sender.deployCreate3(deployment.sender._salt(deployment.entropy), deployment.bytecode, _constructorArgs);
        } else if (deployment.strategy == CreateStrategy.CREATE2) {
            return deployment.sender.deployCreate2(deployment.sender._salt(deployment.entropy), deployment.bytecode, _constructorArgs);
        } else {
            revert InvalidCreateStrategy(deployment.strategy);
        }
    }

    function predict(Deployment storage deployment) internal returns (address) {
        if (bytes(deployment.entropy).length == 0) {
            deployment.entropy = string.concat(deployment.artifact, ":", deployment.label);
        }
        if (deployment.strategy == CreateStrategy.CREATE3) {
            return deployment.sender.predictCreate3(deployment.sender._salt(deployment.entropy));
        } else if (deployment.strategy == CreateStrategy.CREATE2) {
            return deployment.sender.predictCreate2(deployment.sender._salt(deployment.entropy), deployment.bytecode);
        } else {
            revert InvalidCreateStrategy(deployment.strategy);
        }
    }

    // *************** CREATE3 *************** //
    
    function create3(Senders.Sender storage sender, string memory _entropy, bytes memory bytecode) internal returns (Deployment storage deployment) {
        deployment = sender._deploy(bytecode);
        deployment.artifact = _entropy;
        deployment.strategy = CreateStrategy.CREATE3;
    }

    function create3(Senders.Sender storage sender, string memory _artifact) internal returns (Deployment storage deployment) {
        try vm.getCode(_artifact) returns (bytes memory code) {
            deployment = sender._deploy(code);
            deployment.artifact = _artifact;
            deployment.strategy = CreateStrategy.CREATE3;
        } catch {
            revert ContractNotFound(_artifact);
        }
    }

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
            keccak256(bytecode),
            keccak256(initCode),
            constructorArgs,
            "CREATE3"
        );

        return simulatedAddress;
    }

    function predictCreate3(Senders.Sender storage sender, bytes32 salt) internal view returns (address) {
        return CreateX.computeCreate3Address(sender._derivedSalt(salt));
    }

    // *************** CREATE2 *************** //

    function deployCreate2(Senders.Sender storage sender, bytes32 salt, bytes memory bytecode, bytes memory constructorArgs) internal returns (address) {
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        address predictedAddress = sender.predictCreate2(salt, initCode);
        RichTransaction memory bundleTransaction = sender.execute(Transaction({
            to: CREATEX_ADDRESS,
            data: abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode),
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
            keccak256(bytecode),
            keccak256(initCode),
            constructorArgs,
            "CREATE2"
        );

        return simulatedAddress;
    }

    function predictCreate2(Senders.Sender storage sender, bytes32 salt, bytes memory initCode) internal view returns (address) {
        return CreateX.computeCreate2Address(sender._derivedSalt(salt), keccak256(initCode));
    }

    // *************** SALT HELPERS *************** //

    function _salt(Senders.Sender storage sender, string memory _entropy) internal view returns (bytes32) {
        string memory namespace = Senders.registry().namespace;
        bytes32 entropy = keccak256(bytes(string.concat(namespace, ":", _entropy)));
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