// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidSupply {
    struct AutomaticHarvestLocalVars {
        address fTokenCached;
        address merkleRewardToken;
        uint256 lastAssetsValue;
        uint256 accruedAssetsValue;
        uint256 accruedFTokenAmount;
        uint256 fTokensToTreasury;
        uint256 fTokensAmountBefore;
        uint256 reinvestFTokenDelta;
        uint256 feeFromReinvest;
    }

    struct ClaimParams {
        uint256 cumulativeAmount;
        uint256 cycle;
        bytes32[] merkleProof;
        bytes metadata;
    }

    /// @notice Claims rewards from Fluid Merkle distributor
    /// @param claimParams The parameters for the claim operation
    function manualClaim(ClaimParams calldata claimParams) external;
}
