// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {Transaction, SimulatedTransaction} from "../types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {ICreateX} from "createx-forge/script/ICreateX.sol";
import {ITrebEvents} from "../ITrebEvents.sol";

/**
 * @title Deployer
 * @author Trebuchet Team
 * @notice A library for deterministic smart contract deployments using CreateX
 * @dev This library provides a comprehensive deployment system with the following features:
 *      - Deterministic deployments via CREATE2 and CREATE3 opcodes through CreateX factory
 *      - Builder pattern for flexible deployment configuration
 *      - Multi-sender support (EOA, hardware wallet, Safe multisig)
 *      - Automatic salt generation based on entropy, labels, and namespaces
 *      - Address prediction before actual deployment
 *      - Integration with Trebuchet's registry system
 *
 * The library uses CreateX factory (0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed) for all deployments,
 * ensuring consistent addresses across different EVM chains.
 *
 * @custom:security-contact security@trebuchet.org
 */
library Deployer {
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;
    using Deployer for Deployment;

    /**
     * @notice Deployment strategy for deterministic deployments
     * @dev CREATE3 provides address independence from init code, CREATE2 includes init code in address calculation
     */
    enum CreateStrategy {
        CREATE3, // Address = f(deployer, salt) - init code independent
        CREATE2 // Address = f(deployer, salt, initCodeHash) - init code dependent

    }

    /**
     * @notice Deployment configuration using builder pattern
     * @dev This struct is created and configured through the deployment functions
     * @param sender The sender executing the deployment (EOA, hardware wallet, or Safe)
     * @param strategy CREATE2 or CREATE3 deployment strategy
     * @param bytecode The contract bytecode to deploy
     * @param label Optional label for deployment categorization (e.g., "v2", "hotfix")
     * @param entropy Unique string for salt generation (auto-generated if not provided)
     * @param artifact The artifact path used to load bytecode (e.g., "Counter.sol:Counter")
     */
    struct Deployment {
        Senders.Sender sender;
        CreateStrategy strategy;
        bytes bytecode;
        string label;
        string entropy;
        string artifact;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    ICreateX private constant CREATEX = ICreateX(CREATEX_ADDRESS);

    // Keccak256 hashes of known vm.getCode error messages
    bytes32 private constant NO_BYTECODE_HASH = keccak256("vm.getCode: no bytecode for contract; is it abstract or unlinked?");
    bytes32 private constant NO_ARTIFACT_HASH = keccak256("vm.getCode: no matching artifact found");

    // Custom errors for better gas efficiency and clarity
    error ContractNotFound(string what);
    error BytecodeMissing(string what);
    error PredictedAddressMismatch(address predicted, address actual);
    error EntropyAlreadySet();
    error LabelAlreadySet();
    error ConstructorArgsAlreadySet();
    error InvalidCreateStrategy(CreateStrategy strategy);
    error EntropyOrArtifactRequired();

    /**
     * @notice Ensures deployment has valid entropy before execution
     * @dev If no entropy is set, derives it from: namespace/artifact[:label]
     *      Examples:
     *      - "default/Counter" (no label)
     *      - "staging/Counter:v2" (with label)
     *      - "production/UniswapV3Factory" (custom entropy)
     */
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

    // *************** DEPLOYMENT *************** //

    /**
     * @notice Creates a new deployment configuration using the builder pattern
     * @dev Uses a unique storage slot based on sender, bytecode, and transaction counter to avoid collisions.
     *      This ensures multiple deployments within the same transaction don't interfere with each other.
     *      The deployment must be configured with either entropy or artifact before execution.
     * @param sender The sender executing the deployment
     * @param bytecode The contract bytecode to deploy
     * @return deployment Storage pointer to the deployment configuration
     *
     * @custom:example
     * ```solidity
     * // Create deployment and configure with label
     * sender._deploy(bytecode)
     *     .setLabel("v2")
     *     .deploy();
     * ```
     */
    function _deploy(Senders.Sender storage sender, bytes memory bytecode)
        internal
        returns (Deployment storage deployment)
    {
        // Generate unique storage slot to prevent collisions between multiple deployments
        bytes32 deploymentSlot = keccak256(abi.encode(sender.account, bytecode, Senders.registry().transactionCounter));
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

    /**
     * @notice Sets a label for the deployment
     * @dev Labels are used to differentiate multiple deployments of the same contract.
     *      They become part of the salt generation, affecting the deployment address.
     *      Cannot be used with custom entropy.
     * @param deployment The deployment configuration
     * @param _label Label string (e.g., "v2", "hotfix", "staging")
     * @return deployment The same deployment for chaining
     *
     * @custom:example
     * ```solidity
     * // Deploy Counter with label "v2"
     * sender.create3("Counter.sol:Counter")
     *     .setLabel("v2")
     *     .deploy();
     * ```
     */
    function setLabel(Deployment storage deployment, string memory _label) internal returns (Deployment storage) {
        if (bytes(deployment.entropy).length > 0) {
            revert EntropyAlreadySet();
        }
        deployment.label = _label;
        return deployment;
    }

    /**
     * @notice Sets custom entropy for salt generation
     * @dev Entropy directly controls the deployment salt and thus the contract address.
     *      Cannot be used with labels - use one or the other.
     *      For most cases, using artifact + label is recommended over custom entropy.
     * @param deployment The deployment configuration
     * @param _entropy Custom entropy string
     * @return deployment The same deployment for chaining
     *
     * @custom:example
     * ```solidity
     * // Deploy with custom entropy
     * sender.create3("production/UniswapV3Factory", bytecode)
     *     .deploy();
     * ```
     */
    function setEntropy(Deployment storage deployment, string memory _entropy) internal returns (Deployment storage) {
        if (bytes(deployment.label).length > 0) {
            revert LabelAlreadySet();
        }
        deployment.entropy = _entropy;
        return deployment;
    }

    /**
     * @notice Deploys a contract without constructor arguments
     * @dev Convenience function that calls deploy with empty constructor args
     * @param deployment The deployment configuration
     * @return The deployed contract address
     */
    function deploy(Deployment storage deployment) internal returns (address) {
        return deployment.deploy("");
    }

    /**
     * @notice Deploys a contract with the configured settings
     * @dev This is the main deployment function that:
     *      1. Generates salt from entropy/namespace/label
     *      2. Predicts the deployment address
     *      3. Checks if contract already exists at predicted address
     *      4. If collision detected, emits DeploymentCollision event and returns existing address
     *      5. Otherwise, executes deployment via CreateX
     *      6. Verifies the deployed address matches prediction
     *      7. Emits ContractDeployed event
     *
     *      Collision handling ensures that multi-contract deployment scripts can continue
     *      even when some contracts are already deployed, making scripts idempotent.
     * @param deployment The deployment configuration
     * @param _constructorArgs ABI-encoded constructor arguments
     * @return The contract address (either newly deployed or existing)
     *
     * @custom:example
     * ```solidity
     * // Deploy with constructor args
     * address token = sender.create3("Token.sol:Token")
     *     .deploy(abi.encode("MyToken", "MTK", 18));
     *
     * // Deploy with label
     * address tokenV2 = sender.create3("Token.sol:Token")
     *     .setLabel("v2")
     *     .deploy(abi.encode("MyToken V2", "MTK2", 18));
     * ```
     */
    function deploy(Deployment storage deployment, bytes memory _constructorArgs)
        internal
        verify(deployment)
        returns (address)
    {
        bytes32 salt = deployment.sender._salt(deployment.entropy);
        address predictedAddress = deployment.predict(_constructorArgs);
        bytes memory initCode = abi.encodePacked(deployment.bytecode, _constructorArgs);

        // Check if contract already exists at predicted address
        if (predictedAddress.code.length > 0) {
            // Emit collision event if not in quiet mode
            if (!Senders.registry().quiet) {
                ITrebEvents.DeploymentDetails memory deploymentDetails = ITrebEvents.DeploymentDetails({
                    artifact: deployment.artifact,
                    label: deployment.label,
                    entropy: deployment.entropy,
                    salt: salt,
                    bytecodeHash: keccak256(deployment.bytecode),
                    initCodeHash: keccak256(initCode),
                    constructorArgs: _constructorArgs,
                    createStrategy: deployment.strategy == CreateStrategy.CREATE3 ? "CREATE3" : "CREATE2"
                });

                emit ITrebEvents.DeploymentCollision(predictedAddress, deploymentDetails);
            }

            // Return the existing contract address without attempting deployment
            return predictedAddress;
        }

        // Create and execute the deployment transaction
        Transaction memory createTx = _createDeploymentTransaction(deployment.strategy, salt, initCode);

        SimulatedTransaction memory createTxResult = deployment.sender.execute(createTx);
        address simulatedAddress = abi.decode(createTxResult.returnData, (address));

        if (simulatedAddress != predictedAddress) {
            revert PredictedAddressMismatch(predictedAddress, simulatedAddress);
        }

        if (!Senders.registry().quiet) {
            _emitDeploymentEvent(
                deployment, createTxResult.transactionId, simulatedAddress, salt, keccak256(initCode), _constructorArgs
            );
        }

        return simulatedAddress;
    }

    /**
     * @notice Emits the deployment event
     * @dev Emits the deployment event with the deployment details
     * @param deployment The deployment configuration
     * @param transactionId The transaction ID of the deployment
     * @param simulatedAddress The simulated address of the deployed contract
     * @param salt The salt used for the deployment
     * @param initCodeHash The init code hash used for the deployment
     * @param _constructorArgs The constructor arguments used for the deployment
     */
    function _emitDeploymentEvent(
        Deployment storage deployment,
        bytes32 transactionId,
        address simulatedAddress,
        bytes32 salt,
        bytes32 initCodeHash,
        bytes memory _constructorArgs
    ) internal {
        ITrebEvents.DeploymentDetails memory deploymentDetails = ITrebEvents.DeploymentDetails({
            artifact: deployment.artifact,
            label: deployment.label,
            entropy: deployment.entropy,
            salt: salt,
            bytecodeHash: keccak256(deployment.bytecode),
            initCodeHash: initCodeHash,
            constructorArgs: _constructorArgs,
            createStrategy: deployment.strategy == CreateStrategy.CREATE3 ? "CREATE3" : "CREATE2"
        });

        emit ITrebEvents.ContractDeployed(deployment.sender.account, simulatedAddress, transactionId, deploymentDetails);
    }

    /**
     * @notice Predicts the deployment address without constructor arguments
     * @dev Convenience function that calls predict with empty constructor args
     * @param deployment The deployment configuration
     * @return The predicted contract address
     */
    function predict(Deployment storage deployment) internal returns (address) {
        return deployment.predict("");
    }

    /**
     * @notice Predicts the deployment address for the configured settings
     * @dev Address calculation depends on the strategy:
     *      - CREATE3: address = f(factory, deployer, salt)
     *      - CREATE2: address = f(factory, deployer, salt, initCodeHash)
     *
     *      The salt is derived from entropy and includes the sender address.
     *      This ensures different senders get different addresses even with same entropy.
     * @param deployment The deployment configuration
     * @param _constructorArgs ABI-encoded constructor arguments (only affects CREATE2)
     * @return The predicted contract address
     *
     * @custom:example
     * ```solidity
     * // Predict address before deployment
     * address predicted = sender.create3("Token.sol:Token")
     *     .setLabel("v2")
     *     .predict(abi.encode("MyToken", "MTK", 18));
     *
     * // Deploy and verify address matches
     * address actual = sender.create3("Token.sol:Token")
     *     .setLabel("v2")
     *     .deploy(abi.encode("MyToken", "MTK", 18));
     *
     * assert(predicted == actual);
     * ```
     */
    function predict(Deployment storage deployment, bytes memory _constructorArgs)
        internal
        verify(deployment)
        returns (address)
    {
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

    /**
     * @notice Configures CREATE3 deployment with custom bytecode and entropy
     * @dev CREATE3 provides init code independence - the deployment address doesn't change
     *      even if constructor arguments or bytecode change. Use for upgradeable contracts
     *      or when you need stable addresses across different contract versions.
     * @param sender The sender executing the deployment
     * @param _entropy Custom entropy string for salt generation
     * @param bytecode The contract bytecode to deploy
     * @return deployment The configured deployment (use .deploy() to execute)
     *
     * @custom:example
     * ```solidity
     * // Deploy with custom bytecode and entropy
     * address proxy = sender.create3("MyProxy:stable", proxyBytecode)
     *     .deploy(abi.encode(implementationAddress));
     * ```
     */
    function create3(Senders.Sender storage sender, string memory _entropy, bytes memory bytecode)
        internal
        returns (Deployment storage deployment)
    {
        deployment = sender._deploy(bytecode);
        deployment.artifact = "<user-provided-bytecode>";
        deployment.entropy = _entropy;
        deployment.strategy = CreateStrategy.CREATE3;
    }

    /**
     * @notice Configures CREATE3 deployment from artifact path
     * @dev This is the most common deployment method. Loads bytecode from Foundry artifacts
     *      and generates entropy from namespace/artifact[:label] pattern.
     * @param sender The sender executing the deployment
     * @param _artifact The artifact path (e.g., "Counter.sol:Counter")
     * @return deployment The configured deployment (use .deploy() to execute)
     *
     * @custom:example
     * ```solidity
     * // Basic deployment
     * address counter = sender.create3("Counter.sol:Counter").deploy();
     *
     * // Deployment with label for different version
     * address counterV2 = sender.create3("Counter.sol:Counter")
     *     .setLabel("v2")
     *     .deploy();
     *
     * // Different namespaces get different addresses
     * // (assuming NAMESPACE env var is set to "staging")
     * // entropy: "staging/Counter" vs "default/Counter"
     * ```
     */
    function create3(Senders.Sender storage sender, string memory _artifact)
        internal
        returns (Deployment storage deployment)
    {
        try vm.getCode(_artifact) returns (bytes memory code) {
            deployment = sender._deploy(code);
            deployment.artifact = _artifact;
            deployment.strategy = CreateStrategy.CREATE3;
        } catch Error(string memory reason) {
            bytes32 reasonHash = keccak256(bytes(reason));
            if (reasonHash == NO_BYTECODE_HASH) {
                revert BytecodeMissing(_artifact);
            }
            revert ContractNotFound(_artifact);
        } catch (bytes memory lowLevelData) {
            // Check if this is a revert with a reason string
            if (lowLevelData.length >= 68) {
                assembly {
                    lowLevelData := add(lowLevelData, 0x04)
                }
                string memory revertReason = abi.decode(lowLevelData, (string));
                bytes32 reasonHash = keccak256(bytes(revertReason));
                if (reasonHash == NO_BYTECODE_HASH) {
                    revert BytecodeMissing(_artifact);
                }
            }
            revert ContractNotFound(_artifact);
        }
    }

    // *************** CREATE2 *************** //

    /**
     * @notice Configures CREATE2 deployment with custom bytecode and entropy
     * @dev CREATE2 includes init code hash in address calculation - changing constructor
     *      arguments or bytecode will result in a different address. Use when you need
     *      the deployment address to be tied to specific contract code.
     * @param sender The sender executing the deployment
     * @param _entropy Custom entropy string for salt generation
     * @param bytecode The contract bytecode to deploy
     * @return deployment The configured deployment (use .deploy() to execute)
     *
     * @custom:example
     * ```solidity
     * // Deploy singleton with specific bytecode
     * address singleton = sender.create2("MySingleton:v1", singletonBytecode)
     *     .deploy(abi.encode(initParam));
     * ```
     */
    function create2(Senders.Sender storage sender, string memory _entropy, bytes memory bytecode)
        internal
        returns (Deployment storage deployment)
    {
        deployment = sender._deploy(bytecode);
        deployment.artifact = "<user-provided-bytecode>";
        deployment.entropy = _entropy;
        deployment.strategy = CreateStrategy.CREATE2;
    }

    /**
     * @notice Configures CREATE2 deployment from artifact path
     * @dev Similar to CREATE3 but includes init code in address calculation.
     *      Changing constructor args will change the deployment address.
     * @param sender The sender executing the deployment
     * @param _artifact The artifact path (e.g., "Counter.sol:Counter")
     * @return deployment The configured deployment (use .deploy() to execute)
     *
     * @custom:example
     * ```solidity
     * // CREATE2 deployment - address depends on constructor args
     * address token1 = sender.create2("Token.sol:Token")
     *     .deploy(abi.encode("Token1", "TK1"));
     *
     * address token2 = sender.create2("Token.sol:Token")
     *     .deploy(abi.encode("Token2", "TK2"));
     *
     * // token1 != token2 due to different constructor args
     * ```
     */
    function create2(Senders.Sender storage sender, string memory _artifact)
        internal
        returns (Deployment storage deployment)
    {
        try vm.getCode(_artifact) returns (bytes memory code) {
            deployment = sender._deploy(code);
            deployment.artifact = _artifact;
            deployment.strategy = CreateStrategy.CREATE2;
        } catch Error(string memory reason) {
            bytes32 reasonHash = keccak256(bytes(reason));
            if (reasonHash == NO_BYTECODE_HASH) {
                revert BytecodeMissing(_artifact);
            }
            revert ContractNotFound(_artifact);
        } catch (bytes memory lowLevelData) {
            // Check if this is a revert with a reason string
            if (lowLevelData.length >= 68) {
                assembly {
                    lowLevelData := add(lowLevelData, 0x04)
                }
                string memory revertReason = abi.decode(lowLevelData, (string));
                bytes32 reasonHash = keccak256(bytes(revertReason));
                if (reasonHash == NO_BYTECODE_HASH) {
                    revert BytecodeMissing(_artifact);
                }
            }
            revert ContractNotFound(_artifact);
        }
    }

    // *************** SALT HELPERS *************** //

    /**
     * @notice Generates base salt for deterministic deployment
     * @dev Salt format ensures different senders get different addresses even with same entropy:
     *      [20 bytes: sender address][1 byte: flag (0x00)][11 bytes: entropy hash]
     *
     *      The entropy typically follows these patterns:
     *      - "namespace/artifact" (e.g., "default/Counter")
     *      - "namespace/artifact:label" (e.g., "staging/Counter:v2")
     *      - Custom entropy string (e.g., "production/UniswapV3Factory")
     * @param sender The sender executing the deployment
     * @param _entropy String used to generate unique deployment address
     * @return Salt value for CREATE2/CREATE3 deployment
     *
     * @custom:entropy-patterns
     * Common entropy patterns and their effects on addresses:
     * - "default/Counter" → Different address per sender
     * - "staging/Counter:v2" → Different from v1, different per sender
     * - Same entropy + same sender = same address (deterministic)
     * - Same entropy + different sender = different address (sender isolation)
     */
    function _salt(Senders.Sender storage sender, string memory _entropy) internal view returns (bytes32) {
        bytes11 entropy = bytes11(keccak256(bytes(_entropy)));
        return bytes32(abi.encodePacked(sender.account, hex"00", entropy));
    }

    /**
     * @notice Derives final salt based on CreateX salt derivation rules
     * @dev CreateX uses different salt derivation strategies based on salt format:
     *
     *      1. If salt contains deployer address with flag 0x00:
     *         derivedSalt = keccak256(deployer || salt)
     *
     *      2. If salt contains deployer address with flag 0x01:
     *         derivedSalt = keccak256(abi.encode(deployer, chainId, salt))
     *
     *      3. Otherwise (generic salt):
     *         derivedSalt = keccak256(abi.encode(salt))
     *
     *      Our salts use format #1 for consistent cross-chain addresses.
     * @param sender The sender executing the deployment
     * @param salt The base salt value from _salt()
     * @return derivedSalt Final salt value used by CreateX factory
     *
     * @custom:example
     * ```solidity
     * // Generate and derive salt
     * bytes32 baseSalt = sender._salt("default/Counter:v2");
     * bytes32 finalSalt = sender._derivedSalt(baseSalt);
     *
     * // Use with CreateX
     * address predicted = CREATEX.computeCreate3Address(finalSalt);
     * ```
     */
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

    /**
     * @notice Creates the deployment transaction based on strategy
     */
    function _createDeploymentTransaction(CreateStrategy strategy, bytes32 salt, bytes memory initCode)
        internal
        pure
        returns (Transaction memory)
    {
        if (strategy == CreateStrategy.CREATE3) {
            return Transaction({
                to: CREATEX_ADDRESS,
                data: abi.encodeWithSignature("deployCreate3(bytes32,bytes)", salt, initCode),
                value: 0
            });
        } else if (strategy == CreateStrategy.CREATE2) {
            return Transaction({
                to: CREATEX_ADDRESS,
                data: abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, initCode),
                value: 0
            });
        } else {
            revert InvalidCreateStrategy(strategy);
        }
    }

    /**
     * @dev ===============================================
     *      COMPREHENSIVE USAGE EXAMPLES & PATTERNS
     *      ===============================================
     *
     * This section demonstrates common deployment patterns and how entropy,
     * labels, and namespaces work together to create deterministic addresses.
     *
     * @custom:usage-patterns
     *
     * 1. BASIC DEPLOYMENT
     * ```solidity
     * contract DeployBasic is Script {
     *     function run() public {
     *         // Simple deployment - entropy auto-generated as "default/Counter"
     *         address counter = sender().create3("Counter.sol:Counter").deploy();
     *     }
     * }
     * ```
     *
     * 2. LABELED DEPLOYMENTS (Multiple versions)
     * ```solidity
     * contract DeployVersions is Script {
     *     function run() public {
     *         // Deploy v1 - entropy: "default/Counter"
     *         address counterV1 = sender().create3("Counter.sol:Counter").deploy();
     *
     *         // Deploy v2 - entropy: "default/Counter:v2"
     *         address counterV2 = sender().create3("Counter.sol:Counter")
     *             .setLabel("v2")
     *             .deploy();
     *
     *         // Deploy hotfix - entropy: "default/Counter:hotfix-123"
     *         address counterHotfix = sender().create3("Counter.sol:Counter")
     *             .setLabel("hotfix-123")
     *             .deploy();
     *
     *         // All three have different addresses due to different entropy
     *     }
     * }
     * ```
     *
     * 3. NAMESPACE ENVIRONMENTS
     * ```solidity
     * // With NAMESPACE=staging environment variable:
     * contract DeployStaging is Script {
     *     function run() public {
     *         // entropy: "staging/Counter" (different from default/Counter)
     *         address counter = sender().create3("Counter.sol:Counter").deploy();
     *
     *         // entropy: "staging/Counter:v2"
     *         address counterV2 = sender().create3("Counter.sol:Counter")
     *             .setLabel("v2")
     *             .deploy();
     *     }
     * }
     * ```
     *
     * 4. CUSTOM ENTROPY (Advanced usage)
     * ```solidity
     * contract DeployCustom is Script {
     *     function run() public {
     *         // Use custom entropy for special cases
     *         address singleton = sender()
     *             .create3("production/UniswapV3Factory", factoryBytecode)
     *             .deploy();
     *
     *         // This address will be the same across all chains and environments
     *         // because entropy is hardcoded
     *     }
     * }
     * ```
     *
     * 5. CREATE2 vs CREATE3 DIFFERENCES
     * ```solidity
     * contract DeployComparison is Script {
     *     function run() public {
     *         bytes memory args1 = abi.encode("Token1", "TK1");
     *         bytes memory args2 = abi.encode("Token2", "TK2");
     *
     *         // CREATE3: Same address regardless of constructor args
     *         address token1_c3 = sender().create3("Token.sol:Token").deploy(args1);
     *         address token2_c3 = sender().create3("Token.sol:Token").deploy(args2);
     *         // token1_c3 == token2_c3 (same entropy, same sender)
     *
     *         // CREATE2: Different addresses due to different init code
     *         address token1_c2 = sender().create2("Token.sol:Token").deploy(args1);
     *         address token2_c2 = sender().create2("Token.sol:Token").deploy(args2);
     *         // token1_c2 != token2_c2 (constructor args affect address)
     *     }
     * }
     * ```
     *
     * 6. ADDRESS PREDICTION
     * ```solidity
     * contract PredictAndDeploy is Script {
     *     function run() public {
     *         bytes memory constructorArgs = abi.encode("MyToken", "MTK", 18);
     *
     *         // Predict address before deployment
     *         address predicted = sender().create3("Token.sol:Token")
     *             .setLabel("v2")
     *             .predict(constructorArgs);
     *
     *         console.log("Will deploy to:", predicted);
     *
     *         // Deploy and verify
     *         address actual = sender().create3("Token.sol:Token")
     *             .setLabel("v2")
     *             .deploy(constructorArgs);
     *
     *         require(predicted == actual, "Address mismatch");
     *     }
     * }
     * ```
     *
     * 7. MULTI-SENDER ISOLATION
     * ```solidity
     * contract MultiSenderExample is Script {
     *     function run() public {
     *         // Different senders get different addresses even with same entropy
     *         address addr1 = sender("deployer1").create3("Counter.sol:Counter").deploy();
     *         address addr2 = sender("deployer2").create3("Counter.sol:Counter").deploy();
     *         // addr1 != addr2 (different senders, same entropy)
     *
     *         // Same sender + same entropy = same address (deterministic)
     *         address addr3 = sender("deployer1").create3("Counter.sol:Counter").deploy();
     *         // addr1 == addr3 (same sender, same entropy)
     *     }
     * }
     * ```
     *
     * @custom:entropy-reference
     *
     * ENTROPY GENERATION RULES:
     * - If setEntropy() is called: use custom entropy directly
     * - If setLabel() is called: entropy = "namespace/artifact:label"
     * - If neither is called: entropy = "namespace/artifact"
     * - Namespace comes from NAMESPACE environment variable (default: "default")
     *
     * SALT FORMAT:
     * baseSalt = [sender(20)] + [0x00(1)] + [keccak256(entropy)[0:11](11)]
     * finalSalt = keccak256(sender || baseSalt)  // for CreateX
     *
     * ADDRESS CALCULATION:
     * CREATE3: address = CreateX.computeCreate3Address(finalSalt)
     * CREATE2: address = CreateX.computeCreate2Address(finalSalt, keccak256(initCode))
     */
}
