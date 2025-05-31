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
    ICreateX constant CREATEX = ICreateX(CREATEX_ADDRESS);
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;
    using Deployer for Deployment;

    error ContractNotFound(string what);
    error PredictedAddressMismatch(address predicted, address actual);
    error EntropyAlreadySet();
    error LabelAlreadySet();
    error ConstructorArgsAlreadySet();
    error InvalidCreateStrategy(CreateStrategy strategy);
    error EntropyOrArtifactRequired();

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

    struct EventDeployment {
        string artifact;
        string label;
        string entropy;
        bytes32 salt;
        bytes32 bytecodeHash;
        bytes32 initCodeHash;
        bytes constructorArgs;
        string createStrategy;
    }

    event ContractDeployed(
        address indexed deployer,
        address indexed location,
        bytes32 indexed transactionId,
        EventDeployment deployment
    );

    // *************** DEPLOYMENT *************** //

    /// @notice Creates a new deployment configuration
    /// @dev Uses a unique storage slot based on sender, bytecode, and transaction counter to avoid collisions
    /// @param sender The sender executing the deployment
    /// @param bytecode The contract bytecode to deploy
    /// @return deployment Storage pointer to the deployment configuration
    function _deploy(Senders.Sender storage sender, bytes memory bytecode) internal returns (Deployment storage deployment) {
        // Generate unique storage slot to prevent collisions between multiple deployments
        bytes32 deploymentSlot = keccak256(abi.encode(sender.account, bytecode, Senders.registry()._transactionCounter));
        assembly {
            deployment.slot := deploymentSlot
        }
        
        // Clear all storage attributes for fresh deployment
        delete deployment.sender;
        delete deployment.strategy;
        delete deployment.bytecode;
        delete deployment.label;
        delete deployment.entropy;
        delete deployment.artifact;
        
        // Set new values
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

    /// @notice Ensures deployment has valid entropy before execution
    /// @dev If no entropy is set, derives it from artifact name and optional label
    modifier verify(Deployment storage deployment) {
        if (bytes(deployment.entropy).length == 0) {
            if (bytes(deployment.artifact).length == 0) {
                revert EntropyOrArtifactRequired();
            }
            deployment.entropy = string.concat(Senders.registry().namespace, "/", deployment.artifact);
            if (bytes(deployment.label).length > 0) {
                deployment.entropy = string.concat(deployment.entropy, ":", deployment.label);
            }
        }
        _;
    }

    function deploy(Deployment storage deployment) internal returns (address) {
        return deployment.deploy("");
    }

    function deploy(Deployment storage deployment, bytes memory _constructorArgs) internal verify(deployment) returns (address) {
        Senders.Sender storage sender = deployment.sender;

        bytes memory initCode = abi.encodePacked(deployment.bytecode, _constructorArgs);
        bytes32 salt = sender._salt(deployment.entropy);
        address predictedAddress = deployment.predict(_constructorArgs);

        Transaction memory createTx;
        if (deployment.strategy == CreateStrategy.CREATE3) {
            createTx = Transaction({
                to: CREATEX_ADDRESS,
                data: abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode),
                label: "deployCreate3",
                value: 0
            });
        } else if (deployment.strategy == CreateStrategy.CREATE2) {
            createTx = Transaction({
                to: CREATEX_ADDRESS,
                data: abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode),
                label: "deployCreate2",
                value: 0
            });
        } else {
            revert InvalidCreateStrategy(deployment.strategy);
        }

        RichTransaction memory createTxResult = sender.execute(createTx);
        address simulatedAddress = abi.decode(createTxResult.simulatedReturnData, (address));
        if (simulatedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, simulatedAddress);
        }

        EventDeployment memory eventDeployment = EventDeployment({
            artifact: deployment.artifact,
            label: deployment.label,
            entropy: deployment.entropy,
            salt: salt,
            bytecodeHash: keccak256(deployment.bytecode),
            initCodeHash: keccak256(initCode),
            constructorArgs: _constructorArgs,
            createStrategy: deployment.strategy == CreateStrategy.CREATE3 ? "CREATE3" : "CREATE2"
        });

        emit ContractDeployed(
            sender.account,
            simulatedAddress,
            createTxResult.transactionId,
            eventDeployment
        );

        return simulatedAddress;
    }

    function predict(Deployment storage deployment) internal returns (address) {
        return deployment.predict("");
    }

    function predict(Deployment storage deployment, bytes memory _constructorArgs) internal verify(deployment) returns (address) {
        Senders.Sender storage sender = deployment.sender;
        bytes32 salt = sender._salt(deployment.entropy);

        salt = sender._derivedSalt(salt);
        if (deployment.strategy == CreateStrategy.CREATE3) {
            return CREATEX.computeCreate3Address(salt);
        } else if (deployment.strategy == CreateStrategy.CREATE2) {
            bytes memory initCodeHash = abi.encodePacked(deployment.bytecode, _constructorArgs);
            return CREATEX.computeCreate2Address(salt, keccak256(initCodeHash));
        } else {
            revert InvalidCreateStrategy(deployment.strategy);
        }
    }

    // *************** CREATE3 *************** //
    
    function create3(Senders.Sender storage sender, string memory _entropy, bytes memory bytecode) internal returns (Deployment storage deployment) {
        deployment = sender._deploy(bytecode);
        deployment.artifact = "<user-provided-bytecode>";
        deployment.entropy = _entropy;
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

    // *************** CREATE2 *************** //

    function create2(Senders.Sender storage sender, string memory _entropy, bytes memory bytecode) internal returns (Deployment storage deployment) {
        deployment = sender._deploy(bytecode);
        deployment.artifact = "<user-provided-bytecode>";
        deployment.entropy = _entropy;
        deployment.strategy = CreateStrategy.CREATE2;
    }

    function create2(Senders.Sender storage sender, string memory _artifact) internal returns (Deployment storage deployment) {
        try vm.getCode(_artifact) returns (bytes memory code) {
            deployment = sender._deploy(code);
            deployment.artifact = _artifact;
            deployment.strategy = CreateStrategy.CREATE2;
        } catch {
            revert ContractNotFound(_artifact);
        }
    }

    // *************** SALT HELPERS *************** //

    /// @notice Generates a salt for deterministic deployment
    /// @dev Salt format: [20 bytes sender][1 byte flag (0x00)][11 bytes entropy hash]
    /// @param sender The sender executing the deployment
    /// @param _entropy String used to generate unique deployment address
    /// @return Salt value for CREATE2/CREATE3 deployment
    function _salt(Senders.Sender storage sender, string memory _entropy) internal view returns (bytes32) {
        bytes11 entropy = bytes11(keccak256(bytes(_entropy)));
        return bytes32(abi.encodePacked(sender.account, hex"00", entropy));
    }

    /// @notice Derives final salt based on CreateX requirements
    /// @dev Salt derivation depends on the salt format:
    ///      - If salt has deployer address with flag 0x00: keccak256(deployer || salt)
    ///      - If salt has deployer address with flag 0x01: keccak256(deployer, chainId, salt)
    ///      - Otherwise: keccak256(salt)
    /// @param sender The sender executing the deployment
    /// @param salt The base salt value
    /// @return derivedSalt Final salt value for CreateX
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