// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {ICompoundV3Supply} from "contracts/interfaces/ICompoundV3Supply.sol";

import {CompoundV3SupplyBase} from "./CompoundV3SupplyBase.t.sol";

contract CompoundV3SupplyRewardTokensTest is CompoundV3SupplyBase {
    function setUp() public override {
        comet = COMPOUND_V3_USDT;
        rewardToken = COMP;
        super.setUp();
    }

    function test_Initialize_SetsRewardTokens() public view {
        address[] memory rewardTokens = ICompoundV3Supply(address(compoundStrategy)).getRewardTokens();
        assertEq(rewardTokens.length, 1, "test_Initialize_SetsRewardTokens: length");
        assertEq(rewardTokens[0], COMP, "test_Initialize_SetsRewardTokens: COMP");
    }

    function test_SetRewardTokens() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = makeAddr("REWARD_TOKEN_0");
        rewardTokens[1] = makeAddr("REWARD_TOKEN_1");

        vm.expectEmit(address(compoundStrategy));
        emit ICompoundV3Supply.RewardTokensUpdated(rewardTokens);

        vm.prank(roles.harvestManager);
        ICompoundV3Supply(address(compoundStrategy)).setRewardTokens(rewardTokens);

        address[] memory newRewardTokens = ICompoundV3Supply(address(compoundStrategy)).getRewardTokens();
        assertEq(newRewardTokens.length, rewardTokens.length, "test_SetRewardTokens: length");
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            assertEq(newRewardTokens[i], rewardTokens[i], "test_SetRewardTokens: token");
        }
    }

    function test_UnsetRewardTokens() public {
        vm.prank(roles.harvestManager);
        ICompoundV3Supply(address(compoundStrategy)).setRewardTokens(new address[](0));

        assertEq(
            ICompoundV3Supply(address(compoundStrategy)).getRewardTokens().length, 0, "test_UnsetRewardTokens: length"
        );
    }

    function testRevert_SetRewardTokens_Unauthorized() public {
        vm.prank(users.alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        ICompoundV3Supply(address(compoundStrategy)).setRewardTokens(new address[](0));
    }

    function testRevert_SetRewardTokens_ZeroAddress() public {
        address[] memory rewardTokens = new address[](1);

        vm.prank(roles.harvestManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        ICompoundV3Supply(address(compoundStrategy)).setRewardTokens(rewardTokens);
    }

    function testRevert_SetRewardTokens_RewardTokenMatchesBaseToken() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = baseToken;

        vm.prank(roles.harvestManager);
        vm.expectRevert(ICompoundV3Supply.RewardTokenMatchesBaseToken.selector);
        ICompoundV3Supply(address(compoundStrategy)).setRewardTokens(rewardTokens);
    }

    function testRevert_SetRewardTokens_RewardTokenMatchesComet() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = comet;

        vm.prank(roles.harvestManager);
        vm.expectRevert(ICompoundV3Supply.RewardTokenMatchesComet.selector);
        ICompoundV3Supply(address(compoundStrategy)).setRewardTokens(rewardTokens);
    }
}
