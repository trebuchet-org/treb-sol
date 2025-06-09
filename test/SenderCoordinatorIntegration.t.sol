// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SenderCoordinator} from "../src/internal/SenderCoordinator.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {SenderTypes, Transaction} from "../src/internal/types.sol";

contract TestableSenderCoordinator is SenderCoordinator {
    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun)
        SenderCoordinator(_decodeConfigs(_rawConfigs), _namespace, _dryrun, false)
    {}

    function _decodeConfigs(bytes memory _rawConfigs) private pure returns (Senders.SenderInitConfig[] memory) {
        if (_rawConfigs.length == 0) {
            return new Senders.SenderInitConfig[](0);
        }
        return abi.decode(_rawConfigs, (Senders.SenderInitConfig[]));
    }

    // Expose internal functions for testing
    function testGetSender(string memory name) external view returns (Senders.Sender memory) {
        return sender(name);
    }

    function testBroadcast() external broadcast {
        // Empty function to test modifier
    }
}

contract SenderCoordinatorIntegrationTest is Test {
    TestableSenderCoordinator senderCoordinator;

    // Constants for sender names
    string constant SENDER1 = "sender1";
    string constant SENDER2 = "sender2";
    string constant TEST_SENDER = "test";
    string constant LAZY_SENDER = "lazy";
    string constant DISPATCHER_TEST = "senderCoordinator-test";

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

    function test_SenderCoordinatorInitialization() public {
        // Create sender configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);
        configs[0] = Senders.SenderInitConfig({
            name: SENDER1,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x1111)
        });
        configs[1] = Senders.SenderInitConfig({
            name: SENDER2,
            account: vm.addr(0x2222),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x2222)
        });

        // Create senderCoordinator with configs
        bytes memory encodedConfigs = abi.encode(configs);
        senderCoordinator = new TestableSenderCoordinator(encodedConfigs, "default", false);

        // Access sender (should trigger lazy initialization)
        Senders.Sender memory sender1 = senderCoordinator.testGetSender(SENDER1);
        assertEq(sender1.name, SENDER1);
        assertEq(sender1.account, vm.addr(0x1111));

        Senders.Sender memory sender2 = senderCoordinator.testGetSender(SENDER2);
        assertEq(sender2.name, SENDER2);
        assertEq(sender2.account, vm.addr(0x2222));
    }

    function test_SenderCoordinatorMissingSenderConfigs() public {
        // Create senderCoordinator with empty configs
        bytes memory emptyConfigs = "";
        vm.expectRevert(Senders.NoSenders.selector);
        senderCoordinator = new TestableSenderCoordinator(emptyConfigs, "default", false);
    }

    function test_SenderCoordinatorInvalidSenderConfigs() public {
        // Create senderCoordinator with invalid configs (can't decode as SenderInitConfig[])
        bytes memory invalidConfigs = hex"deadbeef";

        // Should revert during construction when trying to decode
        vm.expectRevert();
        senderCoordinator = new TestableSenderCoordinator(invalidConfigs, "default", false);
    }

    function test_SenderCoordinatorBroadcastModifier() public {
        // Setup
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x1111)
        });

        bytes memory encodedConfigs = abi.encode(configs);

        // Test broadcast with dryrun=false
        senderCoordinator = new TestableSenderCoordinator(encodedConfigs, "default", false);
        senderCoordinator.testBroadcast();

        // Test with dryrun=true
        senderCoordinator = new TestableSenderCoordinator(encodedConfigs, "default", true);
        senderCoordinator.testBroadcast();
    }

    function test_SenderCoordinatorLazyLoading() public {
        // Setup configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: LAZY_SENDER,
            account: vm.addr(0x3333),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x3333)
        });

        bytes memory encodedConfigs = abi.encode(configs);

        // Create senderCoordinator
        senderCoordinator = new TestableSenderCoordinator(encodedConfigs, "default", false);

        // Registry should not be initialized yet
        // First access should initialize
        Senders.Sender memory lazySender = senderCoordinator.testGetSender(LAZY_SENDER);
        assertEq(lazySender.name, LAZY_SENDER);

        // Second access should return same sender without re-initializing
        Senders.Sender memory lazySender2 = senderCoordinator.testGetSender(LAZY_SENDER);
        assertEq(lazySender2.name, LAZY_SENDER);
        assertEq(lazySender2.account, vm.addr(0x3333));
        assertEq(lazySender.id, lazySender2.id);
    }

    function test_NestedBroadcastModifier() public {
        // Setup configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: TEST_SENDER,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x1111)
        });

        bytes memory encodedConfigs = abi.encode(configs);

        // Create test coordinator that supports nested broadcasts
        NestedBroadcastTester nestedTester = new NestedBroadcastTester(encodedConfigs, "default", false);

        // This should work without issues - outer broadcast should handle everything
        nestedTester.outerBroadcast();

        // Verify the flag is properly reset after nested calls
        assertFalse(Senders.registry().broadcastQueued);
    }
}

// Test contract to verify nested broadcast behavior
contract NestedBroadcastTester is SenderCoordinator {
    using Senders for Senders.Sender;

    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun)
        SenderCoordinator(_decodeConfigs(_rawConfigs), _namespace, _dryrun, false)
    {}

    function _decodeConfigs(bytes memory _rawConfigs) private pure returns (Senders.SenderInitConfig[] memory) {
        if (_rawConfigs.length == 0) {
            return new Senders.SenderInitConfig[](0);
        }
        return abi.decode(_rawConfigs, (Senders.SenderInitConfig[]));
    }

    function outerBroadcast() public broadcast {
        // This function has broadcast modifier
        innerBroadcast();
        anotherInnerBroadcast();
    }

    function innerBroadcast() public broadcast {
        // This nested broadcast should not trigger duplicate broadcasts
        Senders.Sender storage testSender = sender("test");
        testSender.execute(Transaction({to: address(1), value: 0, data: hex"", label: "test"}));
        // Would normally queue transactions here
    }

    function anotherInnerBroadcast() public broadcast {
        // Another nested broadcast to test multiple nesting levels
        deeperBroadcast();
    }

    function deeperBroadcast() public broadcast {
        // Even deeper nesting to ensure the flag works correctly
        Senders.Sender storage testSender = sender("test");
        testSender.execute(Transaction({to: address(1), value: 0, data: hex"", label: "test"}));
    }
}
