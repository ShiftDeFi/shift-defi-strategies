// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IContainer} from "@shift-defi/core/interfaces/IContainer.sol";
import {ISwapRouter} from "@shift-defi/core/interfaces/ISwapRouter.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {CurveGauge} from "./CurveGauge.sol";

import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";

contract CurveGaugePyusdUsdc is CurveGauge {
    using SafeERC20 for IERC20;
    using Math for uint256;

    error SwapFailed(address token0, address token1, uint256 amount);

    function _enterUnderlyingAssets() internal override {
        address underlyingAsset0Cached = underlyingAsset0;
        address underlyingAsset1Cached = underlyingAsset1;
        address lpTokenCached = lpToken;

        uint256[] memory poolReserves = ICurveStableSwapNG(lpTokenCached).get_balances();
        uint256 reserve1InNotion = getTokenAmountInNotion(underlyingAsset1Cached, poolReserves[1]);
        uint256 totalReserveInNotion = getTokenAmountInNotion(underlyingAsset0Cached, poolReserves[0]) +
            reserve1InNotion;

        uint256 asset1BalanceInNotion = getTokenAmountInNotion(
            underlyingAsset1Cached,
            IERC20(underlyingAsset1Cached).balanceOf(address(this))
        );

        uint256 targetBalanceAsset1InNotion = asset1BalanceInNotion.mulDiv(reserve1InNotion, totalReserveInNotion);
        uint256 amountToSwap = Common.fromUnifiedDecimalsUint8(
            underlyingAsset1Cached,
            asset1BalanceInNotion - targetBalanceAsset1InNotion
        );

        (bool success, ) = ISwapRouter(IContainer(_strategyContainer).swapRouter()).tryPredefinedSwap(
            underlyingAsset1Cached,
            underlyingAsset0Cached,
            amountToSwap,
            0
        );

        require(success, SwapFailed(underlyingAsset1Cached, underlyingAsset0Cached, amountToSwap));
    }

    function _exitUnderlyingAssets(uint256 share) internal override {
        address underlyingAsset0Cached = underlyingAsset0;
        address underlyingAsset1Cached = underlyingAsset1;

        uint256 amount0 = IERC20(underlyingAsset0Cached).balanceOf(address(this));
        uint256 amountToSwap = amount0.mulDiv(share, MAX_BPS);

        (bool success, ) = ISwapRouter(IContainer(_strategyContainer).swapRouter()).tryPredefinedSwap(
            underlyingAsset0Cached,
            underlyingAsset1Cached,
            amountToSwap,
            0
        );

        require(success, SwapFailed(underlyingAsset0Cached, underlyingAsset1Cached, amountToSwap));
    }

    function _harvest(bytes32 _stateId, address _treasury, uint256 _feePct) internal override {
        if (_stateId != CURVE_GAUGE_STATE_ID) {
            return;
        }

        address gaugeCached = gauge;
        address lpTokenCached = lpToken;

        ILiquidityGaugeV6(gaugeCached).claim_rewards();
        uint256 claimedRewards = IERC20(underlyingAsset0).balanceOf(address(this));

        if (claimedRewards == 0) {
            return;
        }

        if (_feePct > 0) {
            uint256 feeToTreasury = claimedRewards.mulDiv(_feePct, MAX_BPS);
            IERC20(underlyingAsset0).safeTransfer(_treasury, feeToTreasury);
            claimedRewards -= feeToTreasury;
        }

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = claimedRewards;
        amounts[1] = 0;

        IERC20(underlyingAsset0).safeIncreaseAllowance(lpTokenCached, claimedRewards);
        ICurveStableSwapNG(lpTokenCached).add_liquidity(amounts, 0);

        uint256 lpBalance = IERC20(lpTokenCached).balanceOf(address(this));
        IERC20(lpTokenCached).safeIncreaseAllowance(gaugeCached, lpBalance);
        ILiquidityGaugeV6(gaugeCached).deposit(lpBalance);
    }
}
