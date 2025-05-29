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
        // Create a new test environment without SENDER_CONFIGS
        // Use invalid env var name to ensure it's not set
        vm.setEnv("SENDER_CONFIGS", "INVALID");
        
        // This should revert because INVALID is not valid hex
        vm.expectRevert();
        new Dispatcher();
    }
    
    function testDispatcherEmptyConfigs() public {
        // Create empty configs
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        Dispatcher dispatcher = new Dispatcher();
        
        // Should deploy successfully but have no senders
        vm.expectRevert(abi.encodeWithSelector(Dispatcher.SenderNotFound.selector, "anything"));
        dispatcher.sender("anything");
    }
    
    function testSenderLookupById() public {
        // Create empty configs for constructor
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        MockDispatcher dispatcher = new MockDispatcher();
        
        // Generate address/key pairs
        (address devAddr, uint256 devKey) = makeAddrAndKey("dev");
        (address stagingAddr, uint256 stagingKey) = makeAddrAndKey("staging");
        (address prodAddr, uint256 prodKey) = makeAddrAndKey("production");
        
        // Create and add senders
        PrivateKeySender devSender = new PrivateKeySender(devAddr, devKey);
        PrivateKeySender stagingSender = new PrivateKeySender(stagingAddr, stagingKey);
        PrivateKeySender prodSender = new PrivateKeySender(prodAddr, prodKey);
        
        dispatcher.addSender("dev", devSender);
        dispatcher.addSender("staging", stagingSender);
        dispatcher.addSender("production", prodSender);
        
        // Test correct sender is returned for each ID
        assertEq(dispatcher.sender("dev").senderAddress(), devAddr);
        assertEq(dispatcher.sender("staging").senderAddress(), stagingAddr);
        assertEq(dispatcher.sender("production").senderAddress(), prodAddr);
    }
    
    function testSenderNotFound() public {
        // Create empty configs
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        MockDispatcher dispatcher = new MockDispatcher();
        
        (address addr, uint256 key) = makeAddrAndKey("only-sender");
        PrivateKeySender onlySender = new PrivateKeySender(addr, key);
        dispatcher.addSender("only-sender", onlySender);
        
        // Try to get a non-existent sender
        vm.expectRevert(abi.encodeWithSelector(Dispatcher.SenderNotFound.selector, "does-not-exist"));
        dispatcher.sender("does-not-exist");
    }
    
    function testHashCollision() public pure {
        // Test that different IDs produce different hashes
        bytes32 hash1 = keccak256(abi.encodePacked("sender1"));
        bytes32 hash2 = keccak256(abi.encodePacked("sender2"));
        assertTrue(hash1 != hash2);
    }
}