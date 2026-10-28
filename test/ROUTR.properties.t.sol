// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ROUTR} from "../src/ROUTR.sol";

/// @dev Complement the existing examples with arithmetic boundaries, recovery, and algebraic properties.
/// forge-config: default.fuzz.runs = 1024
contract ROUTRPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    ROUTR private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        deployer = makeAddr("property deployer");
        alice = makeAddr("property alice");
        bob = makeAddr("property bob");
        spender = makeAddr("property spender");
        vm.prank(deployer);
        token = new ROUTR();
    }

    function test_boundaryAmountsTransferAndReturnExactly() public {
        uint256[6] memory amounts = [uint256(0), 1, 1e18 - 1, 1e18, SUPPLY - 1, SUPPLY];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 amount = amounts[i];
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(deployer, alice, amount);
            vm.prank(deployer);
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);

            vm.prank(alice);
            assertTrue(token.transfer(deployer, amount));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(deployer), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_largestFiniteAllowanceCanBecomeInfiniteThenFiniteAgain() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);

        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.prank(deployer);
        assertTrue(token.approve(spender, 2));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), 1);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 4);
        assertEq(token.balanceOf(deployer), SUPPLY - 4);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRequestsRevertWithoutChangingState() public {
        uint256 maximum = type(uint256).max;
        vm.startPrank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, maximum)
        );
        token.transfer(alice, maximum);
        token.approve(spender, maximum - 1);
        vm.stopPrank();

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, maximum - 1, maximum)
        );
        token.transferFrom(deployer, alice, maximum);
        assertEq(token.allowance(deployer, spender), maximum - 1);

        vm.prank(deployer);
        token.approve(spender, maximum);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, maximum)
        );
        token.transferFrom(deployer, alice, maximum);
        assertEq(token.allowance(deployer, spender), maximum);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_failedDelegatedTransferCanBeRetriedAfterFunding() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, spender), 10);

        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 10));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10);
        assertEq(token.balanceOf(deployer), SUPPLY - 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferPreservesAnExistingAllowance() public {
        vm.prank(alice);
        token.approve(spender, 7);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAmountDoesNotMakeZeroAddressesValid() public {
        vm.startPrank(deployer);
        token.approve(spender, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.stopPrank();

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 0);
        assertEq(token.allowance(deployer, spender), 7);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceCannotBypassBalanceCheckOnSelfTransfer() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_holderCanUseTransferFromWithExplicitSelfApproval() public {
        vm.startPrank(deployer);
        token.approve(deployer, 2);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 1);
        assertTrue(token.transferFrom(deployer, deployer, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientAllowanceWithSufficientBalance(
        uint256 funded,
        uint256 allowed,
        uint256 requested,
        bool selfTransfer
    ) public {
        funded = bound(funded, 1, SUPPLY);
        allowed = bound(allowed, 0, funded - 1);
        requested = bound(requested, allowed + 1, funded);
        address recipient = selfTransfer ? alice : bob;
        vm.prank(deployer);
        token.transfer(alice, funded);
        vm.prank(alice);
        token.approve(spender, allowed);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, requested)
        );
        token.transferFrom(alice, recipient, requested);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientBalanceWithSufficientAllowance(
        uint256 funded,
        uint256 allowed,
        uint256 requested,
        bool selfTransfer
    ) public {
        funded = bound(funded, 0, SUPPLY);
        allowed = bound(allowed, funded + 1, type(uint256).max);
        requested = bound(requested, funded + 1, allowed);
        address recipient = selfTransfer ? alice : bob;
        vm.prank(deployer);
        token.transfer(alice, funded);
        vm.prank(alice);
        token.approve(spender, allowed);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, requested)
        );
        token.transferFrom(alice, recipient, requested);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingOneSpendersApprovalLeavesOtherApprovalsIntact(
        uint256 oldApproval,
        uint256 replacement,
        uint256 otherApproval,
        uint256 spent
    ) public {
        uint256 limit = replacement < SUPPLY ? replacement : SUPPLY;
        spent = bound(spent, 0, limit);
        vm.startPrank(deployer);
        token.approve(spender, oldApproval);
        token.approve(bob, otherApproval);
        token.approve(spender, replacement);
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        assertEq(
            token.allowance(deployer, spender), replacement == type(uint256).max ? replacement : replacement - spent
        );
        assertEq(token.allowance(deployer, bob), otherApproval);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);

        vm.prank(deployer);
        token.approve(spender, 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.allowance(deployer, bob), otherApproval);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev A split payment must have the same balance and approval effects as one aggregate payment.
    function testFuzz_splitDelegatedTransfersMatchSingleTransfer(uint256 total, uint256 first, uint256 approval)
        public
    {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        approval = bound(approval, total, type(uint256).max);
        vm.prank(deployer);
        ROUTR split = new ROUTR();
        vm.startPrank(deployer);
        token.approve(spender, approval);
        split.approve(spender, approval);
        vm.stopPrank();

        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, total));
        assertTrue(split.transferFrom(deployer, alice, first));
        assertTrue(split.transferFrom(deployer, alice, total - first));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(deployer), SUPPLY - total);
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.balanceOf(deployer), token.balanceOf(deployer));
        assertEq(token.allowance(deployer, spender), approval == type(uint256).max ? approval : approval - total);
        assertEq(split.allowance(deployer, spender), token.allowance(deployer, spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(split.totalSupply(), SUPPLY);
    }
}
