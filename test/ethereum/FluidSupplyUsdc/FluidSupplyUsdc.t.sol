// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FluidSupplyBase} from "./FluidSupplyBase.t.sol";

contract FluidSupplyUsdc is FluidSupplyBase {
    function setUp() public override {
        super.setUp(USDC, F_USDC);
    }
}
