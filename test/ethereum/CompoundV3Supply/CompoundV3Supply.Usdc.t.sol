// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CompoundV3SupplyBase} from "./CompoundV3SupplyBase.t.sol";
import {CompoundV3SupplyEmergencyExitTest} from "./CompoundV3Supply.EmergencyExit.t.sol";

contract CompoundV3SupplyUsdcTest is CompoundV3SupplyBase, CompoundV3SupplyEmergencyExitTest {
    function setUp() public override {
        comet = COMPOUND_V3_USDC;
        rewardToken = COMP;
        super.setUp();
    }
}
