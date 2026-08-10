// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3Supply} from "contracts/aave-v3/AaveV3Supply.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Deploys a new `AaveV3Supply` implementation and either executes the upgrade (EXECUTE_UPGRADE=true,
///         EOA admin) or prints the multisig calldata for it (default).
contract UpgradeAaveSupply is UpgradeBase {
    function run() public {
        address proxy = vm.envAddress("AAVE_SUPPLY_PROXY");

        vm.startBroadcast();
        address newImplementation = address(new AaveV3Supply());
        // Plain implementation swap: no re-initialization call.
        _upgrade("AaveV3Supply", proxy, newImplementation, "");
        vm.stopBroadcast();
    }
}
