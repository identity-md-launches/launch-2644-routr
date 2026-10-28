// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ROUTR} from "../../src/ROUTR.sol";

/// @dev Test-only holder used to exercise deployment and transfers by contracts.
contract FactoryHarness {
    function deploy() external returns (ROUTR) {
        return new ROUTR();
    }

    function move(ROUTR token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}
