// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";

import {ICurveGauge} from "contracts/interfaces/ICurveGauge.sol";

contract CurveGauge is StrategyTemplate, ICurveGauge {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public gauge;
    address public lpToken;
    address public underlyingAsset0;
    address public underlyingAsset1;

    uint256 public lastStoredVirtualPrice;
    uint256 public lastStoredGaugeBalance;

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

        require(_gauge != address(0), Errors.ZeroAddress());
        gauge = _gauge;
        lpToken = ILiquidityGaugeV6(_gauge).lp_token();
        underlyingAsset0 = ICurveStableSwapNG(lpToken).coins(0);
        underlyingAsset1 = ICurveStableSwapNG(lpToken).coins(1);

        _setState(UNDERLYING_ASSETS_STATE_ID, false, false, true, 1);
        _setState(CURVE_LP_STATE_ID, false, true, false, 2);
        _setState(CURVE_GAUGE_STATE_ID, true, true, false, 3);

        lastStoredVirtualPrice = ICurveStableSwapNG(lpToken).get_virtual_price();
    }

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == CURVE_GAUGE_STATE_ID) {
            return _curveGaugeNav();
        } else if (stateId == CURVE_LP_STATE_ID) {
            return _curveLpNav();
        } else if (stateId == UNDERLYING_ASSETS_STATE_ID) {
            return _underlyingAssetsNav();
        } else {
            revert StateNotFound(stateId);
        }
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
        uint256 totalSupply = IERC20(lpTokenCached).totalSupply();

        if (totalSupply == 0) {
            return 0;
        }

        uint256[] memory poolReserves = ICurveStableSwapNG(lpTokenCached).get_balances();
        uint256 totalPoolNav = getTokenAmountInNotion(underlyingAsset0, poolReserves[0]) +
            getTokenAmountInNotion(underlyingAsset1, poolReserves[1]);

        return totalPoolNav.mulDiv(lpBalance, totalSupply);
    }

    function _curveGaugeNav() internal view returns (uint256) {
        address gaugeCached = gauge;
        uint256 stakedLp = ILiquidityGaugeV6(gaugeCached).balanceOf(address(this));

        address lpTokenCached = lpToken;
        uint256 totalSupply = IERC20(lpTokenCached).totalSupply();

        if (stakedLp == 0 || totalSupply == 0) {
            return 0;
        }

        uint256[] memory poolReserves = ICurveStableSwapNG(lpTokenCached).get_balances();
        uint256 totalPoolNav = getTokenAmountInNotion(underlyingAsset0, poolReserves[0]) +
            getTokenAmountInNotion(underlyingAsset1, poolReserves[1]);

        return totalPoolNav.mulDiv(stakedLp, totalSupply);
    }

    function _enterCurveLp() internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = IERC20(underlyingAsset0).balanceOf(address(this));
        amounts[1] = IERC20(underlyingAsset1).balanceOf(address(this));

        if (amounts[0] == 0 && amounts[1] == 0) {
            return;
        }

        if (amounts[0] > 0) {
            IERC20(underlyingAsset0).safeIncreaseAllowance(lpToken, amounts[0]);
        }
        if (amounts[1] > 0) {
            IERC20(underlyingAsset1).safeIncreaseAllowance(lpToken, amounts[1]);
        }

        ICurveStableSwapNG(lpToken).add_liquidity(amounts, 0);
    }

    function _enterCurveGauge() internal {
        address lpTokenCached = lpToken;
        address gaugeCached = gauge;

        uint256 lpBalance = IERC20(lpTokenCached).balanceOf(address(this));

        if (lpBalance == 0) {
            return;
        }

        IERC20(lpTokenCached).safeIncreaseAllowance(gaugeCached, lpBalance);
        ILiquidityGaugeV6(gaugeCached).deposit(lpBalance);

        lastStoredGaugeBalance = ILiquidityGaugeV6(gaugeCached).balanceOf(address(this));
        lastStoredVirtualPrice = ICurveStableSwapNG(lpTokenCached).get_virtual_price();
    }

    function _enterTarget() internal override {
        _enterCurveLp();
        _enterCurveGauge();
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == CURVE_GAUGE_STATE_ID) {
            _enterCurveLp();
            _enterCurveGauge();
        } else if (stateId == CURVE_LP_STATE_ID) {
            _enterCurveLp();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _exitCurveLp(uint256 share) internal {
        address lpTokenCached = lpToken;
        uint256 lpBalance = IERC20(lpTokenCached).balanceOf(address(this));
        uint256 lpToWithdraw = lpBalance.mulDiv(share, MAX_BPS);

        if (lpToWithdraw == 0) {
            return;
        }

        uint256[] memory minAmountsOut = new uint256[](2);

        ICurveStableSwapNG(lpTokenCached).remove_liquidity(lpToWithdraw, minAmountsOut);
    }

    function _exitCurveGauge(uint256 share) internal {
        address gaugeCached = gauge;
        uint256 gaugeBalance = ILiquidityGaugeV6(gaugeCached).balanceOf(address(this));
        uint256 gaugeLpToWithdraw = gaugeBalance.mulDiv(share, MAX_BPS);

        if (gaugeLpToWithdraw == 0) {
            return;
        }

        ILiquidityGaugeV6(gaugeCached).withdraw(gaugeLpToWithdraw);

        lastStoredGaugeBalance = ILiquidityGaugeV6(gaugeCached).balanceOf(address(this));
        lastStoredVirtualPrice = ICurveStableSwapNG(lpToken).get_virtual_price();
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
        bytes32 currentStateId = currentStateId();
        if (toStateId == CURVE_LP_STATE_ID) {
            _exitCurveGauge(share);
        } else if (toStateId == UNDERLYING_ASSETS_STATE_ID) {
            if (currentStateId == CURVE_GAUGE_STATE_ID) {
                _exitCurveGauge(share);
                _exitCurveLp(MAX_BPS);
            } else {
                _exitCurveLp(share);
            }
        } else {
            revert StateNotFound(toStateId);
        }
    }

    function _harvest(bytes32 _stateId, address _treasury, uint256 _feePct) internal override {
        AutomaticHarvestLocalVars memory vars;
        vars.gaugeCached = gauge;
        vars.lpTokenCached = lpToken;
        vars.asset0Cached = underlyingAsset0;
        vars.asset1Cached = underlyingAsset1;

        vars.lastStoredGaugeBalance = lastStoredGaugeBalance;
        vars.lastStoredVirtualPrice = lastStoredVirtualPrice;

        vars.currentGaugeBalance = ILiquidityGaugeV6(vars.gaugeCached).balanceOf(address(this));
        vars.currentVirtualPrice = ICurveStableSwapNG(vars.lpTokenCached).get_virtual_price();

        if (vars.lastStoredGaugeBalance == 0) {
            lastStoredGaugeBalance = vars.currentGaugeBalance;
            lastStoredVirtualPrice = vars.currentVirtualPrice;
            return;
        }

        if (_feePct > 0 && vars.currentVirtualPrice > vars.lastStoredVirtualPrice) {
            vars.accruedLpValue =
                (vars.currentGaugeBalance * vars.currentVirtualPrice -
                    vars.lastStoredGaugeBalance * vars.lastStoredVirtualPrice) / vars.currentVirtualPrice;

            vars.gaugeTokensToTreasury = vars.accruedLpValue.mulDiv(_feePct, MAX_BPS);
        }

        vars.asset0BalanceBefore = IERC20(vars.asset0Cached).balanceOf(address(this));
        vars.asset1BalanceBefore = IERC20(vars.asset1Cached).balanceOf(address(this));

        ILiquidityGaugeV6(vars.gaugeCached).claim_rewards();

        vars.asset0Rewards = IERC20(vars.asset0Cached).balanceOf(address(this)) - vars.asset0BalanceBefore;
        vars.asset1Rewards = IERC20(vars.asset1Cached).balanceOf(address(this)) - vars.asset1BalanceBefore;

        if ((vars.asset0Rewards != 0 || vars.asset1Rewards != 0) && _stateId == CURVE_GAUGE_STATE_ID) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = vars.asset0Rewards;
            amounts[1] = vars.asset1Rewards;

            IERC20(vars.asset0Cached).safeIncreaseAllowance(vars.lpTokenCached, amounts[0]);
            IERC20(vars.asset1Cached).safeIncreaseAllowance(vars.lpTokenCached, amounts[1]);

            ICurveStableSwapNG(vars.lpTokenCached).add_liquidity(amounts, 0);

            _enterCurveGauge();

            vars.reinvestGaugeDelta =
                ILiquidityGaugeV6(vars.gaugeCached).balanceOf(address(this)) - vars.currentGaugeBalance;

            if (vars.reinvestGaugeDelta > 0) {
                vars.feeFromReinvest = vars.reinvestGaugeDelta.mulDiv(_feePct, MAX_BPS);
                if (vars.feeFromReinvest > 0) {
                    vars.gaugeTokensToTreasury += vars.feeFromReinvest;
                }
            }
        }

        if (vars.gaugeTokensToTreasury > 0) {
            IERC20(vars.gaugeCached).safeTransfer(_treasury, vars.gaugeTokensToTreasury);
        }

        lastStoredGaugeBalance = ILiquidityGaugeV6(vars.gaugeCached).balanceOf(address(this));
        lastStoredVirtualPrice = ICurveStableSwapNG(vars.lpTokenCached).get_virtual_price();
    }
}
