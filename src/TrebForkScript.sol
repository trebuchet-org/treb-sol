// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TrebScript} from "./TrebScript.sol";
import {Senders} from "./internal/sender/Senders.sol";
import {ForkRpc} from "./internal/ForkRpc.sol";
import {ForkStorage, IERC20Balanceable, IERC20SupplyBalanceable} from "./internal/ForkStorage.sol";

interface ISafeOwnerManager {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function isOwner(address owner) external view returns (bool);
}

/**
 * @title TrebForkScript
 * @notice TrebScript variant for local fork workflows that need impersonation and persistent state mutations.
 * @dev Extends the standard sender model with on-demand fork-prank senders and helpers that keep
 *      simulation fork state aligned with the underlying Anvil node used for broadcast persistence.
 */
abstract contract TrebForkScript is TrebScript {
    using Senders for Senders.Registry;
    using Senders for Senders.Sender;

    address private constant SENTINEL_OWNERS = address(0x1);
    uint256 private constant SAFE_OWNERS_SLOT = 2;
    uint256 private constant SAFE_OWNER_COUNT_SLOT = 3;
    uint256 private constant SAFE_THRESHOLD_SLOT = 4;

    mapping(address => uint256) private erc20BalanceSlots;
    mapping(address => bool) private erc20BalanceSlotCached;
    mapping(address => uint256) private erc20TotalSupplySlots;
    mapping(address => bool) private erc20TotalSupplySlotCached;

    /**
     * @notice Converts a Safe multisig to a single-owner 1/1 configuration on both local forks.
     */
    function convertSafeToSingleOwner(address safe, address newOwner) internal {
        require(newOwner != address(0) && newOwner != SENTINEL_OWNERS, "TrebForkScript: invalid owner");

        address[] memory currentOwners = ISafeOwnerManager(safe).getOwners();

        for (uint256 i = 0; i < currentOwners.length; i++) {
            bytes32 ownerSlot = ForkStorage.mappingSlot(currentOwners[i], SAFE_OWNERS_SLOT);
            storeFork(safe, ownerSlot, bytes32(0));
        }

        bytes32 sentinelSlot = ForkStorage.mappingSlot(SENTINEL_OWNERS, SAFE_OWNERS_SLOT);
        storeFork(safe, sentinelSlot, bytes32(uint256(uint160(newOwner))));

        bytes32 newOwnerSlot = ForkStorage.mappingSlot(newOwner, SAFE_OWNERS_SLOT);
        storeFork(safe, newOwnerSlot, bytes32(uint256(uint160(SENTINEL_OWNERS))));

        storeFork(safe, bytes32(SAFE_OWNER_COUNT_SLOT), bytes32(uint256(1)));
        storeFork(safe, bytes32(SAFE_THRESHOLD_SLOT), bytes32(uint256(1)));
    }

    /**
     * @notice Returns a lazily-registered sender that impersonates any account on a local fork.
     * @dev The returned sender works with `sender.harness(target)` during simulation, and its
     *      broadcast path replays the transaction against Anvil via impersonation RPC.
     */
    function prankSender(address account) internal returns (Senders.Sender storage) {
        return Senders.registry().ensureForkPrank(account);
    }

    /**
     * @notice Sets a native balance on the simulation fork and, in fork mode, on the underlying Anvil node.
     */
    function dealFork(address to, uint256 amount) internal {
        uint256 activeFork = vm.activeFork();
        vm.deal(to, amount);
        _syncExecutionFork(activeFork);
        vm.deal(to, amount);
        vm.selectFork(activeFork);
        if (isForkMode) {
            ForkRpc.setBalance(to, amount);
        }
    }

    /**
     * @notice Sets an ERC20 balance on the simulation fork and, in fork mode, on the underlying Anvil node.
     */
    function dealFork(address token, address to, uint256 amount) internal {
        dealFork(token, to, amount, false);
    }

    /**
     * @notice Sets an ERC20 balance and optionally adjusts totalSupply on both fork contexts.
     */
    function dealFork(address token, address to, uint256 amount, bool adjustTotalSupply) internal {
        uint256 activeFork = vm.activeFork();
        uint256 balanceSlot = _balanceSlot(token, to);
        bytes32 storageSlot = ForkStorage.mappingSlot(to, balanceSlot);
        uint256 previousBalance;
        if (adjustTotalSupply) {
            previousBalance = IERC20Balanceable(token).balanceOf(to);
        }
        vm.store(token, storageSlot, bytes32(amount));
        _syncExecutionFork(activeFork);
        vm.store(token, storageSlot, bytes32(amount));
        vm.selectFork(activeFork);
        if (isForkMode) {
            ForkRpc.setStorageAt(token, storageSlot, bytes32(amount));
        }

        if (adjustTotalSupply) {
            uint256 totalSupplySlot = _totalSupplySlot(token);
            uint256 totalSupply = IERC20SupplyBalanceable(token).totalSupply();
            bytes32 totalSupplyStorageSlot = bytes32(totalSupplySlot);
            bytes32 totalSupplyValue = bytes32(totalSupply + amount - previousBalance);
            vm.store(token, totalSupplyStorageSlot, totalSupplyValue);
            _syncExecutionFork(activeFork);
            vm.store(token, totalSupplyStorageSlot, totalSupplyValue);
            vm.selectFork(activeFork);
            if (isForkMode) {
                ForkRpc.setStorageAt(token, totalSupplyStorageSlot, totalSupplyValue);
            }
        }
    }

    /**
     * @notice Writes an arbitrary storage slot on the simulation fork and, in fork mode, on Anvil.
     */
    function storeFork(address target, bytes32 slot, bytes32 value) internal {
        uint256 activeFork = vm.activeFork();
        vm.store(target, slot, value);
        _syncExecutionFork(activeFork);
        vm.store(target, slot, value);
        vm.selectFork(activeFork);
        if (isForkMode) {
            ForkRpc.setStorageAt(target, slot, value);
        }
    }

    /**
     * @notice Etches bytecode on the simulation fork and, in fork mode, on Anvil.
     */
    function etchFork(address target, bytes memory code) internal {
        uint256 activeFork = vm.activeFork();
        vm.etch(target, code);
        _syncExecutionFork(activeFork);
        vm.etch(target, code);
        vm.selectFork(activeFork);
        if (isForkMode) {
            ForkRpc.setCode(target, code);
        }
    }

    function _balanceSlot(address token, address sampleAccount) private returns (uint256 balanceSlot) {
        if (erc20BalanceSlotCached[token]) {
            return erc20BalanceSlots[token];
        }

        balanceSlot = _detectBalanceSlot(token, sampleAccount);
        erc20BalanceSlots[token] = balanceSlot;
        erc20BalanceSlotCached[token] = true;
    }

    function _totalSupplySlot(address token) private returns (uint256 totalSupplySlot) {
        if (erc20TotalSupplySlotCached[token]) {
            return erc20TotalSupplySlots[token];
        }

        totalSupplySlot = _detectTotalSupplySlot(token);
        erc20TotalSupplySlots[token] = totalSupplySlot;
        erc20TotalSupplySlotCached[token] = true;
    }

    function _detectBalanceSlot(address token, address sampleAccount) private returns (uint256) {
        return ForkStorage.detectBalanceSlot(vm, token, sampleAccount);
    }

    function _detectTotalSupplySlot(address token) private returns (uint256) {
        return ForkStorage.detectTotalSupplySlot(vm, token);
    }

    function _syncExecutionFork(uint256 activeFork) private {
        uint256 executionFork = Senders.registry().executionFork;
        if (executionFork != activeFork) {
            vm.selectFork(executionFork);
        }
    }
}
