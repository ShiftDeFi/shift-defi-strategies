// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Subset of Compound III's `CometInterface` used by the strategies.
/// @dev `balanceOf` is the account's base-token supply balance at its present value, interest accrued.
interface IComet is IERC20 {
    function baseToken() external view returns (address);

    function supply(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;
}
