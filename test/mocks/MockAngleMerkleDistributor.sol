// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAngleMerkleDistributor} from "contracts/dependencies/angle/IAngleMerkleDistributor.sol";

/// @notice Minimal cumulative-claim mock of the Angle Merkle distributor for unit tests: pays out the
///         delta between the requested cumulative `amounts[i]` and whatever `users[i]` has already
///         claimed for `tokens[i]`, skipping proof verification entirely. The real distributor's proof
///         handling is covered separately, against a real historical claim, in MerkleRewardsClaim.t.sol.
contract MockAngleMerkleDistributor is IAngleMerkleDistributor {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public claimed;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata
    ) external override {
        for (uint256 i = 0; i < users.length; ++i) {
            uint256 alreadyClaimed = claimed[users[i]][tokens[i]];
            if (amounts[i] <= alreadyClaimed) {
                continue;
            }

            uint256 payout = amounts[i] - alreadyClaimed;
            claimed[users[i]][tokens[i]] = amounts[i];
            IERC20(tokens[i]).safeTransfer(users[i], payout);
        }
    }
}
