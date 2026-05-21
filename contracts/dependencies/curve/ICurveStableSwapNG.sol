// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICurveStableSwapNG {
    function coins(uint256 index) external view returns (address);

    function get_balances() external view returns (uint256[] memory);

    function totalSupply() external view returns (uint256);

    function add_liquidity(uint256[] memory, uint256) external;

    function remove_liquidity(uint256, uint256[] memory) external;

    function get_virtual_price() external view returns (uint256);
}
