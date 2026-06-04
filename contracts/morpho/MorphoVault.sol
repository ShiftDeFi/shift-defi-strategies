// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";
import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {IMorphoVault} from "../interfaces/IMorphoVault.sol";

import {IAngleMerkleDistributor} from "../dependencies/angle/IAngleMerkleDistributor.sol";

contract MorphoVault is AccessControlUpgradeable, StrategyTemplate, IMorphoVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice State ID for the Morpho vault state (morpho vault)
    bytes32 internal constant MORPHO_VAULT_STATE_ID = keccak256("MORPHO_VAULT_STATE_ID");

    /// @notice State ID for the underlying asset state (holding the asset directly)
    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");

    /// @notice Role for the Merkle claimer
    bytes32 private constant MERKLE_CLAIMER_ROLE = keccak256("MERKLE_CLAIMER_ROLE");

    /// @notice The Morpho vault address
    address public morphoVault;

    /// @notice The underlying asset address
    address public underlyingAsset;

    /// @notice The address of the Morpho Merkle distributor contract
    address public merkleDistributor;

    /// @notice The addresses of the reward tokens
    address[] public rewardTokens;

    /// @notice The last recorded value of vault token amount * share price
    uint256 public lastAssetsValue;

    struct SlippageParams {
        uint256 enterMaxSlippage;
        uint256 exitMaxSlippage;
        uint256 emergencyExitMaxSlippage;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the MorphoVaultStrategy contract
    /// @dev Sets up the Morpho vault, underlying asset, reward tokens, and configures the strategy states
    /// @param strategyContainer The address of the strategy container contract
    /// @param defaultAdmin The address of the default admin
    /// @param merkleClaimer The address of the Merkle claimer
    /// @param _morphoVault The address of the Morpho vault
    /// @param _merkleDistributor The address of the Merkle distributor
    /// @param _rewardTokens The addresses of the reward tokens
    /// @param slippageParams The slippage parameters

    function initialize(
        address strategyContainer,
        address defaultAdmin,
        address merkleClaimer,
        address _morphoVault,
        address _merkleDistributor,
        address[] calldata _rewardTokens,
        SlippageParams calldata slippageParams
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

        require(_morphoVault != address(0), Errors.ZeroAddress());
        morphoVault = _morphoVault;
        underlyingAsset = IERC4626(morphoVault).asset();

        require(_merkleDistributor != address(0), Errors.ZeroAddress());
        merkleDistributor = _merkleDistributor;

        _setRewardTokens(_rewardTokens);

        _setState(UNDERLYING_ASSET_STATE_ID, false, false, true, 0);
        _setState(MORPHO_VAULT_STATE_ID, true, true, false, 1);
    }

    /// @inheritdoc IMorphoVault
    function setRewardTokens(address[] memory _rewardTokens) external onlyStrategyContainerOrHarvestManager {
        _setRewardTokens(_rewardTokens);
    }

    function _setRewardTokens(address[] memory _rewardTokens) private {
        uint256 rewardTokensLength = _rewardTokens.length;
        address underlyingAssetCached = underlyingAsset;
        for (uint256 i = 0; i < rewardTokensLength; i++) {
            require(_rewardTokens[i] != address(0), Errors.ZeroAddress());
            require(_rewardTokens[i] != underlyingAssetCached, RewardTokenMatchesUnderlyingAsset());
        }
        rewardTokens = _rewardTokens;
        emit RewardTokensUpdated(_rewardTokens);
    }

    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == UNDERLYING_ASSET_STATE_ID) {
            return _underlyingAssetNav();
        } else if (stateId == MORPHO_VAULT_STATE_ID) {
            return _morphoVaultNav();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _underlyingAssetNav() private view returns (uint256) {
        address underlyingAssetCached = underlyingAsset;
        return getTokenAmountInNotion(underlyingAssetCached, IERC20(underlyingAssetCached).balanceOf(address(this)));
    }

    function _morphoVaultNav() private view returns (uint256) {
        address morphoVaultCached = morphoVault;
        uint256 lpAmount = IERC4626(morphoVaultCached).balanceOf(address(this));
        uint256 underlyingAssetAmount = IERC4626(morphoVaultCached).convertToAssets(lpAmount);
        return getTokenAmountInNotion(underlyingAsset, underlyingAssetAmount);
    }

    function _enterTarget() internal override {
        _enterMorphoVault();
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == MORPHO_VAULT_STATE_ID) {
            _enterMorphoVault();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _enterMorphoVault() private {
        address underlyingAssetCached = underlyingAsset;
        address morphoVaultCached = morphoVault;

        uint256 enterAmount = IERC20(underlyingAssetCached).balanceOf(address(this));

        if (enterAmount == 0) {
            return;
        }

        IERC20(underlyingAssetCached).safeIncreaseAllowance(morphoVaultCached, enterAmount);
        IERC4626(morphoVaultCached).deposit(enterAmount, address(this));

        lastAssetsValue = IERC4626(morphoVaultCached).convertToAssets(
            IERC4626(morphoVaultCached).balanceOf(address(this))
        );
    }

    function _exitTarget(uint256 share) internal override {
        _exitMorphoVault(share);
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal override {
        if (stateId == MORPHO_VAULT_STATE_ID) {
            _exitMorphoVault(share);
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _exitMorphoVault(uint256 share) private {
        address morphoVaultCached = morphoVault;

        uint256 lpAmount = IERC4626(morphoVaultCached).balanceOf(address(this));
        uint256 lpToWithdraw = lpAmount.mulDiv(share, MAX_BPS);

        if (lpToWithdraw == 0) {
            return;
        }

        IERC4626(morphoVaultCached).redeem(lpToWithdraw, address(this), address(this));

        lastAssetsValue = IERC4626(morphoVaultCached).convertToAssets(
            IERC4626(morphoVaultCached).balanceOf(address(this))
        );
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == UNDERLYING_ASSET_STATE_ID) {
            _exitMorphoVault(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }

    function _calculateAccruedAssetsValue() private view returns (uint256) {
        address morphoVaultCached = morphoVault;
        return
            IERC4626(morphoVaultCached).convertToAssets(IERC4626(morphoVaultCached).balanceOf(address(this))) -
            lastAssetsValue;
    }

    function _harvest(bytes32 _stateId, address _treasury, uint256 _feePct) internal override {
        AutomaticHarvestLocalVars memory vars;

        vars.morphoVaultCached = morphoVault;
        vars.underlyingAssetCached = underlyingAsset;
        vars.rewardTokensLength = rewardTokens.length;

        vars.accruedAssetsValue = _calculateAccruedAssetsValue();

        if (vars.accruedAssetsValue > 0) {
            vars.accruedVaultTokens = IERC4626(vars.morphoVaultCached).convertToShares(vars.accruedAssetsValue);
            vars.vaultTokensToTreasury = vars.accruedVaultTokens.mulDiv(_feePct, MAX_BPS);
        }

        for (uint256 i = 0; i < vars.rewardTokensLength; i++) {
            _swapToInputTokens(rewardTokens[i], vars.underlyingAssetCached, 0, false);
        }

        if (_stateId == MORPHO_VAULT_STATE_ID) {
            vars.lpAmountBefore = IERC4626(vars.morphoVaultCached).balanceOf(address(this));
            _enterMorphoVault();
            vars.reinvestLpDelta = IERC4626(vars.morphoVaultCached).balanceOf(address(this)) - vars.lpAmountBefore;

            if (vars.reinvestLpDelta > 0) {
                vars.feeFromReinvest = vars.reinvestLpDelta.mulDiv(_feePct, MAX_BPS);
                if (vars.feeFromReinvest > 0) {
                    vars.vaultTokensToTreasury += vars.feeFromReinvest;
                }
            }
        }

        if (vars.vaultTokensToTreasury > 0) {
            IERC20(vars.morphoVaultCached).safeTransfer(_treasury, vars.vaultTokensToTreasury);
            lastAssetsValue = IERC4626(vars.morphoVaultCached).convertToAssets(
                IERC4626(vars.morphoVaultCached).balanceOf(address(this))
            );
        }
    }

    /// @inheritdoc IMorphoVault
    function manualClaim(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external onlyRole(MERKLE_CLAIMER_ROLE) {
        ManualClaimLocalVars memory vars;

        vars.morphoVaultCached = morphoVault;
        vars.underlyingAssetCached = underlyingAsset;
        vars.strategyContainerCached = _strategyContainer;

        vars.rewardTokensLength = tokens.length;

        vars.treasury = IStrategyContainer(vars.strategyContainerCached).treasury();
        vars.feePct = IStrategyContainer(vars.strategyContainerCached).feePct();

        vars.accruedAssetsValue = _calculateAccruedAssetsValue();
        if (vars.accruedAssetsValue > 0) {
            vars.accruedVaultTokens = IERC4626(vars.morphoVaultCached).convertToShares(vars.accruedAssetsValue);
            vars.vaultTokensToTreasury = vars.accruedVaultTokens.mulDiv(vars.feePct, MAX_BPS);
        }

        vars.lpAmountBefore = IERC4626(vars.morphoVaultCached).balanceOf(address(this));

        vars.users = new address[](1);
        vars.users[0] = address(this);

        IAngleMerkleDistributor(merkleDistributor).claim(vars.users, tokens, amounts, proofs);

        for (uint256 i = 0; i < vars.rewardTokensLength; i++) {
            if (tokens[i] == vars.underlyingAssetCached) {
                _enterMorphoVault();
                break;
            }
        }

        vars.reinvestLpDelta = IERC4626(vars.morphoVaultCached).balanceOf(address(this)) - vars.lpAmountBefore;

        if (vars.reinvestLpDelta > 0) {
            vars.feeFromReinvest = vars.reinvestLpDelta.mulDiv(vars.feePct, MAX_BPS);
            if (vars.feeFromReinvest > 0) {
                vars.vaultTokensToTreasury += vars.feeFromReinvest;
            }
        }

        if (vars.vaultTokensToTreasury > 0) {
            IERC20(vars.morphoVaultCached).safeTransfer(vars.treasury, vars.vaultTokensToTreasury);
        }

        lastAssetsValue = IERC4626(vars.morphoVaultCached).convertToAssets(
            IERC4626(vars.morphoVaultCached).balanceOf(address(this))
        );
    }
}
