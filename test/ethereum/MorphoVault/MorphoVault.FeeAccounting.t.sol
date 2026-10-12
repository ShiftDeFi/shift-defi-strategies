// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IMorphoVault} from "contracts/interfaces/IMorphoVault.sol";
import {MorphoVault} from "contracts/morpho/MorphoVault.sol";

import {MockAngleMerkleDistributor} from "test/mocks/MockAngleMerkleDistributor.sol";
import {MorphoVaultBase} from "./MorphoVaultBase.t.sol";

/// @notice Regression tests for the fee baseline after a reinvesting harvest or claim: `lastAssetsValue`
///         must equal the position value after the fee shares leave for the treasury, not the pre-fee
///         value `_enterMorphoVault` writes mid-harvest, or the next yield worth the fee goes uncharged.
contract MorphoVaultFeeAccountingTest is MorphoVaultBase {
    uint256 internal constant REINVEST_AMOUNT = 10_000;

    MockAngleMerkleDistributor internal mockDistributor;

    function setUp() public override {
        morphoVault = MORPHO_SENTORA_PYUSD;
        super.setUp();
    }

    function _resolveMerkleDistributor() internal override returns (address) {
        mockDistributor = new MockAngleMerkleDistributor();
        return address(mockDistributor);
    }

    function test_Harvest_ReinvestSetsLastAssetsValueToPostFeeValue() public {
        _enterStrategy();

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        // Underlying left on the strategy stands in for swapped reward tokens: `_harvest` reinvests it.
        deal(underlyingAsset, address(morphoVaultStrategy), _reinvestAmount(), true);

        vm.prank(mockStrategyContainer);
        morphoVaultStrategy.harvest();

        _assertLastAssetsValueIsPostFee("test_Harvest_ReinvestSetsLastAssetsValueToPostFeeValue");
    }

    function test_ManualClaim_ReinvestSetsLastAssetsValueToPostFeeValue() public {
        _enterStrategy();

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        uint256 claimAmount = _reinvestAmount();
        deal(underlyingAsset, address(mockDistributor), claimAmount, true);

        address[] memory tokens = new address[](1);
        tokens[0] = underlyingAsset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.prank(roles.merkleClaimer);
        IMorphoVault(address(morphoVaultStrategy)).manualClaim(tokens, amounts, proofs);

        _assertLastAssetsValueIsPostFee("test_ManualClaim_ReinvestSetsLastAssetsValueToPostFeeValue");
    }

    function _reinvestAmount() internal view returns (uint256) {
        return REINVEST_AMOUNT * 10 ** uint256(IERC20Metadata(underlyingAsset).decimals());
    }

    function _assertLastAssetsValueIsPostFee(string memory testName) internal view {
        assertGt(IERC20(morphoVault).balanceOf(treasury), 0, string.concat(testName, ": no fee shares to treasury"));

        uint256 postFeeAssetsValue = IERC4626(morphoVault).convertToAssets(
            IERC20(morphoVault).balanceOf(address(morphoVaultStrategy))
        );
        assertEq(
            MorphoVault(address(morphoVaultStrategy)).lastAssetsValue(),
            postFeeAssetsValue,
            string.concat(testName, ": lastAssetsValue is not the post-fee value")
        );
    }
}
