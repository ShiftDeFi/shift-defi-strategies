// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {CompoundV3Supply} from "contracts/compound-v3/CompoundV3Supply.sol";
import {IComet} from "contracts/dependencies/compound-v3/IComet.sol";
import {ICompoundV3Supply} from "contracts/interfaces/ICompoundV3Supply.sol";

import {MockAngleMerkleDistributor} from "test/mocks/MockAngleMerkleDistributor.sol";
import {CompoundV3SupplyBase} from "./CompoundV3SupplyBase.t.sol";

/// @notice Exercises `CompoundV3Supply.manualClaim` against a `MockAngleMerkleDistributor`, since no real Merkle
///         proof exists for a not-yet-live strategy address. The real distributor's proof handling is covered
///         against a historical claim in `test/ethereum/MorphoVault/MerkleRewardsClaim.t.sol`.
contract CompoundV3SupplyManualClaimTest is CompoundV3SupplyBase {
    using Math for uint256;

    bytes32 internal constant MERKLE_CLAIMER_ROLE = keccak256("MERKLE_CLAIMER_ROLE");

    MockAngleMerkleDistributor internal mockDistributor;

    function setUp() public override {
        comet = COMPOUND_V3_USDT;
        rewardToken = COMP;
        super.setUp();
    }

    function _resolveMerkleDistributor() internal override returns (address) {
        mockDistributor = new MockAngleMerkleDistributor();
        return address(mockDistributor);
    }

    function test_ManualClaim_ReinvestsBaseTokenInstantly() public {
        _enterStrategy();

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        uint256 claimAmount = _toBaseUnits(REINVEST_AMOUNT);
        deal(baseToken, address(mockDistributor), claimAmount, true);

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);
        uint256 treasuryBalanceBefore = IComet(comet).balanceOf(treasury);

        vm.prank(roles.merkleClaimer);
        ICompoundV3Supply(address(compoundStrategy))
            .manualClaim(_singleton(baseToken), _singleton(claimAmount), _emptyProofs());

        assertEq(
            IERC20(baseToken).balanceOf(address(compoundStrategy)),
            0,
            "test_ManualClaim_ReinvestsBaseTokenInstantly: base token not reinvested"
        );
        assertGt(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            navBefore,
            "test_ManualClaim_ReinvestsBaseTokenInstantly: claim not reinvested into Comet"
        );
        assertGt(
            IComet(comet).balanceOf(treasury),
            treasuryBalanceBefore,
            "test_ManualClaim_ReinvestsBaseTokenInstantly: no performance fee taken on reinvested claim"
        );
        assertEq(
            CompoundV3Supply(address(compoundStrategy)).lastCometBalance(),
            IComet(comet).balanceOf(address(compoundStrategy)),
            "test_ManualClaim_ReinvestsBaseTokenInstantly: checkpoint is not the post-fee balance"
        );
    }

    function test_ManualClaim_LeavesRewardTokenForHarvest() public {
        _enterStrategy();

        uint256 claimAmount = 100 ether;
        deal(COMP, address(mockDistributor), claimAmount);

        uint256 navBefore = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);

        vm.prank(roles.merkleClaimer);
        ICompoundV3Supply(address(compoundStrategy))
            .manualClaim(_singleton(COMP), _singleton(claimAmount), _emptyProofs());

        assertEq(
            IERC20(COMP).balanceOf(address(compoundStrategy)),
            claimAmount,
            "test_ManualClaim_LeavesRewardTokenForHarvest: COMP not credited to strategy"
        );
        assertApproxEqRel(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            navBefore,
            NAV_TOLERANCE_PCT,
            "test_ManualClaim_LeavesRewardTokenForHarvest: Compound V3 NAV moved"
        );
    }

    function test_ManualClaim_ClaimsWithoutReinvestingWhenNotSupplied() public {
        _enterStrategy();

        // A full-share emergency exit lands in `UNDERLYING_ASSETS_STATE_ID` with NAV resolution mode off again
        uint256 navBeforeExit = compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID);
        vm.prank(roles.emergencyExecutor);
        compoundStrategy.emergencyExit(UNDERLYING_ASSETS_STATE_ID, MAX_BPS, navBeforeExit);

        assertFalse(
            compoundStrategy.isNavResolutionMode(),
            "test_ManualClaim_ClaimsWithoutReinvestingWhenNotSupplied: NAV resolution mode left on"
        );

        uint256 baseBalanceBefore = IERC20(baseToken).balanceOf(address(compoundStrategy));
        uint256 treasuryBalanceBefore = IComet(comet).balanceOf(treasury);

        uint256 claimAmount = _toBaseUnits(REINVEST_AMOUNT);
        deal(baseToken, address(mockDistributor), claimAmount, true);

        vm.prank(roles.merkleClaimer);
        ICompoundV3Supply(address(compoundStrategy))
            .manualClaim(_singleton(baseToken), _singleton(claimAmount), _emptyProofs());

        assertEq(
            IERC20(baseToken).balanceOf(address(compoundStrategy)),
            baseBalanceBefore + claimAmount,
            "test_ManualClaim_ClaimsWithoutReinvestingWhenNotSupplied: claim not credited to strategy"
        );
        assertEq(
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID),
            0,
            "test_ManualClaim_ClaimsWithoutReinvestingWhenNotSupplied: claim reinvested while not supplied"
        );
        assertEq(
            IComet(comet).balanceOf(treasury),
            treasuryBalanceBefore,
            "test_ManualClaim_ClaimsWithoutReinvestingWhenNotSupplied: fee taken while not supplied"
        );
    }

    function testRevert_ManualClaim_Unauthorized() public {
        _enterStrategy();

        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, users.alice, MERKLE_CLAIMER_ROLE
            )
        );
        ICompoundV3Supply(address(compoundStrategy)).manualClaim(_singleton(baseToken), _singleton(1), _emptyProofs());
    }

    function testRevert_ManualClaim_NavResolutionModeActivated() public {
        _enterStrategy();

        uint256 partialShare = MAX_BPS / 2;
        uint256 minNavDelta =
            compoundStrategy.stateNav(COMPOUND_V3_SUPPLIED_STATE_ID).mulDiv(partialShare - ONE_PCT / 100, MAX_BPS);

        vm.prank(roles.emergencyExecutor);
        compoundStrategy.emergencyExit(UNDERLYING_ASSETS_STATE_ID, partialShare, minNavDelta);

        assertTrue(
            compoundStrategy.isNavResolutionMode(),
            "testRevert_ManualClaim_NavResolutionModeActivated: partial emergency exit did not activate NAV resolution mode"
        );

        vm.prank(roles.merkleClaimer);
        vm.expectRevert(IStrategyTemplate.NavResolutionModeActivated.selector);
        ICompoundV3Supply(address(compoundStrategy)).manualClaim(_singleton(baseToken), _singleton(1), _emptyProofs());
    }

    function _singleton(address token) private pure returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = token;
    }

    function _singleton(uint256 amount) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = amount;
    }

    function _emptyProofs() private pure returns (bytes32[][] memory proofs) {
        proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);
    }
}
