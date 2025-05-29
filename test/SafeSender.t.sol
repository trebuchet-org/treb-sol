// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SafeSender} from "../src/internal/senders/SafeSender.sol";
import {PrivateKeySender} from "../src/internal/senders/PrivateKeySender.sol";
import {Sender} from "../src/internal/Sender.sol";
import {Dispatcher} from "../src/internal/Dispatcher.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";
import {Safe} from "safe-utils/Safe.sol";

contract SafeSenderTest is Test {
    SafeSender safeSender;
    address safeAddress;
    address proposerAddress;
    uint256 proposerPrivateKey;
    
    function setUp() public {
        vm.setEnv("NAMESPACE", "default");
        vm.setEnv("DEPLOYMENTS_FILE", "test/fixtures/empty.json");
        
        // Generate addresses
        safeAddress = makeAddr("safe");
        (proposerAddress, proposerPrivateKey) = makeAddrAndKey("proposer");
        
        // Setup proposer as a private key sender
        vm.deal(proposerAddress, 100 ether);
        
        // Create sender configs for the Dispatcher
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](1);
        configs.artifacts = new string[](1);
        configs.constructorArgs = new bytes[](1);
        
        configs.ids[0] = "proposer";
        configs.artifacts[0] = "PrivateKeySender.sol:PrivateKeySender";
        configs.constructorArgs[0] = abi.encode(proposerAddress, proposerPrivateKey);
        
        // Encode and set SENDER_CONFIGS
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        // Mock Safe initialization
        vm.mockCall(
            address(0),
            abi.encodeWithSignature("initialize(Safe.Client,address,Safe.Signer)"),
            ""
        );
        
        safeSender = new SafeSender(safeAddress, "proposer");
    }
    
    function testSafeSenderTypes() public {
        assertTrue(safeSender.isType("Safe"));
        assertFalse(safeSender.isType("PrivateKey"));
        assertFalse(safeSender.isType("Ledger"));
        assertFalse(safeSender.isType("Trezor"));
    }
    
    function testSafeSenderAddress() public {
        assertEq(safeSender.senderAddress(), safeAddress);
    }
    
    function testExecuteTransaction() public {
        // Deploy a simple contract to interact with
        address target = address(new MockTarget());
        
        Transaction memory txn = Transaction({
            label: "setValue",
            to: target,
            data: abi.encodeWithSignature("setValue(uint256)", 42),
            value: 0
        });
        
        // Mock the safe proposing transaction
        bytes32 expectedSafeTxHash = keccak256("safeTxHash");
        vm.mockCall(
            address(0),
            abi.encodeWithSignature("proposeTransactions(Safe.Client,address[],bytes[])"),
            abi.encode(expectedSafeTxHash)
        );
        
        BundleTransaction memory result = safeSender.execute(txn);
        
        // Verify the transaction was queued
        assertTrue(result.txId != bytes32(0));
    }
    
    function testExecuteMultipleTransactions() public {
        address target1 = address(new MockTarget());
        address target2 = address(new MockTarget());
        
        Transaction[] memory txns = new Transaction[](2);
        txns[0] = Transaction({
            label: "setValue1",
            to: target1,
            data: abi.encodeWithSignature("setValue(uint256)", 100),
            value: 0
        });
        txns[1] = Transaction({
            label: "setValue2",
            to: target2,
            data: abi.encodeWithSignature("setValue(uint256)", 200),
            value: 0
        });
        
        // Mock the safe proposing transaction
        bytes32 expectedSafeTxHash = keccak256("safeTxHash");
        vm.mockCall(
            address(0),
            abi.encodeWithSignature("proposeTransactions(Safe.Client,address[],bytes[])"),
            abi.encode(expectedSafeTxHash)
        );
        
        BundleTransaction[] memory results = safeSender.execute(txns);
        
        // Verify the transactions were queued
        assertEq(results.length, 2);
        assertTrue(results[0].txId != bytes32(0));
        assertTrue(results[1].txId != bytes32(0));
    }
    
    function testTransactionWithValueReverts() public {
        address target = address(new MockTarget());
        
        Transaction memory txn = Transaction({
            label: "sendEther",
            to: target,
            data: "",
            value: 1 ether
        });
        
        vm.expectRevert(
            abi.encodeWithSelector(SafeSender.SafeTransactionValueNotZero.selector, "sendEther")
        );
        safeSender.execute(txn);
    }
    
    function testRevertWhen_TransactionFails() public {
        address target = address(new MockTarget());
        
        // Try to call a non-existent function
        Transaction memory txn = Transaction({
            label: "nonExistent",
            to: target,
            data: abi.encodeWithSignature("nonExistentFunction()"),
            value: 0
        });
        
        vm.expectRevert(
            abi.encodeWithSelector(Sender.TransactionFailed.selector, "nonExistent")
        );
        safeSender.execute(txn);
    }
    
    function testSafeTransactionQueuedEvent() public {
        address target = address(new MockTarget());
        
        Transaction memory txn = Transaction({
            label: "setValue",
            to: target,
            data: abi.encodeWithSignature("setValue(uint256)", 42),
            value: 0
        });
        
        // Mock the safe proposing transaction
        bytes32 expectedSafeTxHash = keccak256("safeTxHash");
        vm.mockCall(
            address(0),
            abi.encodeWithSignature("proposeTransactions(Safe.Client,address[],bytes[])"),
            abi.encode(expectedSafeTxHash)
        );
        
        // Calculate expected operation ID
        Transaction[] memory txns = new Transaction[](1);
        txns[0] = txn;
        bytes32 expectedOperationId = keccak256(abi.encode(block.timestamp, safeAddress, txns));
        
        vm.expectEmit(true, true, true, true);
        emit SafeSender.SafeTransactionQueued(
            expectedOperationId,
            safeAddress,
            proposerAddress,
            expectedSafeTxHash
        );
        
        safeSender.execute(txn);
    }
    
    function testUnsupportedProposerReverts() public {
        // Create a config with a safe as proposer (not supported)
        Dispatcher.SenderConfigs memory configs;
        configs.ids = new string[](2);
        configs.artifacts = new string[](2);
        configs.constructorArgs = new bytes[](2);
        
        configs.ids[0] = "proposer";
        configs.artifacts[0] = "PrivateKeySender.sol:PrivateKeySender";
        configs.constructorArgs[0] = abi.encode(proposerAddress, proposerPrivateKey);
        
        configs.ids[1] = "safeasproposer";
        configs.artifacts[1] = "SafeSender.sol:SafeSender";
        configs.constructorArgs[1] = abi.encode(address(0x9999), "proposer");
        
        // Encode and set SENDER_CONFIGS
        bytes memory encodedConfigs = abi.encode(configs);
        vm.setEnv("SENDER_CONFIGS", vm.toString(encodedConfigs));
        
        vm.expectRevert(
            abi.encodeWithSelector(SafeSender.ProposerNotSupported.selector, "safeasproposer")
        );
        new SafeSender(safeAddress, "safeasproposer");
    }
}

// Helper contract for testing
contract MockTarget {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    receive() external payable {}
}