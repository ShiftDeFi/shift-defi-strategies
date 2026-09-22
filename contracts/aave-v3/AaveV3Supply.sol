// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AaveV3SupplyBase} from "./AaveV3SupplyBase.sol";

contract AaveV3Supply is AaveV3SupplyBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

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

    function _harvest(bytes32, address treasury, uint256 feePct) internal override {
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
}
