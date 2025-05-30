// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {SenderTypes} from "../src/internal/types.sol";

contract TestableDispatcher is Dispatcher {
    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun) 
        Dispatcher(_rawConfigs, _namespace, _dryrun) {}
    
    // Expose internal functions for testing
    function testGetSender(string memory name) external returns (Senders.Sender memory) {
        return sender(name);
    }
    
    function testBroadcast() external broadcast {
        // Empty function to test modifier
    }
}

contract DispatcherIntegrationTest is Test {
    TestableDispatcher dispatcher;
    
    // Constants for sender names
    string constant SENDER1 = "sender1";
    string constant SENDER2 = "sender2";
    string constant TEST_SENDER = "test";
    string constant LAZY_SENDER = "lazy";
    string constant DISPATCHER_TEST = "dispatcher-test";
    
    function setUp() public {
        // Set required environment variables
        vm.setEnv("NETWORK", "http://localhost:8545");
    }
    
    function tearDown() public {
        // Clean up environment variables
        vm.setEnv("SENDER_CONFIGS", "");
        vm.setEnv("DRYRUN", "");
        vm.setEnv("NAMESPACE", "");
    }
    
    function test_DispatcherInitialization() public {
        // Create sender configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);
        configs[0] = Senders.SenderInitConfig({
            name: SENDER1,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x1111)
        });
        configs[1] = Senders.SenderInitConfig({
            name: SENDER2,
            account: vm.addr(0x2222),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x2222)
        });
        
        // Create dispatcher with configs
        bytes memory encodedConfigs = abi.encode(configs);
        dispatcher = new TestableDispatcher(encodedConfigs, "default", false);
        
        // Access sender (should trigger lazy initialization)
        Senders.Sender memory sender1 = dispatcher.testGetSender(SENDER1);
        assertEq(sender1.name, SENDER1);
        assertEq(sender1.account, vm.addr(0x1111));
        
        Senders.Sender memory sender2 = dispatcher.testGetSender(SENDER2);
        assertEq(sender2.name, SENDER2);
        assertEq(sender2.account, vm.addr(0x2222));
    }
    
    function test_DispatcherMissingSenderConfigs() public {
        // Create dispatcher with empty configs
        bytes memory emptyConfigs = "";
        dispatcher = new TestableDispatcher(emptyConfigs, "default", false);
        
        // Should revert when trying to access sender
        vm.expectRevert(Dispatcher.InvalidSenderConfigs.selector);
        dispatcher.testGetSender("any");
    }
    
    function test_DispatcherInvalidSenderConfigs() public {
        // Create dispatcher with invalid configs (can't decode as SenderInitConfig[])
        bytes memory invalidConfigs = hex"deadbeef";
        dispatcher = new TestableDispatcher(invalidConfigs, "default", false);
        
        // Should revert when trying to decode
        vm.expectRevert();
        dispatcher.testGetSender("any");
    }
    
    
    function test_DispatcherBroadcastModifier() public {
        // Setup
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x1111)
        });
        
        bytes memory encodedConfigs = abi.encode(configs);
        
        // Test broadcast with dryrun=false
        dispatcher = new TestableDispatcher(encodedConfigs, "default", false);
        dispatcher.testBroadcast();
        
        // Test with dryrun=true
        dispatcher = new TestableDispatcher(encodedConfigs, "default", true);
        dispatcher.testBroadcast();
    }
    
    function test_DispatcherLazyLoading() public {
        // Setup configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: LAZY_SENDER,
            account: vm.addr(0x3333),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x3333)
        });
        
        bytes memory encodedConfigs = abi.encode(configs);
        
        // Create dispatcher
        dispatcher = new TestableDispatcher(encodedConfigs, "default", false);
        
        // Registry should not be initialized yet
        // First access should initialize
        Senders.Sender memory lazySender = dispatcher.testGetSender(LAZY_SENDER);
        assertEq(lazySender.name, LAZY_SENDER);
        
        // Second access should return same sender without re-initializing
        Senders.Sender memory lazySender2 = dispatcher.testGetSender(LAZY_SENDER);
        assertEq(lazySender2.name, LAZY_SENDER);
        assertEq(lazySender2.account, vm.addr(0x3333));
        assertEq(lazySender.id, lazySender2.id);
    }
}