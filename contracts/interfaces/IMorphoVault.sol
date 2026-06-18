// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMorphoVault {
    // ---- Structs ----

    struct AutomaticHarvestLocalVars {
        address morphoVaultCached;
        address underlyingAssetCached;
        uint256 rewardTokensLength;
        uint256 accruedAssetsValue;
        uint256 accruedVaultTokens;
        uint256 vaultTokensToTreasury;
        uint256 lpAmountBefore;
        uint256 reinvestLpDelta;
        uint256 feeFromReinvest;
    }

    struct ManualClaimLocalVars {
        address morphoVaultCached;
        address underlyingAssetCached;
        address strategyContainerCached;
        uint256 rewardTokensLength;
        address treasury;
        uint256 feePct;
        uint256 accruedAssetsValue;
        uint256 accruedVaultTokens;
        uint256 vaultTokensToTreasury;
        uint256 lpAmountBefore;
        address[] users;
        uint256 reinvestLpDelta;
        uint256 feeFromReinvest;
    }

    // ---- Events ----

    event RewardTokensUpdated(address[] rewardTokens);

    // ---- Errors ----

    error RewardTokenMatchesUnderlyingAsset();

    // ---- Functions ----

    /// @notice Returns the reward tokens
    /// @return The addresses of the reward tokens
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Sets the reward tokens. Only callabe by role HARVEST_MANAGER_ROLE
    /// @param _rewardTokens The addresses of the reward tokens
    function setRewardTokens(address[] memory _rewardTokens) external;

    /// @notice Manually claims the rewards. Only callable by role MERKLE_CLAIMER_ROLE
    /// @dev Underlying asset claimed via manual claim is instantly reinvested,
    ///      other reward tokens are reinvested during standard harvest
    /// @param tokens The addresses of the tokens
    /// @param amounts The amounts of the tokens
    /// @param proofs The proofs of the merkle proofs
    function manualClaim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external;
}
