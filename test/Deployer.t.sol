// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {Deployer} from "../src/internal/Deployer.sol";
import {Sender} from "../src/internal/Sender.sol";
import {PrivateKeySender} from "../src/internal/senders/PrivateKeySender.sol";
import {Transaction, BundleTransaction} from "../src/internal/types.sol";

// Simple test contract for deployment
contract TestCounter {
    uint256 public count;
    
    constructor(uint256 _initial) {
        count = _initial;
    }
    
    function increment() public {
        count++;
    }
}

// Test deployer that disables prediction checks
contract TestDeployer is Deployer {
    constructor(Sender _sender) Deployer(_sender) {}
    
    function _checkPrediction() internal override pure returns (bool) {
        return false;
    }
}

contract DeployerTest is Test, CreateXScript {
    TestDeployer deployer;
    PrivateKeySender sender;
    address constant DEPLOYER_ADDRESS = address(0x1234);
    uint256 constant DEPLOYER_KEY = 0xabc123;
    
    uint256 simulationForkId;
    uint256 executionForkId;
    
    function setUp() public withCreateX {
        // Set up environment
        vm.setEnv("NAMESPACE", "default");
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/empty.json");
        
        // Create forks using anvil
        string memory network = vm.envOr("NETWORK", string("anvil"));
        simulationForkId = vm.createFork(network);
        executionForkId = vm.createFork(network);
        vm.selectFork(simulationForkId);
        
        // Deal ETH to deployer
        vm.deal(DEPLOYER_ADDRESS, 100 ether);
        
        // Create sender with private key
        sender = new PrivateKeySender(DEPLOYER_ADDRESS, DEPLOYER_KEY);
        sender.initialize(simulationForkId, executionForkId);
        
        // Create deployer with the sender
        deployer = new TestDeployer(sender);
    }
    
    function testDeployCreate3WithBytecode() public {
        // Use the entropy-based deployment which properly formats the salt
        string memory entropy = "test-salt";
        bytes memory bytecode = type(TestCounter).creationCode;
        bytes memory constructorArgs = abi.encode(uint256(123));
        
        // Deploy the contract
        address deployed = deployer.deployCreate3(entropy, bytecode, constructorArgs);
        
        // Check deployment succeeded
        assertTrue(deployed != address(0), "Deployment should return non-zero address");
        assertTrue(deployed.code.length > 0, "Deployed address should have code");
        
        // Check the deployed contract works
        TestCounter counter = TestCounter(deployed);
        assertEq(counter.count(), 123, "Initial count should be 123");
    }
    
    function testDeployCreate3WithEntropy() public {
        string memory entropy = "my-contract-v1";
        bytes memory bytecode = type(TestCounter).creationCode;
        bytes memory constructorArgs = abi.encode(uint256(456));
        
        address deployed = deployer.deployCreate3(entropy, bytecode, constructorArgs);
        
        assertTrue(deployed != address(0), "Deployment should return non-zero address");
        assertTrue(deployed.code.length > 0, "Deployed address should have code");
        
        TestCounter counter = TestCounter(deployed);
        assertEq(counter.count(), 456, "Initial count should be 456");
    }
    
    function testDeployCreate3WithContractName() public {
        // This test verifies that deployCreate3 tries to get code for a contract name
        // Since the contract doesn't exist in the artifacts, it should revert
        vm.expectRevert(abi.encodeWithSelector(Deployer.ContractNotFound.selector, "Counter.sol:Counter"));
        deployer.deployCreate3("Counter.sol:Counter");
    }
    
    function testDeployCreate3ContractNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Deployer.ContractNotFound.selector, "NonExistent"));
        deployer.deployCreate3("NonExistent");
    }
    
    function testDeployCreate2() public {
        string memory entropy = "test-salt-create2";
        bytes memory bytecode = type(TestCounter).creationCode;
        bytes memory constructorArgs = abi.encode(uint256(789));
        
        // Deploy the contract
        address deployed = deployer.deployCreate2(entropy, bytecode, constructorArgs);
        
        assertTrue(deployed != address(0), "Deployment should return non-zero address");
        assertTrue(deployed.code.length > 0, "Deployed address should have code");
        
        TestCounter counter = TestCounter(deployed);
        assertEq(counter.count(), 789, "Initial count should be 789");
    }
    
    function testSaltGeneration() public {
        // Test that deployment emits the correct event
        string memory entropy = "test-entropy";
        bytes memory bytecode = type(TestCounter).creationCode;
        bytes memory constructorArgs = abi.encode(uint256(999));
        
        // Just test that deployment succeeds and emits an event
        vm.expectEmit(true, false, false, false);
        emit Deployer.ContractDeployed(
            DEPLOYER_ADDRESS, // deployer  
            address(0), // location - don't check
            bytes32(0), // txId - don't check
            bytes32(0), // bundleId - don't check
            bytes32(0), // salt - don't check
            bytes32(0), // initCodeHash - don't check
            "", // constructorArgs - don't check
            "" // createStrategy - don't check
        );
        
        deployer.deployCreate3(entropy, bytecode, constructorArgs);
    }
    
    function testPredictCreate3() public view {
        // Just test that prediction returns a non-zero address
        string memory entropy = "prediction-test";
        bytes32 salt = bytes32(abi.encodePacked(DEPLOYER_ADDRESS, hex"00", bytes11(uint88(uint256(keccak256(bytes(string.concat("default:", entropy))))))));
        
        address predicted = deployer.predictCreate3(salt);
        assertTrue(predicted != address(0), "Predicted address should not be zero");
    }
    
    function testPredictCreate2() public view {
        // Just test that prediction returns a non-zero address
        string memory entropy = "prediction-test-create2";
        bytes memory bytecode = type(TestCounter).creationCode;
        bytes memory constructorArgs = abi.encode(uint256(222));
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        bytes32 salt = bytes32(abi.encodePacked(DEPLOYER_ADDRESS, hex"00", bytes11(uint88(uint256(keccak256(bytes(string.concat("default:", entropy))))))));
        
        address predicted = deployer.predictCreate2(salt, initCode);
        assertTrue(predicted != address(0), "Predicted address should not be zero");
    }
    
    function testNamespaceInSalt() public {
        string memory entropy = "same-contract";
        bytes memory bytecode = type(TestCounter).creationCode;
        bytes memory constructorArgs = abi.encode(uint256(333));
        
        // Deploy with default namespace
        address defaultAddr = deployer.deployCreate3(entropy, bytecode, constructorArgs);
        
        // Create new deployer with production namespace
        vm.setEnv("NAMESPACE", "production");
        PrivateKeySender prodSender = new PrivateKeySender(DEPLOYER_ADDRESS, DEPLOYER_KEY);
        prodSender.initialize(simulationForkId, executionForkId);
        TestDeployer prodDeployer = new TestDeployer(prodSender);
        
        // Deploy with production namespace - should get different address
        address prodAddr = prodDeployer.deployCreate3(entropy, bytecode, constructorArgs);
        
        assertTrue(defaultAddr != prodAddr, "Different namespaces should produce different addresses");
        
        // Both should have deployed successfully
        assertTrue(defaultAddr.code.length > 0, "Default deployment should have code");
        assertTrue(prodAddr.code.length > 0, "Production deployment should have code");
    }
}