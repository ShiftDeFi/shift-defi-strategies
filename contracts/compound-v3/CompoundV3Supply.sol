// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {ICompoundV3Supply} from "../interfaces/ICompoundV3Supply.sol";
import {IcASSETv3, IcRewards} from "../dependencies/compound-v3/ICompoundV3.sol";

contract CompoundV3Supply is ICompoundV3Supply, StrategyTemplate {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice State ID for the Compound supply state (asset supplied to Compound)
    bytes32 private constant COMPOUND_SUPPLY_STATE_ID = keccak256("COMPOUND_SUPPLY_STATE_ID");

    /// @notice State ID for the token only state (holding the deposit token directly)
    bytes32 private constant TOKEN_ONLY_STATE_ID = keccak256("TOKEN_ONLY_STATE_ID");

    uint256 private _cTokenDecimalsFactor;
    uint256 private _dTokenDecimalsFactor;

    /// @notice The Compound cToken address
    address public cToken;

    /// @notice The underlying deposit token address
    address public depositToken;

    /// @notice The Compound rewards contract address
    address public rewards;

    /// @notice The COMP token address used for rewards
    address public compToken;

    /// @notice The last recorded balance of cTokens, used for harvest calculations
    uint256 public cTokenLastBalance;

    /// @notice Initializes the CompoundV3Supply strategy contract
    /// @dev Sets up the Compound cToken, rewards contract, and deposit token addresses, and configures the strategy states
    /// @param agent The address of the strategy container contract
    /// @param _cToken The address of the Compound cToken
    /// @param _rewards The address of the Compound rewards contract
    /// @param _compToken The address of the COMP token
    function initialize(address agent, address _cToken, address _rewards, address _compToken) public initializer {
        require(agent != address(0), Errors.ZeroAddress());
        require(_cToken != address(0), Errors.ZeroAddress());
        require(_rewards != address(0), Errors.ZeroAddress());

        __StrategyTemplate_init(agent);
        _setState(COMPOUND_SUPPLY_STATE_ID, true, true, false, 1);
        _setState(TOKEN_ONLY_STATE_ID, false, false, true, 0);

        address dToken = IcASSETv3(_cToken).baseToken();
        depositToken = dToken;
        cToken = _cToken;
        rewards = _rewards;
        compToken = _compToken;
        _cTokenDecimalsFactor = 10 ** IERC20Metadata(_cToken).decimals();
        _dTokenDecimalsFactor = 10 ** IERC20Metadata(dToken).decimals();
    }

    /// @inheritdoc IStrategyTemplate
    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == COMPOUND_SUPPLY_STATE_ID) {
            return compoundNav();
        } else if (stateId == TOKEN_ONLY_STATE_ID) {
            return depositTokenNav();
        } else if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        } else {
            revert StateNotFound(stateId);
        }
    }

    /// @notice Calculates the NAV for the deposit token state
    /// @dev Returns the value of deposit tokens held by the contract in notion
    /// @return The NAV of deposit tokens in notion
    function depositTokenNav() public view returns (uint256) {
        return getTokenAmountInNotion(depositToken, IERC20(depositToken).balanceOf(address(this)));
    }

    /// @notice Calculates the NAV for the Compound supply state
    /// @dev Returns the value of cTokens held by the contract in notion, accounting for decimal differences
    /// @return The NAV of cTokens in notion
    function compoundNav() public view returns (uint256) {
        uint256 cBalance = IERC20(cToken).balanceOf(address(this));
        uint256 cBalanceInNotion = cBalance.mulDiv(_dTokenDecimalsFactor, _cTokenDecimalsFactor);
        return getTokenAmountInNotion(depositToken, cBalanceInNotion);
    }

    function _harvest(bytes32, address _treasury, uint256 _feePct) internal override {
        InternalHarvestLocalVars memory vars;
        vars.depositToken = depositToken;
        vars.cToken = cToken;
        vars.cTokenDecimalsFactor = _cTokenDecimalsFactor;
        vars.dTokenDecimalsFactor = _dTokenDecimalsFactor;

        vars.cTokenIncome = IERC20(vars.cToken).balanceOf(address(this)) - cTokenLastBalance;
        vars.cTokenIncomeInAsset = vars.cTokenIncome.mulDiv(vars.dTokenDecimalsFactor, vars.cTokenDecimalsFactor);

        IcRewards(rewards).claim(vars.cToken, address(this), true);
        vars.beforeBalance = IERC20(vars.depositToken).balanceOf(address(this));
        _swapToInputTokens(compToken, vars.depositToken, 0, false);

        vars.compRewardsInAsset = IERC20(vars.depositToken).balanceOf(address(this)) - vars.beforeBalance;
        vars.treasuryFee = (vars.compRewardsInAsset + vars.cTokenIncomeInAsset).mulDiv(_feePct, MAX_BPS);

        if (vars.compRewardsInAsset >= vars.treasuryFee) {
            if (vars.treasuryFee > 0) {
                IERC20(vars.depositToken).safeTransfer(_treasury, vars.treasuryFee);
            }
            _enterCompound();
        } else {
            vars.missingFeeInAsset = vars.treasuryFee - vars.compRewardsInAsset;
            vars.cTokensToWithdraw = vars.missingFeeInAsset.mulDiv(
                vars.cTokenDecimalsFactor,
                vars.dTokenDecimalsFactor
            );
            _exitCompoundFlat(vars.cTokensToWithdraw);
            IERC20(vars.depositToken).safeTransfer(_treasury, vars.treasuryFee);
        }
    }

    function _exitTarget(uint256 share) internal override {
        _exitCompound(share);
    }

    function _enterTarget() internal override {
        _enterCompound();
    }

    function _enterState(bytes32 stateId) internal override {
        if (stateId == COMPOUND_SUPPLY_STATE_ID) {
            _enterCompound();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal override {
        if (stateId == COMPOUND_SUPPLY_STATE_ID) {
            _exitCompound(share);
        } else if (stateId == TOKEN_ONLY_STATE_ID) {
            _exitDepositTokensOnly(share);
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == TOKEN_ONLY_STATE_ID) {
            _exitCompound(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }

    function _enterCompound() internal {
        InternalEnterLocalVars memory vars;
        vars.depositToken = depositToken;
        vars.cToken = cToken;
        vars.balance = IERC20(vars.depositToken).balanceOf(address(this));
        if (vars.balance > 0) {
            IERC20(vars.depositToken).forceApprove(vars.cToken, vars.balance);
            IcASSETv3(vars.cToken).supply(vars.depositToken, vars.balance);
        }
        cTokenLastBalance = IERC20(vars.cToken).balanceOf(address(this));
    }

    function _exitCompound(uint256 share) internal {
        if (share == 0) revert Errors.ZeroAmount();

        InternalExitLocalVars memory vars;
        vars.cToken = cToken;
        vars.balance = IERC20(vars.cToken).balanceOf(address(this));
        vars.liquidity = vars.balance.mulDiv(share, MAX_BPS, Math.Rounding.Floor);
        if (vars.liquidity > 0) {
            IcASSETv3(vars.cToken).withdraw(depositToken, vars.liquidity);
        }
        cTokenLastBalance = IERC20(vars.cToken).balanceOf(address(this));
    }

    function _exitCompoundFlat(uint256 amount) internal {
        if (amount == 0) revert Errors.ZeroAmount();

        InternalExitLocalVars memory vars;
        vars.cToken = cToken;
        if (amount > 0) {
            IcASSETv3(vars.cToken).withdraw(depositToken, amount);
        }
        cTokenLastBalance = IERC20(vars.cToken).balanceOf(address(this));
    }

    function _exitDepositTokensOnly(uint256 share) internal {}
}
