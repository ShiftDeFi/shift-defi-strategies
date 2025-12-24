// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICompoundV3Supply {
    struct InternalHarvestLocalVars {
        address depositToken;
        address cToken;
        uint256 cTokenDecimalsFactor;
        uint256 dTokenDecimalsFactor;
        uint256 cTokenIncome;
        uint256 cTokenIncomeInAsset;
        uint256 beforeBalance;
        uint256 compRewardsInAsset;
        uint256 treasuryFee;
        uint256 missingFeeInAsset;
        uint256 cTokensToWithdraw;
        uint256 currentCTokenBalance;
        uint256 incomeShare;
    }

    struct InternalEnterLocalVars {
        uint256 balance;
        address depositToken;
        address cToken;
    }

    struct InternalExitLocalVars {
        uint256 balance;
        uint256 liquidity;
        address cToken;
    }
}
