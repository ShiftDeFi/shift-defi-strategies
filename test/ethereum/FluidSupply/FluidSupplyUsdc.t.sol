// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FluidSupplyBase} from "./FluidSupplyBase.t.sol";
import {FluidSupplyEmergencyExitTest} from "./FluidSupply.EmergencyExit.t.sol";

contract FluidSupplyUsdcTest is FluidSupplyBase, FluidSupplyEmergencyExitTest {
    function setUp() public override {
        fToken = F_USDC;
        super.setUp();
    }
}
