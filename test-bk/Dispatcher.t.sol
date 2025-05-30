// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Sender} from "../src/internal/Sender.sol";
import {PrivateKeySender} from "../src/internal/senders/PrivateKeySender.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";

// Mock Dispatcher that bypasses vm.deployCode
contract MockDispatcher is Dispatcher {
    function addSender(string memory id, Sender sender) external {
        senders[keccak256(abi.encodePacked(id))] = sender;
    }
}

contract DispatcherTest is Test {
    function setUp() public {
        // Set test environment
        vm.setEnv("NAMESPACE", "default");
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/empty.json");
        vm.setEnv("NETWORK", "anvil");
    }
    
    function testDispatcherWithMockSenders() public {
        // Create sender configs for the real Dispatcher constructor
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Deploy mock dispatcher
        MockDispatcher dispatcher = new MockDispatcher();
        
        // Generate address/key pairs
        (address addr1, uint256 key1) = makeAddrAndKey("private1");
        (address addr2, uint256 key2) = makeAddrAndKey("private2");
        
        // Create and add senders directly
        PrivateKeySender sender1 = new PrivateKeySender(addr1, key1);
        PrivateKeySender sender2 = new PrivateKeySender(addr2, key2);
        
        dispatcher.addSender("private1", sender1);
        dispatcher.addSender("private2", sender2);
        
        // Verify senders are available
        Sender retrievedSender1 = dispatcher.sender("private1");
        Sender retrievedSender2 = dispatcher.sender("private2");
        
        assertTrue(address(retrievedSender1) != address(0));
        assertTrue(address(retrievedSender2) != address(0));
        assertEq(retrievedSender1.senderAddress(), addr1);
        assertEq(retrievedSender2.senderAddress(), addr2);
    }
    
    function testDispatcherMissingSenderConfigs() public {
        // Clear the SENDER_CONFIGS env var
        vm.setEnv("SENDER_CONFIGS", "");
        
        // Create dispatcher - should not revert on construction anymore (lazy loading)
        Dispatcher dispatcher = new Dispatcher();
        
        // Should revert when trying to access a sender (lazy loading)
        vm.expectRevert(abi.encodeWithSelector(Dispatcher.MissingSenderConfigs.selector));
        dispatcher.sender("any");
    }
    
    function testDispatcherEmptyConfigs() public {
        // Create empty sender configs
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Deploy dispatcher
        Dispatcher dispatcher = new Dispatcher();
        
        // Should revert when trying to access a non-existent sender
        vm.expectRevert(abi.encodeWithSelector(Dispatcher.SenderNotFound.selector, "nonexistent"));
        dispatcher.sender("nonexistent");
    }
    
    function testSenderLookupById() public {
        // Create sender configs with a PrivateKeySender
        (address addr1, uint256 key1) = makeAddrAndKey("testsender");
        
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "testsender";
        configs.artifacts[0] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[0] = abi.encode(addr1, key1);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Deploy dispatcher
        Dispatcher dispatcher = new Dispatcher();
        
        // Verify sender can be retrieved
        Sender retrievedSender = dispatcher.sender("testsender");
        assertTrue(address(retrievedSender) != address(0));
        assertEq(retrievedSender.senderAddress(), addr1);
    }
    
    function testSenderNotFound() public {
        // Create sender configs with one sender
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "existing";
        configs.artifacts[0] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[0] = abi.encode(address(0x1), uint256(0x1));
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Deploy dispatcher
        Dispatcher dispatcher = new Dispatcher();
        
        // Should revert when accessing non-existent sender
        vm.expectRevert(abi.encodeWithSelector(Dispatcher.SenderNotFound.selector, "nonexistent"));
        dispatcher.sender("nonexistent");
    }
    
    function testHashCollision() public pure {
        // Test that different IDs produce different hashes
        bytes32 hash1 = keccak256(abi.encodePacked("sender1"));
        bytes32 hash2 = keccak256(abi.encodePacked("sender2"));
        assertTrue(hash1 != hash2);
    }
}