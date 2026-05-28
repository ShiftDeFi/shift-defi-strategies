// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {FluidSupplyBase} from "./FluidSupplyBase.t.sol";

abstract contract FluidSupplyEmergencyExitTest is FluidSupplyBase {
    using Math for uint256;

    function test_EmergencyExit_ToUnderlyingAssets_FullExit() public {
        _enterStrategy();

        uint256 fluidSupplyNavBefore = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);

        vm.prank(roles.emergencyExecutor);
        fluidSupply.emergencyExit(UNDERLYING_ASSET_STATE_ID, MAX_BPS, fluidSupplyNavBefore);

        uint256 fluidSupplyNavAfter = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        assertEq(fluidSupplyNavAfter, 0, "test_EmergencyExit_ToUnderlyingAssets_FullExit: Fluid Supply NAV");

        uint256 underlyingAssetNav = fluidSupply.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertEq(
            underlyingAssetNav,
            fluidSupplyNavBefore,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Underlying Asset NAV"
        );
    }

    function test_EmergencyExit_ToUnderlyingAssets_PartialExit() public {
        _enterStrategy();

        uint256 fluidSupplyNavBefore = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 minNavDelta = fluidSupplyNavBefore.mulDiv(partialShare - ONE_PCT / 100, MAX_BPS);

        vm.prank(roles.emergencyExecutor);
        fluidSupply.emergencyExit(UNDERLYING_ASSET_STATE_ID, partialShare, minNavDelta);

        uint256 fluidSupplyNavAfter = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        assertApproxEqRel(
            fluidSupplyNavAfter,
            fluidSupplyNavBefore - minNavDelta,
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Fluid Supply NAV"
        );

        uint256 underlyingAssetNav = fluidSupply.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertApproxEqRel(
            underlyingAssetNav,
            fluidSupplyNavBefore - fluidSupplyNavAfter,
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Underlying Asset NAV"
        );
    }
}
