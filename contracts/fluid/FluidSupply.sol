// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {IFluidSupply} from "../interfaces/IFluidSupply.sol";
import {IFluidMerkleDistributor} from "../dependencies/fluid/IFluidMerkleDistributor.sol";
import {IFluidToken} from "../dependencies/fluid/IFluidToken.sol";

contract FluidSupply is AccessControlUpgradeable, IFluidSupply, StrategyTemplate {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice State ID for the Fluid supply state (asset supplied to Fluid)
    bytes32 private constant FLUID_SUPPLY_STATE_ID = keccak256("FLUID_SUPPLY_STATE_ID");

    /// @notice State ID for the token only state (holding the asset directly)
    bytes32 private constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");

    /// @notice Role for the Merkle claimer
    bytes32 private constant MERKLE_CLAIMER_ROLE = keccak256("MERKLE_CLAIMER_ROLE");

    /// @notice Position type for lending positions of Fluid merkle rewards
    uint8 private constant POSITION_TYPE_LENDING = 1;

    /// @notice The Fluid fToken address
    address public fToken;

    /// @notice The underlying asset address
    address public underlyingAsset;

    /// @notice The last recorded value of vault token amount * share price
    uint256 public lastAssetsValue;

    /// @notice The address of the Fluid Merkle distributor contract
    address public merkleDistributor;

    /// @notice The address of the Merkle reward token
    address public merkleRewardToken;

    struct SlippageParams {
        uint256 enterMaxSlippage;
        uint256 exitMaxSlippage;
        uint256 emergencyExitMaxSlippage;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the FluidSupply strategy contract
    /// @dev Sets up the Fluid fToken and asset addresses, and configures the strategy states
    /// @param strategyContainer The address of the strategy container contract
    /// @param defaultAdmin The address of the default admin
    /// @param merkleClaimer The address of the Merkle claimer
    /// @param _fToken The address of the strategy's fToken
    /// @param _merkleDistributor The address of the Merkle distributor
    function initialize(
        address strategyContainer,
        address defaultAdmin,
        address merkleClaimer,
        address _fToken,
        address _merkleDistributor,
        SlippageParams memory slippageParams
    ) external initializer {
        __AccessControl_init();

        __StrategyTemplate_init(
            strategyContainer,
            slippageParams.enterMaxSlippage,
            slippageParams.exitMaxSlippage,
            slippageParams.emergencyExitMaxSlippage
        );

        require(defaultAdmin != address(0), Errors.ZeroAddress());
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        require(merkleClaimer != address(0), Errors.ZeroAddress());
        _grantRole(MERKLE_CLAIMER_ROLE, merkleClaimer);

        require(_fToken != address(0), Errors.ZeroAddress());
        fToken = _fToken;
        underlyingAsset = IFluidToken(_fToken).asset();

        require(_merkleDistributor != address(0), Errors.ZeroAddress());
        merkleDistributor = _merkleDistributor;

        merkleRewardToken = IFluidMerkleDistributor(_merkleDistributor).TOKEN();

        _setState(UNDERLYING_ASSET_STATE_ID, false, false, true, 0);
        _setState(FLUID_SUPPLY_STATE_ID, true, true, false, 1);
    }

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == FLUID_SUPPLY_STATE_ID) {
            return fluidNav();
        } else if (stateId == UNDERLYING_ASSET_STATE_ID) {
            return underlyingAssetNav();
        } else if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        } else {
            revert StateNotFound(stateId);
        }
    }

    /// @notice Calculates the NAV for the Fluid supply state
    /// @dev Returns the value of fTokens held by the contract in notion
    /// @return The NAV of fluid supply state in notion
    function fluidNav() public view returns (uint256) {
        address fTokenCached = fToken;
        uint256 fTokenBalance = IERC20(fTokenCached).balanceOf(address(this));
        return getTokenAmountInNotion(underlyingAsset, IFluidToken(fTokenCached).convertToAssets(fTokenBalance));
    }

    /// @notice Calculates the NAV for the asset state
    /// @dev Returns the value of assets held by the contract in notion
    /// @return The NAV of underlying assets state in notion
    function underlyingAssetNav() public view returns (uint256) {
        address underlyingAssetCached = underlyingAsset;
        return getTokenAmountInNotion(underlyingAssetCached, IERC20(underlyingAssetCached).balanceOf(address(this)));
    }

    /// @inheritdoc IFluidSupply
    function manualClaim(ClaimParams calldata claimParams) external nonReentrant onlyRole(MERKLE_CLAIMER_ROLE) {
        IFluidMerkleDistributor(merkleDistributor).claim(
            address(this),
            claimParams.cumulativeAmount,
            POSITION_TYPE_LENDING,
            bytes32(uint256(uint160(fToken))),
            claimParams.cycle,
            claimParams.merkleProof,
            claimParams.metadata
        );
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == UNDERLYING_ASSET_STATE_ID) {
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
        address underlyingAssetCached = underlyingAsset;
        address fTokenCached = fToken;
        uint256 underlyingAssetBalance = IERC20(underlyingAssetCached).balanceOf(address(this));

        if (underlyingAssetBalance == 0) {
            return;
        }

        IERC20(underlyingAssetCached).safeIncreaseAllowance(fTokenCached, underlyingAssetBalance);
        IFluidToken(fTokenCached).deposit(underlyingAssetBalance, address(this));
        lastAssetsValue = IFluidToken(fTokenCached).convertToAssets(IERC20(fTokenCached).balanceOf(address(this)));
    }

    function _exitFluid(uint256 share) internal {
        require(share > 0, Errors.ZeroAmount());
        require(share <= MAX_BPS, Errors.IncorrectAmount());

        address fTokenCached = fToken;
        uint256 fTokenAmountToRedeem = IERC20(fTokenCached).balanceOf(address(this)).mulDiv(share, MAX_BPS);

        if (fTokenAmountToRedeem == 0) {
            return;
        }

        IERC20(fTokenCached).safeIncreaseAllowance(fTokenCached, fTokenAmountToRedeem);
        IFluidToken(fTokenCached).redeem(fTokenAmountToRedeem, address(this), address(this));
        lastAssetsValue = IFluidToken(fTokenCached).convertToAssets(IERC20(fTokenCached).balanceOf(address(this)));
    }

    function _harvest(bytes32 _stateId, address _treasury, uint256 _feePct) internal override {
        AutomaticHarvestLocalVars memory vars;
        vars.fTokenCached = fToken;
        vars.lastAssetsValue = lastAssetsValue;
        vars.merkleRewardToken = merkleRewardToken;

        vars.accruedAssetsValue =
            IFluidToken(vars.fTokenCached).convertToAssets(IERC20(vars.fTokenCached).balanceOf(address(this))) -
            vars.lastAssetsValue;

        if (vars.accruedAssetsValue > 0) {
            vars.accruedFTokenAmount = IFluidToken(vars.fTokenCached).convertToShares(vars.accruedAssetsValue);
            vars.fTokensToTreasury = vars.accruedFTokenAmount.mulDiv(_feePct, MAX_BPS);
        }

        if (_stateId == FLUID_SUPPLY_STATE_ID) {
            if (IERC20(vars.merkleRewardToken).balanceOf(address(this)) > 0) {
                vars.fTokensAmountBefore = IERC20(vars.fTokenCached).balanceOf(address(this));
                _swapToInputTokens(vars.merkleRewardToken, underlyingAsset, 0, false);
                _enterFluid();
                vars.reinvestFTokenDelta =
                    IERC20(vars.fTokenCached).balanceOf(address(this)) - vars.fTokensAmountBefore;

                if (vars.reinvestFTokenDelta > 0) {
                    vars.feeFromReinvest = vars.reinvestFTokenDelta.mulDiv(_feePct, MAX_BPS);
                    if (vars.feeFromReinvest > 0) {
                        vars.fTokensToTreasury += vars.feeFromReinvest;
                    }
                }
            }
        }

        if (vars.fTokensToTreasury > 0) {
            IERC20(vars.fTokenCached).safeTransfer(_treasury, vars.fTokensToTreasury);
        }

        lastAssetsValue = IFluidToken(vars.fTokenCached).convertToAssets(
            IERC20(vars.fTokenCached).balanceOf(address(this))
        );
    }
}
