// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";
import {Errors} from "@shift-defi/core/libraries/helpers/Errors.sol";

import {IFluidSupply} from "../interfaces/IFluidSupply.sol";
import {IFluidLendingResolver} from "../dependencies/fluid/IFluidLendingResolver.sol";
import {IFluidMerkleDistributor} from "../dependencies/fluid/IFluidMerkleDistributor.sol";
import {IFluidToken} from "../dependencies/fluid/IFluidToken.sol";

contract FluidSupply is IFluidSupply, StrategyTemplate {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice State ID for the Fluid supply state (asset supplied to Fluid)
    bytes32 private constant FLUID_SUPPLY_STATE_ID = keccak256("FLUID_SUPPLY_STATE_ID");

    /// @notice State ID for the token only state (holding the asset directly)
    bytes32 private constant TOKEN_ONLY_STATE_ID = keccak256("TOKEN_ONLY_STATE_ID");

    /// @notice The Fluid fToken address
    address public fToken;

    /// @notice The underlying asset address
    address public asset;

    /// @notice The last recorded deposit balance in asset terms, used for harvest calculations
    uint256 public lastDepositBalance;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the FluidSupply strategy contract
    /// @dev Sets up the Fluid fToken and asset addresses, and configures the strategy states
    /// @param _agent The address of the strategy container contract
    /// @param _asset The address of the underlying asset
    /// @param _resolver The address of the Fluid lending resolver contract
    function initialize(address _agent, address _asset, address _resolver) external initializer {
        require(_agent != address(0), Errors.ZeroAddress());
        require(_asset != address(0), Errors.ZeroAddress());
        require(_resolver != address(0), Errors.ZeroAddress());

        __StrategyTemplate_init(_agent);
        _setState(FLUID_SUPPLY_STATE_ID, true, true, false, 1);
        _setState(TOKEN_ONLY_STATE_ID, false, false, true, 0);

        asset = _asset;
        fToken = IFluidLendingResolver(_resolver).computeFToken(_asset, "fToken");
    }

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == FLUID_SUPPLY_STATE_ID) {
            return fluidNav();
        } else if (stateId == TOKEN_ONLY_STATE_ID) {
            return assetNav();
        } else if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        } else {
            revert StateNotFound(stateId);
        }
    }

    /// @notice Calculates the NAV for the Fluid supply state
    /// @dev Returns the value of fTokens held by the contract in notion, using previewRedeem to get the underlying asset value
    /// @return The NAV of fTokens in notion
    function fluidNav() public view returns (uint256) {
        address fTokenCached = fToken;
        uint256 fBalance = IERC20(fTokenCached).balanceOf(address(this));
        uint256 navInNotion = IFluidToken(fTokenCached).previewRedeem(fBalance);
        return getTokenAmountInNotion(asset, navInNotion);
    }

    /// @notice Calculates the NAV for the asset state
    /// @dev Returns the value of assets held by the contract in notion
    /// @return The NAV of assets in notion
    function assetNav() public view returns (uint256) {
        address assetCached = asset;
        return getTokenAmountInNotion(assetCached, IERC20(assetCached).balanceOf(address(this)));
    }

    /// @notice Claims rewards from Fluid Merkle distributor and reinvests them
    /// @dev Claims rewards using merkle proof, swaps to asset, takes treasury fee, and reinvests remaining amount
    /// @param distributor The address of the Fluid Merkle distributor contract
    /// @param cumulativeAmount The cumulative reward amount to claim
    /// @param positionType The position type identifier
    /// @param positionId The position ID
    /// @param cycle The reward cycle number
    /// @param merkleProof The merkle proof for the claim
    /// @param metadata Additional metadata for the claim
    function claimAndReinvest(
        address distributor,
        uint256 cumulativeAmount,
        uint8 positionType,
        bytes32 positionId,
        uint256 cycle,
        bytes32[] calldata merkleProof,
        bytes memory metadata
    ) external {
        ClaimAndReinvestLocalVariables memory vars;
        vars.strategyContainer = _strategyContainer;

        require(
            AccessControlUpgradeable(vars.strategyContainer).hasRole(HARVEST_MANAGER_ROLE, msg.sender),
            Errors.Unauthorized()
        );

        vars.rewardToken = IFluidMerkleDistributor(distributor).TOKEN();
        vars.rewardsBalance = IERC20(vars.rewardToken).balanceOf(address(this));
        IFluidMerkleDistributor(distributor).claim(
            address(this),
            cumulativeAmount,
            positionType,
            positionId,
            cycle,
            merkleProof,
            metadata
        );

        if (IERC20(vars.rewardToken).balanceOf(address(this)) - vars.rewardsBalance > 0) {
            vars.assetCached = asset;
            vars.assetsBalance = IERC20(vars.assetCached).balanceOf(address(this));
            _swapToInputTokens(vars.rewardToken, vars.assetCached, 0, false);
            vars.rewardInAsset = IERC20(vars.assetCached).balanceOf(address(this)) - vars.assetsBalance;
            vars.treasuryFee = vars.rewardInAsset.mulDiv(IStrategyContainer(vars.strategyContainer).feePct(), BPS);
            if (vars.treasuryFee > 0)
                IERC20(vars.assetCached).safeTransfer(
                    IStrategyContainer(vars.strategyContainer).treasury(),
                    vars.treasuryFee
                );
            _enterFluid();
        }
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == TOKEN_ONLY_STATE_ID) {
            _exitFluid(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == FLUID_SUPPLY_STATE_ID) {
            _enterFluid();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal virtual override {
        if (stateId == FLUID_SUPPLY_STATE_ID) {
            _exitFluid(share);
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _enterTarget() internal override {
        _enterFluid();
    }

    function _exitTarget(uint256 share) internal override {
        _exitFluid(share);
    }

    function _enterFluid() internal {
        address assetCached = asset;
        address fTokenCached = fToken;
        uint256 balance = IERC20(assetCached).balanceOf(address(this));
        if (balance > 0) {
            IERC20(assetCached).safeIncreaseAllowance(fTokenCached, balance);
            IFluidToken(fTokenCached).deposit(balance, address(this));
            lastDepositBalance = IFluidToken(fTokenCached).previewRedeem(IERC20(fTokenCached).balanceOf(address(this)));
        }
    }

    function _exitFluid(uint256 share) internal {
        require(share > 0, Errors.ZeroAmount());
        require(share <= BPS, Errors.IncorrectAmount());

        address fTokenCached = fToken;
        uint256 liquidity = IERC20(fTokenCached).balanceOf(address(this)).mulDiv(share, BPS);
        if (liquidity > 0) {
            IERC20(fTokenCached).safeIncreaseAllowance(fTokenCached, liquidity);
            IFluidToken(fTokenCached).redeem(liquidity, address(this), address(this));
            lastDepositBalance = IFluidToken(fTokenCached).previewRedeem(IERC20(fTokenCached).balanceOf(address(this)));
        }
    }

    function _harvest(bytes32, address _treasury, uint256 _feePct) internal override {
        HarvestLocalVariables memory vars;
        vars.fToken = fToken;
        vars.asset = asset;
        vars.lastDepositBalance = lastDepositBalance;
        vars.fTokensInAsset = IFluidToken(vars.fToken).previewRedeem(IERC20(vars.fToken).balanceOf(address(this)));
        vars.incomeInAsset = vars.fTokensInAsset > vars.lastDepositBalance
            ? vars.fTokensInAsset - vars.lastDepositBalance
            : 0;
        if (vars.incomeInAsset == 0) return;

        vars.balanceBefore = IERC20(vars.asset).balanceOf(address(this));
        vars.treasuryFee = vars.incomeInAsset.mulDiv(_feePct, BPS);
        vars.shares = vars.treasuryFee.mulDiv(BPS, vars.fTokensInAsset);
        if (vars.shares > 0) _exitFluid(vars.shares);
        vars.balanceAfter = IERC20(vars.asset).balanceOf(address(this));

        if (vars.balanceAfter - vars.balanceBefore < vars.treasuryFee) {
            vars.treasuryFee = vars.balanceAfter - vars.balanceBefore;
        }
        IERC20(vars.asset).safeTransfer(_treasury, vars.treasuryFee);
    }
}
