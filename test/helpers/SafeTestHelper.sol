// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Safe} from "safe-utils/Safe.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";

contract SafeTestHelper {
    Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    
    // Deploy MultiSendCallOnly at the expected address for local testing
    function deployMultiSendCallOnly() public {
        // Deploy MultiSendCallOnly at canonical address for local chain
        address canonicalAddr = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
        
        // Check if already deployed
        if (canonicalAddr.code.length > 0) {
            return;
        }
        
        // Deploy the contract
        MultiSendCallOnly multiSend = new MultiSendCallOnly();
        
        // Etch it at the canonical address
        vm.etch(canonicalAddr, address(multiSend).code);
    }
    
    // Mock HTTP responses for Safe API
    function mockSafeApiResponses() public {
        // This would need to mock the HTTP calls made by safe-utils
        // For now, we'll need to skip these tests or use a different approach
    }
}