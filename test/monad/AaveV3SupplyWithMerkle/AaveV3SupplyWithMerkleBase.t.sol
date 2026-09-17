// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {AaveV3Supply} from "contracts/aave-v3/AaveV3Supply.sol";
import {AaveV3SupplyWithMerkle} from "contracts/aave-v3/AaveV3SupplyWithMerkle.sol";

import {MonadContext} from "test/monad/MonadContext.t.sol";

abstract contract AaveV3SupplyWithMerkleBase is MonadContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal aaveSupplyStrategy;

    uint256 internal constant ENTER_AMOUNT = 100_000;
    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%

    uint256 internal constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    AaveV3Supply.SlippageParams internal SLIPPAGE_PARAMS =
        AaveV3Supply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");
    bytes32 internal constant AAVE_RESERVE_SUPPLIED_STATE_ID = keccak256("AAVE_RESERVE_SUPPLIED_STATE_ID");

    function setUp() public virtual override {
        super.setUp();

        // Resolved after the fork switch above, not before: a `MockAngleMerkleDistributor` deployed any
        // earlier would land on whatever fork was active before `MonadContext.setUp()` ran, which vanishes
        // once the switch happens (e.g. a `--fork-url` CLI flag establishing a separate root fork).
        address merkleDistributor = _resolveMerkleDistributor();

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = WMON;

        address implementation = address(new AaveV3SupplyWithMerkle());
        aaveSupplyStrategy = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(
                    AaveV3SupplyWithMerkle.initialize.selector,
                    mockStrategyContainer,
                    roles.defaultAdmin,
                    roles.merkleClaimer,
                    AAVE_V3_POOL,
                    USDC,
                    merkleDistributor,
                    rewardTokens,
                    SLIPPAGE_PARAMS
                )
            )
        );

        vm.label(address(aaveSupplyStrategy), "AAVE_V3_SUPPLY_WITH_MERKLE_STRATEGY");

        address[] memory inputTokens = new address[](1);
        inputTokens[0] = USDC;

        _addStrategy(address(aaveSupplyStrategy), inputTokens, inputTokens);
    }

    /// @dev Overridden by the manual-claim unit tests to deploy a `MockAngleMerkleDistributor` instead -
    ///      see the ordering note on the call site above.
    function _resolveMerkleDistributor() internal virtual returns (address) {
        return AAVE_MERKLE_DISTRIBUTOR;
    }

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(USDC).decimals());

        deal(USDC, mockStrategyContainer, amounts[0], true);

        vm.startPrank(mockStrategyContainer);
        IERC20(USDC).forceApprove(address(aaveSupplyStrategy), type(uint256).max);

        uint256 minNavDelta = (aaveSupplyStrategy.getTokenAmountInNotion(USDC, amounts[0]) *
            (MAX_BPS - ENTER_MAX_SLIPPAGE + ONE_PCT)) / MAX_BPS;
        aaveSupplyStrategy.enter(amounts, minNavDelta);

        vm.stopPrank();
    }

    function test_EnterTarget() public {
        _enterStrategy();

        assertApproxEqRel(
            aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID),
            Common.toUnifiedDecimalsUint8(USDC, ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(USDC).decimals())),
            NAV_TOLERANCE_PCT,
            "test_EnterTarget: Aave V3 Supply With Merkle NAV"
        );
    }

    function test_Harvest_LendingInterestOnly() public {
        _enterStrategy();

        vm.warp(block.timestamp + 100 minutes);
        vm.roll(block.number + 100);

        uint256 treasuryBalanceBefore = IERC20(A_MON_USDC).balanceOf(treasury);

        vm.startPrank(mockStrategyContainer);
        aaveSupplyStrategy.harvest();
        vm.stopPrank();

        uint256 treasuryBalanceAfter = IERC20(A_MON_USDC).balanceOf(treasury);
        assertGe(
            treasuryBalanceAfter,
            treasuryBalanceBefore,
            "test_Harvest_LendingInterestOnly: no treasury rewards"
        );
    }

    /// @dev Exercises the real WMON -> USDC predefined swap registered in `MonadContext` against the
    ///      Uniswap V3 adapter already deployed and whitelisted on the fork, not a no-op fallback.
    function test_Harvest_SwapsAndReinvestsRewardToken() public {
        _enterStrategy();

        uint256 rewardAmount = 1_000 ether;
        // adjustTotalSupply=false: WMON's totalSupply() mirrors the contract's native MON balance
        // rather than an SSTORE-backed counter, so stdstore can't locate a slot to adjust it.
        deal(WMON, address(aaveSupplyStrategy), rewardAmount, false);

        uint256 aTokenNavBefore = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        uint256 treasuryBalanceBefore = IERC20(A_MON_USDC).balanceOf(treasury);

        vm.startPrank(mockStrategyContainer);
        aaveSupplyStrategy.harvest();
        vm.stopPrank();

        assertEq(
            IERC20(WMON).balanceOf(address(aaveSupplyStrategy)),
            0,
            "test_Harvest_SwapsAndReinvestsRewardToken: WMON not fully swapped"
        );

        uint256 aTokenNavAfter = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        assertGt(
            aTokenNavAfter,
            aTokenNavBefore,
            "test_Harvest_SwapsAndReinvestsRewardToken: reward not reinvested into Aave"
        );

        uint256 treasuryBalanceAfter = IERC20(A_MON_USDC).balanceOf(treasury);
        assertGt(
            treasuryBalanceAfter,
            treasuryBalanceBefore,
            "test_Harvest_SwapsAndReinvestsRewardToken: no performance fee taken on reinvested reward"
        );
    }

    function test_ExitTarget_Partial() public {
        _enterStrategy();

        uint256 aaveNavBefore = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 expectedNavDelta = aaveNavBefore.mulDiv(partialShare, MAX_BPS);
        // `exit`'s `maxNavDelta` is an upper bound on the accepted NAV decrease. Aave's aToken withdraw
        // rounds the scaled-balance burn in the protocol's favor, so an exact half-share redemption can
        // cost a dust amount more than the naive half - allow a tiny epsilon of headroom above it.
        uint256 maxNavDelta = aaveNavBefore.mulDiv(partialShare + ONE_PCT / 100, MAX_BPS);

        vm.prank(mockStrategyContainer);
        aaveSupplyStrategy.exit(partialShare, maxNavDelta);

        uint256 aaveNavAfter = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        assertApproxEqRel(
            aaveNavAfter,
            aaveNavBefore - expectedNavDelta,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Aave V3 Supply With Merkle NAV"
        );

        uint256 underlyingAssetNav = aaveSupplyStrategy.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertApproxEqRel(
            underlyingAssetNav,
            aaveNavBefore - aaveNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Underlying Asset NAV"
        );

        uint256 exitedAmount = IERC20(USDC).balanceOf(address(aaveSupplyStrategy));
        assertApproxEqRel(
            Common.toUnifiedDecimalsUint8(USDC, exitedAmount),
            aaveNavBefore - aaveNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Exited Amount"
        );
    }

    function test_ExitTarget_Full() public {
        _enterStrategy();

        uint256 aaveNavBefore = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        uint256 maxNavDelta = aaveNavBefore;

        vm.prank(mockStrategyContainer);
        aaveSupplyStrategy.exit(MAX_BPS, maxNavDelta);

        uint256 aaveNavAfter = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        assertEq(aaveNavAfter, 0, "test_ExitTarget_Full: Aave V3 Supply With Merkle NAV");

        uint256 underlyingAssetNav = aaveSupplyStrategy.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertApproxEqRel(
            underlyingAssetNav,
            aaveNavBefore,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Full: Underlying Asset NAV"
        );

        uint256 exitedAmount = IERC20(USDC).balanceOf(address(aaveSupplyStrategy));
        assertApproxEqRel(
            Common.toUnifiedDecimalsUint8(USDC, exitedAmount),
            aaveNavBefore,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Full: Exited Amount"
        );
    }
}
