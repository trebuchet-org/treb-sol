// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Senders} from "./Senders.sol";
import {SimulatedTransaction, SenderTypes} from "../types.sol";
import {ITrebEvents} from "../ITrebEvents.sol";

/**
 * @title IGovernor
 * @notice Minimal interface for OpenZeppelin Governor propose function
 */
interface IGovernor {
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId);
}

/**
 * @title OZGovernor
 * @author Trebuchet Team
 * @notice Library for managing OpenZeppelin Governor transactions within the Trebuchet sender system
 * @dev This library provides integration with OpenZeppelin Governor contracts, enabling:
 *      - Transaction queueing for proposal creation
 *      - Support for various proposer types (private key, hardware wallets)
 *      - Optional timelock integration for execution context
 *      - Flexible proposal description handling
 *
 * The library handles the complexities of Governor proposal creation, including:
 * - Collecting multiple transactions into a single proposal
 * - Managing proposer authentication (EOA, Ledger, Trezor)
 * - Generating proposal IDs for tracking
 * - Supporting both direct Governor and Timelock-controlled execution
 */
library OZGovernor {
    using Senders for Senders.Sender;
    using OZGovernor for OZGovernor.Sender;

    /**
     * @dev Sender structure for OZ Governor integration
     * @param id Unique identifier for the sender
     * @param name Human-readable name for the sender
     * @param account Executor address: timelock if provided, otherwise governor (used for vm.prank)
     * @param senderType Type identifier (must be OZGovernor)
     * @param canBroadcast Whether this sender can broadcast transactions
     * @param config Encoded configuration containing (governor, timelock, proposerName)
     * @param proposerId ID of the proposer sender who will submit the proposal
     * @param governor Governor contract address (where propose is called)
     * @param timelock Optional timelock address (address(0) if none)
     * @param txQueue Queue of transactions to be included in the proposal
     * @param description Proposal description text
     */
    struct Sender {
        bytes32 id;
        string name;
        address account;
        bytes8 senderType;
        bool canBroadcast;
        bytes config;
        // OZGovernor-specific fields:
        bytes32 proposerId;
        address governor;
        address timelock;
        SimulatedTransaction[] txQueue;
        string description;
    }

    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error InvalidOZGovernorConfig(string name);
    error ProposalDescriptionAlreadySet(string name);
    error ProposalDescriptionNotSet(string name);

    /**
     * @notice Initializes an OZGovernor sender with its configuration
     * @dev Sets up the governor, timelock, and proposer. The account field is set to
     *      timelock if provided, otherwise governor, for correct vm.prank behavior during simulation.
     *      The proposer must be an InMemory, Ledger, or Trezor sender.
     * @param _sender The OZGovernor sender to initialize
     */
    function initialize(Sender storage _sender) internal {
        (address governor, address timelock, string memory proposerName) =
            abi.decode(_sender.config, (address, address, string));

        if (governor == address(0) || bytes(proposerName).length == 0) {
            revert InvalidOZGovernorConfig(_sender.name);
        }

        _sender.governor = governor;
        _sender.timelock = timelock;
        _sender.proposerId = keccak256(abi.encodePacked(proposerName));

        // Set account to timelock if provided, otherwise governor
        // This is the address that vm.prank uses during simulation
        if (timelock != address(0)) {
            _sender.account = timelock;
        } else {
            _sender.account = governor;
        }

        // Validate proposer type (same pattern as GnosisSafe)
        Senders.Sender storage proposerSender = _sender.proposer();
        if (
            !proposerSender.isType(SenderTypes.InMemory) && !proposerSender.isType(SenderTypes.Ledger)
                && !proposerSender.isType(SenderTypes.Trezor)
        ) {
            revert InvalidOZGovernorConfig(_sender.name);
        }
    }

    /**
     * @notice Clears the proposal description for testing purposes
     * @dev Resets the description storage field to empty. Only use in tests.
     * @param _sender The OZGovernor sender
     */
    function clearDescription(Sender storage _sender) internal {
        _sender.description = "";
    }

    /**
     * @notice Sets the proposal description directly
     * @dev Can only be called once per sender. Must be called before broadcast.
     * @param _sender The OZGovernor sender
     * @param _description The proposal description text
     */
    function setProposalDescription(Sender storage _sender, string memory _description) internal {
        if (_sender._isDescriptionSet()) {
            revert ProposalDescriptionAlreadySet(_sender.name);
        }
        _sender.description = _description;
    }

    /**
     * @notice Sets the proposal description from a file path
     * @dev Reads the file content and uses it as the description. Can only be called once.
     * @param _sender The OZGovernor sender
     * @param _path Path to the file containing the proposal description
     */
    function setProposalDescriptionPath(Sender storage _sender, string memory _path) internal {
        if (_sender._isDescriptionSet()) {
            revert ProposalDescriptionAlreadySet(_sender.name);
        }
        _sender.description = vm.readFile(_path);
    }

    /**
     * @notice Queues a transaction for inclusion in the proposal
     * @dev Transactions are accumulated until broadcast() is called.
     * @param _sender The OZGovernor sender
     * @param _tx The transaction to queue
     */
    function queue(Sender storage _sender, SimulatedTransaction memory _tx) internal {
        _sender.txQueue.push(_tx);
    }

    /**
     * @notice Broadcasts all queued transactions as a governance proposal
     * @dev Creates a proposal on the Governor contract with all queued transactions.
     *      Reverts if description is not set. Supports ETH value in transactions.
     * @param _sender The OZGovernor sender
     */
    function broadcast(Sender storage _sender) internal {
        if (_sender.txQueue.length == 0) {
            return;
        }

        if (!_sender._isDescriptionSet()) {
            revert ProposalDescriptionNotSet(_sender.name);
        }

        string memory description = _sender.description;

        // Prepare proposal arrays
        address[] memory targets = new address[](_sender.txQueue.length);
        uint256[] memory values = new uint256[](_sender.txQueue.length);
        bytes[] memory calldatas = new bytes[](_sender.txQueue.length);

        for (uint256 i = 0; i < _sender.txQueue.length; i++) {
            targets[i] = _sender.txQueue[i].transaction.to;
            values[i] = _sender.txQueue[i].transaction.value;
            calldatas[i] = _sender.txQueue[i].transaction.data;
        }

        // Call propose on the Governor using the proposer
        address proposerAddress = _sender.proposer().account;

        vm.broadcast(proposerAddress);
        uint256 proposalId = IGovernor(_sender.governor).propose(targets, values, calldatas, description);

        // Emit event for CLI tracking
        if (!Senders.registry().quiet) {
            bytes32[] memory transactionIds = new bytes32[](_sender.txQueue.length);
            for (uint256 i = 0; i < _sender.txQueue.length; i++) {
                transactionIds[i] = _sender.txQueue[i].transactionId;
            }
            emit ITrebEvents.GovernorProposalCreated(proposalId, _sender.governor, proposerAddress, transactionIds);
        }

        delete _sender.txQueue;
    }

    /**
     * @notice Checks if description has been set for this sender
     * @dev Checks if the description storage field is non-empty
     * @param _sender The OZGovernor sender
     * @return True if description is set
     */
    function _isDescriptionSet(Sender storage _sender) internal view returns (bool) {
        return bytes(_sender.description).length > 0;
    }

    /**
     * @notice Retrieves the proposer sender for this Governor
     * @dev The proposer is responsible for calling propose() on the Governor
     * @param _sender The OZGovernor sender
     * @return The proposer sender instance
     */
    function proposer(Sender storage _sender) internal view returns (Senders.Sender storage) {
        return Senders.get(_sender.proposerId);
    }

    /**
     * @notice Casts a generic Sender to an OZGovernor.Sender
     * @dev Validates that the sender is of OZGovernor type before casting
     * @param _sender The generic sender to cast
     * @return _ozGovernorSender The casted OZGovernor sender
     */
    function cast(Senders.Sender storage _sender) internal view returns (Sender storage _ozGovernorSender) {
        if (!_sender.isType(SenderTypes.OZGovernor)) {
            revert Senders.InvalidCast(_sender.name, _sender.senderType, SenderTypes.OZGovernor);
        }
        assembly {
            _ozGovernorSender.slot := _sender.slot
        }
    }
}
