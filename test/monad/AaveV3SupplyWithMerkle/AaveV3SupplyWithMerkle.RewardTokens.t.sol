// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {IAaveV3SupplyWithMerkle} from "contracts/interfaces/IAaveV3SupplyWithMerkle.sol";
import {AaveV3SupplyWithMerkleBase} from "./AaveV3SupplyWithMerkleBase.t.sol";

contract AaveV3SupplyWithMerkleRewardTokensTest is AaveV3SupplyWithMerkleBase {
    function setUp() public override {
        merkleDistributor = AAVE_MERKLE_DISTRIBUTOR;
        super.setUp();
    }

    function test_SetRewardTokens() public {
        uint256 rewardTokensLength = 3;
        address[] memory rewardTokens = new address[](rewardTokensLength);

        for (uint256 i = 0; i < rewardTokensLength; i++) {
            rewardTokens[i] = makeAddr("REWARD_TOKEN_i");
        }

        vm.startPrank(roles.harvestManager);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();

        address[] memory newRewardTokens = IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).getRewardTokens();
        assertEq(newRewardTokens.length, rewardTokensLength);
        for (uint256 i = 0; i < rewardTokensLength; i++) {
            assertEq(newRewardTokens[i], rewardTokens[i]);
        }
    }

    function test_UnsetRewardTokens() public {
        uint256 rewardTokensLength = 3;
        address[] memory rewardTokens = new address[](rewardTokensLength);
        for (uint256 i = 0; i < rewardTokensLength; i++) {
            rewardTokens[i] = makeAddr("REWARD_TOKEN_i");
        }

        vm.prank(roles.harvestManager);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).setRewardTokens(rewardTokens);

        address[] memory newRewardTokens = IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).getRewardTokens();
        assertEq(newRewardTokens.length, rewardTokensLength);

        rewardTokensLength = 0;
        rewardTokens = new address[](rewardTokensLength);

        vm.prank(roles.harvestManager);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).setRewardTokens(rewardTokens);

        newRewardTokens = IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).getRewardTokens();
        assertEq(newRewardTokens.length, rewardTokensLength);
    }

    function testRevert_SetRewardTokens_ZeroAddress() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(0);

        vm.startPrank(roles.harvestManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();
    }

    function testRevert_SetRewardTokens_RewardTokenMatchesReserveAsset() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = USDC;

        vm.startPrank(roles.harvestManager);
        vm.expectRevert(IAaveV3SupplyWithMerkle.RewardTokenMatchesReserveAsset.selector);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();
    }

    function testRevert_SetRewardTokens_RewardTokenMatchesReserveAToken() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = A_MON_USDC;

        vm.startPrank(roles.harvestManager);
        vm.expectRevert(IAaveV3SupplyWithMerkle.RewardTokenMatchesReserveAToken.selector);
        IAaveV3SupplyWithMerkle(address(aaveSupplyStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();
    }
}
