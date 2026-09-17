// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3SupplyWithMerkle} from "contracts/aave-v3/AaveV3SupplyWithMerkle.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Deploys a new `AaveV3SupplyWithMerkle` implementation and either executes the upgrade
///         (EXECUTE_UPGRADE=true, EOA admin) or prints the multisig calldata for it (default).
contract UpgradeAaveSupplyWithMerkle is UpgradeBase {
    function run() public {
        address proxy = vm.envAddress("AAVE_SUPPLY_WITH_MERKLE_PROXY");

        vm.startBroadcast();
        address newImplementation = address(new AaveV3SupplyWithMerkle());
        // Plain implementation swap: no re-initialization call.
        _upgrade("AaveV3SupplyWithMerkle", proxy, newImplementation, "");
        vm.stopBroadcast();
    }
}
