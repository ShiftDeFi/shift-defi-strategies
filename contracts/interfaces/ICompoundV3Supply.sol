// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICompoundV3Supply {
    // ---- Structs ----

    struct SlippageParams {
        uint256 enterMaxSlippage;
        uint256 exitMaxSlippage;
        uint256 emergencyExitMaxSlippage;
    }

    struct AutomaticHarvestLocalVars {
        address cometCached;
        address baseTokenCached;
        uint256 rewardTokensLength;
        uint256 balanceBeforeReinvest;
        uint256 currentBalance;
        uint256 cometBalanceBefore;
        uint256 cometBalanceDelta;
        uint256 feeToTreasury;
        uint256 feeFromReinvest;
    }

    struct ManualClaimLocalVars {
        address cometCached;
        address baseTokenCached;
        address strategyContainerCached;
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

    error NoSupplyAllocation();
    error WithdrawAmountTooSmall();
    error RewardTokenMatchesBaseToken();
    error RewardTokenMatchesComet();

    // ---- Functions ----

    /// @notice Returns the reward tokens swapped and reinvested by the automatic harvest.
    /// @return The addresses of the reward tokens.
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Sets the reward tokens. Only callable by the strategy container or role HARVEST_MANAGER_ROLE.
    /// @param _rewardTokens The addresses of the reward tokens.
    function setRewardTokens(address[] memory _rewardTokens) external;

    /// @notice Manually claims Merkl rewards. Only callable by role MERKLE_CLAIMER_ROLE.
    /// @dev Only the base token is reinvested instantly, and only while supplied to Comet; any other claimed
    ///      reward (e.g. COMP), and any claim made while not supplied, is left for the next automatic harvest.
    /// @param tokens The addresses of the claimed tokens.
    /// @param amounts The cumulative claimable amounts of the tokens.
    /// @param proofs The Merkle proofs of the claims.
    function manualClaim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external;
}
