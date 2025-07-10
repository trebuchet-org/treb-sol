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

    function testLookup() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry("default", "test/fixtures/basic.json");
        // Test that it returns the correct address from basic.json
        assertEq(registry.lookup("Counter"), address(0x1234567890123456789012345678901234567890));
    }

    function testLookupByNamespace() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry("default", "test/fixtures/basic.json");
        // Test that it returns the correct address for staging
        assertEq(registry.lookup("Counter", "staging"), address(0x2345678901234567890123456789012345678901));
    }

    function testLookupNonExistent() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry("default", "test/fixtures/basic.json");
        // Test that lookup returns address(0) for non-existent
        assertEq(registry.lookup("NonExistent"), address(0));
    }

    function testNamespaceOverride() public isolatedEnv("test/fixtures/basic.json", "staging") {
        Registry stagingRegistry = new Registry("staging", "test/fixtures/basic.json");

        // The staging registry should lookup from staging namespace
        assertEq(stagingRegistry.lookup("Counter"), address(0x2345678901234567890123456789012345678901));
    }

    function testMissingDeploymentFile() public isolatedEnv("test/fixtures/non-existent.json", "default") {
        Registry emptyRegistry = new Registry("default", "test/fixtures/non-existent.json");

        // Should return address(0) for non-existent deployments
        assertEq(emptyRegistry.lookup("Counter"), address(0));
    }

    function testMultipleNamespaces() public isolatedEnv("test/fixtures/duplicate-sid.json", "default") {
        Registry dupRegistry = new Registry("default", "test/fixtures/duplicate-sid.json");

        // Test that we can access the same identifier in different namespaces
        assertEq(dupRegistry.lookup("Token"), address(0x1111111111111111111111111111111111111111));
        assertEq(dupRegistry.lookup("Token", "staging"), address(0x2222222222222222222222222222222222222222));
    }

    function testEmptyDeployments() public isolatedEnv("test/fixtures/empty.json", "default") {
        Registry emptyRegistry = new Registry("default", "test/fixtures/empty.json");

        assertEq(emptyRegistry.lookup("Counter"), address(0));
    }

    function testLookupWithFullParams() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry("default", "test/fixtures/basic.json");

        // Test the full three-parameter lookup method
        assertEq(registry.lookup("Counter", "default", "31337"), address(0x1234567890123456789012345678901234567890));
        assertEq(registry.lookup("Counter", "staging", "31337"), address(0x2345678901234567890123456789012345678901));

        // Test non-existent chain ID
        assertEq(registry.lookup("Counter", "default", "1"), address(0));
    }

    function testLookupWithPathWithColumns() public isolatedEnv("test/fixtures/basic.json", "default") {
        registry = new Registry("default", "test/fixtures/basic.json");

        assertEq(
            registry.lookup("ERC1967Proxy:Counter", "staging", "31337"),
            address(0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E)
        );
    }
}
