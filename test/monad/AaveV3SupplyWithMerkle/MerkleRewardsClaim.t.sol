// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAngleMerkleDistributor} from "contracts/dependencies/angle/IAngleMerkleDistributor.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Replays a real Monad mainnet claim (tx
///      0xabdde1c89f4d16db2ea8499ea7d4a8b45203f299262d8476f0c8961634831cf2, mined at block 105_592_537 -
///      one of a 3-token claim; only the hyAUSD leg is replayed here) one block before it actually landed,
///      to prove the real Angle Merkle distributor and this exact historical proof both still work.
///      `CUMULATIVE_AMOUNT` is the full lifetime-cumulative amount claimable as of this proof;
///      `EXPECTED_REWARDS` is the smaller delta actually paid out by that tx (confirmed via its Transfer
///      log), since REWARD_WHALE had already claimed most of this token's cumulative total in earlier
///      epochs. Requires `MONAD_RPC_URL` - not part of `make verify`.
contract MerkleRewardsClaimTest is Test {
    string private RPC_URL = vm.envString("MONAD_RPC_URL");
    uint256 private constant FORK_BLOCK_NUMBER = 105_592_536;

    address private constant REWARD_WHALE = 0xace64DBF9B86975756A79a28A8614e9E97c707a6;
    address private constant ANGLE_MERKLE_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address private constant CLAIMED_TOKEN = 0xaD663aC84052b52BE4ed1b27BA416505e84a00Bf; // hyAUSD
    uint256 private constant CUMULATIVE_AMOUNT = 567561394;
    uint256 private constant EXPECTED_REWARDS = 393;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK_NUMBER);
    }

    function test_ClaimAaveMerkleRewards() public {
        address[] memory users = new address[](1);
        users[0] = REWARD_WHALE;
        address[] memory tokens = new address[](1);
        tokens[0] = CLAIMED_TOKEN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = CUMULATIVE_AMOUNT;

        bytes32[][] memory claimProofs = new bytes32[][](1);
        bytes32[] memory proof = new bytes32[](16);

        proof[0] = 0x66017832a88781cea95e3d11810d4b2e43555833fc1d1425fa19fa8041128447;
        proof[1] = 0x264c70ffe5678bfaae1e2669a19ac740eeadb8bf54aecf752e05421da2529c1f;
        proof[2] = 0x6df98f1dbdfe9190c7eca1896b463c0c38c9afde4a46c31967999df7f063ffdd;
        proof[3] = 0x7d150c587b1a700c4ff0e1b5499966acdf77613602e671003add9625deaf6a80;
        proof[4] = 0x441fffbfa77c40745e9244ec75d2529173882e312a4dbd9e35bc47e05792158a;
        proof[5] = 0x684ddd81deed1ecf7e1907638d39243e47b91aed81ed633e93c6a31b3738308a;
        proof[6] = 0xe01ee02491e912c61e5489376b2b17ed08465325998ec71fec0e80dc40ae772a;
        proof[7] = 0xf568b8237af39a4adaf18e1d8423e411b79431e5c47a03663399483b0d5c3715;
        proof[8] = 0xed9583cb0beab4c7073dd1e40a59662dd9d7994db9f7734b9d97701bf44dff15;
        proof[9] = 0xab3fddafe9cff795768a638ccb423a180e310db34b833460348ee831fc8274e6;
        proof[10] = 0x2ae10470c106c9970a497637636faca22a034b19ad012f0d295cb241b6985a06;
        proof[11] = 0xcfa5f3510bf968db3f6a09ac0934575c520a6a36497a2ba60e522f2d5e09a4aa;
        proof[12] = 0x7f3602ea396cb55be1d2acdef136f7a676bba2ffc9a7849f499bff1e3f595223;
        proof[13] = 0x46475518cf3b129f7799c926985bf751d03cefcfc2ab9b33a47bd805376ae2b1;
        proof[14] = 0x4ec98d40af0fa994d0cafef3d8d2262efb13b5afdcb94f6d704a4a5b8014007a;
        proof[15] = 0x59de45a1cfe691a6b3fa10e23e6045b7ec218c0c32201a96e9b70ee07f917b19;
        claimProofs[0] = proof;

        uint256 balanceBefore = IERC20(CLAIMED_TOKEN).balanceOf(REWARD_WHALE);

        vm.prank(REWARD_WHALE);
        IAngleMerkleDistributor(ANGLE_MERKLE_DISTRIBUTOR).claim(users, tokens, amounts, claimProofs);

        uint256 balanceAfter = IERC20(CLAIMED_TOKEN).balanceOf(REWARD_WHALE);

        assertEq(balanceAfter, balanceBefore + EXPECTED_REWARDS, "test_ClaimAaveMerkleRewards: unexpected payout");
    }
}
