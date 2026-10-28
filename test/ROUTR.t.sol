// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ROUTR} from "../src/ROUTR.sol";
import {FactoryHarness} from "./helpers/FactoryHarness.sol";

contract ROUTRTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    ROUTR private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new ROUTR();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "ROUTR");
        assertEq(token.symbol(), "ROUTR");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(alice);
        ROUTR fresh = new ROUTR();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_factoryReceivesSupplyInsteadOfItsCallerOrOrigin() public {
        FactoryHarness factory = new FactoryHarness();
        vm.prank(alice, bob);
        ROUTR launched = factory.deploy();

        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 123e18);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123e18));
        assertEq(token.balanceOf(deployer), SUPPLY - 123e18);
        assertEq(token.balanceOf(alice), 123e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromEmptyAccountReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 100e18);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 100e18));
        assertEq(token.allowance(deployer, spender), 100e18);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanExceedCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveOverwritesAndRevocationPreventsSpending() public {
        vm.startPrank(deployer);
        token.approve(spender, 100e18);
        token.approve(spender, 20e18);
        assertEq(token.allowance(deployer, spender), 20e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        token.approve(spender, 0);
        vm.stopPrank();

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_transferFromUsesAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 100e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 40e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 40e18));

        assertEq(token.balanceOf(deployer), SUPPLY - 40e18);
        assertEq(token.balanceOf(alice), 40e18);
        assertEq(token.allowance(deployer, spender), 60e18);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 60e18));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(bob), 60e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transferFromSelfStillConsumesAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 100));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_zeroTransferFromWithoutAllowanceEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_unapprovedSpenderCannotUseAnotherSpendersApproval() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_holderUsingTransferFromAlsoNeedsApproval() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromToZeroRollsBackAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 100);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroAddressRevertsEvenForZeroAmount() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_insufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_deployerHasNoPrivilegeOverHolder() public {
        vm.prank(deployer);
        token.transfer(alice, 100e18);

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);

        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("pause()");
        calls[1] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[2] = abi.encodeWithSignature("freeze(address)", alice);
        calls[3] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[4] = abi.encodeWithSignature("lock(address)", alice);
        calls[5] = abi.encodeWithSignature("disableTransfers()");
        calls[6] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[7] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 100e18);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", deployer);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", deployer);
        calls[11] = abi.encodeWithSignature("owner()");
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok);
        }

        assertEq(token.balanceOf(alice), 100e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100e18));
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrInitializationEntryPoint() public {
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1e18);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1e18);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1e18);
        calls[4] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[5] = abi.encodeWithSignature("initialize(address)", bob);
        calls[6] = abi.encodeWithSignature("initialize()");
        calls[7] = abi.encodeWithSignature("burn(uint256)", 1);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool deployerOk,) = address(token).call(calls[i]);
            assertFalse(deployerOk);
            vm.prank(bob);
            (bool strangerOk,) = address(token).call(calls[i]);
            assertFalse(strangerOk);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(deployer), SUPPLY);
            assertEq(token.balanceOf(bob), 0);
        }
    }

    function test_directEtherAndUnknownCallsRevert() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool received,) = address(token).call{value: 1 ether}("");
        assertFalse(received);
        assertEq(address(token).balance, 0);

        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_launchDistributionClaimsAndPoolTransfersArriveWhole() public {
        FactoryHarness factory = new FactoryHarness();
        FactoryHarness distributor = new FactoryHarness();
        FactoryHarness poolHolder = new FactoryHarness();
        ROUTR launched = factory.deploy();

        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 85 / 100;
        uint256 remainder = SUPPLY * 5 / 100;
        factory.move(launched, address(distributor), swarmShare);
        factory.move(launched, address(poolHolder), poolShare);
        factory.move(launched, alice, remainder);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(address(distributor)), swarmShare);
        assertEq(launched.balanceOf(address(poolHolder)), poolShare);
        assertEq(launched.balanceOf(alice), remainder);

        distributor.move(launched, bob, swarmShare);
        assertEq(launched.balanceOf(address(distributor)), 0);
        assertEq(launched.balanceOf(bob), swarmShare);

        poolHolder.move(launched, spender, 25e18);
        assertEq(launched.balanceOf(spender), 25e18);
        vm.prank(spender);
        assertTrue(launched.transfer(address(poolHolder), 25e18));
        assertEq(launched.balanceOf(spender), 0);
        assertEq(launched.balanceOf(address(poolHolder)), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRejectsOverspend(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRespectsBalanceAndAllowance(uint256 funded, uint256 approved, uint256 requested)
        public
    {
        funded = bound(funded, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, funded);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.prank(spender);
        if (requested > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, requested)
            );
        } else if (requested > funded) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, requested)
            );
        }
        token.transferFrom(alice, bob, requested);

        if (requested <= approved && requested <= funded) {
            assertEq(token.balanceOf(alice), funded - requested);
            assertEq(token.balanceOf(bob), requested);
            assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - requested);
        } else {
            assertEq(token.balanceOf(alice), funded);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.allowance(alice, spender), approved);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvedTransferSucceeds(uint256 amount, uint256 extraAllowance) public {
        amount = bound(amount, 0, SUPPLY);
        extraAllowance = bound(extraAllowance, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, amount + extraAllowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, spender), extraAllowance);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferRequiresSufficientBalance(uint256 amount) public {
        vm.prank(deployer);
        if (amount > SUPPLY) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
            );
        }
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
