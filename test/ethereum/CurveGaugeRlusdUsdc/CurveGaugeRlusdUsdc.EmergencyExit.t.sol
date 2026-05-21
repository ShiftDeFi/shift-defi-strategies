// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {CurveGaugeRlusdUsdcBase} from "./CurveGaugeRlusdUsdc.t.sol";

contract CurveGaugeRlusdUsdcEmergencyExitTest is CurveGaugeRlusdUsdcBase {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
        _enterStrategy();
    }

    function test_EmergencyExit_ToCurveLp_FullExit() public {
        uint256 stateNav = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        vm.startPrank(roles.emergencyExecutor);
        curveGaugeRlusdUsdc.emergencyExit(CURVE_LP_STATE_ID, MAX_BPS, stateNav);
        vm.stopPrank();

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID),
            0,
            "test_EmergencyExit_ToCurveLp_FullExit: Curve Gauge NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_LP_STATE_ID),
            stateNav,
            "test_EmergencyExit_ToCurveLp_FullExit: Curve LP NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            0,
            "test_EmergencyExit_ToCurveLp_FullExit: Underlying Assets NAV"
        );
    }

    function test_EmergencyExit_ToCurveLp_PartialExit() public {
        uint256 stateNav = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 minNavDelta = stateNav.mulDiv(partialShare, MAX_BPS);
        vm.startPrank(roles.emergencyExecutor);
        curveGaugeRlusdUsdc.emergencyExit(CURVE_LP_STATE_ID, partialShare, minNavDelta);
        vm.stopPrank();

        assertApproxEqRel(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID),
            stateNav - minNavDelta,
            NAV_TOLERANCE_PCT_LOW,
            "test_EmergencyExit_ToCurveLp_PartialExit: Curve Gauge NAV"
        );

        assertApproxEqRel(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_LP_STATE_ID),
            minNavDelta,
            NAV_TOLERANCE_PCT_LOW,
            "test_EmergencyExit_ToCurveLp_PartialExit: Curve LP NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            0,
            "test_EmergencyExit_ToCurveLp_PartialExit: Underlying Assets NAV"
        );
    }

    function test_EmergencyExit_ToUnderlyingAssets_FullExit() public {
        uint256 stateNav = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        vm.startPrank(roles.emergencyExecutor);
        uint256 minNavDelta = stateNav.mulDiv(MAX_BPS - EMERGENCY_EXIT_MAX_SLIPPAGE + ONE_PCT, MAX_BPS);
        curveGaugeRlusdUsdc.emergencyExit(UNDERLYING_ASSETS_STATE_ID, MAX_BPS, minNavDelta);
        vm.stopPrank();

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID),
            0,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Curve Gauge NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_LP_STATE_ID),
            0,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Curve LP NAV"
        );

        assertApproxEqRel(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            stateNav,
            NAV_TOLERANCE_PCT_LOW,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Underlying Assets NAV"
        );
    }

    function test_EmergencyExit_ToUnderlyingAssets_PartialExit() public {
        uint256 stateNav = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 minNavDelta = stateNav.mulDiv(partialShare, MAX_BPS);
        vm.startPrank(roles.emergencyExecutor);
        curveGaugeRlusdUsdc.emergencyExit(UNDERLYING_ASSETS_STATE_ID, partialShare, minNavDelta - ONE_PCT);
        vm.stopPrank();

        assertApproxEqRel(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID),
            stateNav - minNavDelta,
            NAV_TOLERANCE_PCT_LOW,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Curve Gauge NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_LP_STATE_ID),
            0,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Curve LP NAV"
        );

        assertApproxEqRel(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            minNavDelta,
            NAV_TOLERANCE_PCT_LOW,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Underlying Assets NAV"
        );
    }
}
