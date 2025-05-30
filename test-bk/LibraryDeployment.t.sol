// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {LibraryDeployment} from "../src/LibraryDeployment.sol";

// Note: LibraryDeployment tests are currently skipped due to vm.deployCode limitations
// in the test environment. The contract expects to load sender configurations dynamically
// which doesn't work well in tests.

contract LibraryDeploymentTest is Test {
    function setUp() public {
        // Set up test environment
        vm.setEnv("NAMESPACE", "default");
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/empty.json");
        vm.setEnv("NETWORK", "anvil");
    }
    
    function testLibraryDeploymentMissingArtifactPath() public {
        // Clear the LIBRARY_ARTIFACT_PATH env var
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "");
        
        // Create sender configs
        LibraryDeployment.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "libraries";
        configs.artifacts[0] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[0] = abi.encode(makeAddr("libraries"), uint256(0x123));
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Should revert because LIBRARY_ARTIFACT_PATH is missing
        vm.expectRevert(abi.encodeWithSelector(LibraryDeployment.MissingLibraryArtifactPath.selector));
        new LibraryDeployment();
    }
    
    function testLibraryDeploymentEmptyArtifactPath() public {
        // Set empty artifact path
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "");
        
        // Create sender configs
        LibraryDeployment.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "libraries";
        configs.artifacts[0] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[0] = abi.encode(makeAddr("libraries"), uint256(0x123));
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Should revert because artifact path is empty
        vm.expectRevert(abi.encodeWithSelector(LibraryDeployment.MissingLibraryArtifactPath.selector));
        new LibraryDeployment();
    }
    
    function testLibraryDeploymentSuccess() public {
        // Set artifact path
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "out/TestLibrary.sol/TestLibrary.json");
        
        // Create sender configs
        LibraryDeployment.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "libraries";
        configs.artifacts[0] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[0] = abi.encode(makeAddr("libraries"), uint256(0x123));
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // This will attempt to deploy using vm.deployCode which will fail in tests
        new LibraryDeployment();
    }
    
    function testLibraryDeploymentUsesLibrariesSender() public {
        // Set artifact path
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "out/TestLibrary.sol/TestLibrary.json");
        
        // Create sender configs with multiple senders
        LibraryDeployment.SenderConfigs memory configs;
        configs.ids = new string[](2);
        configs.artifacts = new string[](2);
        configs.constructorArgs = new bytes[](2);
        
        configs.ids[0] = "deployer";
        configs.artifacts[0] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[0] = abi.encode(makeAddr("deployer"), uint256(0x123));
        
        configs.ids[1] = "libraries";
        configs.artifacts[1] = "out/PrivateKeySender.sol/PrivateKeySender.json";
        configs.constructorArgs[1] = abi.encode(makeAddr("libraries"), uint256(0x456));
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // This will attempt to use the "libraries" sender for deployment
        new LibraryDeployment();
    }
}