// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICurveGauge {
    struct HarvestLocalVariables {
        address gaugeCached;
        address lpTokenCached;
        address asset0Cached;
        address asset1Cached;
        uint256 currentGaugeBalance;
        uint256 currentVirtualPrice;
        uint256 lpValueDelta;
        uint256 gaugeTokensToTreausury;
        uint256 asset0BalanceBefore;
        uint256 asset1BalanceBefore;
        uint256 asset0Rewards;
        uint256 asset1Rewards;
        uint256 gaugeTokenBalanceBefore;
        uint256 gaugeTokensHarvested;
    }

    function gauge() external view returns (address);

    function lpToken() external view returns (address);

    function underlyingAsset0() external view returns (address);

    function underlyingAsset1() external view returns (address);

    function lastStoredVirtualPrice() external view returns (uint256);

    function lastStoredGaugeBalance() external view returns (uint256);
}
