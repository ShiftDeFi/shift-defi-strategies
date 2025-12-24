// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidToken {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    function previewRedeem(uint256 shares_) external view returns (uint256);

    function previewDeposit(uint256 assets_) external view returns (uint256);

    function updateRates() external;
}
