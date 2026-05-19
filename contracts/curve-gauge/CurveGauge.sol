// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IContainer} from "@shift-defi/core/interfaces/IContainer.sol";
import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";

abstract contract CurveGauge is StrategyTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public gauge;
    address public lpToken;
    address public underlyingAsset0;
    address public underlyingAsset1;
    address internal swapRouter;

    bytes32 internal constant ONLY_NOTION_STATE_ID = keccak256("ONLY_NOTION_STATE_ID");
    bytes32 internal constant UNDERLYING_ASSETS_STATE_ID = keccak256("UNDERLYING_ASSETS_STATE_ID");
    bytes32 internal constant CURVE_LP_STATE_ID = keccak256("CURVE_LP_STATE_ID");
    bytes32 internal constant CURVE_GAUGE_STATE_ID = keccak256("CURVE_GAUGE_STATE_ID");

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address strategyContainer,
        address _gauge,
        uint256 _enterMaxSlippage,
        uint256 _exitMaxSlippage,
        uint256 _emergencyExitMaxSlippage
    ) external initializer {
        __StrategyTemplate_init(strategyContainer, _enterMaxSlippage, _exitMaxSlippage, _emergencyExitMaxSlippage);

        swapRouter = IContainer(strategyContainer).swapRouter();

        require(_gauge != address(0), Errors.ZeroAddress());
        gauge = _gauge;
        lpToken = ILiquidityGaugeV6(_gauge).lp_token();
        underlyingAsset0 = ICurveStableSwapNG(lpToken).coins(0);
        underlyingAsset1 = ICurveStableSwapNG(lpToken).coins(1);

        _setState(ONLY_NOTION_STATE_ID, false, false, true, 1);
        _setState(UNDERLYING_ASSETS_STATE_ID, false, false, true, 2);
        _setState(CURVE_LP_STATE_ID, false, true, false, 3);
        _setState(CURVE_GAUGE_STATE_ID, true, true, false, 4);
    }

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == CURVE_GAUGE_STATE_ID) {
            return _curveGaugeNav();
        } else if (stateId == CURVE_LP_STATE_ID) {
            return _curveLpNav();
        } else if (stateId == UNDERLYING_ASSETS_STATE_ID) {
            return _underlyingAssetsNav();
        } else if (stateId == ONLY_NOTION_STATE_ID) {
            return _onlyNotionNav();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _onlyNotionNav() internal view returns (uint256) {
        // TODO: This is non-zero in underlyingAssets stateId
        address notionCached = _notion;
        return getTokenAmountInNotion(notionCached, IERC20(notionCached).balanceOf(address(this)));
    }

    function _underlyingAssetsNav() internal view returns (uint256) {
        address asset0 = underlyingAsset0;
        address asset1 = underlyingAsset1;
        uint256 balance0 = IERC20(asset0).balanceOf(address(this));
        uint256 balance1 = IERC20(asset1).balanceOf(address(this));
        return getTokenAmountInNotion(asset0, balance0) + getTokenAmountInNotion(asset1, balance1);
    }

    function _curveLpNav() internal view returns (uint256) {
        address lpTokenCached = lpToken;
        uint256 lpBalance = IERC20(lpTokenCached).balanceOf(address(this));
        uint256 totalSupply = ICurveStableSwapNG(lpTokenCached).totalSupply();

        uint256[] memory poolReserves = ICurveStableSwapNG(lpTokenCached).get_balances();
        uint256 totalPoolNav = getTokenAmountInNotion(underlyingAsset0, poolReserves[0]) +
            getTokenAmountInNotion(underlyingAsset1, poolReserves[1]);

        return totalPoolNav.mulDiv(lpBalance, totalSupply);
    }

    function _curveGaugeNav() internal view returns (uint256) {
        address gaugeCached = gauge;
        uint256 stakedLp = ILiquidityGaugeV6(gaugeCached).balanceOf(address(this));

        address lpTokenCached = lpToken;
        uint256 totalSupply = ICurveStableSwapNG(lpTokenCached).totalSupply();

        uint256[] memory poolReserves = ICurveStableSwapNG(lpTokenCached).get_balances();
        uint256 totalPoolNav = getTokenAmountInNotion(underlyingAsset0, poolReserves[0]) +
            getTokenAmountInNotion(underlyingAsset1, poolReserves[1]);

        return totalPoolNav.mulDiv(stakedLp, totalSupply);
    }

    function _enterUnderlyingAssets() internal virtual;

    function _enterCurveLp() internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = IERC20(underlyingAsset0).balanceOf(address(this));
        amounts[1] = IERC20(underlyingAsset1).balanceOf(address(this));

        IERC20(underlyingAsset0).safeIncreaseAllowance(lpToken, amounts[0]);
        IERC20(underlyingAsset1).safeIncreaseAllowance(lpToken, amounts[1]);

        ICurveStableSwapNG(lpToken).add_liquidity(amounts, 0);
    }

    function _enterCurveGauge() internal {
        address lpTokenCached = lpToken;
        address gaugeCached = gauge;

        _enterCurveLp();

        uint256 lpBalance = IERC20(lpTokenCached).balanceOf(address(this));
        IERC20(lpTokenCached).safeIncreaseAllowance(gaugeCached, lpBalance);
        ILiquidityGaugeV6(gaugeCached).deposit(lpBalance);
    }

    function _enterTarget() internal override {
        _enterCurveGauge();
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == CURVE_GAUGE_STATE_ID) {
            _enterCurveGauge();
        } else if (stateId == CURVE_LP_STATE_ID) {
            _enterCurveLp();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _exitUnderlyingAssets(uint256 share) internal virtual;

    function _exitCurveLp(uint256 share) internal {
        address lpTokenCached = lpToken;
        uint256 lpBalance = IERC20(lpTokenCached).balanceOf(address(this));
        uint256 lpToWithdraw = lpBalance.mulDiv(share, MAX_BPS);

        uint256[] memory minAmountsOut = new uint256[](2);

        ICurveStableSwapNG(lpTokenCached).remove_liquidity(lpToWithdraw, minAmountsOut);
    }

    function _exitCurveGauge(uint256 share) internal {
        address gaugeCached = gauge;
        uint256 gaugeBalance = ILiquidityGaugeV6(gaugeCached).balanceOf(address(this));
        uint256 lpToWithdraw = gaugeBalance.mulDiv(share, MAX_BPS);
        ILiquidityGaugeV6(gaugeCached).withdraw(lpToWithdraw);
    }

    function _exitTarget(uint256 share) internal override {
        _exitCurveGauge(share);
        _exitCurveLp(MAX_BPS);
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal override {
        if (stateId == CURVE_GAUGE_STATE_ID) {
            _exitCurveGauge(share);
        } else if (stateId == CURVE_LP_STATE_ID) {
            _exitCurveLp(share);
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        address gaugeCached = gauge;
        if (toStateId == CURVE_LP_STATE_ID) {
            _exitCurveGauge(share);
        } else if (toStateId == UNDERLYING_ASSETS_STATE_ID) {
            // TODO: Check this function
            if (IERC20(gaugeCached).balanceOf(address(this)) > 0) {
                _exitCurveGauge(share);
                _exitCurveLp(MAX_BPS);
            } else {
                _exitCurveLp(share);
            }
        } else if (toStateId == ONLY_NOTION_STATE_ID) {
            if (IERC20(gaugeCached).balanceOf(address(this)) > 0) {
                _exitCurveGauge(share);
            }
            if (IERC20(lpToken).balanceOf(address(this)) > 0) {
                _exitCurveLp(share);
            }
            _exitUnderlyingAssets(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }
}
