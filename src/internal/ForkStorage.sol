// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

interface IERC20Balanceable {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20SupplyBalanceable is IERC20Balanceable {
    function totalSupply() external view returns (uint256);
}

library ForkStorage {
    uint256 internal constant MAX_BALANCE_SLOT_PROBE = 10;

    error ERC20BalanceSlotNotFound(address token);
    error ERC20TotalSupplySlotNotFound(address token);

    function detectBalanceSlot(Vm vm, address token, address sampleAccount) internal returns (uint256) {
        for (uint256 candidateSlot = 0; candidateSlot < MAX_BALANCE_SLOT_PROBE; candidateSlot++) {
            bytes32 storageKey = mappingSlot(sampleAccount, candidateSlot);
            bytes32 oldValue = vm.load(token, storageKey);

            uint256 testValue = uint256(keccak256(abi.encode("TrebForkScript.dealFork.probe", candidateSlot)));
            vm.store(token, storageKey, bytes32(testValue));

            if (IERC20Balanceable(token).balanceOf(sampleAccount) == testValue) {
                vm.store(token, storageKey, oldValue);
                return candidateSlot;
            }

            vm.store(token, storageKey, oldValue);
        }

        revert ERC20BalanceSlotNotFound(token);
    }

    function detectTotalSupplySlot(Vm vm, address token) internal returns (uint256) {
        for (uint256 candidateSlot = 0; candidateSlot < MAX_BALANCE_SLOT_PROBE; candidateSlot++) {
            bytes32 storageKey = bytes32(candidateSlot);
            bytes32 oldValue = vm.load(token, storageKey);

            uint256 testValue = uint256(keccak256(abi.encode("TrebForkScript.totalSupply.probe", candidateSlot)));
            vm.store(token, storageKey, bytes32(testValue));

            if (IERC20SupplyBalanceable(token).totalSupply() == testValue) {
                vm.store(token, storageKey, oldValue);
                return candidateSlot;
            }

            vm.store(token, storageKey, oldValue);
        }

        revert ERC20TotalSupplySlotNotFound(token);
    }

    function mappingSlot(address key, uint256 baseSlot) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, baseSlot));
    }
}
