// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import "../src/internal/sender/Senders.sol";
import {Deployer} from "../src/internal/sender/Deployer.sol";
import {SenderTypes, Transaction} from "../src/internal/types.sol";
import {CREATEX_ADDRESS} from "createx-forge/script/CreateX.d.sol";
import {SendersTestHarness} from "./helpers/SendersTestHarness.sol";

contract SimpleContract {
    uint256 public value;
    
    constructor(uint256 _value) {
        value = _value;
    }
}

contract DeployerEntropyPatternsTest is Test, CreateXScript {
    using Senders for Senders.Sender;
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;
    
    SendersTestHarness harness;
    string constant DEPLOYER = "deployer";
    
    function setUp() public withCreateX {
        // Reset Senders registry to avoid test pollution
        Senders.reset();
        
        // Setup deployer sender
        uint256 privateKey = 0x12345;
        address senderAddr = vm.addr(privateKey);
        vm.deal(senderAddr, 10 ether);
        
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: DEPLOYER,
            account: senderAddr,
            senderType: SenderTypes.InMemory,
            config: abi.encode(privateKey)
        });
        
        harness = new SendersTestHarness(configs);
    }
    
    // Test 1: Artifact-only deployment pattern
    function test_ArtifactOnlyPattern() public {
        // Predict address using artifact-only pattern
        address predicted = harness.predictCreate3ArtifactOnly(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract");
        
        // Deploy using factory pattern with artifact only
        address deployed = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", abi.encode(100));
        
        // Should match
        assertEq(predicted, deployed);
        
        // Verify deployment
        assertEq(SimpleContract(deployed).value(), 100);
    }
    
    // Test 2: Artifact + Label pattern
    function test_ArtifactWithLabelPattern() public {
        // Predict address using artifact + label pattern
        address predicted = harness.predictCreate3WithLabel(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v1");
        
        // Deploy using factory pattern with artifact + label
        address deployed = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v1", abi.encode(200));
        
        // Should match
        assertEq(predicted, deployed);
        
        // Different labels should give different addresses
        address predictedV2 = harness.predictCreate3WithLabel(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v2");
        assertTrue(predicted != predictedV2);
    }
    
    // Test 3: Direct entropy pattern
    function test_DirectEntropyPattern() public {
        bytes memory bytecode = type(SimpleContract).creationCode;
        
        // Deploy with custom entropy using WithEntropy method
        string memory customEntropy = "my-custom-entropy-string";
        address deployed = harness.deployCreate3WithEntropy(DEPLOYER, customEntropy, bytecode, abi.encode(300));
        
        // Predict should match
        address predicted = harness.predictCreate3(DEPLOYER, customEntropy);
        assertEq(deployed, predicted);
        
        // Custom entropy should be different from artifact patterns
        address artifactPredicted = harness.predictCreate3ArtifactOnly(DEPLOYER, customEntropy);
        assertTrue(deployed != artifactPredicted);
    }
    
    // Test 4: Namespace affects entropy
    function test_NamespaceAffectsEntropy() public {
        string memory artifact = "DeployerEntropyPatterns.t.sol:SimpleContract";
        string memory label = "v1";
        
        // Deploy in default namespace
        harness.setNamespace("default");
        address deployedDefault = harness.deployCreate3(DEPLOYER, artifact, label, abi.encode(400));
        
        // Deploy in production namespace
        harness.setNamespace("production");
        address deployedProd = harness.deployCreate3(DEPLOYER, artifact, label, abi.encode(500));
        
        // Should be different addresses
        assertTrue(deployedDefault != deployedProd);
        
        // Verify both deployed correctly
        assertEq(SimpleContract(deployedDefault).value(), 400);
        assertEq(SimpleContract(deployedProd).value(), 500);
    }
    
    // Test 5: Salt generation consistency
    function test_SaltGenerationConsistency() public {
        // Same entropy generates same salt
        bytes32 salt1 = harness._salt(DEPLOYER, "test-entropy");
        bytes32 salt2 = harness._salt(DEPLOYER, "test-entropy");
        assertEq(salt1, salt2);
        
        // Different entropy generates different salt
        bytes32 salt3 = harness._salt(DEPLOYER, "different-entropy");
        assertTrue(salt1 != salt3);
        
        // Namespace affects salt
        harness.setNamespace("production");
        bytes32 salt4 = harness._salt(DEPLOYER, "test-entropy");
        assertTrue(salt1 != salt4);
    }
    
    // Test 6: Empty label behavior
    function test_EmptyLabelBehavior() public view {
        // Artifact with empty label should be same as artifact-only
        address predicted1 = harness.predictCreate3ArtifactOnly(DEPLOYER, "Contract");
        address predicted2 = harness.predictCreate3WithLabel(DEPLOYER, "Contract", "");
        assertEq(predicted1, predicted2);
        
        // Both should equal "Contract:"
        address predicted3 = harness.predictCreate3(DEPLOYER, "Contract:");
        assertEq(predicted1, predicted3);
    }
    
    // Test 7: Complex entropy strings
    function test_ComplexEntropyStrings() public {
        bytes memory bytecode = type(SimpleContract).creationCode;
        
        // Test with special characters
        string memory specialEntropy = "test@#$%^&*()_+-=[]{}|;:',.<>?/";
        address deployed1 = harness.deployCreate3WithEntropy(DEPLOYER, specialEntropy, bytecode, abi.encode(600));
        assertTrue(deployed1 != address(0));
        
        // Test with very long entropy
        string memory longEntropy = "very-long-entropy-string-that-exceeds-normal-length-expectations-and-tests-the-limits-of-the-system";
        address deployed2 = harness.deployCreate3WithEntropy(DEPLOYER, longEntropy, bytecode, abi.encode(700));
        assertTrue(deployed2 != address(0));
        
        // Should be different
        assertTrue(deployed1 != deployed2);
    }
    
    // Test 8: Derived salt behavior
    function test_DerivedSaltBehavior() public view {
        bytes32 baseSalt = harness._salt(DEPLOYER, "test");
        bytes32 derivedSalt = harness._derivedSalt(DEPLOYER, baseSalt);
        
        // Derived salt should be different from base salt
        assertTrue(baseSalt != derivedSalt);
        
        // Derived salt should be consistent
        bytes32 derivedSalt2 = harness._derivedSalt(DEPLOYER, baseSalt);
        assertEq(derivedSalt, derivedSalt2);
    }
    
    // Test 9: Prediction accuracy across all patterns
    function test_PredictionAccuracyAllPatterns() public {
        bytes memory bytecode = type(SimpleContract).creationCode;
        
        // Pattern 1: Direct entropy
        string memory entropy1 = "direct-entropy";
        address predicted1 = harness.predictCreate3(DEPLOYER, entropy1);
        address deployed1 = harness.deployCreate3WithEntropy(DEPLOYER, entropy1, bytecode, abi.encode(800));
        assertEq(predicted1, deployed1);
        
        // Pattern 2: Artifact-only
        address predicted2 = harness.predictCreate3ArtifactOnly(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract");
        address deployed2 = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", abi.encode(900));
        assertEq(predicted2, deployed2);
        
        // Pattern 3: Artifact + label
        address predicted3 = harness.predictCreate3WithLabel(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v2");
        address deployed3 = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v2", abi.encode(1000));
        assertEq(predicted3, deployed3);
        
        // All should be different
        assertTrue(deployed1 != deployed2);
        assertTrue(deployed2 != deployed3);
        assertTrue(deployed1 != deployed3);
    }
    
    // Test 10: Multiple deployments with different patterns don't collide
    function test_MultipleDeploymentPatterns() public {
        // Deploy same artifact with different labels - should get different addresses
        address deployed1 = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v1", abi.encode(1100));
        address deployed2 = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v2", abi.encode(1200));
        
        assertTrue(deployed1 != deployed2);
        
        // Deploy different artifacts - use different entropy for the third one
        bytes memory bytecode = type(SimpleContract).creationCode;
        address deployed3 = harness.deployCreate3WithEntropy(DEPLOYER, "different-contract-v1", bytecode, abi.encode(1300));
        
        assertTrue(deployed1 != deployed3);
        assertTrue(deployed2 != deployed3);
        
        // All should work
        assertEq(SimpleContract(deployed1).value(), 1100);
        assertEq(SimpleContract(deployed2).value(), 1200);
        assertEq(SimpleContract(deployed3).value(), 1300);
    }
    
    // Test 11: Factory pattern validation
    function test_FactoryPatternValidation() public {
        // Use actual factory pattern
        address deployed = harness.deployCreate3(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v1", abi.encode(1200));
        
        // Verify it matches the helper prediction
        address predicted = harness.predictCreate3WithLabel(DEPLOYER, "DeployerEntropyPatterns.t.sol:SimpleContract", "v1");
        assertEq(deployed, predicted);
    }
    
    // Test 12: Entropy edge cases
    function test_EntropyEdgeCases() public view {
        // Empty entropy
        bytes32 emptySalt = harness._salt(DEPLOYER, "");
        assertTrue(emptySalt != bytes32(0));
        
        // Single character
        bytes32 singleSalt = harness._salt(DEPLOYER, "a");
        assertTrue(singleSalt != emptySalt);
        
        // Unicode characters
        bytes32 unicodeSalt = harness._salt(DEPLOYER, unicode"🚀🌙");
        assertTrue(unicodeSalt != emptySalt);
        assertTrue(unicodeSalt != singleSalt);
    }
}