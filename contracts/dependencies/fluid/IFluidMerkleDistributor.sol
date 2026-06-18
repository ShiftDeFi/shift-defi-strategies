// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidMerkleDistributor {
    /// @notice Claims rewards for a given recipient
    /// @param recipient_ - address of the recipient
    /// @param cumulativeAmount_ - cumulative amount of rewards to claim
    /// @param positionType_ - type of position, 1 for lending, 2 for vaults, 3 for smart lending, etc
    /// @param positionId_ - id of the position, fToken address for lending and vaultId for vaults
    /// @param cycle_ - cycle of the rewards
    /// @param merkleProof_ - merkle proof of the rewards
    /// @param metadata_ - metadata of the rewards
    function claim(
        address recipient_,
        uint256 cumulativeAmount_,
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_,
        bytes calldata metadata_
    ) external;

    /// @notice Gets the address of the reward token
    /// @return The address of the reward token
    function TOKEN() external view returns (address);
}
