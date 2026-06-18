// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IFluidMerkleDistributor} from "contracts/dependencies/fluid/IFluidMerkleDistributor.sol";

import {Test} from "forge-std/Test.sol";

contract MerkleRewardsClaimTest is Test {
    string private RPC_URL = vm.envString("ETH_RPC_URL");
    uint256 private constant FORK_BLOCK_NUMBER = 25144082;

    address private constant FLUID_MERKLE_DISTRIBUTOR = 0x7060FE0Dd3E31be01EFAc6B28C8D38018fD163B0;
    address private constant F_USDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;

    address private constant REWARD_WHALE = 0xE1066FFCb6951bed71C1870C62B3759270510Be5;

    uint256 private constant CUMULATIVE_AMOUNT = 576572778769941734417;
    uint256 private constant EXPECTED_REWARDS = 16684959298892654310;
    uint8 private constant POSITION_TYPE = 1;
    uint256 private constant CYCLE = 1568;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK_NUMBER);
    }

    function test_ClaimFluidMerkleRewards() public {
        bytes32[] memory merkleProof = new bytes32[](14);

        merkleProof[0] = 0x632a860ad9a40c422d8f79544b61600622ddaab16469759e665bd6ccc1bddb5c;
        merkleProof[1] = 0xc3c5f0f322f8bb0926243530586a9435996b977128974cf1ee27aed57d230a74;
        merkleProof[2] = 0xd9f35b06d4982a5d6776d45e01becea9facf824fab47dde376ee98da4be0d9a2;
        merkleProof[3] = 0x2e2c791fbc9a1dbf0c9d403253436212f4a712b8a3f5409a7c3b1f16f48fb8c7;
        merkleProof[4] = 0x6f073a6d14183c91d948b06094ea3a7bed4a52efa768581f71264ac20d4a77f3;
        merkleProof[5] = 0x05a18f93c396c8b7d7d876827d684c9857eefba9f1eb9bfc2f15406801b9b8c8;
        merkleProof[6] = 0xee3c5d6d73ec8f542a25cbeb3b701da40285a2d83f89ef71c906358e8209f467;
        merkleProof[7] = 0x8fc211e40069c3d5fd6ddc071f9f1237dadd718e40fc1eac84c71aa2631c30b8;
        merkleProof[8] = 0x0998b317f34de7ff3d04fe878867dd85108d2fb8e68d04a7e63c383e45312a9f;
        merkleProof[9] = 0x2870ee48d1cb958e93eabc15bc60bf5af63954e0cb7e074eaee745df822dc177;
        merkleProof[10] = 0xd4d4fd7850c51d0ec54e7e1746133c0c840442167c91eb889a1cddd1171f7e90;
        merkleProof[11] = 0x5199c61ebe02b70c0a8239be5ade8a8e1859297e612f704fa402e9c6ce7399b1;
        merkleProof[12] = 0x2a715e759adbbe73816a0a5c619f2a4e8bd620fd97ab0e38c2005dea14069842;
        merkleProof[13] = 0x8e750fa4fadd4381da2e71eac8733afc1aedba41c1ffa3466d29fe10badfc3ba;

        address rewardToken = IFluidMerkleDistributor(FLUID_MERKLE_DISTRIBUTOR).TOKEN();
        uint256 rewardTokenBalanceBefore = IERC20(rewardToken).balanceOf(REWARD_WHALE);

        bytes32 positionId = bytes32(uint256(uint160(F_USDC)));

        vm.prank(REWARD_WHALE);
        IFluidMerkleDistributor(FLUID_MERKLE_DISTRIBUTOR).claim(
            REWARD_WHALE,
            CUMULATIVE_AMOUNT,
            POSITION_TYPE,
            positionId,
            CYCLE,
            merkleProof,
            new bytes(0)
        );

        uint256 rewardTokenBalanceAfter = IERC20(rewardToken).balanceOf(REWARD_WHALE);
        assertEq(rewardTokenBalanceAfter, rewardTokenBalanceBefore + EXPECTED_REWARDS);
    }
}
