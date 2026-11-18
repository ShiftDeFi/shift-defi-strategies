// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {CurveGaugePyusdUsdcBase} from "./CurveGaugePyusdUsdc.t.sol";

contract CurveGaugePyusdUsdcEnterTest is CurveGaugePyusdUsdcBase {
    function setUp() public override {
        super.setUp();
    }

    function test_EnterTarget() public {
        _enterStrategy();

        assertApproxEqRel(
            IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_GAUGE_STATE_ID),
            Common.toUnifiedDecimalsUint8(USDC, ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(USDC).decimals())),
            NAV_TOLERANCE_PCT,
            "test_EnterTarget: Curve Gauge NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_LP_STATE_ID), 0, "test_EnterTarget: Curve LP NAV"
        );
        assertEq(
            IStrategyTemplate(curveGaugePyusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            0,
            "test_EnterTarget: Underlying Assets NAV"
        );
    }
}
