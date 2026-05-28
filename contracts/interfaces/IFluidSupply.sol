// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidSupply {
    struct HarvestLocalVariables {
        address fToken;
        address underlyingAsset;
        uint256 lastFTokenBalance;
        uint256 fTokenBalanceAfter;
        uint256 underlyingAssetDelta;
        uint256 fTokenDelta;
        uint256 feeToTreasury;
        address merkleRewardToken;
    }

    struct ClaimParams {
        uint256 cumulativeAmount;
        uint256 cycle;
        bytes32[] merkleProof;
        bytes metadata;
    }

    /// @notice Gets the last recorded fToken balance
    /// @return The last recorded fToken balance
    function lastFTokenBalance() external view returns (uint256);

    /// @notice Claims rewards from Fluid Merkle distributor
    /// @param claimParams The parameters for the claim operation
    function manualClaim(ClaimParams calldata claimParams) external;

    /// @notice Gets the address of the Merkle reward token
    /// @return The address of the Merkle reward token
    function merkleRewardToken() external view returns (address);
}
