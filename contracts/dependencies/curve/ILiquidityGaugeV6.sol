// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILiquidityGaugeV6 {
    function lp_token() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    function deposit(uint256) external;

    function withdraw(uint256) external;

    function claim_rewards() external;

    function reward_count() external view returns (uint256);
}
