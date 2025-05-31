// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {ConfigurableTrebScript} from "../src/TrebScript.sol";
import {Deployer} from "../src/internal/sender/Deployer.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {SenderTypes} from "../src/internal/types.sol";
import {ExampleContract} from "./ExampleContract.sol";
import {console} from "forge-std/console.sol";

/**
 * @title ExampleDeploy
 * @notice Comprehensive example demonstrating ConfigurableTrebScript usage with Safe multisig workflow
 * @dev This script demonstrates:
 *      1. Manual sender configuration (no environment variables required)
 *      2. Deploying a contract with a private key sender
 *      3. Transferring ownership to a Safe multisig
 *      4. Executing owner-only transactions through the Safe
 */
contract ExampleDeploy is ConfigurableTrebScript, CreateXScript {
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;
    using Senders for Senders.Sender;

    constructor()
        ConfigurableTrebScript(
            _getSenderConfigs(), // Custom sender configuration
            "example", // Namespace
            "example-registry.json", // Registry file
            false // Not dry run
        )
    {}

    /**
     * @notice Configure senders for the deployment script
     * @dev This function demonstrates how to set up a complete Safe multisig workflow with:
     *      - A deployer (private key sender) for initial contract deployment
     *      - A proposer (private key sender) that can propose Safe transactions
     *      - A Safe multisig as the final owner of deployed contracts
     * @return Array of sender configurations
     */
    function _getSenderConfigs()
        internal
        pure
        returns (Senders.SenderInitConfig[] memory)
    {
        Senders.SenderInitConfig[]
            memory configs = new Senders.SenderInitConfig[](3);

        // 1. Deployer - Private key sender for initial deployment
        // In production, this would be a hardware wallet or secure key management
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil test account #0
            senderType: SenderTypes.InMemory,
            config: abi.encode(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
            ) // Anvil private key #0
        });

        // 2. Proposer - Private key sender that can propose Safe transactions
        // This account will have permission to propose transactions to the Safe
        configs[1] = Senders.SenderInitConfig({
            name: "proposer",
            account: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // Anvil test account #1
            senderType: SenderTypes.InMemory,
            config: abi.encode(
                0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
            ) // Anvil private key #1
        });

        // 3. Safe - Multisig wallet that will become the owner of deployed contracts
        // The proposer (account #1) must be an owner of this Safe
        configs[2] = Senders.SenderInitConfig({
            name: "safe",
            account: 0x90F79bf6EB2c4f870365E785982E1f101E93b906, // Example Safe address (Anvil #3)
            senderType: SenderTypes.GnosisSafe,
            config: abi.encode("proposer") // References the proposer sender by name
        });

        return configs;
    }

    /**
     * @notice Main deployment function demonstrating complete Safe multisig workflow
     * @dev This function executes a complete deployment and ownership transfer workflow:
     *      1. Deploy contract using deployer sender
     *      2. Transfer ownership to Safe multisig
     *      3. Execute owner-only operations through Safe
     */
    function run() public broadcast withCreateX {
        // Phase 1: Deploy contract with deployer account
        console.log("=== Phase 1: Deploying Contract ===");

        Senders.Sender storage deployer = sender("deployer");
        Senders.Sender storage safe = sender("safe");

        // Deploy the example contract with deployer as initial owner
        address contractAddr = deployer.create3("ExampleContract").deploy(
            abi.encode(deployer.account, "Initial Contract")
        );

        console.log("Contract deployed at:", contractAddr);
        console.log("Initial owner:", deployer.account);

        // Phase 2: Transfer ownership to Safe
        console.log("\n=== Phase 2: Transferring Ownership to Safe ===");

        // Get harness for the deployed contract and transfer ownership to Safe
        // This can be just an interface as well.
        ExampleContract example = ExampleContract(
            deployer.harness(contractAddr)
        );
        example.transferOwnership(safe.account);

        console.log("Ownership transferred to Safe:", safe.account);

        // Phase 3: Execute owner-only operations through Safe
        console.log("\n=== Phase 3: Executing Safe Transactions ===");

        // Use Safe harness to execute owner-only functions
        // These calls will be batched and proposed to the Safe multisig
        ExampleContract safeExample = ExampleContract(
            safe.harness(contractAddr)
        );

        // Set new name through Safe
        safeExample.setName("Safe-Managed Contract");

        // Set value through Safe
        safeExample.setValue(42);

        console.log("Safe transactions queued:");
        console.log("- setName('Safe-Managed Contract')");
        console.log("- setValue(42)");

        // All Safe transactions will be automatically batched and proposed
        // when the broadcast modifier completes
    }

    /**
     * @notice Demonstrate conditional deployment logic
     * @dev Shows how to check for existing deployments and handle upgrades
     */
    function conditionalDeploy() public {
        console.log("=== Conditional Deployment ===");

        // Check if contract already exists
        address existing = lookup("ExampleContract");

        if (existing == address(0)) {
            console.log("Contract not found, deploying new instance...");
            run();
        } else {
            console.log("Contract already deployed at:", existing);
            console.log("Skipping deployment, executing configuration only...");

            // Just execute configuration through Safe
            Senders.Sender storage safe = sender("safe");
            ExampleContract example = ExampleContract(safe.harness(existing));
            example.setValue(100); // Update to new value
        }
    }
}

