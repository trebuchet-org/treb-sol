// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {SimulatedTransaction, SenderTypes} from "../types.sol";
import {ITrebEvents} from "../ITrebEvents.sol";
import {Transaction} from "../types.sol";

// OpenZeppelin Governor interfaces
interface IGovernor {
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId);

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 balance);

    function state(uint256 proposalId) external view returns (uint8);

    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);

    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
}

interface ITimelockController {
    function getMinDelay() external view returns (uint256);
}

/**
 * @title MentoGovernance
 * @author Mento Labs
 * @notice Library for managing Mento Governance transactions within the Trebuchet sender system
 * @dev This library provides integration with MentoGovernor and TimelockController, enabling:
 *      - Transaction proposal through governance
 *      - Automatic transaction batching for gas efficiency
 *      - Simulation of governance approval and execution flow
 *      - Support for testing governance proposals in a local environment
 *
 * The MentoGovernance sender simulates transactions as if executed by the Timelock,
 * allowing scripts to test governance proposals before submission. During broadcast,
 * it creates a governance proposal that can be voted on and executed.
 */
library MentoGovernance {
    using Senders for Senders.Sender;
    using MentoGovernance for MentoGovernance.Sender;

    /**
     * @dev Sender structure for Mento Governance integration
     * @param id Unique identifier for the sender
     * @param name Human-readable name for the sender
     * @param account Timelock contract address (the actual executor)
     * @param senderType Type identifier (must be MentoGovernance)
     * @param canBroadcast Whether this sender can broadcast transactions
     * @param config Encoded configuration containing governor, timelock, proposer, and delay params
     * @param governor MentoGovernor contract address
     * @param proposerId ID of the proposer sender who will submit proposals
     * @param votingDelay Number of blocks before voting starts (0 = read from governor)
     * @param votingPeriod Number of blocks for voting period (0 = read from governor)
     * @param timelockDelay Number of seconds for timelock delay (0 = read from timelock)
     * @param txQueue Queue of transactions to be batched and proposed
     */
    struct Sender {
        bytes32 id;
        string name;
        address account;        // Timelock address
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
        // MentoGovernance specific fields:
        address governor;
        bytes32 proposerId;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 timelockDelay;
        SimulatedTransaction[] txQueue;
    }

    /**
     * @dev Configuration structure for MentoGovernance sender
     * @param governor MentoGovernor contract address
     * @param proposer Name of the proposer sender
     * @param votingDelay Optional: blocks before voting starts (0 = read from governor)
     * @param votingPeriod Optional: blocks for voting period (0 = read from governor)
     * @param timelockDelay Optional: seconds for timelock delay (0 = read from timelock)
     */
    struct Config {
        address governor;
        string proposer;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 timelockDelay;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidMentoGovernanceConfig(string name, string reason);
    error GovernanceTransactionValueNotZero(Transaction transaction);

    event GovernanceProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description
    );

    event GovernanceProposalSimulated(
        uint256 indexed proposalId,
        address indexed timelock,
        uint8 finalState
    );

    /**
     * @notice Initializes a MentoGovernance sender with its configuration
     * @dev Decodes the config and sets up the governance parameters.
     *      Validates that governor and proposer are properly configured.
     *      If delay parameters are 0, they will be read from on-chain contracts during broadcast.
     * @param _sender The MentoGovernance sender to initialize
     */
    function initialize(Sender storage _sender) internal {
        Config memory config = abi.decode(_sender.config, (Config));

        if (config.governor == address(0)) {
            revert InvalidMentoGovernanceConfig(_sender.name, "Governor address is zero");
        }

        if (bytes(config.proposer).length == 0) {
            revert InvalidMentoGovernanceConfig(_sender.name, "Proposer name is empty");
        }

        _sender.governor = config.governor;
        _sender.proposerId = bytes32(keccak256(abi.encodePacked(config.proposer)));
        _sender.votingDelay = config.votingDelay;
        _sender.votingPeriod = config.votingPeriod;
        _sender.timelockDelay = config.timelockDelay;
    }

    /**
     * @notice Queues a transaction for batch execution
     * @dev Adds the transaction to the sender's queue. Transactions are
     *      accumulated until broadcast() is called, enabling efficient batching.
     * @param _sender The MentoGovernance sender
     * @param _tx The transaction to queue
     */
    function queue(Sender storage _sender, SimulatedTransaction memory _tx) internal {
        _sender.txQueue.push(_tx);
    }

    /**
     * @notice Broadcasts all queued transactions as a governance proposal
     * @dev Collects all queued transactions into a batch proposal.
     *      Validates that transactions don't include ETH transfers (currently unsupported).
     *      Creates a governance proposal through the MentoGovernor contract.
     *      Optionally simulates the full governance flow for testing.
     * @param _sender The MentoGovernance sender
     */
    function broadcast(Sender storage _sender) internal {
        if (_sender.txQueue.length == 0) {
            return;
        }

        address[] memory targets = new address[](_sender.txQueue.length);
        uint256[] memory values = new uint256[](_sender.txQueue.length);
        bytes[] memory calldatas = new bytes[](_sender.txQueue.length);

        for (uint256 i = 0; i < _sender.txQueue.length; i++) {
            if (_sender.txQueue[i].transaction.value > 0) {
                revert GovernanceTransactionValueNotZero(_sender.txQueue[i].transaction);
            }
            targets[i] = _sender.txQueue[i].transaction.to;
            values[i] = _sender.txQueue[i].transaction.value;
            calldatas[i] = _sender.txQueue[i].transaction.data;
        }

        // Generate proposal description from transaction IDs
        string memory description = _generateDescription(_sender);

        // Get proposer address
        address proposerAddress = _sender.proposer().account;

        // Create the governance proposal
        vm.broadcast(proposerAddress);
        uint256 proposalId = IGovernor(_sender.governor).propose(
            targets,
            values,
            calldatas,
            description
        );

        // Emit event for tracking
        if (!Senders.registry().quiet) {
            emit GovernanceProposalCreated(
                proposalId,
                proposerAddress,
                targets,
                values,
                calldatas,
                description
            );
        }

        // In simulation mode, fast-forward through governance process
        if (vm.envOr("SIMULATE_GOVERNANCE", false)) {
            _simulateGovernanceFlow(_sender, proposalId, targets, values, calldatas, description);
        }

        delete _sender.txQueue;
    }

    /**
     * @notice Simulates the full governance flow for testing
     * @dev Fast-forwards through:
     *      1. Voting delay period
     *      2. Voting period (with automatic approval)
     *      3. Timelock queueing
     *      4. Timelock delay period
     *      5. Proposal execution
     *      This allows testing governance proposals in a local environment.
     * @param _sender The MentoGovernance sender
     * @param proposalId The proposal ID to simulate
     * @param targets Array of target addresses
     * @param values Array of values
     * @param calldatas Array of calldatas
     * @param description Proposal description
     */
    function _simulateGovernanceFlow(
        Sender storage _sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal {
        IGovernor governor = IGovernor(_sender.governor);

        // Get actual values from contracts if not provided
        uint256 votingDelay = _sender.votingDelay > 0 ? _sender.votingDelay : governor.votingDelay();
        uint256 votingPeriod = _sender.votingPeriod > 0 ? _sender.votingPeriod : governor.votingPeriod();
        uint256 timelockDelay = _sender.timelockDelay > 0
            ? _sender.timelockDelay
            : ITimelockController(_sender.account).getMinDelay();

        // Fast-forward through voting delay
        vm.roll(block.number + votingDelay + 1);

        // Cast vote (1 = For, 0 = Against, 2 = Abstain)
        // In a real scenario, this would be done by token holders
        // For simulation, we just assume the proposal passes
        address proposerAddress = _sender.proposer().account;
        vm.prank(proposerAddress);
        governor.castVote(proposalId, 1);

        // Fast-forward through voting period
        vm.roll(block.number + votingPeriod + 1);

        // Queue the proposal in the timelock
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.prank(proposerAddress);
        governor.queue(targets, values, calldatas, descriptionHash);

        // Fast-forward through timelock delay
        vm.warp(block.timestamp + timelockDelay + 1);

        // Execute the proposal
        vm.prank(proposerAddress);
        governor.execute(targets, values, calldatas, descriptionHash);

        // Emit event for tracking
        if (!Senders.registry().quiet) {
            emit GovernanceProposalSimulated(
                proposalId,
                _sender.account,
                governor.state(proposalId)
            );
        }
    }

    /**
     * @notice Generates a proposal description from queued transactions
     * @dev Creates a description string that includes transaction IDs for tracking
     * @param _sender The MentoGovernance sender
     * @return description The generated description string
     */
    function _generateDescription(Sender storage _sender) internal view returns (string memory) {
        string memory description = "Treb Governance Proposal\n\nTransaction IDs:\n";
        for (uint256 i = 0; i < _sender.txQueue.length; i++) {
            description = string(abi.encodePacked(
                description,
                "- ",
                _bytes32ToString(_sender.txQueue[i].transactionId),
                "\n"
            ));
        }
        return description;
    }

    /**
     * @notice Converts bytes32 to hex string
     * @param _bytes The bytes32 to convert
     * @return result The hex string representation
     */
    function _bytes32ToString(bytes32 _bytes) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(66);
        result[0] = "0";
        result[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            result[2 + i * 2] = hexChars[uint8(_bytes[i] >> 4)];
            result[3 + i * 2] = hexChars[uint8(_bytes[i] & 0x0f)];
        }
        return string(result);
    }

    /**
     * @notice Retrieves the proposer sender for this governance sender
     * @dev The proposer is responsible for submitting proposals to the governor
     * @param _sender The MentoGovernance sender
     * @return The proposer sender instance
     */
    function proposer(Sender storage _sender) internal view returns (Senders.Sender storage) {
        return Senders.get(_sender.proposerId);
    }

    /**
     * @notice Casts a generic Sender to a MentoGovernance.Sender
     * @dev Validates that the sender is of MentoGovernance type before casting
     * @param _sender The generic sender to cast
     * @return _mentoGovernanceSender The casted MentoGovernance sender
     */
    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _mentoGovernanceSender) {
        if (!_sender.isType(SenderTypes.MentoGovernance)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.MentoGovernance);
        }
        assembly {
            _mentoGovernanceSender.slot := _sender.slot
        }
    }
}
