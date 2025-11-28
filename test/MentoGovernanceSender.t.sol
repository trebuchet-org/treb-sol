// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {MentoGovernance} from "../src/internal/sender/MentoGovernanceSender.sol";
import {SenderTypes, Transaction, SimulatedTransaction} from "../src/internal/types.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

contract MockTarget {
    uint256 public value;
    string public name;

    event ValueSet(uint256 newValue);
    event NameSet(string newName);

    function setValue(uint256 _value) external returns (uint256) {
        value = _value;
        emit ValueSet(_value);
        return _value;
    }

    function setName(string memory _name) external {
        name = _name;
        emit NameSet(_name);
    }

    function getValue() external view returns (uint256) {
        return value;
    }
}

contract MockGovernor {
    struct Proposal {
        uint256 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 eta;
        bool executed;
        uint8 state;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    address public timelock;
    uint256 public votingDelayBlocks = 1;
    uint256 public votingPeriodBlocks = 50400;

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
    event ProposalQueued(uint256 proposalId, uint256 eta);
    event ProposalExecuted(uint256 proposalId);

    constructor(address _timelock) {
        timelock = _timelock;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        proposalCount++;
        uint256 proposalId = proposalCount;

        bytes32 descriptionHash = keccak256(bytes(description));

        proposals[proposalId] = Proposal({
            id: proposalId,
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: descriptionHash,
            voteStart: block.number + votingDelayBlocks,
            voteEnd: block.number + votingDelayBlocks + votingPeriodBlocks,
            eta: 0,
            executed: false,
            state: 0 // Pending
        });

        string[] memory signatures = new string[](targets.length);
        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            proposals[proposalId].voteStart,
            proposals[proposalId].voteEnd,
            description
        );

        return proposalId;
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function castVote(uint256 proposalId, uint8 support) external returns (uint256) {
        emit VoteCast(msg.sender, proposalId, support, 1000, "");
        proposals[proposalId].state = 4; // Succeeded
        return 1000;
    }

    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256) {
        uint256 proposalId = this.hashProposal(targets, values, calldatas, descriptionHash);
        proposals[proposalId].eta = block.timestamp + MockTimelockController(timelock).getMinDelay();
        proposals[proposalId].state = 5; // Queued
        emit ProposalQueued(proposalId, proposals[proposalId].eta);
        return proposalId;
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256) {
        uint256 proposalId = this.hashProposal(targets, values, calldatas, descriptionHash);

        MockTimelockController(timelock).executeBatch(targets, values, calldatas, bytes32(0), bytes32(proposalId));

        proposals[proposalId].executed = true;
        proposals[proposalId].state = 7; // Executed
        emit ProposalExecuted(proposalId);
        return proposalId;
    }

    function state(uint256 proposalId) external view returns (uint8) {
        return proposals[proposalId].state;
    }

    function votingDelay() external view returns (uint256) {
        return votingDelayBlocks;
    }

    function votingPeriod() external view returns (uint256) {
        return votingPeriodBlocks;
    }
}

contract MockTimelockController {
    uint256 public minDelay = 2 days;

    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);

    function getMinDelay() external view returns (uint256) {
        return minDelay;
    }

    function executeBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external payable {
        require(targets.length == values.length, "TimelockController: length mismatch");
        require(targets.length == payloads.length, "TimelockController: length mismatch");

        bytes32 id = keccak256(abi.encode(targets, values, payloads, predecessor, salt));

        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 value = values[i];
            bytes memory payload = payloads[i];

            (bool success,) = target.call{value: value}(payload);
            require(success, "TimelockController: underlying transaction reverted");

            emit CallExecuted(id, i, target, value, payload);
        }
    }
}

contract MentoGovernanceSenderTest is Test {
    MockTarget target;
    MockGovernor governor;
    MockTimelockController timelock;
    SendersTestHarness harness;

    string constant internal PROPOSER = "proposer";
    string constant internal GOVERNANCE = "governance";
    address internal proposer = makeAddr("proposer");

    function setUp() public {
        target = new MockTarget();
        timelock = new MockTimelockController();
        governor = new MockGovernor(address(timelock));

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);

        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: proposer,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x12345)
        });

        MentoGovernance.Config memory govConfig = MentoGovernance.Config({
            governor: address(governor),
            proposer: PROPOSER,
            votingDelay: 0, // Will read from governor
            votingPeriod: 0, // Will read from governor
            timelockDelay: 0 // Will read from timelock
        });

        configs[1] = Senders.SenderInitConfig({
            name: GOVERNANCE,
            account: address(timelock),
            senderType: SenderTypes.MentoGovernance,
            canBroadcast: true,
            config: abi.encode(govConfig)
        });

        vm.deal(proposer, 10 ether);

        harness = new SendersTestHarness(configs);
    }

    function test_MentoGovernanceSenderInitialization() public view {
        MentoGovernance.Sender memory govSender = harness.getMentoGovernance(GOVERNANCE);

        assertEq(govSender.name, GOVERNANCE);
        assertEq(govSender.account, address(timelock));
        assertEq(govSender.governor, address(governor));
        assertTrue(govSender.canBroadcast);
    }

    function test_MentoGovernanceProposalCreation() public {
        Transaction memory txn = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 42),
            value: 0
        });

        SimulatedTransaction memory simulatedTxn = harness.execute(GOVERNANCE, txn);

        assertEq(target.getValue(), 42);
        assertEq(abi.decode(simulatedTxn.returnData, (uint256)), 42);

        vm.expectEmit(true, true, false, false);
        emit MockGovernor.ProposalCreated(
            1,
            proposer,
            new address[](1),
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            0,
            0,
            ""
        );

        harness.broadcastAll();

        // TODO: check governor.proposalCount()
    }

    function test_MentoGovernanceBatchTransactions() public {
        Transaction[] memory txns = new Transaction[](3);
        txns[0] = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 100),
            value: 0
        });
        txns[1] = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setName.selector, "Test"),
            value: 0
        });
        txns[2] = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 200),
            value: 0
        });

        SimulatedTransaction[] memory results = harness.execute(GOVERNANCE, txns);

        assertEq(results.length, 3);
        assertEq(target.getValue(), 200);
        assertEq(target.name(), "Test");

        vm.expectEmit(true, true, false, false);
        emit MockGovernor.ProposalCreated(
            1,
            proposer,
            new address[](3),
            new uint256[](3),
            new string[](3),
            new bytes[](3),
            0,
            0,
            ""
        );

        harness.broadcastAll();
    }

    function test_MentoGovernanceFullFlowSimulation() public {
        vm.setEnv("SIMULATE_GOVERNANCE", "true");

        Transaction memory txn = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 999),
            value: 0
        });

        harness.execute(GOVERNANCE, txn);

        vm.expectEmit(true, true, false, false);
        emit MockGovernor.ProposalCreated(1, proposer, new address[](1), new uint256[](1), new string[](1), new bytes[](1), 0, 0, "");

        harness.broadcastAll();

        vm.setEnv("SIMULATE_GOVERNANCE", "false");
    }

    function test_MentoGovernanceRejectsValueTransfers() public {
        Transaction memory txn = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 42),
            value: 0
        });

        harness.execute(GOVERNANCE, txn);

        Transaction memory valueTxn = Transaction({
            to: address(target),
            data: "",
            value: 1 ether
        });

        vm.expectRevert();
        harness.execute(GOVERNANCE, valueTxn);
    }

    function test_MentoGovernanceProposerValidation() public {
        MentoGovernance.Config memory invalidConfig = MentoGovernance.Config({
            governor: address(governor),
            proposer: "", // Invalid: empty proposer
            votingDelay: 0,
            votingPeriod: 0,
            timelockDelay: 0
        });

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "invalid-gov",
            account: address(timelock),
            senderType: SenderTypes.MentoGovernance,
            canBroadcast: true,
            config: abi.encode(invalidConfig)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                MentoGovernance.InvalidMentoGovernanceConfig.selector,
                "invalid-gov",
                "Proposer name is empty"
            )
        );
        new SendersTestHarness(configs);
    }

    function test_MentoGovernanceGovernorValidation() public {
        MentoGovernance.Config memory invalidConfig = MentoGovernance.Config({
            governor: address(0), // Invalid: zero address
            proposer: PROPOSER,
            votingDelay: 0,
            votingPeriod: 0,
            timelockDelay: 0
        });

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);

        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: proposer,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x12345)
        });

        configs[1] = Senders.SenderInitConfig({
            name: "invalid-gov",
            account: address(timelock),
            senderType: SenderTypes.MentoGovernance,
            canBroadcast: true,
            config: abi.encode(invalidConfig)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                MentoGovernance.InvalidMentoGovernanceConfig.selector,
                "invalid-gov",
                "Governor address is zero"
            )
        );
        new SendersTestHarness(configs);
    }

    function test_MentoGovernanceCustomDelayParameters() public {
        MentoGovernance.Config memory customConfig = MentoGovernance.Config({
            governor: address(governor),
            proposer: PROPOSER,
            votingDelay: 100,
            votingPeriod: 1000,
            timelockDelay: 1 days
        });

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](2);

        configs[0] = Senders.SenderInitConfig({
            name: PROPOSER,
            account: proposer,
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(0x12345)
        });

        configs[1] = Senders.SenderInitConfig({
            name: "custom-gov",
            account: address(timelock),
            senderType: SenderTypes.MentoGovernance,
            canBroadcast: true,
            config: abi.encode(customConfig)
        });

        vm.deal(proposer, 10 ether);
        SendersTestHarness customHarness = new SendersTestHarness(configs);

        MentoGovernance.Sender memory govSender = customHarness.getMentoGovernance("custom-gov");
        assertEq(govSender.votingDelay, 100);
        assertEq(govSender.votingPeriod, 1000);
        assertEq(govSender.timelockDelay, 86400);
    }

    function test_MentoGovernanceTransactionOrdering() public {
        Transaction[] memory txns = new Transaction[](2);
        txns[0] = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 1),
            value: 0
        });
        txns[1] = Transaction({
            to: address(target),
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 2),
            value: 0
        });

        harness.execute(GOVERNANCE, txns);

        assertEq(target.getValue(), 2);

        vm.expectEmit(true, true, false, false);
        emit MockGovernor.ProposalCreated(1, proposer, new address[](2), new uint256[](2), new string[](2), new bytes[](2), 0, 0, "");

        harness.broadcastAll();
    }
}
