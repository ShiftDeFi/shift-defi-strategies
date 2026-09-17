// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAngleMerkleDistributor} from "contracts/dependencies/angle/IAngleMerkleDistributor.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Replays a real Monad mainnet claim (see the "Rewards claim" transaction example in
///      entry-exit-design/AaveV3MonadUSDC.md - tx 0x14562de1d8d2bfce3d9c1f3ac70fab25902bc0e3e71ed86a64c5314902c4ceb1,
///      mined at block 101_871_052) one block before it actually landed, to prove the real Angle Merkle
///      distributor and this exact historical proof both still work. `EXPECTED_REWARDS` is the real
///      amount that tx's own Transfer log paid out (confirmed via the receipt), which also confirms this
///      was REWARD_WHALE's first-ever claim of this token (the full cumulative amount was paid as the
///      delta). Requires `MONAD_RPC_URL` - not part of `make verify`.
contract MerkleRewardsClaimTest is Test {
    string private RPC_URL = vm.envString("MONAD_RPC_URL");
    uint256 private constant FORK_BLOCK_NUMBER = 101_871_051;

    address private constant REWARD_WHALE = 0xa4e102c843765053E17998F18Ad1b6a740281615;
    address private constant ANGLE_MERKLE_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address private constant CLAIMED_TOKEN = 0x561Ad6156D0106E7a59EE788759dF7B7Ec679BD0;
    uint256 private constant CUMULATIVE_AMOUNT = 13255056721191557;
    uint256 private constant EXPECTED_REWARDS = 13255056721191557;

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

        proof[0] = 0xedc4099ab2610f6654ec5806e866f1ceea3fe5c30c634223528b9c433af39c16;
        proof[1] = 0x9cf04b09b39da67b6993d5c4ee8c149fd5ad47b1b621a19a58f59f441a0326cc;
        proof[2] = 0xa3c091acebecfe193cfbc81073240ab8d9cd183120da0b3fd75a3a28f3f712d0;
        proof[3] = 0x35e84900244cabc3088b15aada5e5a4ee17a71e0a5d0e84084bfbc0aae2a2cdc;
        proof[4] = 0x99aaffd5ea9c2538beafa5c1255f032675d0f4c492b522f4eba83975cc1fe492;
        proof[5] = 0xa45bd9fc5f697ac7c3c1cc3b6df362d142978c07f9c023cb8aceeb34c280423a;
        proof[6] = 0xaaee303062cc076b715eec06a90ddb1fb28db297b5664f4031ad944a58a44591;
        proof[7] = 0x22cd4ebd451d6dc984bb10c3468cca83faf34c63d5cd27ad300f2cfccd7d2dd8;
        proof[8] = 0x37da78bb275439b09cd0d6cb822cfe3ce1b9630f9eb7127cf3ac1385324bd733;
        proof[9] = 0x9b613f897c4c64f15e620c82203a3f50a857b6b04f587de8e3fa70e8b959635f;
        proof[10] = 0x22973d2b59aba3288e36e3dffa87b4d37346b9bf4b5ff88e167938afed830918;
        proof[11] = 0x00a8d7805b18e81596e7b3bfa9c1197e1ea0313ee5307de556eb15f4a6f58637;
        proof[12] = 0x61cdf39c9cef68e80e7f54df1dfaf254edc636dbc62e5f818afc278993423a84;
        proof[13] = 0xcd2e549f855a0dcda17d13042ed2b5f9c459f2a32d684d4923fc10218d62dbff;
        proof[14] = 0xcdb9b7b2687f877a98826be99b1eda0d0c7bc431c0f3a97a5f919c596034cd63;
        proof[15] = 0x724b4c81f103b8c6761393b6977f160e5767cf1da3fa65e6b12f5cedf2e62080;
        claimProofs[0] = proof;

        uint256 balanceBefore = IERC20(CLAIMED_TOKEN).balanceOf(REWARD_WHALE);

        vm.prank(REWARD_WHALE);
        IAngleMerkleDistributor(ANGLE_MERKLE_DISTRIBUTOR).claim(users, tokens, amounts, claimProofs);

        uint256 balanceAfter = IERC20(CLAIMED_TOKEN).balanceOf(REWARD_WHALE);

        assertEq(balanceAfter, balanceBefore + EXPECTED_REWARDS, "test_ClaimAaveMerkleRewards: unexpected payout");
    }
}
