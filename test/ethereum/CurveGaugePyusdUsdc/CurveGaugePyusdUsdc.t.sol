// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {CurveGaugePyusdUsdc} from "contracts/curve-gauge/CurveGaugePyusdUsdc.sol";

import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";

import {EthContext} from "test/ethereum/EthContext.t.sol";

import {console2 as console} from "forge-std/console2.sol";

abstract contract CurveGaugePyusdUsdcBase is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal curveGaugePyusdUsdc;

    uint256 internal enterAmountUsdc;
    uint256 internal enterAmountPyusd;

    uint256 internal constant ENTER_AMOUNT = 1_00_000_000_000; // 100k USDC
    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%
    uint256 internal constant NAV_TOLERANCE_PCT_LOW = 1e8; // 0.000001%

    bytes32 internal constant ONLY_NOTION_STATE_ID = keccak256("ONLY_NOTION_STATE_ID");
    bytes32 internal constant UNDERLYING_ASSETS_STATE_ID = keccak256("UNDERLYING_ASSETS_STATE_ID");
    bytes32 internal constant CURVE_LP_STATE_ID = keccak256("CURVE_LP_STATE_ID");
    bytes32 internal constant CURVE_GAUGE_STATE_ID = keccak256("CURVE_GAUGE_STATE_ID");

    function setUp() public virtual override {
        super.setUp();

        address implementation = address(new CurveGaugePyusdUsdc());
        curveGaugePyusdUsdc = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(CurveGauge.initialize.selector, STRATEGY_CONTAINER, CURVE_GAUGE_PYUSD_USDC)
            )
        );

        vm.label(address(curveGaugePyusdUsdc), "CURVE_GAUGE_PYUSD_USDC");

        address pool = ILiquidityGaugeV6(CURVE_GAUGE_PYUSD_USDC).lp_token();
        uint256[] memory balances = ICurveStableSwapNG(pool).get_balances();
        uint256 totalReserve = balances[0] + balances[1];
        enterAmountPyusd = ENTER_AMOUNT.mulDiv(balances[0], totalReserve);
        enterAmountUsdc = ENTER_AMOUNT.mulDiv(balances[1], totalReserve);

        address[] memory inputTokens = new address[](2);
        inputTokens[0] = PYUSD;
        inputTokens[1] = USDC;

        _addStrategy(address(curveGaugePyusdUsdc), inputTokens, inputTokens);
    }

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = enterAmountPyusd;
        amounts[1] = enterAmountUsdc;

        deal(PYUSD, STRATEGY_CONTAINER, enterAmountPyusd, true);
        deal(USDC, STRATEGY_CONTAINER, enterAmountUsdc, true);

        vm.startPrank(STRATEGY_CONTAINER);
        IERC20(PYUSD).forceApprove(address(curveGaugePyusdUsdc), type(uint256).max);
        IERC20(USDC).forceApprove(address(curveGaugePyusdUsdc), type(uint256).max);

        IStrategyTemplate(curveGaugePyusdUsdc).enter(amounts, 0);

        vm.stopPrank();
    }

    function test_ExitTarget_Partial() public {
        _enterStrategy();

        uint256 partialShare = MAX_BPS / 2;

        uint256 curveGaugeNavBefore = IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        uint256 maxNavDelta = curveGaugeNavBefore.mulDiv(partialShare, MAX_BPS);

        vm.startPrank(STRATEGY_CONTAINER);
        IStrategyTemplate(curveGaugePyusdUsdc).exit(partialShare, maxNavDelta);
        vm.stopPrank();

        uint256 curveGaugeNavAfter = IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);

        assertApproxEqRel(
            curveGaugeNavAfter,
            curveGaugeNavBefore - maxNavDelta,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Curve Gauge NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_LP_STATE_ID),
            0,
            "test_ExitTarget_Partial: Curve LP NAV"
        );

        assertApproxEqRel(
            IStrategyTemplate(curveGaugePyusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            curveGaugeNavBefore - curveGaugeNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Underlying Assets NAV"
        );

        uint256 exitedUsdcAmount = IERC20(USDC).balanceOf(address(curveGaugePyusdUsdc));
        uint256 exitedPyusdAmount = IERC20(PYUSD).balanceOf(address(curveGaugePyusdUsdc));

        uint256 exitedNav = Common.toUnifiedDecimalsUint8(USDC, exitedUsdcAmount) +
            Common.toUnifiedDecimalsUint8(PYUSD, exitedPyusdAmount);

        assertApproxEqRel(
            exitedNav,
            curveGaugeNavBefore - curveGaugeNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Exited NAV from Curve Gauge"
        );
    }

    function test_ExitTarget_Full() public {
        _enterStrategy();

        uint256 curveGaugeNavBefore = IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);

        vm.startPrank(STRATEGY_CONTAINER);
        curveGaugePyusdUsdc.exit(MAX_BPS, curveGaugeNavBefore);
        vm.stopPrank();

        assertEq(curveGaugePyusdUsdc.stateNav(CURVE_GAUGE_STATE_ID), 0, "test_ExitTarget_Full: Curve Gauge NAV");

        assertEq(curveGaugePyusdUsdc.stateNav(CURVE_LP_STATE_ID), 0, "test_ExitTarget_Full: Curve LP NAV");

        assertApproxEqRel(
            curveGaugePyusdUsdc.stateNav(UNDERLYING_ASSETS_STATE_ID),
            curveGaugeNavBefore,
            NAV_TOLERANCE_PCT_LOW,
            "test_ExitTarget_Full: Underlying Assets NAV"
        );
    }

    function test_Harvest() public {
        _enterStrategy();

        // Simulate reward accrual window on the fork before harvesting.
        vm.warp(block.timestamp + 10 minutes);
        vm.roll(block.number + 2);

        uint256 treasuryBalanceBefore = IERC20(PYUSD).balanceOf(treasury);

        vm.startPrank(STRATEGY_CONTAINER);
        curveGaugePyusdUsdc.harvest();
        vm.stopPrank();

        uint256 treasuryBalanceAfter = IERC20(PYUSD).balanceOf(treasury);
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore, "test_Harvest: no treasury rewards");
    }
}
