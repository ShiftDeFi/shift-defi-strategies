// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAngleMerkleDistributor} from "contracts/dependencies/angle/IAngleMerkleDistributor.sol";
import {Test} from "forge-std/Test.sol";

contract MerkleRewardsClaimTest is Test {
    string private RPC_URL = vm.envString("ETH_RPC_URL");
    uint256 private constant FORK_BLOCK_NUMBER = 25286782;

    address private constant REWARD_WHALE = 0xa4e102c843765053E17998F18Ad1b6a740281615;
    address internal constant RLUSD = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address private constant ANGLE_MERKLE_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    uint256 private constant EXPECTED_REWARDS = 2379227300040198;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK_NUMBER);
    }

    function test_ClaimMorphoMerkleRewards() public {
        address[] memory users = new address[](1);
        users[0] = REWARD_WHALE;
        address[] memory tokens = new address[](1);
        tokens[0] = RLUSD;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = EXPECTED_REWARDS;

        bytes32[][] memory rlusdProofs = new bytes32[][](1);
        bytes32[] memory rlusdProof = new bytes32[](19);

        rlusdProof[0] = 0x2ba992ce8116cf4bad1ecbfe7b1d3916f782c4659f42db39d1ec8391a174af29;
        rlusdProof[1] = 0xacd4c3b79006735dc838d4c1d3d634ecb7f5ca98c34e0d1f36a3a6c1db21c6d7;
        rlusdProof[2] = 0xa3d289755abe734e23d424cab0a7b8131b40957b65ed274b1c5be3de03f449b3;
        rlusdProof[3] = 0x558b6f95a6c66fc5149fbeb56b7d76f1136084da8898de51d327e3b580547452;
        rlusdProof[4] = 0x8e16b20a454c1e70bb7098857623a908cb867ccbbbeebb31456366d5dc75db53;
        rlusdProof[5] = 0xd24637eef0856106ce4515f7761dd1d989fba67eac07d1a46587c64ea1de1d91;
        rlusdProof[6] = 0x935003955ce16c36758b9ef8cd339ef7b96a601a42fe61a580925209accd1cc6;
        rlusdProof[7] = 0xbcbeaf8a3c8692e8bfb4472a9c2b17cf0c2a6847d2a7fb1c49a5e3b0122e6af5;
        rlusdProof[8] = 0xa9143b25db4304c532dbbe06459f5532b19eda81a281af4a87400d9fa50e425e;
        rlusdProof[9] = 0x0ad47b48df8fbe5d6dc1ec3aff34f7439feb834222e56e93be05658be2b17c3e;
        rlusdProof[10] = 0x2fe38e41f146567ad58385ce74af6cd98b72f91af5440e0ef6e3db110e18b699;
        rlusdProof[11] = 0xfef9d10d1ea752357e5fcdcd31d4050790d24546dd2db0f2a21b6e0588503cc4;
        rlusdProof[12] = 0x78b5f91ca57c7c0d0691af8ece7ced78be37357c91f0f34115195f9474f83794;
        rlusdProof[13] = 0x55ea13c3eda5cb76ee46d2f3fdb33a722a7938de2c837a2ab38405771f3ff5f7;
        rlusdProof[14] = 0xc201c512d9a494ccace8054ab4700aebff2d7bbe025f940f6c9a8b52ebac3f40;
        rlusdProof[15] = 0x9db5e1493bdf54b8d56bee560ac18e69c334a2dfbdcd77bc50bfd2ad8136466a;
        rlusdProof[16] = 0xe4dd14b1c80d293e2b314b4754e9abc688357eecc0fa801b6721cf3ea24810a3;
        rlusdProof[17] = 0xffc9de2b97442a56887a456e9b3a8a3dd3900948563e151a418948b3d069f5b7;
        rlusdProof[18] = 0x46c04c729dabbd800c6d1e8cba414540b5a98f744a4cede83faf3ba129674856;
        rlusdProofs[0] = rlusdProof;

        uint256 rlusdBalanceBefore = IERC20(RLUSD).balanceOf(REWARD_WHALE);

        vm.prank(REWARD_WHALE);
        IAngleMerkleDistributor(ANGLE_MERKLE_DISTRIBUTOR).claim(users, tokens, amounts, rlusdProofs);

        uint256 rlusdBalanceAfter = IERC20(RLUSD).balanceOf(REWARD_WHALE);

        assertEq(rlusdBalanceAfter, rlusdBalanceBefore + EXPECTED_REWARDS);
    }
}
