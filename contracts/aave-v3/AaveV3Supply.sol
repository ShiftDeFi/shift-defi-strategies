// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {IPool} from "../dependencies/aave-v3/IPool.sol";
import {IAaveV3Supply} from "../interfaces/IAaveV3Supply.sol";

contract AaveV3Supply is StrategyTemplate, IAaveV3Supply {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Aave V3 Pool contract address
    address public pool;

    /// @notice The underlying asset address that is being supplied to Aave
    address public reserveAsset;

    /// @notice The aToken address corresponding to the reserve asset
    address public reserveAToken;

    /// @notice The last recorded balance of aTokens, used for harvest calculations
    uint256 public lastReserveATokenBalance;

    /// @notice State ID for the underlying asset state (holding the asset directly)
    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");

    /// @notice State ID for the Aave reserve supplied state (asset supplied to Aave)
    bytes32 internal constant AAVE_RESERVE_SUPPLIED_STATE_ID = keccak256("AAVE_RESERVE_SUPPLIED_STATE_ID");

    struct SlippageParams {
        uint256 enterMaxSlippage;
        uint256 exitMaxSlippage;
        uint256 emergencyExitMaxSlippage;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the AaveV3Supply strategy contract
    /// @dev Sets up the Aave pool, reserve asset, and aToken addresses, and configures the strategy states
    /// @param strategyContainer The address of the strategy container contract
    /// @param _pool The address of the Aave V3 Pool contract
    /// @param _reserveAsset The address of the underlying asset to be supplied to Aave
    /// @param slippageParams The enter/exit/emergency-exit maximum slippage parameters
    function initialize(
        address strategyContainer,
        address _pool,
        address _reserveAsset,
        SlippageParams calldata slippageParams
    ) external initializer {
        __AaveV3Supply_init(strategyContainer, _pool, _reserveAsset, slippageParams);
    }

    /// @dev Shared initializer logic, exposed so subclasses can compose it with their own additional setup
    ///      inside a single `initializer`-guarded call.
    function __AaveV3Supply_init(
        address strategyContainer,
        address _pool,
        address _reserveAsset,
        SlippageParams calldata slippageParams
    ) internal onlyInitializing {
        __StrategyTemplate_init(
            strategyContainer,
            slippageParams.enterMaxSlippage,
            slippageParams.exitMaxSlippage,
            slippageParams.emergencyExitMaxSlippage
        );

        require(_pool != address(0), Errors.ZeroAddress());
        pool = _pool;

        require(_reserveAsset != address(0), Errors.ZeroAddress());
        reserveAsset = _reserveAsset;

        reserveAToken = IPool(_pool).getReserveAToken(_reserveAsset);

        _setState(UNDERLYING_ASSET_STATE_ID, false, false, true, 0);
        _setState(AAVE_RESERVE_SUPPLIED_STATE_ID, true, true, false, 1);
    }

    // -------- Strategy Template Implementations --------

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == UNDERLYING_ASSET_STATE_ID) {
            return underlyingAssetNav();
        } else if (stateId == AAVE_RESERVE_SUPPLIED_STATE_ID) {
            return aaveReserveSuppliedNav();
        } else if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        }
        revert StateNotFound(stateId);
    }

    /// @notice Calculates the NAV for the underlying asset state
    /// @dev Returns the value of underlying assets held by the contract in notion
    /// @return The NAV of underlying assets in notion
    function underlyingAssetNav() public view returns (uint256) {
        address reserveAssetCached = reserveAsset;
        return getTokenAmountInNotion(reserveAssetCached, IERC20(reserveAssetCached).balanceOf(address(this)));
    }

    /// @notice Calculates the NAV for the Aave reserve supplied state
    /// @dev Returns the value of aTokens held by the contract in notion
    /// @return The NAV of aTokens in notion
    function aaveReserveSuppliedNav() public view returns (uint256) {
        return getTokenAmountInNotion(reserveAsset, IERC20(reserveAToken).balanceOf(address(this)));
    }

    function _enterTarget() internal override {
        _enterAaveReserveSupplied();
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == AAVE_RESERVE_SUPPLIED_STATE_ID) {
            _enterAaveReserveSupplied();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _enterAaveReserveSupplied() internal {
        address reserveAssetCached = reserveAsset;
        uint256 underlyingAssetBalance = IERC20(reserveAssetCached).balanceOf(address(this));

        if (underlyingAssetBalance == 0) {
            return;
        }

        address poolCached = pool;
        IERC20(reserveAssetCached).safeIncreaseAllowance(poolCached, underlyingAssetBalance);
        IPool(poolCached).supply(reserveAssetCached, underlyingAssetBalance, address(this), 0);
        lastReserveATokenBalance = IERC20(reserveAToken).balanceOf(address(this));
    }

    function _exitTarget(uint256 share) internal override {
        _exitAaveReserveSupplied(share);
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal override {
        if (stateId == AAVE_RESERVE_SUPPLIED_STATE_ID) {
            _exitAaveReserveSupplied(share);
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _exitAaveReserveSupplied(uint256 share) internal {
        uint256 allocatedAmount = IERC20(reserveAToken).balanceOf(address(this));
        require(allocatedAmount > 0, NoReserveAllocation());

        uint256 amountToWithdraw = allocatedAmount.mulDiv(share, MAX_BPS);
        _exitAaveReserveSuppliedFlat(amountToWithdraw);
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == UNDERLYING_ASSET_STATE_ID) {
            _exitAaveReserveSupplied(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }

    function _harvest(bytes32, address treasury, uint256 feePct) internal virtual override {
        AaveHarvestLocalVars memory vars;
        vars.reserveATokenCached = reserveAToken;
        vars.currentReserveATokenBalance = IERC20(vars.reserveATokenCached).balanceOf(address(this));
        vars.lastReserveATokenBalanceCached = lastReserveATokenBalance;

        if (vars.currentReserveATokenBalance <= vars.lastReserveATokenBalanceCached) {
            return;
        }

        vars.income = vars.currentReserveATokenBalance - vars.lastReserveATokenBalanceCached;
        vars.fee = Math.min(vars.income.mulDiv(feePct, MAX_BPS), vars.currentReserveATokenBalance);

        if (vars.fee > 0) {
            IERC20(vars.reserveATokenCached).safeTransfer(treasury, vars.fee);
        }

        lastReserveATokenBalance = IERC20(vars.reserveATokenCached).balanceOf(address(this));
    }

    function _exitAaveReserveSuppliedFlat(uint256 amount) internal returns (uint256) {
        require(amount > 0, WithdrawAmountTooSmall());
        address reserveAssetCached = reserveAsset;

        uint256 reserveBalanceBefore = IERC20(reserveAssetCached).balanceOf(address(this));
        uint256 withdrawnAmount = IPool(pool).withdraw(reserveAssetCached, amount, address(this));

        require(
            IERC20(reserveAssetCached).balanceOf(address(this)) >= reserveBalanceBefore + withdrawnAmount,
            WithdrawAmountMismatch()
        );

        lastReserveATokenBalance = IERC20(reserveAToken).balanceOf(address(this));
        return withdrawnAmount;
    }

    uint256[50] private __gap;
}
