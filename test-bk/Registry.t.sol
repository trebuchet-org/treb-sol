// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Registry} from "../src/internal/Registry.sol";

contract RegistryTest is Test {
    Registry registry;
    uint256 chainId;
    
    modifier isolatedEnv(string memory deploymentFile, string memory namespace) {
        // Set test environment
        vm.setEnv("DEPLOYMENTS_FILE", deploymentFile);
        vm.setEnv("NAMESPACE", namespace);
        
        _;
    }
    
    function setUp() public {
        chainId = block.chainid;
    }
    
    function testGetDeployment() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry();
        // Test that it returns the correct address from basic.json
        assertEq(registry.getDeployment("Counter"), address(0x1234567890123456789012345678901234567890));
    }
    
    function testGetDeploymentByEnv() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry();
        // Test that it returns the correct address for staging
        assertEq(registry.getDeploymentByEnv("Counter", "staging"), address(0x2345678901234567890123456789012345678901));
    }
    
    function testGetFullyQualifiedId() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry();
        string memory fqid = registry.getFullyQualifiedId("Counter");
        string memory expected = string.concat(vm.toString(chainId), "/default/Counter");
        assertEq(fqid, expected);
    }
    
    function testHasDeployment() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry();
        // Test that hasDeployment returns true
        assertTrue(registry.hasDeployment("Counter"));
        
        // Test that it returns false for non-existent
        assertFalse(registry.hasDeployment("NonExistent"));
    }
    
    function testNamespaceOverride() public isolatedEnv("test/fixtures/basic.json", "staging") {
        Registry stagingRegistry = new Registry();
        
        // The staging registry should generate staging FQIDs
        string memory fqid = stagingRegistry.getFullyQualifiedId("Counter");
        assertTrue(vm.contains(fqid, "/staging/"));
    }
    
    function testMissingDeploymentFile() public isolatedEnv("test/fixtures/non-existent.json", "default") {
        Registry emptyRegistry = new Registry();
        
        // Should return address(0) for non-existent deployments
        assertEq(emptyRegistry.getDeployment("Counter"), address(0));
    }
    
    function testDuplicateShortId() public isolatedEnv("test/fixtures/duplicate-sid.json", "default") {
        Registry dupRegistry = new Registry();
        
        // When short IDs conflict, the first one in the JSON should win
        // Let's just verify it loads without error
        assertEq(dupRegistry.getDeployment("Token"), address(0x1111111111111111111111111111111111111111));
    }
    
    function testEmptyDeployments() public isolatedEnv("test/fixtures/empty.json", "default") {
        Registry emptyRegistry = new Registry();
        
        assertEq(emptyRegistry.getDeployment("Counter"), address(0));
    }
}