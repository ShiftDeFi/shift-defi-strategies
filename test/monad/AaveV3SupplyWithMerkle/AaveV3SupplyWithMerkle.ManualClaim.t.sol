// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {IAaveV3SupplyWithMerkle} from "contracts/interfaces/IAaveV3SupplyWithMerkle.sol";

import {MockAngleMerkleDistributor} from "test/mocks/MockAngleMerkleDistributor.sol";
import {AaveV3SupplyWithMerkleBase} from "./AaveV3SupplyWithMerkleBase.t.sol";

bytes32 constant MERKLE_CLAIMER_ROLE = keccak256("MERKLE_CLAIMER_ROLE");

/// @notice Exercises `AaveV3SupplyWithMerkle.manualClaim` itself (permissioning, reinvestment and the
///         NAV-resolution guard) against a `MockAngleMerkleDistributor`, since a real Merkle proof for a
///         not-yet-live strategy address does not exist. The real distributor's own proof handling is
///         checked independently, against a real historical claim, in MerkleRewardsClaim.t.sol.
contract AaveV3SupplyWithMerkleManualClaimTest is AaveV3SupplyWithMerkleBase {
    using Math for uint256;

    MockAngleMerkleDistributor internal mockDistributor;

    function setUp() public override {
        mockDistributor = new MockAngleMerkleDistributor();
        merkleDistributor = address(mockDistributor);
        super.setUp();
    }

    function test_ManualClaim_ReinvestsReserveAssetInstantly() public {
        _enterStrategy();

        uint256 claimAmount = 10_000 * 10 ** uint256(IERC20Metadata(USDC).decimals());
        deal(USDC, address(mockDistributor), claimAmount, true);

        uint256 aaveNavBefore = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        uint256 treasuryBalanceBefore = IERC20(A_MON_USDC).balanceOf(treasury);

        vm.prank(roles.merkleClaimer);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).manualClaim(
            _singleton(USDC),
            _singleton(claimAmount),
            _emptyProofs()
        );

        assertEq(
            IERC20(USDC).balanceOf(address(aaveSupplyStrategy)),
            0,
            "test_ManualClaim_ReinvestsReserveAssetInstantly: USDC not reinvested"
        );

        uint256 aaveNavAfter = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        assertGt(
            aaveNavAfter,
            aaveNavBefore,
            "test_ManualClaim_ReinvestsReserveAssetInstantly: claim not reinvested into Aave"
        );

        uint256 treasuryBalanceAfter = IERC20(A_MON_USDC).balanceOf(treasury);
        assertGt(
            treasuryBalanceAfter,
            treasuryBalanceBefore,
            "test_ManualClaim_ReinvestsReserveAssetInstantly: no performance fee taken on reinvested claim"
        );
    }

    function test_ManualClaim_LeavesNonReserveRewardForHarvest() public {
        _enterStrategy();

        uint256 claimAmount = 500 ether;
        // adjustTotalSupply=false: WMON's totalSupply() mirrors the contract's native MON balance
        // rather than an SSTORE-backed counter, so stdstore can't locate a slot to adjust it.
        deal(WMON, address(mockDistributor), claimAmount, false);

        vm.prank(roles.merkleClaimer);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).manualClaim(
            _singleton(WMON),
            _singleton(claimAmount),
            _emptyProofs()
        );

        assertEq(
            IERC20(WMON).balanceOf(address(aaveSupplyStrategy)),
            claimAmount,
            "test_ManualClaim_LeavesNonReserveRewardForHarvest: WMON not credited to strategy"
        );

        uint256 aaveNavBeforeHarvest = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);

        vm.prank(mockStrategyContainer);
        aaveSupplyStrategy.harvest();

        assertEq(
            IERC20(WMON).balanceOf(address(aaveSupplyStrategy)),
            0,
            "test_ManualClaim_LeavesNonReserveRewardForHarvest: WMON not swept by harvest"
        );
        assertGt(
            aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID),
            aaveNavBeforeHarvest,
            "test_ManualClaim_LeavesNonReserveRewardForHarvest: claimed WMON not reinvested by harvest"
        );
    }

    function testRevert_ManualClaim_Unauthorized() public {
        _enterStrategy();

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, users.alice, MERKLE_CLAIMER_ROLE)
        );
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).manualClaim(
            _singleton(USDC),
            _singleton(1),
            _emptyProofs()
        );
        vm.stopPrank();
    }

    function testRevert_ManualClaim_NavResolutionModeActivated() public {
        _enterStrategy();

        uint256 partialShare = MAX_BPS / 2;
        // `emergencyExit`'s third argument is `minNavDelta`, a lower bound the resulting target-state
        // NAV must clear - kept a tiny epsilon below the exact half so Aave's rounding can't trip it.
        uint256 minNavDelta = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID).mulDiv(
            partialShare - ONE_PCT / 100,
            MAX_BPS
        );

        vm.prank(roles.emergencyExecutor);
        aaveSupplyStrategy.emergencyExit(UNDERLYING_ASSET_STATE_ID, partialShare, minNavDelta);

        assertTrue(
            aaveSupplyStrategy.isNavResolutionMode(),
            "testRevert_ManualClaim_NavResolutionModeActivated: partial emergency exit did not activate NAV resolution mode"
        );

        vm.prank(roles.merkleClaimer);
        vm.expectRevert(IStrategyTemplate.NavResolutionModeActivated.selector);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).manualClaim(
            _singleton(USDC),
            _singleton(1),
            _emptyProofs()
        );
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
