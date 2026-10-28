// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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
}

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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = ROUTRHandler.transfer.selector;
        selectors[1] = ROUTRHandler.approve.selector;
        selectors[2] = ROUTRHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balancesAllowancesAndSupplyMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
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
}
