// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Errors} from "@shift-defi/core/libraries/Errors.sol";

import {IMorphoVault} from "contracts/interfaces/IMorphoVault.sol";
import {MorphoVaultBase} from "./MorphoVaultBase.t.sol";

contract MorphoVaultRewardTokensTest is MorphoVaultBase {
    function setUp() public override {
        morphoVault = MORPHO_SENTORA_PYUSD;
        super.setUp();
    }

    function test_SetRewardTokens() public {
        uint256 rewardTokensLength = 3;
        address[] memory rewardTokens = new address[](rewardTokensLength);

        for (uint256 i = 0; i < rewardTokensLength; i++) {
            rewardTokens[i] = makeAddr("REWARD_TOKEN_i");
        }

        vm.startPrank(roles.harvestManager);
        IMorphoVault(address(morphoVaultStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();

        address[] memory newRewardTokens = IMorphoVault(address(morphoVaultStrategy)).getRewardTokens();
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
        IMorphoVault(address(morphoVaultStrategy)).setRewardTokens(rewardTokens);

        address[] memory newRewardTokens = IMorphoVault(address(morphoVaultStrategy)).getRewardTokens();
        assertEq(newRewardTokens.length, rewardTokensLength);

        rewardTokensLength = 0;
        rewardTokens = new address[](rewardTokensLength);

        vm.prank(roles.harvestManager);
        IMorphoVault(address(morphoVaultStrategy)).setRewardTokens(rewardTokens);

        newRewardTokens = IMorphoVault(address(morphoVaultStrategy)).getRewardTokens();
        assertEq(newRewardTokens.length, rewardTokensLength);
    }

    function testRevert_SetRewardTokens_ZeroAddress() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(0);

        vm.startPrank(roles.harvestManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IMorphoVault(address(morphoVaultStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();
    }

    function testRevert_SetRewardTokens_RewardTokenMatchesUnderlyingAsset() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = underlyingAsset;

        vm.startPrank(roles.harvestManager);
        vm.expectRevert(IMorphoVault.RewardTokenMatchesUnderlyingAsset.selector);
        IMorphoVault(address(morphoVaultStrategy)).setRewardTokens(rewardTokens);
        vm.stopPrank();
    }
}
