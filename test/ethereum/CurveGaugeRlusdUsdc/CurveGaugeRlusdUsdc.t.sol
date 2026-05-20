// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";

import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";

import {EthContext} from "test/ethereum/EthContext.t.sol";

abstract contract CurveGaugeRlusdUsdcBase is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal curveGaugeRlusdUsdc;

    uint256 internal enterAmountUsdc;
    uint256 internal enterAmountRlusd;

    uint256 internal constant ENTER_AMOUNT = 100_000; // 100k
    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%
    uint256 internal constant NAV_TOLERANCE_PCT_LOW = 1e8; // 0.000001%

    uint256 internal constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    bytes32 internal constant UNDERLYING_ASSETS_STATE_ID = keccak256("UNDERLYING_ASSETS_STATE_ID");
    bytes32 internal constant CURVE_LP_STATE_ID = keccak256("CURVE_LP_STATE_ID");
    bytes32 internal constant CURVE_GAUGE_STATE_ID = keccak256("CURVE_GAUGE_STATE_ID");

    function setUp() public virtual override {
        super.setUp();

        address implementation = address(new CurveGauge());
        curveGaugeRlusdUsdc = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(
                    CurveGauge.initialize.selector,
                    mockStrategyContainer,
                    CURVE_GAUGE_RLUSD_USDC,
                    ENTER_MAX_SLIPPAGE,
                    EXIT_MAX_SLIPPAGE,
                    EMERGENCY_EXIT_MAX_SLIPPAGE
                )
            )
        );

        vm.label(address(curveGaugeRlusdUsdc), "CURVE_GAUGE_RLUSD_USDC");

        address pool = ILiquidityGaugeV6(CURVE_GAUGE_RLUSD_USDC).lp_token();
        uint256[] memory balances = ICurveStableSwapNG(pool).get_balances();
        uint256 totalReserve = Common.toUnifiedDecimalsUint8(USDC, balances[0]) +
            Common.toUnifiedDecimalsUint8(RLUSD, balances[1]);
        enterAmountUsdc =
            ENTER_AMOUNT.mulDiv(Common.toUnifiedDecimalsUint8(USDC, balances[0]), totalReserve) *
            10 ** uint256(IERC20Metadata(USDC).decimals());
        enterAmountRlusd =
            ENTER_AMOUNT.mulDiv(Common.toUnifiedDecimalsUint8(RLUSD, balances[1]), totalReserve) *
            10 ** uint256(IERC20Metadata(RLUSD).decimals());

        address[] memory inputTokens = new address[](2);
        inputTokens[0] = USDC;
        inputTokens[1] = RLUSD;

        _addStrategy(address(curveGaugeRlusdUsdc), inputTokens, inputTokens);
    }

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = enterAmountUsdc;
        amounts[1] = enterAmountRlusd;

        deal(USDC, mockStrategyContainer, enterAmountUsdc, true);
        deal(RLUSD, mockStrategyContainer, enterAmountRlusd, true);

        vm.startPrank(mockStrategyContainer);
        IERC20(USDC).forceApprove(address(curveGaugeRlusdUsdc), type(uint256).max);
        IERC20(RLUSD).forceApprove(address(curveGaugeRlusdUsdc), type(uint256).max);

        uint256 minAsset0Delta = amounts[0].mulDiv(MAX_BPS - ENTER_MAX_SLIPPAGE / 2, MAX_BPS);
        uint256 minAsset1Delta = amounts[1].mulDiv(MAX_BPS - ENTER_MAX_SLIPPAGE / 2, MAX_BPS);

        uint256 minNavDelta0 = curveGaugeRlusdUsdc.getTokenAmountInNotion(USDC, minAsset0Delta);
        uint256 minNavDelta1 = curveGaugeRlusdUsdc.getTokenAmountInNotion(RLUSD, minAsset1Delta);

        IStrategyTemplate(curveGaugeRlusdUsdc).enter(amounts, minNavDelta0 + minNavDelta1);

        vm.stopPrank();
    }

    function test_ExitTarget_Partial() public {
        _enterStrategy();

        uint256 partialShare = MAX_BPS / 2;

        uint256 curveGaugeNavBefore = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        uint256 maxNavDelta = curveGaugeNavBefore.mulDiv(partialShare, MAX_BPS);

        vm.startPrank(mockStrategyContainer);
        IStrategyTemplate(curveGaugeRlusdUsdc).exit(partialShare, maxNavDelta);
        vm.stopPrank();

        uint256 curveGaugeNavAfter = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);

        assertApproxEqRel(
            curveGaugeNavAfter,
            curveGaugeNavBefore - maxNavDelta,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Curve Gauge NAV"
        );

        assertEq(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_LP_STATE_ID),
            0,
            "test_ExitTarget_Partial: Curve LP NAV"
        );

        assertApproxEqRel(
            IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(UNDERLYING_ASSETS_STATE_ID),
            curveGaugeNavBefore - curveGaugeNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Underlying Assets NAV"
        );

        uint256 exitedUsdcAmount = IERC20(USDC).balanceOf(address(curveGaugeRlusdUsdc));
        uint256 exitedRlusdAmount = IERC20(RLUSD).balanceOf(address(curveGaugeRlusdUsdc));

        uint256 exitedNav = Common.toUnifiedDecimalsUint8(USDC, exitedUsdcAmount) +
            Common.toUnifiedDecimalsUint8(RLUSD, exitedRlusdAmount);

        assertApproxEqRel(
            exitedNav,
            curveGaugeNavBefore - curveGaugeNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Exited NAV from Curve Gauge"
        );
    }

    function test_ExitTarget_Full() public {
        _enterStrategy();

        uint256 curveGaugeNavBefore = IStrategyTemplate(curveGaugeRlusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);

        vm.startPrank(mockStrategyContainer);
        curveGaugeRlusdUsdc.exit(MAX_BPS, curveGaugeNavBefore);
        vm.stopPrank();

        assertEq(curveGaugeRlusdUsdc.stateNav(CURVE_GAUGE_STATE_ID), 0, "test_ExitTarget_Full: Curve Gauge NAV");

        assertEq(curveGaugeRlusdUsdc.stateNav(CURVE_LP_STATE_ID), 0, "test_ExitTarget_Full: Curve LP NAV");

        assertApproxEqRel(
            curveGaugeRlusdUsdc.stateNav(UNDERLYING_ASSETS_STATE_ID),
            curveGaugeNavBefore,
            NAV_TOLERANCE_PCT_LOW,
            "test_ExitTarget_Full: Underlying Assets NAV"
        );
    }

    function test_Harvest() public {
        _enterStrategy();

        // Simulate reward accrual window on the fork before harvesting.
        vm.warp(block.timestamp + 100 minutes);
        vm.roll(block.number + 100);

        uint256 treasuryBalanceBefore = IERC20(CURVE_GAUGE_RLUSD_USDC).balanceOf(treasury);

        vm.startPrank(mockStrategyContainer);
        curveGaugeRlusdUsdc.harvest();
        vm.stopPrank();

        uint256 treasuryBalanceAfter = IERC20(CURVE_GAUGE_RLUSD_USDC).balanceOf(treasury);
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore, "test_Harvest: no treasury rewards");
    }
}
