// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {Deployer} from "../src/internal/sender/Deployer.sol";
import {SenderCoordinator} from "../src/internal/SenderCoordinator.sol";
import {SenderTypes, Transaction, RichTransaction, TransactionStatus} from "../src/internal/types.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";

contract TestContract {
    uint256 public value;

    event ValueSet(uint256 value);

    constructor(uint256 _value) {
        value = _value;
    }

    function setValue(uint256 _value) external {
        value = _value;
        emit ValueSet(_value);
    }
}

// Simple test contract that uses the new architecture
contract IntegrationTest is Test, CreateXScript {
    using Senders for Senders.Sender;
    using Senders for Senders.Registry;
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;

    // Constants for sender names
    string constant TEST = "test";
    string constant COORDINATOR_TEST = "coordinator-test";
    string constant MEMORY = "memory";
    string constant LEDGER = "ledger";
    string constant SAFE = "safe";

    function setUp() public withCreateX {}

    function test_BasicSenderWorkflow() public {
        // Create sender config
        uint256 pk = 0x12345;
        address senderAddr = vm.addr(pk);
        vm.deal(senderAddr, 10 ether);

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: TEST,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(pk)
        });

        // Initialize
        Senders.initialize(configs, "default", false);

        // Get sender directly from registry
        Senders.Registry storage reg = Senders.registry();
        bytes32 senderId = keccak256(abi.encodePacked("test"));
        Senders.Sender storage s = reg.senders[senderId];

        // Deploy contract using factory pattern
        string memory artifact = "TestContract";
        bytes memory args = abi.encode(42);

        // Use the factory pattern: create3 -> deploy
        address deployed = s.create3(artifact).deploy(args);

        // Verify deployment worked
        assertTrue(deployed != address(0));

        // Execute transaction
        Transaction memory txn = Transaction({
            label: "setValue",
            to: deployed,
            data: abi.encodeWithSelector(TestContract.setValue.selector, 100),
            value: 0
        });

        s.execute(txn);

        // Broadcast through registry
        Senders.registry().broadcast();

        // Verify
        TestContract tc = TestContract(deployed);
        assertEq(tc.value(), 100);
    }

    function test_SenderCoordinatorWorkflow() public {
        // Setup config
        uint256 pk = 0x54321;
        address senderAddr = vm.addr(pk);
        vm.deal(senderAddr, 10 ether);

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: COORDINATOR_TEST,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(pk)
        });

        // Set environment
        vm.setEnv("NETWORK", "http://localhost:8545");

        // Create custom sender coordinator for testing
        bytes memory encodedConfigs = abi.encode(configs);
        TestSenderCoordinator disp = new TestSenderCoordinator(encodedConfigs, "default", false);

        // Use the sender
        TestContract tc = disp.deployTestContract(123, COORDINATOR_TEST);
        assertEq(tc.value(), 123);
    }

    function test_MultipleSenderTypes() public {
        // Create multiple sender configs
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](3);

        // InMemory sender
        configs[0] = Senders.SenderInitConfig({
            name: MEMORY,
            account: vm.addr(0x1111),
            senderType: SenderTypes.InMemory,
            config: abi.encode(0x1111)
        });

        // Hardware wallet sender
        configs[1] = Senders.SenderInitConfig({
            name: LEDGER,
            account: makeAddr("ledger"),
            senderType: SenderTypes.Ledger,
            config: abi.encode("m/44'/60'/0'/0/0")
        });

        // Safe sender
        configs[2] = Senders.SenderInitConfig({
            name: SAFE,
            account: makeAddr("safe"),
            senderType: SenderTypes.GnosisSafe,
            config: abi.encode(MEMORY) // Use memory sender as proposer
        });

        // Initialize all
        Senders.initialize(configs, "default", false);

        // Verify all initialized correctly
        Senders.Registry storage reg = Senders.registry();

        // Check memory sender
        bytes32 memId = keccak256(abi.encodePacked("memory"));
        assertTrue(reg.senders[memId].isType(SenderTypes.InMemory));

        // Check ledger sender
        bytes32 ledgerId = keccak256(abi.encodePacked("ledger"));
        assertTrue(reg.senders[ledgerId].isType(SenderTypes.HardwareWallet));
        assertTrue(reg.senders[ledgerId].isType(SenderTypes.Ledger));

        // Check safe sender
        bytes32 safeId = keccak256(abi.encodePacked("safe"));
        assertTrue(reg.senders[safeId].isType(SenderTypes.GnosisSafe));
    }
}

// Test sender coordinator that exposes internal functions
contract TestSenderCoordinator is SenderCoordinator {
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;

    constructor(bytes memory _rawConfigs, string memory _namespace, bool _dryrun)
        SenderCoordinator(abi.decode(_rawConfigs, (Senders.SenderInitConfig[])), _namespace, _dryrun, false)
    {}

    function deployTestContract(uint256 value, string memory senderName) external returns (TestContract) {
        Senders.Sender storage s = sender(senderName);

        bytes memory bytecode = type(TestContract).creationCode;
        bytes memory args = abi.encode(value);

        // Use the new factory pattern
        string memory entropy = "TestContract";
        address deployed = s.create3(entropy, bytecode).deploy(args);

        // Manually broadcast
        _broadcast();

        return TestContract(deployed);
    }
}
