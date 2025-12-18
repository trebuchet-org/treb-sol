// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "lib/openzeppelin-contracts/contracts/utils/Nonces.sol";
import {Governor} from "lib/openzeppelin-contracts/contracts/governance/Governor.sol";
import {
    GovernorCountingSimple
} from "lib/openzeppelin-contracts/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "lib/openzeppelin-contracts/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "lib/openzeppelin-contracts/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {
    GovernorTimelockControl
} from "lib/openzeppelin-contracts/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IVotes} from "lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

/// @notice ERC20 token with voting capabilities for testing
contract TestVotesToken is ERC20, ERC20Permit, ERC20Votes {
    constructor() ERC20("TestVotesToken", "TVT") ERC20Permit("TestVotesToken") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Required overrides for diamond inheritance
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

/// @notice Governor without timelock - executor is the governor itself
contract TestGovernorDirect is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    constructor(IVotes _token)
        Governor("TestGovernorDirect")
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum

    {}

    function votingDelay() public pure override returns (uint256) {
        return 0; // No delay for testing
    }

    function votingPeriod() public pure override returns (uint256) {
        return 50; // 50 blocks for testing
    }

    function proposalThreshold() public pure override returns (uint256) {
        return 0; // Anyone can propose
    }
}

/// @notice Governor with timelock - executor is the timelock controller
contract TestGovernorTimelock is
    Governor,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(IVotes _token, TimelockController _timelock)
        Governor("TestGovernorTimelock")
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(_timelock)
    {}

    function votingDelay() public pure override returns (uint256) {
        return 0; // No delay for testing
    }

    function votingPeriod() public pure override returns (uint256) {
        return 50; // 50 blocks for testing
    }

    function proposalThreshold() public pure override returns (uint256) {
        return 0; // Anyone can propose
    }

    // Required overrides for GovernorTimelockControl conflicts
    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        virtual
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
