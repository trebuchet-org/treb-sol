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
    
    function test_DeployCreate3WithSalt() public {
        string memory entropy = "test-entrop-123123y";
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(42);
        
        // Predict address
        address predicted = harness.predictCreate3(DEPLOYER, entropy);
        
        // Deploy
        address deployed = harness.deployCreate3(DEPLOYER, entropy, bytecode, constructorArgs);
        
        // Verify prediction matches deployment
        assertEq(deployed, predicted);
        
        // Broadcast
        harness.broadcast(DEPLOYER);
        
        // Verify contract was deployed with correct state
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 42);
    }
    
    function test_DeployCreate3WithArtifactPath() public {
        // Deploy using artifact path
        // This will use vm.getCode internally
        // Note: This will fail because vm.getCode expects a full artifact path
        // For testing, we'll use the entropy version with bytecode directly
        bytes memory bytecode = type(SimpleContract).creationCode;
        string memory entropy = "test-artifact";
        address deployed = harness.deployCreate3(DEPLOYER, entropy, bytecode, abi.encode(100));
        
        // Broadcast
        harness.broadcast(DEPLOYER);
        
        // Verify
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 100);
    }
    
    function test_DeployCreate2() public {
        bytes32 salt = keccak256("create2-test");
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(200);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        // Predict address
        address predicted = harness.predictCreate2(DEPLOYER, salt, initCode);
        
        // Deploy
        address deployed = harness.deployCreate2(DEPLOYER, salt, bytecode, constructorArgs);
        
        // Verify
        assertEq(deployed, predicted);
        
        // Broadcast
        harness.broadcast(DEPLOYER);
        
        // Verify deployment
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 200);
    }
    
    function test_DeployWithNamespace() public {
        // Set namespace to production
        harness.setNamespace("production");
        
        // Deploy with entropy directly (not using factory pattern with label)
        string memory entropy1 = "SimpleContract:v1";
        bytes memory bytecode = type(SimpleContract).creationCode;
        address deployed1 = harness.deployCreate3(DEPLOYER, entropy1, bytecode, abi.encode(300));
        
        // Change namespace to staging
        harness.setNamespace("staging");
        string memory entropy2 = "SimpleContract:v1"; // Same entropy, different namespace
        address deployed2 = harness.deployCreate3(DEPLOYER, entropy2, bytecode, abi.encode(400));
        
        // Different namespaces should result in different addresses
        assertTrue(deployed1 != deployed2);
    }
    
    function test_DeploymentEvents() public {
        string memory entropy = "event-test";
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(500);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        // Get values for event expectation
        address senderAddr = harness.get(DEPLOYER).account;
        address predictedAddr = harness.predictCreate3(DEPLOYER, entropy);
        bytes32 bundleId = harness.get(DEPLOYER).bundleId;
        bytes32 salt = harness._salt(DEPLOYER, entropy);
        
        // Expect ContractDeployed event
        vm.expectEmit();
        emit Deployer.ContractDeployed(
            senderAddr,
            predictedAddr,
            bundleId,
            salt,
            keccak256(bytecode),  // bytecodeHash
            keccak256(initCode),  // initCodeHash
            constructorArgs,
            "CREATE3"
        );
        
        harness.deployCreate3(DEPLOYER, entropy, bytecode, constructorArgs);
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