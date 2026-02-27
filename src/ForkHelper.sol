// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";

interface IERC20Balanceable {
    function balanceOf(address account) external view returns (uint256);
}

interface ISafeOwnerManager {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function isOwner(address owner) external view returns (bool);
}

/**
 * @title ForkHelper
 * @author Trebuchet
 * @notice Utility contract providing common fork setup tasks using Foundry cheatcodes
 * @dev Designed to be inherited by SetupFork scripts that run on local forks of live networks.
 *      All functions use anvil/forge cheatcodes (vm.store, vm.deal) and require running on a
 *      local fork environment.
 *
 *      Provides three main utilities:
 *      - Safe multisig conversion to single-owner for fork testing
 *      - Native token balance manipulation
 *      - ERC20 token balance manipulation with auto-detection of storage layout
 *
 *      Usage:
 *      ```solidity
 *      contract SetupFork is ForkHelper, TrebScript {
 *          function run() public broadcast {
 *              convertSafeToSingleOwner(mySafe, myEOA);
 *              dealNativeToken(myEOA, 100 ether);
 *              dealERC20(usdcAddress, myEOA, 1000e6);
 *          }
 *      }
 *      ```
 */
abstract contract ForkHelper is CommonBase {
    /// @dev Sentinel value used by Safe's owner linked list (OwnerManager.sol)
    address private constant SENTINEL_OWNERS = address(0x1);

    /// @dev Storage slot for Safe's owners mapping (from SafeStorage.sol layout)
    uint256 private constant SAFE_OWNERS_SLOT = 2;

    /// @dev Storage slot for Safe's ownerCount
    uint256 private constant SAFE_OWNER_COUNT_SLOT = 3;

    /// @dev Storage slot for Safe's threshold
    uint256 private constant SAFE_THRESHOLD_SLOT = 4;

    /// @dev Maximum number of storage slots to probe for ERC20 balanceOf mapping
    uint256 private constant MAX_BALANCE_SLOT_PROBE = 10;

    /// @notice Reverts when the ERC20 balanceOf storage slot cannot be auto-detected
    error ERC20BalanceSlotNotFound(address token);

    /**
     * @notice Converts a Safe multisig to a single-owner 1/1 configuration
     * @dev Uses vm.store to directly rewrite Safe storage, bypassing access controls.
     *      Rewrites the owner linked list to contain only newOwner, sets ownerCount to 1
     *      and threshold to 1. This makes the Safe act as a regular EOA for fork testing.
     *
     *      Safe owner storage layout (from OwnerManager.sol / SafeStorage.sol):
     *      - owners mapping at slot 2: linked list where owners[sentinel] -> first -> ... -> sentinel
     *      - ownerCount at slot 3
     *      - threshold at slot 4
     *
     * @param safe The address of the Safe proxy contract
     * @param newOwner The address to set as the sole owner
     */
    function convertSafeToSingleOwner(address safe, address newOwner) internal {
        require(newOwner != address(0) && newOwner != SENTINEL_OWNERS, "ForkHelper: invalid owner");

        // Read existing owners to clear their linked list entries
        address[] memory currentOwners = ISafeOwnerManager(safe).getOwners();

        // Clear all existing owner mapping entries
        for (uint256 i = 0; i < currentOwners.length; i++) {
            bytes32 ownerSlot = _getMappingSlot(currentOwners[i], SAFE_OWNERS_SLOT);
            vm.store(safe, ownerSlot, bytes32(0));
        }

        // Set up new single-owner linked list: sentinel -> newOwner -> sentinel
        bytes32 sentinelSlot = _getMappingSlot(SENTINEL_OWNERS, SAFE_OWNERS_SLOT);
        vm.store(safe, sentinelSlot, bytes32(uint256(uint160(newOwner))));

        bytes32 newOwnerSlot = _getMappingSlot(newOwner, SAFE_OWNERS_SLOT);
        vm.store(safe, newOwnerSlot, bytes32(uint256(uint160(SENTINEL_OWNERS))));

        // Set ownerCount = 1
        vm.store(safe, bytes32(SAFE_OWNER_COUNT_SLOT), bytes32(uint256(1)));

        // Set threshold = 1
        vm.store(safe, bytes32(SAFE_THRESHOLD_SLOT), bytes32(uint256(1)));
    }

    /**
     * @notice Sets the native token (ETH) balance of an address
     * @dev Wrapper around vm.deal(to, amount) for convenience and readability in fork setup scripts.
     * @param to The address to receive the native tokens
     * @param amount The balance to set (replaces current balance, does not add to it)
     */
    function dealNativeToken(address to, uint256 amount) internal {
        vm.deal(to, amount);
    }

    /**
     * @notice Sets the ERC20 token balance of an address
     * @dev Uses vm.store to directly write the balanceOf mapping storage slot.
     *      Auto-detects the storage slot by probing common layouts (slot 0 and slot 1
     *      are most common, but probes up to slot 9 for broader compatibility).
     *
     *      The detection works by:
     *      1. Writing a distinctive test value to the candidate slot
     *      2. Calling balanceOf() to check if it reflects the change
     *      3. If matched, writing the desired amount
     *      4. If not matched, restoring the original value and trying the next candidate
     *
     *      Supports most standard ERC20 implementations (OpenZeppelin, Solmate, etc.)
     *      where the balanceOf mapping is at a low storage slot.
     *
     * @param token The ERC20 token contract address
     * @param to The address to set the balance for
     * @param amount The token balance to set
     */
    function dealERC20(address token, address to, uint256 amount) internal {
        for (uint256 candidateSlot = 0; candidateSlot < MAX_BALANCE_SLOT_PROBE; candidateSlot++) {
            bytes32 storageKey = _getMappingSlot(to, candidateSlot);
            bytes32 oldValue = vm.load(token, storageKey);

            // Write a distinctive test value unlikely to match any real balance
            uint256 testValue = uint256(keccak256(abi.encode("ForkHelper.dealERC20.probe", candidateSlot)));
            vm.store(token, storageKey, bytes32(testValue));

            // Check if balanceOf reflects the change
            if (IERC20Balanceable(token).balanceOf(to) == testValue) {
                // Found the right slot - write the actual desired amount
                vm.store(token, storageKey, bytes32(amount));
                return;
            }

            // Restore original value and try next slot
            vm.store(token, storageKey, oldValue);
        }

        revert ERC20BalanceSlotNotFound(token);
    }

    /**
     * @dev Computes the storage slot for a Solidity mapping entry.
     *      For mapping(address => T) at base slot N, the value for key K is at keccak256(abi.encode(K, N)).
     * @param key The mapping key (address)
     * @param baseSlot The base storage slot of the mapping declaration
     * @return The computed storage slot
     */
    function _getMappingSlot(address key, uint256 baseSlot) private pure returns (bytes32) {
        return keccak256(abi.encode(key, baseSlot));
    }
}
