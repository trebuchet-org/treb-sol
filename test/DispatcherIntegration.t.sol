// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {SenderTypes} from "../src/internal/types.sol";

contract TestDispatcher is Dispatcher {
    // Expose internal functions for testing
    function testGetSender(string memory name) external returns (Senders.Sender memory) {
        return sender(name);
    }
    
    function testBroadcast() external broadcast {
        // Empty function to test modifier
    }
}

contract DispatcherIntegrationTest is Test {
    TestDispatcher dispatcher;
    
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
        
        // Set configs in environment
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Create dispatcher
        dispatcher = new TestDispatcher();
        
        // Access sender (should trigger lazy initialization)
        Senders.Sender memory sender1 = dispatcher.testGetSender(SENDER1);
        assertEq(sender1.name, SENDER1);
        assertEq(sender1.account, vm.addr(0x1111));
        
        Senders.Sender memory sender2 = dispatcher.testGetSender(SENDER2);
        assertEq(sender2.name, SENDER2);
        assertEq(sender2.account, vm.addr(0x2222));
    }
    
    function test_DispatcherMissingSenderConfigs() public {
        // Don't set SENDER_CONFIGS
        dispatcher = new TestDispatcher();
        
        // Should revert when trying to access sender
        vm.expectRevert(Dispatcher.InvalidSenderConfigs.selector);
        dispatcher.testGetSender("any");
    }
    
    function test_DispatcherInvalidSenderConfigs() public {
        // Set invalid configs
        vm.setEnv("SENDER_CONFIGS", "0xdeadbeef");
        
        dispatcher = new TestDispatcher();
        
        // Should revert when trying to decode
        vm.expectRevert(Dispatcher.InvalidSenderConfigs.selector);
        dispatcher.testGetSender("any");
    }
    
    function test_DispatcherForkManagement() public {
        // Setup configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x1111)
        });
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Create dispatcher
        uint256 originalFork = vm.activeFork();
        dispatcher = new TestDispatcher();
        
        // Should be on simulation fork after construction
        uint256 currentFork = vm.activeFork();
        assertTrue(currentFork != originalFork);
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
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        dispatcher = new TestDispatcher();
        
        // Test with DRYRUN=false (default)
        uint256 simFork = vm.activeFork();
        dispatcher.testBroadcast();
        uint256 execFork = vm.activeFork();
        
        // Should have switched to execution fork
        assertTrue(simFork != execFork);
        
        // Test with DRYRUN=true
        vm.selectFork(simFork);
        vm.setEnv("DRYRUN", "true");
        dispatcher.testBroadcast();
        
        // Should stay on simulation fork
        assertEq(vm.activeFork(), simFork);
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
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Create dispatcher
        dispatcher = new TestDispatcher();
        
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