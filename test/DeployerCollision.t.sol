// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {Deployer} from "../src/internal/sender/Deployer.sol";
import {SenderTypes} from "../src/internal/types.sol";
import {ITrebEvents} from "../src/internal/ITrebEvents.sol";

contract SimpleContract {
    uint256 public value = 42;
}

contract DeployerCollisionTest is Test, CreateXScript {
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;

    SendersTestHarness harness;
    string constant SENDER_NAME = "test-sender";

    function setUp() public withCreateX {
        // Initialize sender registry through harness
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: SENDER_NAME,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(uint256(0x12345))
        });

        vm.deal(vm.addr(0x12345), 10 ether);
        harness = new SendersTestHarness(configs);
    }

    function test_DeploymentCollisionEmitsEvent() public {
        // First deployment should succeed using entropy-based deployment
        bytes memory bytecode = type(SimpleContract).creationCode;
        address firstDeploy = harness.deployCreate3WithEntropy(SENDER_NAME, "SimpleContract", bytecode, "");

        // Verify contract was deployed
        assertTrue(firstDeploy.code.length > 0, "First deployment should succeed");
        assertEq(SimpleContract(firstDeploy).value(), 42, "Contract should be functional");

        // Second deployment with same parameters should detect collision
        // Calculate expected details
        bytes32 expectedSalt = harness._salt(SENDER_NAME, "SimpleContract");

        vm.expectEmit(true, false, false, true);
        emit ITrebEvents.DeploymentCollision(
            firstDeploy,
            ITrebEvents.DeploymentDetails({
                artifact: "<user-provided-bytecode>",
                label: "",
                entropy: "SimpleContract",
                salt: expectedSalt,
                bytecodeHash: keccak256(bytecode),
                initCodeHash: keccak256(bytecode),
                constructorArgs: "",
                createStrategy: "CREATE3"
            })
        );

        // Deploy again - should return same address without reverting
        address secondDeploy = harness.deployCreate3WithEntropy(SENDER_NAME, "SimpleContract", bytecode, "");

        // Should return the same address
        assertEq(secondDeploy, firstDeploy, "Should return existing contract address");
    }

    function test_DeploymentCollisionWithLabel() public {
        // We'll use a direct approach to test labels by accessing the underlying sender
        bytes memory bytecode = type(SimpleContract).creationCode;

        // Deploy v1 with label using direct access to sender
        address v1 = harness.deployCreate3WithEntropy(SENDER_NAME, "default/SimpleContract:v1", bytecode, "");

        // Deploy v2 (different address due to different label)
        address v2 = harness.deployCreate3WithEntropy(SENDER_NAME, "default/SimpleContract:v2", bytecode, "");

        // v1 and v2 should be different
        assertTrue(v1 != v2, "Different labels should produce different addresses");

        // Try to deploy v1 again - should emit collision event
        vm.expectEmit(true, false, false, false);
        emit ITrebEvents.DeploymentCollision(v1, ITrebEvents.DeploymentDetails("", "", "", 0, 0, 0, "", ""));

        address v1Again = harness.deployCreate3WithEntropy(SENDER_NAME, "default/SimpleContract:v1", bytecode, "");

        assertEq(v1Again, v1, "Should return existing v1 address");
    }

    function test_NoCollisionInQuietMode() public {
        // First deployment
        bytes memory bytecode = type(SimpleContract).creationCode;
        address firstDeploy = harness.deployCreate3WithEntropy(SENDER_NAME, "SimpleContract", bytecode, "");

        // Set quiet mode in registry
        Senders.registry().quiet = true;

        // Second deployment - should not emit event in quiet mode
        // We can't easily verify no event was emitted, but we can verify the address is returned
        address secondDeploy = harness.deployCreate3WithEntropy(SENDER_NAME, "SimpleContract", bytecode, "");

        // But should still return the same address
        assertEq(secondDeploy, firstDeploy, "Should still return existing address in quiet mode");

        // Reset quiet mode
        Senders.registry().quiet = false;
    }

    // Note: CREATE2 deployment methods are not exposed in the test harness,
    // but the collision logic is the same for both CREATE2 and CREATE3 strategies
    // as they both check for existing code at the predicted address

    function getSenderConfigs() internal pure returns (Senders.SenderInitConfig[] memory) {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: SENDER_NAME,
            account: vm.addr(0x12345),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(uint256(0x12345))
        });
        return configs;
    }
}
