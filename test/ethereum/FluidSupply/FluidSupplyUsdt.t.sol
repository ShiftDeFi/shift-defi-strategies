// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FluidSupplyBase} from "./FluidSupplyBase.t.sol";

contract FluidSupplyUsdt is FluidSupplyBase {
    function setUp() public override {
        fToken = F_USDT;
        super.setUp();
    }
}
