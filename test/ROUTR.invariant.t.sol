// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ROUTR} from "../src/ROUTR.sol";

/// @dev Keeps a separate ledger rather than deriving expectations from token storage.
contract ROUTRHandler is Test {
    ROUTR private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ROUTR token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 1e18;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, 0, allowed < held ? allowed : held);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Hit approval boundaries deliberately, including the largest finite approval.
    function approveBoundary(uint8 ownerSeed, uint8 spenderSeed, uint8 choice) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[choice % amounts.length]);
    }

    function transferOverBalance(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        amount = bound(amount, held + 1, type(uint256).max);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(to, amount);
        // No ghost update: the next invariant checks that every balance and allowance survived.
    }

    function transferFromOverBalance(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, held + 1, type(uint256).max);
        _approve(owner, spender, infinite ? type(uint256).max : amount);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        token.transferFrom(owner, to, amount);
        // The preceding approval persists, but a failing transfer must not consume any of it.
    }

    function revokeAndAttemptSpend(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, type(uint256).max);
        _approve(owner, spender, 0);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        token.transferFrom(owner, to, amount);
    }

    function transferFromOverAllowance(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        // Unlimited approval cannot be exceeded. Replace it with the largest finite approval first.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            _approve(owner, spender, allowed);
        }
        amount = bound(amount, allowed + 1, type(uint256).max);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroAddress(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, uint8 operation) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        if (operation % 3 == 0) {
            vm.prank(owner);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amount);
        } else if (operation % 3 == 1) {
            vm.prank(owner);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transfer(address(0), amount);
        } else {
            _approve(owner, spender, amount);
            vm.prank(spender);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transferFrom(owner, address(0), amount);
        }
    }

    /// @dev Check the intermediate movement as well as the final identity, so two no-ops cannot pass.
    function roundTrip(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // Both ghost ledgers stay unchanged: a round trip restores balances and does not spend approvals.
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ROUTRInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    ROUTR private token;
    ROUTRHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("first"), makeAddr("second"), makeAddr("third"), makeAddr("fourth")];
        vm.prank(actors[0]);
        token = new ROUTR();
        handler = new ROUTRHandler(token, actors);

        // Give every actor funds and a spender before randomization, so delegated calls can move value immediately.
        for (uint8 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / actors.length);
        }
        for (uint8 i; i < actors.length; ++i) {
            handler.approve(i, uint8((i + 1) % actors.length), SUPPLY / 8);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = ROUTRHandler.transfer.selector;
        selectors[1] = ROUTRHandler.approve.selector;
        selectors[2] = ROUTRHandler.transferFrom.selector;
        selectors[3] = ROUTRHandler.approveBoundary.selector;
        selectors[4] = ROUTRHandler.transferOverBalance.selector;
        selectors[5] = ROUTRHandler.transferFromOverBalance.selector;
        selectors[6] = ROUTRHandler.revokeAndAttemptSpend.selector;
        selectors[7] = ROUTRHandler.rejectZeroAddress.selector;
        selectors[8] = ROUTRHandler.roundTrip.selector;
        selectors[9] = ROUTRHandler.transferFromOverAllowance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balancesAllowancesAndSupplyMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            sum += balance;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actor, actors[j]), handler.expectedAllowance(actor, actors[j]));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev After every random sequence, each holder must still be able to transfer its whole balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            uint256 held = token.balanceOf(actors[i]);
            vm.prank(actors[i]);
            assertTrue(token.transfer(actors[0], held));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
