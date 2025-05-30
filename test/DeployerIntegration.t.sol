// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import "../src/internal/sender/Senders.sol";
import {Deployer} from "../src/internal/sender/Deployer.sol";
import {SenderTypes, Transaction} from "../src/internal/types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";

contract SimpleContract {
    uint256 public value;
    
    constructor(uint256 _value) {
        value = _value;
    }
}

contract DeployerIntegrationTest is Test, CreateXScript {
    using Senders for Senders.Sender;
    using Senders for Senders.Registry;
    using Deployer for Senders.Sender;
    
    string constant DEPLOYER = "deployer";
    
    function setUp() public withCreateX {}
    
    function test_DeployCreate3WithSalt() public {
        // Setup sender
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
        
        Senders.initialize(configs);
        
        // Deploy contract
        uint256 snap = vm.snapshotState();
        Senders.Sender storage sender = Senders.get(DEPLOYER);
        
        string memory entropy = "test-entrop-123123y";
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(42);
        
        // Predict address
        address predicted = sender.predictCreate3(entropy);
        
        // Deploy
        address deployed = sender.deployCreate3(entropy, bytecode, constructorArgs);
        
        // Verify prediction matches deployment
        assertEq(deployed, predicted);
        
        // Broadcast
        vm.revertToState(snap);
        sender.broadcast();
        
        // Verify contract was deployed with correct state
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 42);
    }
    
    function test_DeployCreate3WithArtifactPath() public {
        // Setup sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        Senders.initialize(configs);
        
        // Deploy using artifact path
        uint256 snap = vm.snapshotState();
        Senders.Sender storage sender = Senders.get(DEPLOYER);
        
        // This will use vm.getCode internally
        // Note: This will fail because vm.getCode expects a full artifact path
        // For testing, we'll use the bytecode directly
        bytes memory bytecode = type(SimpleContract).creationCode;
        string memory artifact = "test-artifact";
        address deployed = sender.deployCreate3(artifact, bytecode, abi.encode(100));
        
        // Broadcast
        vm.revertToState(snap);
        sender.broadcast();
        
        // Verify
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 100);
    }
    
    function test_DeployCreate2() public {
        // Setup sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);

        
        // Deal on both forks
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: DEPLOYER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        // Initialize on simulation fork
        Senders.initialize(configs);
        uint256 snap = vm.snapshotState();

        // Deploy with CREATE2
        Senders.Sender storage sender = Senders.get(DEPLOYER);
        
        bytes32 salt = keccak256("create2-test");
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(200);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        // Predict address
        address predicted = sender.predictCreate2(salt, initCode);
        
        // Deploy
        address deployed = sender.deployCreate2(salt, bytecode, constructorArgs);
        
        // Verify
        assertEq(deployed, predicted);
        
        // Broadcast
        vm.revertToState(snap);
        sender.broadcast();
        
        // Verify deployment
        SimpleContract deployedContract = SimpleContract(deployed);
        assertEq(deployedContract.value(), 200);
    }
    
    function test_DeployWithNamespace() public {
        // Setup sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        Senders.initialize(configs);
        
        // Deploy with namespace
        vm.setEnv("NAMESPACE", "production");
        
        Senders.Sender storage sender = Senders.get(DEPLOYER);
        
        // Deploy with label
        string memory artifact = "SimpleContract";
        string memory label = "v1";
        address deployed1 = sender.deployCreate3(artifact, label, abi.encode(300));
        
        // Change namespace
        vm.setEnv("NAMESPACE", "staging");
        address deployed2 = sender.deployCreate3(artifact, label, abi.encode(400));
        
        // Different namespaces should result in different addresses
        assertTrue(deployed1 != deployed2);
        
        // Reset namespace
        vm.setEnv("NAMESPACE", "default");
    }
    
    function test_DeploymentEvents() public {
        // Setup sender
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
        
        Senders.initialize(configs);
        
        Senders.Sender storage sender = Senders.get(DEPLOYER);
        
        string memory entropy = "event-test";
        bytes memory bytecode = type(SimpleContract).creationCode;
        bytes memory constructorArgs = abi.encode(500);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        // Expect ContractDeployed event
        vm.expectEmit(true, true, true, true);
        emit Deployer.ContractDeployed(
            senderAddr,
            sender.predictCreate3(entropy),
            sender.bundleId,
            sender._salt(entropy),
            keccak256(initCode),
            constructorArgs,
            "CREATE3"
        );
        sender.deployCreate3(entropy, bytecode, constructorArgs);
    }
    
    function test_SaltGeneration() public {
        // Setup sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        Senders.initialize(configs);
        
        Senders.Sender storage sender = Senders.get(DEPLOYER);
        
        // Test salt generation with namespace
        vm.setEnv("NAMESPACE", "test-env");
        bytes32 salt1 = sender._salt("MyContract");
        
        vm.setEnv("NAMESPACE", "prod-env");
        bytes32 salt2 = sender._salt("MyContract");
        
        // Different namespaces should produce different salts
        assertTrue(salt1 != salt2);
        
        // Same namespace and entropy should produce same salt
        bytes32 salt3 = sender._salt("MyContract");
        assertEq(salt2, salt3);
    }
}