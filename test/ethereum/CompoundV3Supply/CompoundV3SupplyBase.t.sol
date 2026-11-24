// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {CompoundV3Supply} from "contracts/compound-v3/CompoundV3Supply.sol";
import {IComet} from "contracts/dependencies/compound-v3/IComet.sol";
import {ICompoundV3Supply} from "contracts/interfaces/ICompoundV3Supply.sol";

import {EthContext} from "test/ethereum/EthContext.t.sol";

abstract contract CompoundV3SupplyBase is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal compoundStrategy;
    address internal comet;
    address internal baseToken;
    address internal rewardToken;

    uint256 internal constant ENTER_AMOUNT = 100_000;
    uint256 internal constant REINVEST_AMOUNT = 10_000;
    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%

    uint256 internal constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    ICompoundV3Supply.SlippageParams internal SLIPPAGE_PARAMS = ICompoundV3Supply.SlippageParams({
        enterMaxSlippage: ENTER_MAX_SLIPPAGE,
        exitMaxSlippage: EXIT_MAX_SLIPPAGE,
        emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
    });

    bytes32 internal constant UNDERLYING_ASSETS_STATE_ID = keccak256("UNDERLYING_ASSETS_STATE_ID");
    bytes32 internal constant COMPOUND_V3_SUPPLIED_STATE_ID = keccak256("COMPOUND_V3_SUPPLIED_STATE_ID");

    function setUp() public virtual override {
        super.setUp();

        // Resolved after the fork switch in `EthContext.setUp()`, so a mock distributor lands on the active fork
        address merkleDistributor = _resolveMerkleDistributor();

        baseToken = IComet(comet).baseToken();

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = rewardToken;

        address implementation = address(new CompoundV3Supply());
        compoundStrategy = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(
                    CompoundV3Supply.initialize.selector,
                    mockStrategyContainer,
                    roles.defaultAdmin,
                    roles.merkleClaimer,
                    comet,
                    merkleDistributor,
                    rewardTokens,
                    SLIPPAGE_PARAMS
                )
            )
        );

        vm.label(address(compoundStrategy), "COMPOUND_V3_SUPPLY_STRATEGY");
        vm.label(comet, "COMET");

        address[] memory inputTokens = new address[](1);
        inputTokens[0] = baseToken;

        _addStrategy(address(compoundStrategy), inputTokens, inputTokens);
    }

    /// @dev Overridden by the manual-claim tests to deploy a `MockAngleMerkleDistributor` instead.
    function _resolveMerkleDistributor() internal virtual returns (address) {
        return COMPOUND_MERKLE_DISTRIBUTOR;
    }

    function _toBaseUnits(uint256 wholeTokens) internal view returns (uint256) {
        return wholeTokens * 10 ** uint256(IERC20Metadata(baseToken).decimals());
    }

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _toBaseUnits(ENTER_AMOUNT);

        deal(baseToken, mockStrategyContainer, amounts[0], true);

        vm.startPrank(mockStrategyContainer);
        IERC20(baseToken).forceApprove(address(compoundStrategy), type(uint256).max);

        uint256 minNavDelta =
            (compoundStrategy.getTokenAmountInNotion(baseToken, amounts[0]) * (MAX_BPS - ENTER_MAX_SLIPPAGE + ONE_PCT))
                / MAX_BPS;
        compoundStrategy.enter(amounts, minNavDelta);

        vm.stopPrank();
    }

    function test_EnterTarget() public {
        _enterStrategy();

        assertApproxEqRel(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            compoundStrategy.getTokenAmountInNotion(baseToken, _toBaseUnits(ENTER_AMOUNT)),
            NAV_TOLERANCE_PCT,
            "test_EnterTarget: Compound V3 NAV"
        );
        assertEq(IERC20(baseToken).balanceOf(address(compoundStrategy)), 0, "test_EnterTarget: base token left idle");
        assertEq(
            CompoundV3Supply(address(compoundStrategy)).lastCometBalance(),
            IComet(comet).balanceOf(address(compoundStrategy)),
            "test_EnterTarget: checkpoint is not the supplied balance"
        );
    }

    function test_Harvest_LendingInterestOnly() public {
        _enterStrategy();

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        uint256 treasuryBalanceBefore = IComet(comet).balanceOf(treasury);

        vm.prank(mockStrategyContainer);
        compoundStrategy.harvest();

        assertGt(
            IComet(comet).balanceOf(treasury),
            treasuryBalanceBefore,
            "test_Harvest_LendingInterestOnly: no performance fee taken on interest"
        );
    }

    function test_Harvest_ReinvestsIdleBaseToken() public {
        _enterStrategy();

        // Base token left on the strategy stands in for swapped reward tokens: `_harvest` reinvests it
        deal(baseToken, address(compoundStrategy), _toBaseUnits(REINVEST_AMOUNT), true);

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);
        uint256 treasuryBalanceBefore = IComet(comet).balanceOf(treasury);

        vm.prank(mockStrategyContainer);
        compoundStrategy.harvest();

        assertEq(
            IERC20(baseToken).balanceOf(address(compoundStrategy)),
            0,
            "test_Harvest_ReinvestsIdleBaseToken: base token not reinvested"
        );
        assertGt(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            navBefore,
            "test_Harvest_ReinvestsIdleBaseToken: reward not reinvested into Comet"
        );
        assertGt(
            IComet(comet).balanceOf(treasury),
            treasuryBalanceBefore,
            "test_Harvest_ReinvestsIdleBaseToken: no performance fee taken on reinvested reward"
        );
    }

    /// @dev A reward token the swap router cannot swap must stay on the strategy without reverting the harvest.
    function test_Harvest_DoesNotRevertOnUnswappableRewardToken() public {
        _enterStrategy();

        deal(rewardToken, address(compoundStrategy), 100 * 10 ** uint256(IERC20Metadata(rewardToken).decimals()));

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);

        vm.prank(mockStrategyContainer);
        compoundStrategy.harvest();

        assertGe(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID).mulDiv(MAX_BPS + NAV_TOLERANCE_PCT, MAX_BPS),
            navBefore,
            "test_Harvest_DoesNotRevertOnUnswappableRewardToken: NAV dropped"
        );
    }

    /// @dev At a 100% fee the post-fee balance returns to the checkpoint cached at the start of harvest, so the
    ///      final write must still replace the pre-fee balance `_enterCompoundV3Supplied` stored mid-harvest.
    function test_Harvest_ReinvestAtFullFeeSetsCheckpointToPostFeeBalance() public {
        _enterStrategy();

        vm.prank(roles.strategyManager);
        IStrategyContainer(mockStrategyContainer).setFeePct(MAX_BPS);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        deal(baseToken, address(compoundStrategy), _toBaseUnits(REINVEST_AMOUNT), true);

        vm.prank(mockStrategyContainer);
        compoundStrategy.harvest();

        // Comet converts transfers to principal and back, so the post-fee balance can land a wei off the checkpoint
        assertApproxEqAbs(
            CompoundV3Supply(address(compoundStrategy)).lastCometBalance(),
            IComet(comet).balanceOf(address(compoundStrategy)),
            2,
            "test_Harvest_ReinvestAtFullFeeSetsCheckpointToPostFeeBalance: checkpoint is not the post-fee balance"
        );
    }

    function test_ExitTarget_Partial() public {
        _enterStrategy();

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 expectedNavDelta = navBefore.mulDiv(partialShare, MAX_BPS);
        // Comet rounds the remaining principal down, so a half-share withdrawal can cost a wei more than half
        uint256 maxNavDelta = navBefore.mulDiv(partialShare + ONE_PCT / 100, MAX_BPS);

        vm.prank(mockStrategyContainer);
        compoundStrategy.exit(partialShare, maxNavDelta);

        uint256 navAfter = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);
        assertApproxEqRel(
            navAfter, navBefore - expectedNavDelta, NAV_TOLERANCE_PCT, "test_ExitTarget_Partial: Compound V3 NAV"
        );

        assertApproxEqRel(
            compoundStrategy.stateNav(UNDERLYING_ASSETS_STATE_ID),
            navBefore - navAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Underlying Asset NAV"
        );
        assertEq(
            CompoundV3Supply(address(compoundStrategy)).lastCometBalance(),
            IComet(comet).balanceOf(address(compoundStrategy)),
            "test_ExitTarget_Partial: checkpoint is not the remaining balance"
        );
    }

    function test_ExitTarget_Full() public {
        _enterStrategy();

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);

        vm.prank(mockStrategyContainer);
        compoundStrategy.exit(MAX_BPS, navBefore);

        assertEq(compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID), 0, "test_ExitTarget_Full: Compound V3 NAV");
        assertApproxEqRel(
            compoundStrategy.stateNav(UNDERLYING_ASSETS_STATE_ID),
            navBefore,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Full: Underlying Asset NAV"
        );
        assertEq(CompoundV3Supply(address(compoundStrategy)).lastCometBalance(), 0, "test_ExitTarget_Full: checkpoint");
    }

    function testRevert_StateNav_UnknownState() public {
        bytes32 unknownStateId = keccak256("UNKNOWN_STATE_ID");
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, unknownStateId));
        compoundStrategy.stateNav(unknownStateId);
    }
}
