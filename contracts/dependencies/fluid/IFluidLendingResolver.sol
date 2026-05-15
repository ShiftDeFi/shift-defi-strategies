// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFluidLendingResolver {
    function computeFToken(address asset, string memory fTokenType) external view returns (address);
}
