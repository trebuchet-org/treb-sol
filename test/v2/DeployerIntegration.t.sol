// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {Senders} from "../../src/v2/internal/sender/Senders.sol";
import {Deployer} from "../../src/v2/internal/sender/Deployer.sol";
import {SenderTypes, Transaction} from "../../src/internal/types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

contract SimpleContract {
    uint256 public value;

    constructor(uint256 _value) {
        value = _value;
    }
}

contract V2DeployerIntegrationTest is Test, CreateXScript {
    SendersTestHarness harness;

    string constant DEPLOYER = "deployer";

    function setUp() public withCreateX {
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: DEPLOYER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(privateKey)
        });

        harness = new SendersTestHarness(configs);
    }

    function test_DeployCreate3WithEntropy() public {
        string memory entropy = "test-entropy-123";
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(42);

        address predicted = harness.predictCreate3WithEntropy(DEPLOYER, entropy, bytecode, constructorArgs);
        address deployed = harness.deployCreate3WithEntropy(DEPLOYER, entropy, bytecode, constructorArgs);

        assertEq(deployed, predicted);
        assertEq(SimpleContract(deployed).value(), 42);
    }

    function test_DeployCreate3WithArtifactPath() public {
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        address deployed = harness.deployCreate3WithArtifact(DEPLOYER, artifact, abi.encode(100));

        assertEq(SimpleContract(deployed).value(), 100);
    }

    function test_DeployCreate3WithLabel() public {
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        string memory label = "v2";
        address deployed = harness.deployCreate3WithArtifactAndLabel(DEPLOYER, artifact, label, abi.encode(200));

        assertEq(SimpleContract(deployed).value(), 200);
    }

    function test_DeployWithNamespace() public {
        harness.setNamespace("production");
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        address deployed1 = harness.deployCreate3WithArtifactAndLabel(DEPLOYER, artifact, "v1", abi.encode(300));

        harness.setNamespace("staging");
        address deployed2 = harness.deployCreate3WithArtifactAndLabel(DEPLOYER, artifact, "v1", abi.encode(400));

        assertTrue(deployed1 != deployed2);
    }

    function test_DeploymentEvents() public {
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        // Just verify the deployment works and events are emitted without reverts
        harness.deployCreate3WithArtifactAndLabel(DEPLOYER, artifact, "test", abi.encode(500));
    }

    function test_SaltGeneration() public {
        harness.setNamespace("test-env");
        bytes32 salt1 = harness._salt(DEPLOYER, "MyContract");

        harness.setNamespace("prod-env");
        bytes32 salt2 = harness._salt(DEPLOYER, "MyContract");

        // Same entropy → same salt regardless of namespace
        assertEq(salt1, salt2);

        // Different entropy → different salt
        bytes32 salt3 = harness._salt(DEPLOYER, "DifferentContract");
        assertTrue(salt1 != salt3);
    }

    function test_DeployCreate2WithArtifactPath() public {
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        bytes memory args = abi.encode(999);

        address predicted = harness.predictCreate2WithArtifact(DEPLOYER, artifact, args);
        address deployed = harness.deployCreate2WithArtifact(DEPLOYER, artifact, args);

        assertEq(deployed, predicted);
        assertEq(SimpleContract(deployed).value(), 999);
    }
}
