// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Registry} from "../src/internal/Registry.sol";

contract RegistryTest is Test {
    Registry registry;
    
    function setUp() public {
        // Use basic fixture for most tests
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/basic.json");
        vm.setEnv("NAMESPACE", "default");
        registry = new Registry();
    }
    
    function testGetDeployment() public view {
        address deployment = registry.getDeployment("Counter");
        assertEq(deployment, 0x1234567890123456789012345678901234567890);
    }
    
    function testGetDeploymentByEnv() public view {
        address deployment = registry.getDeploymentByEnv("Counter", "staging");
        assertEq(deployment, 0x2345678901234567890123456789012345678901);
    }
    
    function testHasDeployment() public view {
        assertTrue(registry.hasDeployment("Counter"));
        assertFalse(registry.hasDeployment("NonExistent"));
    }
    
    function testGetFullyQualifiedId() public view {
        string memory fqid = registry.getFullyQualifiedId("Counter");
        assertEq(fqid, "31337/default/Counter");
    }
    
    function testMissingDeploymentFile() public {
        // Use a non-existent file
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/non-existent.json");
        Registry emptyRegistry = new Registry();
        assertEq(emptyRegistry.getDeployment("Counter"), address(0));
    }
    
    function testNamespaceOverride() public {
        // Use basic fixture with staging namespace
        vm.setEnv("NAMESPACE", "staging");
        Registry stagingRegistry = new Registry();
        
        // Should look for staging namespace by default
        // Since both have same short ID "Counter", staging should have address(0) due to duplicate
        address deployment = stagingRegistry.getDeployment("Counter");
        assertEq(deployment, address(0));
        
        // But should be able to get by full ID
        string memory fqid = stagingRegistry.getFullyQualifiedId("Counter");
        assertEq(fqid, "31337/staging/Counter");
    }
    
    function testDuplicateShortId() public {
        // Use duplicate sid fixture
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/duplicate-sid.json");
        Registry dupRegistry = new Registry();
        
        // When short IDs conflict, it should return address(0)
        assertEq(dupRegistry.getDeployment("Token"), address(0));
    }
    
    function testEmptyDeployments() public {
        // Use empty fixture
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/empty.json");
        Registry emptyRegistry = new Registry();
        
        assertEq(emptyRegistry.getDeployment("Counter"), address(0));
    }
}