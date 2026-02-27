// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ForkHelper, ISafeOwnerManager, IERC20Balanceable} from "../src/ForkHelper.sol";
import {Safe} from "safe-smart-account/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/proxies/SafeProxyFactory.sol";

/// @dev Minimal ERC20 with balanceOf mapping at slot 0 (after no other state variables)
contract MockERC20Slot0 {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @dev ERC20 with balanceOf mapping at slot 1 (one state variable before it)
contract MockERC20Slot1 {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @dev Concrete contract exposing ForkHelper internals for testing
contract ForkHelperHarness is ForkHelper, Test {
    function callConvertSafeToSingleOwner(address safe, address newOwner) external {
        convertSafeToSingleOwner(safe, newOwner);
    }

    function callDealNativeToken(address to, uint256 amount) external {
        dealNativeToken(to, amount);
    }

    function callDealERC20(address token, address to, uint256 amount) external {
        dealERC20(token, to, amount);
    }
}

contract ForkHelperTest is Test {
    ForkHelperHarness harness;

    // Safe contracts
    Safe safeMasterCopy;
    SafeProxyFactory safeFactory;

    bytes32 constant salt = keccak256("ForkHelperTest");

    function setUp() public {
        harness = new ForkHelperHarness();

        // Deploy Safe infrastructure
        safeMasterCopy = new Safe{salt: salt}();
        safeFactory = new SafeProxyFactory{salt: salt}();
    }

    // =========================================================================
    // convertSafeToSingleOwner tests
    // =========================================================================

    function test_convertSafeToSingleOwner_singleOwner() public {
        // Deploy a Safe with 1 owner
        address originalOwner = makeAddr("originalOwner");
        address newOwner = makeAddr("newOwner");

        Safe safe = _deploySafe(_toArray(originalOwner), 1);

        // Verify initial state
        assertEq(safe.getThreshold(), 1);
        assertTrue(safe.isOwner(originalOwner));
        assertFalse(safe.isOwner(newOwner));

        // Convert to single owner
        harness.callConvertSafeToSingleOwner(address(safe), newOwner);

        // Verify conversion
        assertEq(safe.getThreshold(), 1);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], newOwner);
        assertTrue(safe.isOwner(newOwner));
        assertFalse(safe.isOwner(originalOwner));
    }

    function test_convertSafeToSingleOwner_multipleOwners() public {
        // Deploy a Safe with 3 owners and threshold 2
        address owner1 = makeAddr("owner1");
        address owner2 = makeAddr("owner2");
        address owner3 = makeAddr("owner3");
        address newOwner = makeAddr("newOwner");

        address[] memory initialOwners = new address[](3);
        initialOwners[0] = owner1;
        initialOwners[1] = owner2;
        initialOwners[2] = owner3;

        Safe safe = _deploySafe(initialOwners, 2);

        // Verify initial state
        assertEq(safe.getThreshold(), 2);
        assertEq(safe.getOwners().length, 3);

        // Convert to single owner
        harness.callConvertSafeToSingleOwner(address(safe), newOwner);

        // Verify conversion
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
        // Deploy a Safe with 2 owners, convert to just one of them
        address owner1 = makeAddr("owner1");
        address owner2 = makeAddr("owner2");

        address[] memory initialOwners = new address[](2);
        initialOwners[0] = owner1;
        initialOwners[1] = owner2;

        Safe safe = _deploySafe(initialOwners, 2);

        // Convert to owner1 only
        harness.callConvertSafeToSingleOwner(address(safe), owner1);

        // Verify
        assertEq(safe.getThreshold(), 1);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], owner1);
        assertTrue(safe.isOwner(owner1));
        assertFalse(safe.isOwner(owner2));
    }

    function test_convertSafeToSingleOwner_revert_zeroAddress() public {
        Safe safe = _deploySafe(_toArray(makeAddr("owner")), 1);

        vm.expectRevert("ForkHelper: invalid owner");
        harness.callConvertSafeToSingleOwner(address(safe), address(0));
    }

    function test_convertSafeToSingleOwner_revert_sentinelAddress() public {
        Safe safe = _deploySafe(_toArray(makeAddr("owner")), 1);

        vm.expectRevert("ForkHelper: invalid owner");
        harness.callConvertSafeToSingleOwner(address(safe), address(0x1));
    }

    // =========================================================================
    // dealNativeToken tests
    // =========================================================================

    function test_dealNativeToken_setsBalance() public {
        address recipient = makeAddr("recipient");
        assertEq(recipient.balance, 0);

        harness.callDealNativeToken(recipient, 100 ether);

        assertEq(recipient.balance, 100 ether);
    }

    function test_dealNativeToken_replacesExistingBalance() public {
        address recipient = makeAddr("recipient");
        vm.deal(recipient, 50 ether);
        assertEq(recipient.balance, 50 ether);

        harness.callDealNativeToken(recipient, 10 ether);

        assertEq(recipient.balance, 10 ether);
    }

    function test_dealNativeToken_zeroAmount() public {
        address recipient = makeAddr("recipient");
        vm.deal(recipient, 100 ether);

        harness.callDealNativeToken(recipient, 0);

        assertEq(recipient.balance, 0);
    }

    // =========================================================================
    // dealERC20 tests
    // =========================================================================

    function test_dealERC20_slot0() public {
        MockERC20Slot0 token = new MockERC20Slot0();
        address recipient = makeAddr("recipient");

        // Mint some initial tokens
        token.mint(recipient, 100);
        assertEq(token.balanceOf(recipient), 100);

        // Deal tokens via ForkHelper
        harness.callDealERC20(address(token), recipient, 5000);

        assertEq(token.balanceOf(recipient), 5000);
    }

    function test_dealERC20_slot1() public {
        MockERC20Slot1 token = new MockERC20Slot1();
        address recipient = makeAddr("recipient");

        // Deal tokens via ForkHelper
        harness.callDealERC20(address(token), recipient, 1000);

        assertEq(token.balanceOf(recipient), 1000);
    }

    function test_dealERC20_zeroAmount() public {
        MockERC20Slot0 token = new MockERC20Slot0();
        address recipient = makeAddr("recipient");
        token.mint(recipient, 500);

        harness.callDealERC20(address(token), recipient, 0);

        assertEq(token.balanceOf(recipient), 0);
    }

    function test_dealERC20_largeAmount() public {
        MockERC20Slot0 token = new MockERC20Slot0();
        address recipient = makeAddr("recipient");

        uint256 largeAmount = type(uint128).max;
        harness.callDealERC20(address(token), recipient, largeAmount);

        assertEq(token.balanceOf(recipient), largeAmount);
    }

    function test_dealERC20_multipleRecipients() public {
        MockERC20Slot0 token = new MockERC20Slot0();
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        harness.callDealERC20(address(token), alice, 1000);
        harness.callDealERC20(address(token), bob, 2000);

        assertEq(token.balanceOf(alice), 1000);
        assertEq(token.balanceOf(bob), 2000);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _deploySafe(address[] memory owners, uint256 threshold) internal returns (Safe) {
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            threshold,
            address(0), // to
            "", // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            payable(0) // paymentReceiver
        );

        return Safe(payable(safeFactory.createProxyWithNonce(address(safeMasterCopy), initializer, block.timestamp)));
    }

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
}
