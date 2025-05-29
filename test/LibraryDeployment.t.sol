// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {LibraryDeployment} from "../src/LibraryDeployment.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Deployer} from "../src/internal/Deployer.sol";
import {Sender} from "../src/internal/Sender.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";

// Mock library for testing
library MockLibrary {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }
}

// Concrete implementation for testing
contract TestLibraryDeployment is LibraryDeployment {
    // LibraryDeployment already implements run()
}

// Mock Sender that returns pre-configured library address
contract MockLibrarySender is Sender {
    address public deployedLibrary;
    
    constructor(address _sender, address _deployedLibrary) Sender(_sender) {
        deployedLibrary = _deployedLibrary;
    }
    
    function senderType() public pure override returns (bytes4) {
        return bytes4(keccak256("Mock"));
    }
    
    function _execute(Transaction[] memory _transactions) internal view override returns (BundleStatus status, bytes[] memory returnDatas) {
        status = BundleStatus.EXECUTED;
        returnDatas = new bytes[](_transactions.length);
        
        for (uint256 i = 0; i < _transactions.length; i++) {
            // Return the pre-configured library address
            returnDatas[i] = abi.encode(deployedLibrary);
        }
    }
}

contract LibraryDeploymentTest is Test, CreateXScript {
    TestLibraryDeployment libraryDeployment;
    address constant LIBRARY_ADDRESS = address(0x1234567890);
    address constant DEPLOYER_ADDRESS = address(0x9999);
    
    function setUp() public withCreateX {
        vm.setEnv("NAMESPACE", "default");
        
        // Create registry deployments file
        string memory json = '{"networks":{"31337":{"deployments":{}}}}';
        vm.writeFile("deployments.json", json);
    }
    
    function testLibraryDeploymentSuccess() public {
        // Set library artifact path
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "MockLibrary.sol:MockLibrary");
        
        // Create sender configs with library deployer
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "libraries";
        configs.artifacts[0] = "MockLibrarySender.sol:MockLibrarySender";
        configs.constructorArgs[0] = abi.encode(DEPLOYER_ADDRESS, LIBRARY_ADDRESS);
        
        // Deploy the mock sender bytecode
        bytes memory senderBytecode = type(MockLibrarySender).creationCode;
        bytes memory senderArgs = abi.encode(DEPLOYER_ADDRESS, LIBRARY_ADDRESS);
        bytes memory fullBytecode = abi.encodePacked(senderBytecode, senderArgs);
        
        // Calculate the deployment address
        address expectedAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.etch(expectedAddr, fullBytecode);
        
        // Set SENDER_CONFIGS
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Deploy LibraryDeployment
        libraryDeployment = new TestLibraryDeployment();
        
        // Run deployment
        address deployedAddress = libraryDeployment.run();
        assertEq(deployedAddress, LIBRARY_ADDRESS);
    }
    
    function testLibraryDeploymentMissingArtifactPath() public {
        // Don't set LIBRARY_ARTIFACT_PATH
        
        // Set minimal sender configs to pass Dispatcher
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        vm.expectRevert("LIBRARY_ARTIFACT_PATH is not set");
        new TestLibraryDeployment();
    }
    
    function testLibraryDeploymentEmptyArtifactPath() public {
        // Set empty LIBRARY_ARTIFACT_PATH
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "");
        
        // Set minimal sender configs to pass Dispatcher
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](0);
        configs.artifacts = new string[](0);
        configs.constructorArgs = new bytes[](0);
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        vm.expectRevert("LIBRARY_ARTIFACT_PATH is not set");
        new TestLibraryDeployment();
    }
    
    function testLibraryDeploymentUsesLibrariesSender() public {
        vm.setEnv("LIBRARY_ARTIFACT_PATH", "MockLibrary.sol:MockLibrary");
        
        // Create sender configs with different senders
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](2);
        configs.artifacts = new string[](2);
        configs.constructorArgs = new bytes[](2);
        
        // Libraries sender
        configs.ids[0] = "libraries";
        configs.artifacts[0] = "MockLibrarySender.sol:MockLibrarySender";
        configs.constructorArgs[0] = abi.encode(DEPLOYER_ADDRESS, LIBRARY_ADDRESS);
        
        // Another sender
        configs.ids[1] = "other";
        configs.artifacts[1] = "MockLibrarySender.sol:MockLibrarySender";
        configs.constructorArgs[1] = abi.encode(address(0x5555), address(0x6666));
        
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        libraryDeployment = new TestLibraryDeployment();
        
        // Should use the "libraries" sender and return its configured address
        address deployedAddress = libraryDeployment.run();
        assertEq(deployedAddress, LIBRARY_ADDRESS);
    }
}