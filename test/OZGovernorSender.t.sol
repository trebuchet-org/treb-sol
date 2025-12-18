// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {OZGovernor} from "../src/internal/sender/OZGovernorSender.sol";
import {SenderTypes, Transaction, SimulatedTransaction} from "../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";
import {ITrebEvents} from "../src/internal/ITrebEvents.sol";
import {TestVotesToken, TestGovernorDirect, TestGovernorTimelock} from "./helpers/OZGovernor.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IVotes} from "lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "lib/openzeppelin-contracts/contracts/governance/IGovernor.sol";

/**
 * @title MockTarget
 * @notice Simple target contract for transaction testing
 */
contract MockTarget {
    uint256 public value;
    address public lastCaller;

    event ValueSet(uint256 value, address caller);

    function setValue(uint256 _value) external returns (uint256) {
        value = _value;
        lastCaller = msg.sender;
        emit ValueSet(_value, msg.sender);
        return _value;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    function requireCaller(address expected) external view {
        require(msg.sender == expected, "Unexpected caller");
    }

    receive() external payable {}
}

/**
 * @title MockSenderTracker
 * @notice Helper contract to track msg.sender during calls
 */
contract MockSenderTracker {
    address public lastSender;

    function track() external {
        lastSender = msg.sender;
    }
}

contract OZGovernorSenderTest is Test {
    TestVotesToken votesToken;
    TestGovernorDirect governor;
    TestGovernorTimelock governorWithTimelock;
    TimelockController timelock;
    MockTarget target;
    SendersTestHarness harness;

    // Sender names
    string constant PROPOSER = "proposer";
    string constant GOV_NO_TIMELOCK = "gov-no-timelock";
    string constant GOV_WITH_TIMELOCK = "gov-with-timelock";

    // Proposer private key
    uint256 constant PROPOSER_PK = 0x54321;

    function setUp() public {
        // Deploy voting token and set up voting power
        votesToken = new TestVotesToken();
        address proposerAddr = vm.addr(PROPOSER_PK);
        votesToken.mint(proposerAddr, 1_000_000 ether);

        // Proposer must delegate to self to activate voting power
        vm.prank(proposerAddr);
        votesToken.delegate(proposerAddr);

        // Advance block for checkpoint
        vm.roll(block.number + 1);

        // Deploy direct governor (no timelock)
        governor = new TestGovernorDirect(IVotes(address(votesToken)));

        // Deploy timelock with open executor role
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Placeholder, will grant to governor later
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Open executor role (anyone can execute)
        timelock = new TimelockController(0, proposers, executors, address(this));

        // Deploy governor with timelock
        governorWithTimelock = new TestGovernorTimelock(IVotes(address(votesToken)), timelock);

        // Grant proposer role to governor with timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governorWithTimelock));

        // Deploy target contract
        target = new MockTarget();

        // Initialize senders
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](3);

        // Proposer (InMemory) - required for OZGovernor
        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: proposerAddr,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(PROPOSER_PK)
        });

        // OZGovernor without timelock
        configs[1] = Senders.SenderInitConfig({
            name: GOV_NO_TIMELOCK,
            account: address(governor), // Will be used as executor
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: abi.encode(address(governor), address(0), PROPOSER)
        });

        // OZGovernor with timelock
        configs[2] = Senders.SenderInitConfig({
            name: GOV_WITH_TIMELOCK,
            account: address(timelock), // Initial value, will be overridden
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: abi.encode(address(governorWithTimelock), address(timelock), PROPOSER)
        });

        // Deal ether to proposer
        harness = new SendersTestHarness(configs);

        vm.deal(proposerAddr, 10 ether);
        vm.deal(address(governor), 10 ether);
        vm.deal(address(timelock), 10 ether);

        vm.selectFork(harness.getExecutionFork());
        vm.deal(proposerAddr, 10 ether);
        vm.deal(address(governor), 10 ether);
        vm.deal(address(timelock), 10 ether);

        vm.selectFork(harness.getSimulationFork());
    }

    // ============ Initialization Tests ============

    function test_InitializationWithoutTimelock() public view {
        OZGovernor.Sender memory sender = harness.getOZGovernor(GOV_NO_TIMELOCK);

        assertEq(sender.governor, address(governor), "Governor address mismatch");
        assertEq(sender.timelock, address(0), "Timelock should be zero");
        assertEq(sender.account, address(governor), "Account should be governor when no timelock");
    }

    function test_InitializationWithTimelock() public view {
        OZGovernor.Sender memory sender = harness.getOZGovernor(GOV_WITH_TIMELOCK);

        assertEq(sender.governor, address(governorWithTimelock), "Governor address mismatch");
        assertEq(sender.timelock, address(timelock), "Timelock address mismatch");
        assertEq(sender.account, address(timelock), "Account should be timelock when provided");
    }

    function test_SenderTypeIsOZGovernor() public view {
        assertTrue(harness.isType(GOV_NO_TIMELOCK, SenderTypes.OZGovernor), "Should be OZGovernor type");
        assertTrue(harness.isType(GOV_NO_TIMELOCK, SenderTypes.Governance), "Should also be Governance type");
        assertTrue(harness.isType(GOV_WITH_TIMELOCK, SenderTypes.OZGovernor), "Should be OZGovernor type");
    }

    function test_RevertOnInvalidConfig_ZeroGovernor() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);

        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: vm.addr(PROPOSER_PK),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(PROPOSER_PK)
        });

        configs[1] = Senders.SenderInitConfig({
            name: "bad-gov",
            account: address(0),
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: abi.encode(address(0), address(0), PROPOSER) // Zero governor
        });

        vm.expectRevert(abi.encodeWithSelector(OZGovernor.InvalidOZGovernorConfig.selector, "bad-gov"));
        new SendersTestHarness(configs);
    }

    function test_RevertOnInvalidConfig_EmptyProposer() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);

        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: vm.addr(PROPOSER_PK),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(PROPOSER_PK)
        });

        configs[1] = Senders.SenderInitConfig({
            name: "bad-gov",
            account: address(governor),
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: abi.encode(address(governor), address(0), "") // Empty proposer
        });

        vm.expectRevert(abi.encodeWithSelector(OZGovernor.InvalidOZGovernorConfig.selector, "bad-gov"));
        new SendersTestHarness(configs);
    }

    // ============ Description Tests ============

    function test_SetProposalDescription() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Test proposal description");

        // Verify description was set by trying to set again (should revert)
        vm.expectRevert(abi.encodeWithSelector(OZGovernor.ProposalDescriptionAlreadySet.selector, GOV_NO_TIMELOCK));
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Another description");
    }

    function test_SetProposalDescriptionPath() public {
        // Create a temp file with description in test/fixtures
        string memory path = "test/fixtures/test-proposal-description.md";
        vm.writeFile(path, "# Proposal from file\n\nThis is a test proposal.");

        harness.setProposalDescriptionPath(GOV_NO_TIMELOCK, path);

        // Verify description was set by trying to set again (should revert)
        vm.expectRevert(abi.encodeWithSelector(OZGovernor.ProposalDescriptionAlreadySet.selector, GOV_NO_TIMELOCK));
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Another description");

        // Cleanup
        vm.removeFile(path);
    }

    function test_RevertOnDoubleSetDescription() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "First description");

        vm.expectRevert(abi.encodeWithSelector(OZGovernor.ProposalDescriptionAlreadySet.selector, GOV_NO_TIMELOCK));
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Second description");
    }

    function test_RevertOnSetDescriptionAfterPath() public {
        string memory path = "test/fixtures/test-proposal-after-path.md";
        vm.writeFile(path, "Description from file");

        harness.setProposalDescriptionPath(GOV_NO_TIMELOCK, path);

        vm.expectRevert(abi.encodeWithSelector(OZGovernor.ProposalDescriptionAlreadySet.selector, GOV_NO_TIMELOCK));
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Another description");

        vm.removeFile(path);
    }

    function test_RevertOnSetPathAfterDescription() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Direct description");

        string memory path = "test/fixtures/test-proposal-after-desc.md";
        vm.writeFile(path, "Description from file");

        vm.expectRevert(abi.encodeWithSelector(OZGovernor.ProposalDescriptionAlreadySet.selector, GOV_NO_TIMELOCK));
        harness.setProposalDescriptionPath(GOV_NO_TIMELOCK, path);

        vm.removeFile(path);
    }

    // ============ Broadcast Tests ============

    function test_RevertBroadcastWithoutDescription() public {
        // Queue a transaction without setting description
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 42), value: 0
        });

        harness.execute(GOV_NO_TIMELOCK, txn);

        vm.expectRevert(abi.encodeWithSelector(OZGovernor.ProposalDescriptionNotSet.selector, GOV_NO_TIMELOCK));
        harness.broadcastAll();
    }

    function test_BroadcastCreatesProposal() public {
        // Set description
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Test upgrade proposal");

        // Queue transaction
        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 100), value: 0
        });

        SimulatedTransaction memory simTx = harness.execute(GOV_NO_TIMELOCK, txn);

        // Record logs to capture events (state is reverted after broadcast)
        vm.recordLogs();

        // Broadcast should create proposal
        harness.broadcastAll();

        // Verify GovernorProposalCreated event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundProposalEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundProposalEvent = true;
                // Verify indexed parameters
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(governor)))), "Governor address mismatch");
                assertEq(
                    logs[i].topics[3], bytes32(uint256(uint160(vm.addr(PROPOSER_PK)))), "Proposer address mismatch"
                );
                // Verify non-indexed parameters (transactionIds array)
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 1, "Should have 1 transaction ID");
                assertEq(txIds[0], simTx.transactionId, "Transaction ID mismatch");
                break;
            }
        }
        assertTrue(foundProposalEvent, "GovernorProposalCreated event not found");
    }

    function test_BroadcastWithMultipleTransactions() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Multi-action proposal");

        // Queue multiple transactions
        Transaction[] memory txns = new Transaction[](3);
        txns[0] = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 10), value: 0
        });
        txns[1] = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 20), value: 0
        });
        txns[2] = Transaction({to: address(target), data: "", value: 1 ether});

        SimulatedTransaction[] memory simTxs = harness.execute(GOV_NO_TIMELOCK, txns);

        vm.recordLogs();
        harness.broadcastAll();

        // Verify GovernorProposalCreated event includes all 3 transactions
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundProposalEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundProposalEvent = true;
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 3, "Should have 3 transaction IDs");
                assertEq(txIds[0], simTxs[0].transactionId, "Transaction ID 0 mismatch");
                assertEq(txIds[1], simTxs[1].transactionId, "Transaction ID 1 mismatch");
                assertEq(txIds[2], simTxs[2].transactionId, "Transaction ID 2 mismatch");
                break;
            }
        }
        assertTrue(foundProposalEvent, "GovernorProposalCreated event not found");
    }

    function test_BroadcastEmitsEvent() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Event test proposal");

        Transaction memory txn = Transaction({
            to: address(target), data: abi.encodeWithSelector(MockTarget.setValue.selector, 42), value: 0
        });

        harness.execute(GOV_NO_TIMELOCK, txn);

        // Expect the GovernorProposalCreated event
        vm.expectEmit(false, true, true, false);
        emit ITrebEvents.GovernorProposalCreated(0, address(governor), vm.addr(PROPOSER_PK), new bytes32[](1));

        harness.broadcastAll();
    }

    function test_EmptyQueueDoesNotRevert() public {
        // Set description but don't queue any transactions
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Empty proposal");

        vm.recordLogs();
        // Broadcast should not revert (just does nothing)
        harness.broadcastAll();

        // No GovernorProposalCreated event should be emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != ITrebEvents.GovernorProposalCreated.selector, "No proposal event should be emitted"
            );
        }
    }

    // ============ Prank Source Tests ============

    function test_SimulationPranksFromGovernorWhenNoTimelock() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "Prank test");

        // Set up target to track msg.sender
        MockSenderTracker tracker = new MockSenderTracker();

        Transaction memory txn = Transaction({
            to: address(tracker), data: abi.encodeWithSelector(MockSenderTracker.track.selector), value: 0
        });

        harness.execute(GOV_NO_TIMELOCK, txn);

        // During simulation, msg.sender should be the governor
        assertEq(tracker.lastSender(), address(governor), "Simulation should prank from governor");
    }

    function test_SimulationPranksFromTimelockWhenProvided() public {
        harness.setProposalDescription(GOV_WITH_TIMELOCK, "Timelock prank test");

        MockSenderTracker tracker = new MockSenderTracker();

        Transaction memory txn = Transaction({
            to: address(tracker), data: abi.encodeWithSelector(MockSenderTracker.track.selector), value: 0
        });

        harness.execute(GOV_WITH_TIMELOCK, txn);

        // During simulation, msg.sender should be the timelock
        assertEq(tracker.lastSender(), address(timelock), "Simulation should prank from timelock");
    }

    // ============ Value Transfer Tests ============

    function test_AllowsValueTransfers() public {
        harness.setProposalDescription(GOV_NO_TIMELOCK, "ETH transfer proposal");

        // Fund the governor (which will be pranked as sender)
        vm.deal(address(governor), 10 ether);

        // Queue transaction with ETH value
        Transaction memory txn = Transaction({to: address(target), data: "", value: 1 ether});

        // Should not revert - simulation should succeed
        SimulatedTransaction memory simTx = harness.execute(GOV_NO_TIMELOCK, txn);

        vm.recordLogs();
        harness.broadcastAll();

        // Verify GovernorProposalCreated event was emitted (value is included in proposal)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundProposalEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundProposalEvent = true;
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 1, "Should have 1 transaction ID");
                assertEq(txIds[0], simTx.transactionId, "Transaction ID mismatch");
                break;
            }
        }
        assertTrue(foundProposalEvent, "GovernorProposalCreated event not found");
    }
}

// ============================================================================
// Integration Tests - Tests both Governor setups (with/without timelock)
// ============================================================================

/**
 * @title OZGovernorIntegrationTest
 * @notice Comprehensive integration tests for OZGovernor sender
 * @dev Tests real-world scenarios with both timelock and non-timelock configurations
 */
contract OZGovernorIntegrationTest is Test {
    // Voting token for governance
    TestVotesToken votesToken;

    // Two separate governors for testing different configurations
    TestGovernorDirect governorDirect; // Direct execution (no timelock)
    TestGovernorTimelock governorWithTimelock; // Execution through timelock
    TimelockController timelockController;

    // Target contracts
    MockTarget treasury;
    MockTarget registry;
    MockTarget upgradeableContract;

    SendersTestHarness harness;

    // Sender names
    string constant DEPLOYER = "deployer";
    string constant PROPOSER_DIRECT = "proposer-direct";
    string constant PROPOSER_TIMELOCK = "proposer-timelock";
    string constant GOV_DIRECT = "gov-direct";
    string constant GOV_TIMELOCK = "gov-timelock";

    // Private keys
    uint256 constant DEPLOYER_PK = 0x1;
    uint256 constant PROPOSER_DIRECT_PK = 0x2;
    uint256 constant PROPOSER_TIMELOCK_PK = 0x3;

    function setUp() public {
        // Deploy voting token
        votesToken = new TestVotesToken();

        // Mint and delegate for both proposers
        address proposerDirectAddr = vm.addr(PROPOSER_DIRECT_PK);
        address proposerTimelockAddr = vm.addr(PROPOSER_TIMELOCK_PK);

        votesToken.mint(proposerDirectAddr, 1_000_000 ether);
        votesToken.mint(proposerTimelockAddr, 1_000_000 ether);

        vm.prank(proposerDirectAddr);
        votesToken.delegate(proposerDirectAddr);

        vm.prank(proposerTimelockAddr);
        votesToken.delegate(proposerTimelockAddr);

        // Advance block for checkpoint
        vm.roll(block.number + 1);

        // Deploy direct governor (no timelock)
        governorDirect = new TestGovernorDirect(IVotes(address(votesToken)));

        // Deploy timelock with open executor role
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Placeholder
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Open executor role
        timelockController = new TimelockController(0, proposers, executors, address(this));

        // Deploy governor with timelock
        governorWithTimelock = new TestGovernorTimelock(IVotes(address(votesToken)), timelockController);

        // Grant proposer role to governor with timelock
        timelockController.grantRole(timelockController.PROPOSER_ROLE(), address(governorWithTimelock));

        // Deploy target contracts
        treasury = new MockTarget();
        registry = new MockTarget();
        upgradeableContract = new MockTarget();

        // Initialize senders - mix of direct deployer and two governor configurations
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](5);

        // Direct deployer (for non-governance transactions)
        configs[0] = Senders.SenderInitConfig({
            name: DEPLOYER,
            account: vm.addr(DEPLOYER_PK),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(DEPLOYER_PK)
        });

        // Proposer for direct governor
        configs[1] = Senders.SenderInitConfig({
            name: PROPOSER_DIRECT,
            account: proposerDirectAddr,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(PROPOSER_DIRECT_PK)
        });

        // Proposer for timelock governor
        configs[2] = Senders.SenderInitConfig({
            name: PROPOSER_TIMELOCK,
            account: proposerTimelockAddr,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(PROPOSER_TIMELOCK_PK)
        });

        // Governor without timelock (direct execution)
        configs[3] = Senders.SenderInitConfig({
            name: GOV_DIRECT,
            account: address(governorDirect),
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: abi.encode(address(governorDirect), address(0), PROPOSER_DIRECT)
        });

        // Governor with timelock
        configs[4] = Senders.SenderInitConfig({
            name: GOV_TIMELOCK,
            account: address(timelockController),
            senderType: SenderTypes.OZGovernor,
            canBroadcast: true,
            config: abi.encode(address(governorWithTimelock), address(timelockController), PROPOSER_TIMELOCK)
        });

        // Fund proposers
        vm.deal(vm.addr(DEPLOYER_PK), 100 ether);
        vm.deal(proposerDirectAddr, 100 ether);
        vm.deal(proposerTimelockAddr, 100 ether);

        harness = new SendersTestHarness(configs);
    }

    // ============ Direct Governor Integration Tests ============

    function test_Integration_DirectGovernor_SingleAction() public {
        // Scenario: Protocol upgrade via direct governor
        harness.setProposalDescription(GOV_DIRECT, "# PIP-1: Update Treasury Parameter\n\nSet treasury value to 1000.");

        Transaction memory txn = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 1000), value: 0
        });

        // Simulation should execute from governor address
        SimulatedTransaction memory simTx = harness.execute(GOV_DIRECT, txn);
        assertEq(treasury.lastCaller(), address(governorDirect), "Simulation should prank from governor");
        assertEq(treasury.value(), 1000, "Value should be set during simulation");

        vm.recordLogs();
        // Broadcast creates the proposal
        harness.broadcastAll();

        // Verify GovernorProposalCreated event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundTrebEvent = false;
        bool foundOZEvent = false;
        bytes32 ozProposalCreatedSelector =
            keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for Treb event
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundTrebEvent = true;
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(governorDirect)))), "Governor mismatch");
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 1, "Should have 1 transaction");
                assertEq(txIds[0], simTx.transactionId, "Transaction ID mismatch");
            }

            // Check for OZ ProposalCreated event
            if (logs[i].topics[0] == ozProposalCreatedSelector) {
                foundOZEvent = true;
                (
                    uint256 proposalId,
                    address proposer,
                    address[] memory targets,
                    uint256[] memory values,, // signatures (always empty)
                    bytes[] memory calldatas,, // voteStart
                    , // voteEnd
                    // description
                ) = abi.decode(
                    logs[i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
                );

                // Assert tx count
                assertEq(targets.length, 1, "OZ: Wrong number of targets");
                assertEq(values.length, 1, "OZ: Wrong number of values");
                assertEq(calldatas.length, 1, "OZ: Wrong number of calldatas");

                // Assert tx data matches
                assertEq(targets[0], address(treasury), "OZ: Target mismatch");
                assertEq(values[0], 0, "OZ: Value mismatch");
                assertEq(
                    calldatas[0], abi.encodeWithSelector(MockTarget.setValue.selector, 1000), "OZ: Calldata mismatch"
                );

                // Verify proposal exists via state() - must switch to execution fork
                vm.selectFork(harness.getExecutionFork());
                IGovernor.ProposalState state = governorDirect.state(proposalId);
                assertTrue(
                    state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
                    "OZ: Proposal should exist"
                );
                vm.selectFork(harness.getSimulationFork());

                // Verify proposer matches
                assertEq(proposer, vm.addr(PROPOSER_DIRECT_PK), "OZ: Proposer mismatch");
            }
        }
        assertTrue(foundTrebEvent, "Treb GovernorProposalCreated event not found");
        assertTrue(foundOZEvent, "OZ ProposalCreated event not found");
    }

    function test_Integration_DirectGovernor_MultipleActions() public {
        // Scenario: Batch governance proposal with multiple actions
        harness.setProposalDescription(
            GOV_DIRECT,
            "# PIP-2: Protocol Configuration Update\n\n" "1. Update treasury\n" "2. Update registry\n"
            "3. Fund upgradeable contract"
        );

        // Fund governor for ETH transfer simulation
        vm.deal(address(governorDirect), 10 ether);

        Transaction[] memory txns = new Transaction[](3);
        txns[0] = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 100), value: 0
        });
        txns[1] = Transaction({
            to: address(registry), data: abi.encodeWithSelector(MockTarget.setValue.selector, 200), value: 0
        });
        txns[2] = Transaction({to: address(upgradeableContract), data: "", value: 5 ether});

        SimulatedTransaction[] memory simTxs = harness.execute(GOV_DIRECT, txns);

        // Verify simulation effects
        assertEq(treasury.value(), 100);
        assertEq(registry.value(), 200);

        vm.recordLogs();
        // Broadcast
        harness.broadcastAll();

        // Verify GovernorProposalCreated event with all 3 actions
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundTrebEvent = false;
        bool foundOZEvent = false;
        bytes32 ozProposalCreatedSelector =
            keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for Treb event
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundTrebEvent = true;
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 3, "Should have 3 transactions");
                assertEq(txIds[0], simTxs[0].transactionId, "Transaction 0 ID mismatch");
                assertEq(txIds[1], simTxs[1].transactionId, "Transaction 1 ID mismatch");
                assertEq(txIds[2], simTxs[2].transactionId, "Transaction 2 ID mismatch");
            }

            // Check for OZ ProposalCreated event
            if (logs[i].topics[0] == ozProposalCreatedSelector) {
                foundOZEvent = true;
                (
                    uint256 proposalId,
                    address proposer,
                    address[] memory targets,
                    uint256[] memory values,, // signatures (always empty)
                    bytes[] memory calldatas,, // voteStart
                    , // voteEnd
                    // description
                ) = abi.decode(
                    logs[i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
                );

                // Assert tx count
                assertEq(targets.length, 3, "OZ: Wrong number of targets");
                assertEq(values.length, 3, "OZ: Wrong number of values");
                assertEq(calldatas.length, 3, "OZ: Wrong number of calldatas");

                // Assert all targets
                assertEq(targets[0], address(treasury), "OZ: Target 0 mismatch");
                assertEq(targets[1], address(registry), "OZ: Target 1 mismatch");
                assertEq(targets[2], address(upgradeableContract), "OZ: Target 2 mismatch");

                // Assert all values
                assertEq(values[0], 0, "OZ: Value 0 mismatch");
                assertEq(values[1], 0, "OZ: Value 1 mismatch");
                assertEq(values[2], 5 ether, "OZ: Value 2 mismatch");

                // Assert all calldatas
                assertEq(
                    calldatas[0], abi.encodeWithSelector(MockTarget.setValue.selector, 100), "OZ: Calldata 0 mismatch"
                );
                assertEq(
                    calldatas[1], abi.encodeWithSelector(MockTarget.setValue.selector, 200), "OZ: Calldata 1 mismatch"
                );
                assertEq(calldatas[2], "", "OZ: Calldata 2 mismatch");

                // Verify proposal exists via state() - must switch to execution fork
                vm.selectFork(harness.getExecutionFork());
                IGovernor.ProposalState state = governorDirect.state(proposalId);
                assertTrue(
                    state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
                    "OZ: Proposal should exist"
                );
                vm.selectFork(harness.getSimulationFork());

                // Verify proposer matches
                assertEq(proposer, vm.addr(PROPOSER_DIRECT_PK), "OZ: Proposer mismatch");
            }
        }
        assertTrue(foundTrebEvent, "Treb GovernorProposalCreated event not found");
        assertTrue(foundOZEvent, "OZ ProposalCreated event not found");
    }

    // ============ Timelock Governor Integration Tests ============

    function test_Integration_TimelockGovernor_SingleAction() public {
        // Scenario: Critical upgrade that goes through timelock
        harness.setProposalDescription(
            GOV_TIMELOCK, "# TIP-1: Critical Parameter Update\n\nThis change requires timelock delay."
        );

        Transaction memory txn = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 9999), value: 0
        });

        // Simulation should execute from TIMELOCK address (not governor)
        SimulatedTransaction memory simTx = harness.execute(GOV_TIMELOCK, txn);
        assertEq(treasury.lastCaller(), address(timelockController), "Should prank from timelock");

        vm.recordLogs();
        // Broadcast creates proposal on the governor
        harness.broadcastAll();

        // Verify GovernorProposalCreated event - proposal is on governorWithTimelock
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundTrebEvent = false;
        bool foundOZEvent = false;
        bytes32 ozProposalCreatedSelector =
            keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for Treb event
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundTrebEvent = true;
                assertEq(
                    logs[i].topics[2], bytes32(uint256(uint160(address(governorWithTimelock)))), "Governor mismatch"
                );
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 1, "Should have 1 transaction");
                assertEq(txIds[0], simTx.transactionId, "Transaction ID mismatch");
            }

            // Check for OZ ProposalCreated event
            if (logs[i].topics[0] == ozProposalCreatedSelector) {
                foundOZEvent = true;
                (
                    uint256 proposalId,
                    address proposer,
                    address[] memory targets,
                    uint256[] memory values,, // signatures (always empty)
                    bytes[] memory calldatas,, // voteStart
                    , // voteEnd
                    // description
                ) = abi.decode(
                    logs[i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
                );

                // Assert tx count
                assertEq(targets.length, 1, "OZ: Wrong number of targets");
                assertEq(values.length, 1, "OZ: Wrong number of values");
                assertEq(calldatas.length, 1, "OZ: Wrong number of calldatas");

                // Assert tx data matches
                assertEq(targets[0], address(treasury), "OZ: Target mismatch");
                assertEq(values[0], 0, "OZ: Value mismatch");
                assertEq(
                    calldatas[0], abi.encodeWithSelector(MockTarget.setValue.selector, 9999), "OZ: Calldata mismatch"
                );

                // Verify proposal exists via state() - must switch to execution fork
                vm.selectFork(harness.getExecutionFork());
                IGovernor.ProposalState state = governorWithTimelock.state(proposalId);
                assertTrue(
                    state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
                    "OZ: Proposal should exist"
                );
                vm.selectFork(harness.getSimulationFork());

                // Verify proposer matches
                assertEq(proposer, vm.addr(PROPOSER_TIMELOCK_PK), "OZ: Proposer mismatch");
            }
        }
        assertTrue(foundTrebEvent, "Treb GovernorProposalCreated event not found");
        assertTrue(foundOZEvent, "OZ ProposalCreated event not found");
    }

    function test_Integration_TimelockGovernor_MultipleActions() public {
        // Scenario: Complex governance action through timelock
        harness.setProposalDescription(
            GOV_TIMELOCK,
            "# TIP-2: Multi-step Protocol Upgrade\n\n" "Critical changes requiring timelock:\n" "1. Treasury update\n"
            "2. Registry migration"
        );

        Transaction[] memory txns = new Transaction[](2);
        txns[0] = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 500), value: 0
        });
        txns[1] = Transaction({
            to: address(registry), data: abi.encodeWithSelector(MockTarget.setValue.selector, 600), value: 0
        });

        SimulatedTransaction[] memory simTxs = harness.execute(GOV_TIMELOCK, txns);

        // Both should be called from timelock
        assertEq(treasury.lastCaller(), address(timelockController));

        vm.recordLogs();
        harness.broadcastAll();

        // Verify GovernorProposalCreated event with 2 actions
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundTrebEvent = false;
        bool foundOZEvent = false;
        bytes32 ozProposalCreatedSelector =
            keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for Treb event
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundTrebEvent = true;
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 2, "Should have 2 transactions");
                assertEq(txIds[0], simTxs[0].transactionId, "Transaction 0 ID mismatch");
                assertEq(txIds[1], simTxs[1].transactionId, "Transaction 1 ID mismatch");
            }

            // Check for OZ ProposalCreated event
            if (logs[i].topics[0] == ozProposalCreatedSelector) {
                foundOZEvent = true;
                (
                    uint256 proposalId,
                    address proposer,
                    address[] memory targets,
                    uint256[] memory values,, // signatures (always empty)
                    bytes[] memory calldatas,, // voteStart
                    , // voteEnd
                    // description
                ) = abi.decode(
                    logs[i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
                );

                // Assert tx count
                assertEq(targets.length, 2, "OZ: Wrong number of targets");
                assertEq(values.length, 2, "OZ: Wrong number of values");
                assertEq(calldatas.length, 2, "OZ: Wrong number of calldatas");

                // Assert all targets
                assertEq(targets[0], address(treasury), "OZ: Target 0 mismatch");
                assertEq(targets[1], address(registry), "OZ: Target 1 mismatch");

                // Assert all values
                assertEq(values[0], 0, "OZ: Value 0 mismatch");
                assertEq(values[1], 0, "OZ: Value 1 mismatch");

                // Assert all calldatas
                assertEq(
                    calldatas[0], abi.encodeWithSelector(MockTarget.setValue.selector, 500), "OZ: Calldata 0 mismatch"
                );
                assertEq(
                    calldatas[1], abi.encodeWithSelector(MockTarget.setValue.selector, 600), "OZ: Calldata 1 mismatch"
                );

                // Verify proposal exists via state() - must switch to execution fork
                vm.selectFork(harness.getExecutionFork());
                IGovernor.ProposalState state = governorWithTimelock.state(proposalId);
                assertTrue(
                    state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
                    "OZ: Proposal should exist"
                );
                vm.selectFork(harness.getSimulationFork());

                // Verify proposer matches
                assertEq(proposer, vm.addr(PROPOSER_TIMELOCK_PK), "OZ: Proposer mismatch");
            }
        }
        assertTrue(foundTrebEvent, "Treb GovernorProposalCreated event not found");
        assertTrue(foundOZEvent, "OZ ProposalCreated event not found");
    }

    // ============ Mixed Sender Integration Tests ============

    function test_Integration_MixedSenders_DeployerAndGovernor() public {
        // Scenario: Some actions via deployer, some via governance
        // This tests that different sender types work together

        // First, deployer sets initial value
        Transaction memory deployerTxn = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 1), value: 0
        });
        harness.execute(DEPLOYER, deployerTxn);
        assertEq(treasury.value(), 1, "Deployer should set value");

        // Then governor proposes a change
        harness.setProposalDescription(GOV_DIRECT, "Update after deployment");
        Transaction memory govTxn = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 2), value: 0
        });
        SimulatedTransaction memory simTx = harness.execute(GOV_DIRECT, govTxn);
        assertEq(treasury.value(), 2, "Governor simulation should update value");

        vm.recordLogs();
        // Broadcast both
        harness.broadcastAll();

        // Verify GovernorProposalCreated event was emitted for governor tx
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundProposalEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundProposalEvent = true;
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 1, "Should have 1 governor transaction");
                assertEq(txIds[0], simTx.transactionId, "Transaction ID mismatch");
                break;
            }
        }
        assertTrue(foundProposalEvent, "GovernorProposalCreated event not found");
    }

    function test_Integration_BothGovernorsInSameScript() public {
        // Scenario: Two different governance systems updated in same script
        harness.setProposalDescription(GOV_DIRECT, "Direct gov proposal");
        harness.setProposalDescription(GOV_TIMELOCK, "Timelock gov proposal");

        // Queue to direct governor
        Transaction memory directTxn = Transaction({
            to: address(treasury), data: abi.encodeWithSelector(MockTarget.setValue.selector, 111), value: 0
        });
        SimulatedTransaction memory directSimTx = harness.execute(GOV_DIRECT, directTxn);

        // Queue to timelock governor
        Transaction memory timelockTxn = Transaction({
            to: address(registry), data: abi.encodeWithSelector(MockTarget.setValue.selector, 222), value: 0
        });
        SimulatedTransaction memory timelockSimTx = harness.execute(GOV_TIMELOCK, timelockTxn);

        vm.recordLogs();
        // Broadcast creates both proposals
        harness.broadcastAll();

        // Verify both GovernorProposalCreated events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 proposalEventCount = 0;
        bool foundDirectEvent = false;
        bool foundTimelockEvent = false;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                proposalEventCount++;
                address eventGovernor = address(uint160(uint256(logs[i].topics[2])));
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));

                if (eventGovernor == address(governorDirect)) {
                    foundDirectEvent = true;
                    assertEq(txIds[0], directSimTx.transactionId, "Direct tx ID mismatch");
                } else if (eventGovernor == address(governorWithTimelock)) {
                    foundTimelockEvent = true;
                    assertEq(txIds[0], timelockSimTx.transactionId, "Timelock tx ID mismatch");
                }
            }
        }

        assertEq(proposalEventCount, 2, "Should have 2 proposal events");
        assertTrue(foundDirectEvent, "Direct governor event not found");
        assertTrue(foundTimelockEvent, "Timelock governor event not found");
    }

    // ============ Error Scenario Tests ============

    function test_Integration_ProposalIdIsCorrect() public {
        harness.setProposalDescription(GOV_DIRECT, "Test proposal for ID verification");

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Calculate expected proposal ID (same as OZ Governor)
        uint256 expectedProposalId = uint256(
            keccak256(abi.encode(targets, values, calldatas, keccak256(bytes("Test proposal for ID verification"))))
        );

        Transaction memory txn = Transaction({to: address(treasury), data: calldatas[0], value: 0});

        harness.execute(GOV_DIRECT, txn);

        vm.recordLogs();
        harness.broadcastAll();

        // Verify proposal ID from the event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundTrebEvent = false;
        bool foundOZEvent = false;
        bytes32 ozProposalCreatedSelector =
            keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for Treb event
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundTrebEvent = true;
                uint256 proposalId = uint256(logs[i].topics[1]);
                assertEq(proposalId, expectedProposalId, "Proposal ID should match OZ calculation");
            }

            // Check for OZ ProposalCreated event
            if (logs[i].topics[0] == ozProposalCreatedSelector) {
                foundOZEvent = true;
                (
                    uint256 proposalId,
                    address proposer,
                    address[] memory ozTargets,
                    uint256[] memory ozValues,, // signatures (always empty)
                    bytes[] memory ozCalldatas,, // voteStart
                    , // voteEnd
                    // description
                ) = abi.decode(
                    logs[i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
                );

                // Verify proposal ID matches expected
                assertEq(proposalId, expectedProposalId, "OZ: Proposal ID mismatch");

                // Assert tx count and data
                assertEq(ozTargets.length, 1, "OZ: Wrong number of targets");
                assertEq(ozTargets[0], address(treasury), "OZ: Target mismatch");
                assertEq(ozValues[0], 0, "OZ: Value mismatch");
                assertEq(ozCalldatas[0], calldatas[0], "OZ: Calldata mismatch");

                // Verify proposal exists via state() - must switch to execution fork
                vm.selectFork(harness.getExecutionFork());
                IGovernor.ProposalState state = governorDirect.state(proposalId);
                assertTrue(
                    state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
                    "OZ: Proposal should exist"
                );
                vm.selectFork(harness.getSimulationFork());

                // Verify proposer matches
                assertEq(proposer, vm.addr(PROPOSER_DIRECT_PK), "OZ: Proposer mismatch");
            }
        }
        assertTrue(foundTrebEvent, "Treb GovernorProposalCreated event not found");
        assertTrue(foundOZEvent, "OZ ProposalCreated event not found");
    }

    function test_Integration_ETHTransfersThroughGovernance() public {
        // Scenario: Governance proposal to send ETH from treasury
        harness.setProposalDescription(GOV_DIRECT, "Grant: Send 10 ETH to recipient");

        // Fund governor for ETH transfer simulation
        vm.deal(address(governorDirect), 20 ether);

        address recipient = makeAddr("recipient");
        Transaction memory txn = Transaction({to: recipient, data: "", value: 10 ether});

        SimulatedTransaction memory simTx = harness.execute(GOV_DIRECT, txn);

        vm.recordLogs();
        harness.broadcastAll();

        // Verify GovernorProposalCreated event was emitted with ETH value
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundTrebEvent = false;
        bool foundOZEvent = false;
        bytes32 ozProposalCreatedSelector =
            keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for Treb event
            if (logs[i].topics[0] == ITrebEvents.GovernorProposalCreated.selector) {
                foundTrebEvent = true;
                bytes32[] memory txIds = abi.decode(logs[i].data, (bytes32[]));
                assertEq(txIds.length, 1, "Should have 1 transaction");
                assertEq(txIds[0], simTx.transactionId, "Transaction ID mismatch");
            }

            // Check for OZ ProposalCreated event
            if (logs[i].topics[0] == ozProposalCreatedSelector) {
                foundOZEvent = true;
                (
                    uint256 proposalId,
                    address proposer,
                    address[] memory targets,
                    uint256[] memory values,, // signatures (always empty)
                    bytes[] memory calldatas,, // voteStart
                    , // voteEnd
                    // description
                ) = abi.decode(
                    logs[i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
                );

                // Assert tx count
                assertEq(targets.length, 1, "OZ: Wrong number of targets");
                assertEq(values.length, 1, "OZ: Wrong number of values");
                assertEq(calldatas.length, 1, "OZ: Wrong number of calldatas");

                // Assert tx data matches - ETH transfer
                assertEq(targets[0], recipient, "OZ: Target mismatch");
                assertEq(values[0], 10 ether, "OZ: Value mismatch - should be 10 ETH");
                assertEq(calldatas[0], "", "OZ: Calldata mismatch - should be empty");

                // Verify proposal exists via state() - must switch to execution fork
                vm.selectFork(harness.getExecutionFork());
                IGovernor.ProposalState state = governorDirect.state(proposalId);
                assertTrue(
                    state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
                    "OZ: Proposal should exist"
                );
                vm.selectFork(harness.getSimulationFork());

                // Verify proposer matches
                assertEq(proposer, vm.addr(PROPOSER_DIRECT_PK), "OZ: Proposer mismatch");
            }
        }
        assertTrue(foundTrebEvent, "Treb GovernorProposalCreated event not found");
        assertTrue(foundOZEvent, "OZ ProposalCreated event not found");
    }
}
