// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TrebForkScript} from "../src/TrebForkScript.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {Transaction, SimulatedTransaction, SenderTypes} from "../src/internal/types.sol";
import {Safe} from "safe-smart-account/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/proxies/SafeProxyFactory.sol";

contract TrebForkScriptTarget {
    uint256 public value;

    function setValue(uint256 newValue) external returns (uint256) {
        value = newValue;
        return newValue;
    }
}

contract TrebForkScriptTokenSlot0 {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
}

contract TrebForkScriptTokenSlot1 {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
}

contract TrebForkScriptHarness is TrebForkScript {
    using Senders for Senders.Sender;

    function executeAs(address account, Transaction memory txn) external returns (SimulatedTransaction memory) {
        return prankSender(account).execute(txn);
    }

    function convertSafe(address safe, address newOwner) external {
        convertSafeToSingleOwner(safe, newOwner);
    }

    function harnessAs(address account, address target) external returns (address) {
        return prankSender(account).harness(target);
    }

    function dealNative(address to, uint256 amount) external {
        dealFork(to, amount);
    }

    function dealToken(address token, address to, uint256 amount) external {
        dealFork(token, to, amount);
    }

    function dealToken(address token, address to, uint256 amount, bool adjustTotalSupply) external {
        dealFork(token, to, amount, adjustTotalSupply);
    }

    function etchCode(address target, bytes memory code) external {
        etchFork(target, code);
    }

    function broadcastAll() external {
        _broadcast();
    }
}

contract TrebForkScriptTest is Test {
    TrebForkScriptHarness internal script;
    TrebForkScriptTarget internal target;
    Safe internal safeMasterCopy;
    SafeProxyFactory internal safeFactory;

    bytes32 constant salt = keccak256("TrebForkScriptTest");

    function setUp() public {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "bootstrap",
            account: vm.addr(0xB00757A),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(uint256(0xB00757A))
        });

        vm.setEnv("SENDER_CONFIGS", vm.toString(abi.encode(configs)));
        vm.setEnv("NAMESPACE", "default");
        vm.setEnv("NETWORK", "sepolia");
        vm.setEnv("REGISTRY_FILE", ".treb/registry.json");
        vm.setEnv("ADDRESSBOOK_FILE", ".treb/addressbook.json");
        vm.setEnv("DRYRUN", "false");
        vm.setEnv("QUIET", "true");
        vm.setEnv("TREB_FORK_MODE", "false");

        script = new TrebForkScriptHarness();
        target = new TrebForkScriptTarget();
        safeMasterCopy = new Safe{salt: salt}();
        safeFactory = new SafeProxyFactory{salt: salt}();
    }

    function test_convertSafeToSingleOwner_singleOwner() public {
        address originalOwner = makeAddr("originalOwner");
        address newOwner = makeAddr("newOwner");

        Safe safe = _deploySafe(_toArray(originalOwner), 1);

        assertEq(safe.getThreshold(), 1);
        assertTrue(safe.isOwner(originalOwner));
        assertFalse(safe.isOwner(newOwner));

        script.convertSafe(address(safe), newOwner);

        assertEq(safe.getThreshold(), 1);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], newOwner);
        assertTrue(safe.isOwner(newOwner));
        assertFalse(safe.isOwner(originalOwner));
    }

    function test_convertSafeToSingleOwner_multipleOwners() public {
        address owner1 = makeAddr("owner1");
        address owner2 = makeAddr("owner2");
        address owner3 = makeAddr("owner3");
        address newOwner = makeAddr("newOwner");

        address[] memory initialOwners = new address[](3);
        initialOwners[0] = owner1;
        initialOwners[1] = owner2;
        initialOwners[2] = owner3;

        Safe safe = _deploySafe(initialOwners, 2);

        assertEq(safe.getThreshold(), 2);
        assertEq(safe.getOwners().length, 3);

        script.convertSafe(address(safe), newOwner);

        assertEq(safe.getThreshold(), 1);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], newOwner);
        assertTrue(safe.isOwner(newOwner));
        assertFalse(safe.isOwner(owner1));
        assertFalse(safe.isOwner(owner2));
        assertFalse(safe.isOwner(owner3));
    }

    function test_convertSafeToSingleOwner_replaceWithExistingOwner() public {
        address owner1 = makeAddr("owner1");
        address owner2 = makeAddr("owner2");

        address[] memory initialOwners = new address[](2);
        initialOwners[0] = owner1;
        initialOwners[1] = owner2;

        Safe safe = _deploySafe(initialOwners, 2);

        script.convertSafe(address(safe), owner1);

        assertEq(safe.getThreshold(), 1);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], owner1);
        assertTrue(safe.isOwner(owner1));
        assertFalse(safe.isOwner(owner2));
    }

    function test_convertSafeToSingleOwner_revert_zeroAddress() public {
        Safe safe = _deploySafe(_toArray(makeAddr("owner")), 1);

        vm.expectRevert("TrebForkScript: invalid owner");
        script.convertSafe(address(safe), address(0));
    }

    function test_convertSafeToSingleOwner_revert_sentinelAddress() public {
        Safe safe = _deploySafe(_toArray(makeAddr("owner")), 1);

        vm.expectRevert("TrebForkScript: invalid owner");
        script.convertSafe(address(safe), address(0x1));
    }

    function test_prankSender_executesTransactions() public {
        address prankAccount = makeAddr("fork-prank");
        Transaction memory txn =
            Transaction({to: address(target), data: abi.encodeCall(target.setValue, (42)), value: 0});

        SimulatedTransaction memory simulatedTx = script.executeAs(prankAccount, txn);

        assertEq(target.value(), 42);
        assertEq(simulatedTx.sender, prankAccount);
        assertEq(abi.decode(simulatedTx.returnData, (uint256)), 42);
    }

    function test_prankSender_harnessReusesSenderHarness() public {
        address prankAccount = makeAddr("fork-prank");
        address harnessA = script.harnessAs(prankAccount, address(target));
        address harnessB = script.harnessAs(prankAccount, address(target));

        assertEq(harnessA, harnessB);

        TrebForkScriptTarget(harnessA).setValue(77);
        assertEq(target.value(), 77);
    }

    function test_dealFork_setsNativeBalance() public {
        address recipient = makeAddr("recipient");

        script.dealNative(recipient, 5 ether);

        assertEq(recipient.balance, 5 ether);
    }

    function test_dealFork_setsERC20BalanceAcrossCommonLayouts() public {
        address recipient = makeAddr("recipient");
        address other = makeAddr("other");
        TrebForkScriptTokenSlot0 token0 = new TrebForkScriptTokenSlot0();
        TrebForkScriptTokenSlot1 token1 = new TrebForkScriptTokenSlot1();

        script.dealToken(address(token0), recipient, 123);
        script.dealToken(address(token0), other, 456);
        script.dealToken(address(token1), recipient, 789);

        assertEq(token0.balanceOf(recipient), 123);
        assertEq(token0.balanceOf(other), 456);
        assertEq(token1.balanceOf(recipient), 789);
    }

    function test_dealFork_adjustsTotalSupplyWhenRequested() public {
        address recipient = makeAddr("recipient");
        address other = makeAddr("other");
        TrebForkScriptTokenSlot0 token = new TrebForkScriptTokenSlot0();

        script.dealToken(address(token), recipient, 100, true);
        script.dealToken(address(token), other, 40, true);
        script.dealToken(address(token), recipient, 70, true);

        assertEq(token.balanceOf(recipient), 70);
        assertEq(token.balanceOf(other), 40);
        assertEq(token.totalSupply(), 110);
    }

    function _deploySafe(address[] memory owners, uint256 threshold) internal returns (Safe) {
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            threshold,
            address(0),
            bytes(""),
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        return Safe(payable(safeFactory.createProxyWithNonce(address(safeMasterCopy), initializer, uint256(salt))));
    }

    function _toArray(address owner) internal pure returns (address[] memory owners) {
        owners = new address[](1);
        owners[0] = owner;
    }
}
