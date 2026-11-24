// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {ICompoundV3Supply} from "../interfaces/ICompoundV3Supply.sol";

import {IAngleMerkleDistributor} from "../dependencies/angle/IAngleMerkleDistributor.sol";
import {IComet} from "../dependencies/compound-v3/IComet.sol";

contract CompoundV3Supply is AccessControlUpgradeable, StrategyTemplate, ICompoundV3Supply {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice State ID for holding the base token directly
    bytes32 internal constant UNDERLYING_ASSETS_STATE_ID = keccak256("UNDERLYING_ASSETS_STATE_ID");

    /// @notice State ID for the base token supplied to the Comet market
    bytes32 internal constant COMPOUND_V3_SUPPLIED_STATE_ID = keccak256("COMPOUND_V3_SUPPLIED_STATE_ID");

    /// @notice Role for the Merkle claimer
    bytes32 private constant MERKLE_CLAIMER_ROLE = keccak256("MERKLE_CLAIMER_ROLE");

    /// @notice The Compound V3 (Comet) market address
    address public comet;

    /// @notice The base token of the Comet market, supplied by the strategy
    address public baseToken;

    /// @notice The address of the Merkl (Angle) distributor contract
    address public merkleDistributor;

    /// @notice The addresses of the reward tokens reinvested during automatic harvest
    address[] internal rewardTokens;

    /// @notice Comet balance, in base token units, at the last fee checkpoint
    uint256 public lastCometBalance;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the CompoundV3Supply strategy contract
    /// @param strategyContainer The address of the strategy container contract
    /// @param defaultAdmin The address of the default admin
    /// @param merkleClaimer The address of the Merkle claimer
    /// @param _comet The address of the Comet market
    /// @param _merkleDistributor The address of the Merkl (Angle) distributor
    /// @param _rewardTokens The addresses of the reward tokens
    /// @param slippageParams The enter/exit/emergency-exit maximum slippage parameters
    function initialize(
        address strategyContainer,
        address defaultAdmin,
        address merkleClaimer,
        address _comet,
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

        require(_comet != address(0), Errors.ZeroAddress());
        comet = _comet;
        baseToken = IComet(_comet).baseToken();

        require(_merkleDistributor != address(0), Errors.ZeroAddress());
        merkleDistributor = _merkleDistributor;

        _setRewardTokens(_rewardTokens);

        _setState(UNDERLYING_ASSETS_STATE_ID, false, false, true, 1);
        _setState(COMPOUND_V3_SUPPLIED_STATE_ID, true, true, false, 2);
    }

    /// @inheritdoc ICompoundV3Supply
    function getRewardTokens() external view override returns (address[] memory) {
        return rewardTokens;
    }

    /// @inheritdoc ICompoundV3Supply
    function setRewardTokens(address[] memory _rewardTokens) external onlyStrategyContainerOrHarvestManager {
        _setRewardTokens(_rewardTokens);
    }

    function _setRewardTokens(address[] memory _rewardTokens) private {
        uint256 rewardTokensLength = _rewardTokens.length;
        address baseTokenCached = baseToken;
        address cometCached = comet;

        for (uint256 i = 0; i < rewardTokensLength; ++i) {
            require(_rewardTokens[i] != address(0), Errors.ZeroAddress());
            require(_rewardTokens[i] != baseTokenCached, RewardTokenMatchesBaseToken());
            require(_rewardTokens[i] != cometCached, RewardTokenMatchesComet());
        }

        rewardTokens = _rewardTokens;
        emit RewardTokensUpdated(_rewardTokens);
    }

    // -------- Strategy Template Implementations --------

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == UNDERLYING_ASSETS_STATE_ID) {
            return _underlyingAssetNav();
        } else if (stateId == COMPOUND_V3_SUPPLIED_STATE_ID) {
            return _compoundV3SuppliedNav();
        } else if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        }
        revert StateNotFound(stateId);
    }

    function _underlyingAssetNav() private view returns (uint256) {
        address baseTokenCached = baseToken;
        return getTokenAmountInNotion(baseTokenCached, IERC20(baseTokenCached).balanceOf(address(this)));
    }

    function _compoundV3SuppliedNav() private view returns (uint256) {
        return getTokenAmountInNotion(baseToken, IComet(comet).balanceOf(address(this)));
    }

    function _enterTarget() internal override {
        _enterCompoundV3Supplied();
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == COMPOUND_V3_SUPPLIED_STATE_ID) {
            _enterCompoundV3Supplied();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _enterCompoundV3Supplied() private {
        address baseTokenCached = baseToken;
        uint256 baseTokenBalance = IERC20(baseTokenCached).balanceOf(address(this));

        if (baseTokenBalance == 0) {
            return;
        }

        address cometCached = comet;
        IERC20(baseTokenCached).forceApprove(cometCached, baseTokenBalance);
        IComet(cometCached).supply(baseTokenCached, baseTokenBalance);
        lastCometBalance = IComet(cometCached).balanceOf(address(this));
    }

    function _exitTarget(uint256 share) internal override {
        _exitCompoundV3Supplied(share);
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal override {
        if (stateId == COMPOUND_V3_SUPPLIED_STATE_ID) {
            _exitCompoundV3Supplied(share);
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == UNDERLYING_ASSETS_STATE_ID) {
            _exitCompoundV3Supplied(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }

    function _exitCompoundV3Supplied(uint256 share) private {
        address cometCached = comet;
        uint256 suppliedAmount = IComet(cometCached).balanceOf(address(this));
        require(suppliedAmount > 0, NoSupplyAllocation());

        uint256 amountToWithdraw = suppliedAmount.mulDiv(share, MAX_BPS, Math.Rounding.Floor);
        require(amountToWithdraw > 0, WithdrawAmountTooSmall());

        IComet(cometCached).withdraw(baseToken, amountToWithdraw);
        lastCometBalance = IComet(cometCached).balanceOf(address(this));
    }

    function _harvest(bytes32 stateId, address treasury, uint256 feePct) internal override {
        // Supplied state only: a transfer-paused Comet reverts the fee transfer, which must not block token-state exits
        if (stateId != COMPOUND_V3_SUPPLIED_STATE_ID) {
            return;
        }

        AutomaticHarvestLocalVars memory vars;
        vars.cometCached = comet;
        vars.baseTokenCached = baseToken;
        vars.balanceBeforeReinvest = lastCometBalance;
        vars.currentBalance = IComet(vars.cometCached).balanceOf(address(this));

        if (vars.currentBalance > vars.balanceBeforeReinvest) {
            vars.feeToTreasury =
                (vars.currentBalance - vars.balanceBeforeReinvest).mulDiv(feePct, MAX_BPS, Math.Rounding.Floor);
        }

        vars.rewardTokensLength = rewardTokens.length;
        for (uint256 i = 0; i < vars.rewardTokensLength; ++i) {
            _swapToInputTokens(rewardTokens[i], vars.baseTokenCached, 0, false);
        }

        vars.cometBalanceBefore = IComet(vars.cometCached).balanceOf(address(this));
        _enterCompoundV3Supplied();
        vars.cometBalanceDelta = IComet(vars.cometCached).balanceOf(address(this)) - vars.cometBalanceBefore;
        if (vars.cometBalanceDelta > 0) {
            vars.feeFromReinvest = vars.cometBalanceDelta.mulDiv(feePct, MAX_BPS, Math.Rounding.Floor);
            vars.feeToTreasury += vars.feeFromReinvest;
        }

        if (vars.feeToTreasury > 0) {
            IERC20(vars.cometCached).safeTransfer(treasury, vars.feeToTreasury);
        }

        vars.currentBalance = IComet(vars.cometCached).balanceOf(address(this));

        lastCometBalance = Math.max(vars.currentBalance, vars.balanceBeforeReinvest);
    }

    /// @inheritdoc ICompoundV3Supply
    function manualClaim(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external nonReentrant onlyRole(MERKLE_CLAIMER_ROLE) {
        require(!isNavResolutionMode(), NavResolutionModeActivated());

        ManualClaimLocalVars memory vars;
        vars.cometCached = comet;
        vars.baseTokenCached = baseToken;
        vars.strategyContainerCached = _strategyContainer;

        vars.treasury = IStrategyContainer(vars.strategyContainerCached).treasury();
        require(vars.treasury != address(0), Errors.ZeroAddress());
        vars.feePct = IStrategyContainer(vars.strategyContainerCached).feePct();
        vars.lastBalanceCached = lastCometBalance;

        vars.users = new address[](1);
        vars.users[0] = address(this);
        IAngleMerkleDistributor(merkleDistributor).claim(vars.users, tokens, amounts, proofs);

        if (currentStateId() == COMPOUND_V3_SUPPLIED_STATE_ID) {
            uint256 tokensLength = tokens.length;
            for (uint256 i = 0; i < tokensLength; ++i) {
                if (tokens[i] == vars.baseTokenCached) {
                    _enterCompoundV3Supplied();
                    break;
                }
            }

            vars.currentBalance = IComet(vars.cometCached).balanceOf(address(this));
            if (vars.currentBalance > vars.lastBalanceCached) {
                vars.fee =
                    (vars.currentBalance - vars.lastBalanceCached).mulDiv(vars.feePct, MAX_BPS, Math.Rounding.Floor);
                if (vars.fee > 0) {
                    IERC20(vars.cometCached).safeTransfer(vars.treasury, vars.fee);
                }
            }
        }

        lastCometBalance = IComet(vars.cometCached).balanceOf(address(this));
    }
}
