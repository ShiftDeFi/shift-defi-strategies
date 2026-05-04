// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidSupply {
    struct HarvestLocalVariables {
        address fToken;
        address underlyingAsset;
        uint256 lastFTokenBalance;
        uint256 underlyingAssetBalance;
        uint256 incomeInAsset;
        uint256 feeToTreasury;
    }

    struct ClaimAndReinvestLocalVariables {
        address strategyContainer;
        address merkleDistributor;
        address underlyingAsset;
        uint256 underlyingAssetBalanceBefore;
        address rewardToken;
        uint256 fee;
        uint256 underlyingAssetIncome;
        uint256 feeToTreasury;
    }

    struct ClaimParams {
        uint256 cumulativeAmount;
        uint8 positionType;
        bytes32 positionId;
        uint256 cycle;
        bytes32[] merkleProof;
        bytes metadata;
    }

    /// @notice Gets the last recorded fToken balance
    /// @return The last recorded fToken balance
    function lastFTokenBalance() external view returns (uint256);

    /// @notice Claims rewards from Fluid Merkle distributor and reinvests them
    /// @dev Claims rewards using merkle proof, swaps to asset, takes treasury fee, and reinvests remaining amount
    /// @param claimParams The parameters for the claim and reinvest operation
    function claimAndReinvest(ClaimParams calldata claimParams) external;
}
