// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {CompoundV3SupplyBase} from "./CompoundV3SupplyBase.t.sol";

abstract contract CompoundV3SupplyEmergencyExitTest is CompoundV3SupplyBase {
    using Math for uint256;

    function test_EmergencyExit_ToUnderlyingAssets_FullExit() public {
        _enterStrategy();

        uint256 minNavDelta = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);

        vm.prank(roles.emergencyExecutor);
        compoundStrategy.emergencyExit(UNDERLYING_ASSETS_STATE_ID, MAX_BPS, minNavDelta);

        assertEq(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            0,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Compound V3 NAV"
        );
        assertApproxEqRel(
            compoundStrategy.stateNav(UNDERLYING_ASSETS_STATE_ID),
            minNavDelta,
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Underlying Asset NAV"
        );
        assertEq(
            compoundStrategy.currentStateId(),
            UNDERLYING_ASSETS_STATE_ID,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: current state"
        );
    }

    /// @dev Height 0 belongs to the unregistered no-allocation state, so every registered state sits above it
    function testRevert_EmergencyExit_FromNoAllocation() public {
        vm.prank(roles.emergencyExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyTemplate.CannotExitToStateWithHigherHeight.selector, UNDERLYING_ASSETS_STATE_ID, bytes32(0)
            )
        );
        compoundStrategy.emergencyExit(UNDERLYING_ASSETS_STATE_ID, MAX_BPS, 0);
    }

    function test_EmergencyExit_ToUnderlyingAssets_PartialExit() public {
        _enterStrategy();

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        // Lower bound on the underlying-state NAV gained, a hair below half to absorb Comet's rounding
        uint256 minNavDelta = navBefore.mulDiv(partialShare - ONE_PCT / 100, MAX_BPS);

        vm.prank(roles.emergencyExecutor);
        compoundStrategy.emergencyExit(UNDERLYING_ASSETS_STATE_ID, partialShare, minNavDelta);

        assertApproxEqRel(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            navBefore - navBefore.mulDiv(partialShare, MAX_BPS),
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Compound V3 NAV"
        );
        assertApproxEqRel(
            compoundStrategy.stateNav(UNDERLYING_ASSETS_STATE_ID),
            navBefore.mulDiv(partialShare, MAX_BPS),
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Underlying Asset NAV"
        );
    }
}
