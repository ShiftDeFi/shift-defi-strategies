// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {AaveV3SupplyBase} from "./AaveV3SupplyBase.sol";
import {IAngleMerkleDistributor} from "../dependencies/angle/IAngleMerkleDistributor.sol";
import {IAaveV3SupplyWithMerkle} from "../interfaces/IAaveV3SupplyWithMerkle.sol";

contract AaveV3SupplyWithMerkle is AccessControlUpgradeable, AaveV3SupplyBase, IAaveV3SupplyWithMerkle {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Role for the Merkle claimer
    bytes32 private constant MERKLE_CLAIMER_ROLE = keccak256("MERKLE_CLAIMER_ROLE");

    /// @notice The address of the Merkle distributor contract
    address public merkleDistributor;

    /// @notice The addresses of the reward tokens reinvested during automatic harvest
    address[] internal rewardTokens;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the AaveV3SupplyWithMerkle strategy contract
    /// @dev Composes `AaveV3SupplyBase`'s initializer with the Merkle claim setup inside one
    ///      `initializer`-guarded call
    /// @param strategyContainer The address of the strategy container contract
    /// @param defaultAdmin The address of the default admin
    /// @param merkleClaimer The address of the Merkle claimer
    /// @param _pool The address of the Aave V3 Pool contract
    /// @param _reserveAsset The address of the underlying asset to be supplied to Aave
    /// @param _merkleDistributor The address of the Merkle distributor
    /// @param _rewardTokens The addresses of the reward tokens
    /// @param slippageParams The enter/exit/emergency-exit maximum slippage parameters
    function initialize(
        address strategyContainer,
        address defaultAdmin,
        address merkleClaimer,
        address _pool,
        address _reserveAsset,
        address _merkleDistributor,
        address[] calldata _rewardTokens,
        SlippageParams calldata slippageParams
    ) external initializer {
        __AccessControl_init();
        __AaveV3Supply_init(strategyContainer, _pool, _reserveAsset, slippageParams);

        require(defaultAdmin != address(0), Errors.ZeroAddress());
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        require(merkleClaimer != address(0), Errors.ZeroAddress());
        _grantRole(MERKLE_CLAIMER_ROLE, merkleClaimer);

        require(_merkleDistributor != address(0), Errors.ZeroAddress());
        merkleDistributor = _merkleDistributor;

        _setRewardTokens(_rewardTokens);
    }

    /// @inheritdoc IAaveV3SupplyWithMerkle
    function getRewardTokens() external view override returns (address[] memory) {
        return rewardTokens;
    }

    /// @inheritdoc IAaveV3SupplyWithMerkle
    function setRewardTokens(address[] memory _rewardTokens) external onlyStrategyContainerOrHarvestManager {
        _setRewardTokens(_rewardTokens);
    }

    function _setRewardTokens(address[] memory _rewardTokens) private {
        uint256 rewardTokensLength = _rewardTokens.length;
        address reserveAssetCached = reserveAsset;
        address reserveATokenCached = reserveAToken;

        for (uint256 i = 0; i < rewardTokensLength; ++i) {
            require(_rewardTokens[i] != address(0), Errors.ZeroAddress());
            require(_rewardTokens[i] != reserveAssetCached, RewardTokenMatchesReserveAsset());
            require(_rewardTokens[i] != reserveATokenCached, RewardTokenMatchesReserveAToken());
        }

        rewardTokens = _rewardTokens;
        emit RewardTokensUpdated(_rewardTokens);
    }

    function _harvest(bytes32 stateId, address treasury, uint256 feePct) internal override {
        AutomaticHarvestLocalVars memory vars;
        vars.reserveATokenCached = reserveAToken;
        vars.reserveAssetCached = reserveAsset;
        vars.balanceBeforeReinvest = lastReserveATokenBalance;
        vars.currentBalance = IERC20(vars.reserveATokenCached).balanceOf(address(this));

        if (vars.currentBalance > vars.balanceBeforeReinvest) {
            vars.feeToTreasury = (vars.currentBalance - vars.balanceBeforeReinvest).mulDiv(feePct, MAX_BPS);
        }

        if (stateId == AAVE_RESERVE_SUPPLIED_STATE_ID) {
            for (uint256 i = 0; i < rewardTokens.length; ++i) {
               _swapToInputTokens(rewardTokens[i], vars.reserveAssetCached, 0, false);
            }
            vars.aTokenBalanceBefore = IERC20(vars.reserveATokenCached).balanceOf(address(this));
            _enterAaveReserveSupplied();
            vars.aTokenDelta = IERC20(vars.reserveATokenCached).balanceOf(address(this)) - vars.aTokenBalanceBefore;
            if (vars.aTokenDelta > 0) {
                vars.feeFromReinvest = vars.aTokenDelta.mulDiv(feePct, MAX_BPS);
                if (vars.feeFromReinvest > 0) {
                    vars.feeToTreasury += vars.feeFromReinvest;
                }
            }
        }

        if (vars.feeToTreasury > 0) {
            IERC20(vars.reserveATokenCached).safeTransfer(treasury, vars.feeToTreasury);
        }

        vars.currentBalance = IERC20(vars.reserveATokenCached).balanceOf(address(this));

        if (vars.currentBalance > vars.balanceBeforeReinvest) {
            lastReserveATokenBalance = vars.currentBalance;
        }
    }

    /// @inheritdoc IAaveV3SupplyWithMerkle
    function manualClaim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs)
        external
        nonReentrant
        onlyRole(MERKLE_CLAIMER_ROLE)
    {
        require(!isNavResolutionMode(), NavResolutionModeActivated());

        ManualClaimLocalVars memory vars;
        vars.reserveATokenCached = reserveAToken;
        vars.reserveAssetCached = reserveAsset;
        vars.strategyContainerCached = _strategyContainer;

        vars.treasury = IStrategyContainer(vars.strategyContainerCached).treasury();
        require(vars.treasury != address(0), Errors.ZeroAddress());
        vars.feePct = IStrategyContainer(vars.strategyContainerCached).feePct();
        vars.lastBalanceCached = lastReserveATokenBalance;

        vars.users = new address[](1);
        vars.users[0] = address(this);
        IAngleMerkleDistributor(merkleDistributor).claim(vars.users, tokens, amounts, proofs);

        if (currentStateId() == AAVE_RESERVE_SUPPLIED_STATE_ID) {
            uint256 tokensLength = tokens.length;
            for (uint256 i = 0; i < tokensLength; ++i) {
                if (tokens[i] == vars.reserveAssetCached) {
                    _enterAaveReserveSupplied();
                    break;
                }
            }

            vars.currentBalance = IERC20(vars.reserveATokenCached).balanceOf(address(this));
            if (vars.currentBalance > vars.lastBalanceCached) {
                vars.fee = Math.min(
                    (vars.currentBalance - vars.lastBalanceCached).mulDiv(vars.feePct, MAX_BPS), vars.currentBalance
                );
                if (vars.fee > 0) {
                    IERC20(vars.reserveATokenCached).safeTransfer(vars.treasury, vars.fee);
                }
            }
        }

        lastReserveATokenBalance = IERC20(vars.reserveATokenCached).balanceOf(address(this));
    }
}
