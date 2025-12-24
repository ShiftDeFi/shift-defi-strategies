// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidSupply {
    struct HarvestLocalVariables {
        address fToken;
        address asset;
        uint256 lastDepositBalance;
        uint256 fTokensInAsset;
        uint256 incomeInAsset;
        uint256 balanceBefore;
        uint256 balanceAfter;
        uint256 treasuryFee;
        uint256 shares;
    }

    struct ClaimAndReinvestLocalVariables {
        address strategyContainer;
        address rewardToken;
        uint256 rewardsBalance;
        uint256 assetsBalance;
        address assetCached;
        uint256 rewardInAsset;
        uint256 treasuryFee;
    }

    function lastDepositBalance() external view returns (uint256);

    function claimAndReinvest(
        address distributor,
        uint256 cumulativeAmount,
        uint8 positionType,
        bytes32 positionId,
        uint256 cycle,
        bytes32[] calldata merkleProof,
        bytes memory metadata
    ) external;
}
