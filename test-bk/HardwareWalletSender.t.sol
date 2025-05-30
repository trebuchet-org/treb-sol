// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {LedgerSender, TrezorSender, HardwareWalletSender} from "../src/internal/senders/HardwareWalletSender.sol";
import {Transaction, BundleTransaction, BundleStatus} from "../src/internal/types.sol";

contract HardwareWalletSenderTest is Test {
    LedgerSender ledgerSender;
    TrezorSender trezorSender;
    
    address senderAddress;
    uint256 privateKey;
    uint256 constant MNEMONIC_INDEX = 0;
    string constant DERIVATION_PATH = "m/44'/60'/0'/0/0";
    
    uint256 simulationForkId;
    uint256 executionForkId;
    
    function setUp() public {
        vm.setEnv("NAMESPACE", "default");
        
        // Create forks
        string memory network = vm.envOr("NETWORK", string("anvil"));
        simulationForkId = vm.createFork(network);
        executionForkId = vm.createFork(network);
        vm.selectFork(simulationForkId);
        
        // Generate address/key pair
        (senderAddress, privateKey) = makeAddrAndKey("hardware-wallet");
        
        // Fund the sender
        vm.deal(senderAddress, 100 ether);
        
        ledgerSender = new LedgerSender(senderAddress, privateKey, DERIVATION_PATH);
        trezorSender = new TrezorSender(senderAddress, privateKey, DERIVATION_PATH);
        
        ledgerSender.initialize(simulationForkId, executionForkId);
        trezorSender.initialize(simulationForkId, executionForkId);
    }
    
    function testLedgerSenderTypes() public {
        assertTrue(ledgerSender.isType("Ledger"));
        assertFalse(ledgerSender.isType("Trezor"));
        assertFalse(ledgerSender.isType("Safe"));
        assertEq(ledgerSender.senderType(), bytes4(keccak256("Ledger")));
    }
    
    function testTrezorSenderTypes() public {
        assertTrue(trezorSender.isType("Trezor"));
        assertFalse(trezorSender.isType("Ledger"));
        assertFalse(trezorSender.isType("Safe"));
        assertEq(trezorSender.senderType(), bytes4(keccak256("Trezor")));
    }
    
    function testDerivationPath() public {
        assertEq(ledgerSender.derivationPath(), DERIVATION_PATH);
        assertEq(trezorSender.derivationPath(), DERIVATION_PATH);
    }
    
    function testLedgerExecuteTransaction() public {
        // Deploy a simple contract to interact with
        MockTarget target = new MockTarget();
        
        Transaction memory txn = Transaction({
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSignature("setValue(uint256)", 42),
            value: 0
        });
        
        // Hardware wallet execution is simulated the same as private key
        BundleTransaction memory result = ledgerSender.execute(txn);
        
        // Verify the transaction was executed
        assertTrue(result.txId != bytes32(0));
        
        // Verify the value was set
        assertEq(target.value(), 42);
    }
    
    function testTrezorExecuteTransaction() public {
        MockTarget target = new MockTarget();
        
        Transaction memory txn = Transaction({
            label: "setValue",
            to: address(target),
            data: abi.encodeWithSignature("setValue(uint256)", 99),
            value: 0
        });
        
        BundleTransaction memory result = trezorSender.execute(txn);
        
        // Verify the transaction was executed
        assertTrue(result.txId != bytes32(0));
        assertEq(target.value(), 99);
    }
    
    function testDifferentDerivationPaths() public {
        string memory customPath = "m/44'/60'/0'/0/1";
        LedgerSender customLedger = new LedgerSender(senderAddress, privateKey, customPath);
        
        assertEq(customLedger.derivationPath(), customPath);
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