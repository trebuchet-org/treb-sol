// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import "../src/internal/sender/Senders.sol";
import {Deployer} from "../src/internal/sender/Deployer.sol";
import {SenderTypes, Transaction} from "../src/internal/types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

contract SimpleContract {
    uint256 public value;
    
    constructor(uint256 _value) {
        value = _value;
    }
}

contract DeployerIntegrationTest is Test, CreateXScript {
    SendersTestHarness harness;
    
    string constant DEPLOYER = "deployer";
    
    function setUp() public withCreateX {
        // Setup deployer sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: DEPLOYER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        harness = new SendersTestHarness(configs);
    }
    
    function test_DeployCreate3WithEntropy() public {
        string memory entropy = "test-entrop-123123y";
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(42);
        
        // Predict address
        address predicted = harness.predictCreate3(DEPLOYER, entropy);
        
        // Deploy using entropy pattern
        address deployed = harness.deployCreate3WithEntropy(DEPLOYER, entropy, bytecode, constructorArgs);
        
        // Verify prediction matches deployment
        assertEq(deployed, predicted);
        
        // Broadcast
        harness.broadcastSender(DEPLOYER);
        
        // Verify contract was deployed with correct state
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 42);
    }
    
    function test_DeployCreate3WithArtifactPath() public {
        // Deploy using artifact pattern with proper artifact path
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        address deployed = harness.deployCreate3(DEPLOYER, artifact, abi.encode(100));
        
        // Broadcast
        harness.broadcastSender(DEPLOYER);
        
        // Verify
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 100);
    }
    
    function test_DeployCreate3WithLabel() public {
        // Deploy using artifact + label pattern
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        string memory label = "v2";
        address deployed = harness.deployCreate3(DEPLOYER, artifact, label, abi.encode(200));
        
        // Broadcast
        harness.broadcastSender(DEPLOYER);
        
        // Verify deployment
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 200);
    }
    
    function test_DeployWithNamespace() public {
        // Set namespace to production
        harness.setNamespace("production");
        
        // Deploy with factory pattern
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        string memory label = "v1";
        address deployed1 = harness.deployCreate3(DEPLOYER, artifact, label, abi.encode(300));
        
        // Change namespace to staging
        harness.setNamespace("staging");
        // Same artifact and label, different namespace
        address deployed2 = harness.deployCreate3(DEPLOYER, artifact, label, abi.encode(400));
        
        // Different namespaces should result in different addresses
        assertTrue(deployed1 != deployed2);
    }
    
    function test_DeploymentEvents() public {
        string memory artifact = "DeployerIntegration.t.sol:SimpleContract";
        string memory label = "test";
        string memory expectedEntropy = "DeployerIntegration.t.sol:SimpleContract:test";
        bytes memory constructorArgs = abi.encode(500);
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        // Get values for event expectation
        address senderAddr = harness.get(DEPLOYER).account;
        address predictedAddr = harness.predictCreate3(DEPLOYER, expectedEntropy);
        bytes32 bundleId = harness.get(DEPLOYER).bundleId;
        bytes32 salt = harness._salt(DEPLOYER, expectedEntropy);
        
        // Expect ContractDeployed event with new struct format
        Deployer.EventDeployment memory expectedDeployment = Deployer.EventDeployment({
            artifact: artifact,
            label: label,
            entropy: expectedEntropy,
            salt: salt,
            bytecodeHash: keccak256(bytecode),
            initCodeHash: keccak256(initCode),
            constructorArgs: constructorArgs,
            createStrategy: "CREATE3"
        });
        
        vm.expectEmit();
        emit Deployer.ContractDeployed(
            senderAddr,
            predictedAddr,
            bundleId,
            expectedDeployment
        );
        
        harness.deployCreate3(DEPLOYER, artifact, label, constructorArgs);
    }
    
    function test_SaltGeneration() public {
        // Set namespace to test-env
        harness.setNamespace("test-env");
        bytes32 salt1 = harness._salt(DEPLOYER, "MyContract");
        
        // Change namespace to prod-env
        harness.setNamespace("prod-env");
        bytes32 salt2 = harness._salt(DEPLOYER, "MyContract");
        
        // Different namespaces should produce different salts
        assertTrue(salt1 != salt2);
        
        // Same namespace and entropy should produce same salt
        bytes32 salt3 = harness._salt(DEPLOYER, "MyContract");
        assertEq(salt2, salt3);
    }
}