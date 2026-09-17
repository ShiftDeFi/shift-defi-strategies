// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAaveV3Supply {
    // ---- Structs ----

    struct AaveHarvestLocalVars {
        address reserveATokenCached;
        uint256 lastReserveATokenBalanceCached;
        uint256 currentReserveATokenBalance;
        uint256 income;
        uint256 fee;
    }

    // ---- Errors ----

    error NoReserveAllocation();
    error WithdrawAmountTooSmall();
    error WithdrawAmountMismatch();
}
