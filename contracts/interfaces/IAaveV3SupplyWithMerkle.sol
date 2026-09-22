// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAaveV3SupplyWithMerkle {
    // ---- Structs ----

    struct AutomaticHarvestLocalVars {
        address reserveAssetCached;
        address reserveATokenCached;
        uint256 rewardTokensLength;
        uint256 aTokenBalanceBefore;
        uint256 aTokenDelta;
        uint256 balanceBeforeReinvest;
        uint256 currentBalance;
        uint256 feeToTreasury;
        uint256 feeFromReinvest;
    }

    struct ManualClaimLocalVars {
        address reserveATokenCached;
        address strategyContainerCached;
        address reserveAssetCached;
        address treasury;
        uint256 feePct;
        uint256 lastBalanceCached;
        uint256 currentBalance;
        uint256 fee;
        address[] users;
    }

    // ---- Events ----

    event RewardTokensUpdated(address[] rewardTokens);

    // ---- Errors ----

    error RewardTokenMatchesReserveAsset();
    error RewardTokenMatchesReserveAToken();

    // ---- Functions ----

    /// @notice Returns the reward tokens
    /// @return The addresses of the reward tokens
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Sets the reward tokens. Only callable by role HARVEST_MANAGER_ROLE
    /// @param _rewardTokens The addresses of the reward tokens
    function setRewardTokens(address[] memory _rewardTokens) external;

    /// @notice Manually claims the rewards. Only callable by role MERKLE_CLAIMER_ROLE
    /// @dev Only the reserve asset is reinvested instantly, and only while currently supplied to Aave;
    ///      any other claimed reward (e.g. WMON), and any claim made while not supplied, is left on the
    ///      contract and reinvested by the next automatic harvest instead
    /// @param tokens The addresses of the tokens
    /// @param amounts The amounts of the tokens
    /// @param proofs The proofs of the merkle proofs
    function manualClaim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external;
}
