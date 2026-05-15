// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IcASSETv3 is IERC20 {
    function baseToken() external view returns (address);

    function supply(address, uint) external;

    function withdraw(address, uint) external;

    function accrueAccount(address) external;
}

interface IcRewards {
    function claim(address, address, bool) external;
}
