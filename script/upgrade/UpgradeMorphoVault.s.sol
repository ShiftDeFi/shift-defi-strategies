// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MorphoVault} from "contracts/morpho/MorphoVault.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Deploys a new `MorphoVault` implementation and either executes the upgrade (EXECUTE_UPGRADE=true,
///         EOA admin) or prints the multisig calldata for it (default).
contract UpgradeMorphoVault is UpgradeBase {
    function run() public {
        address proxy = vm.envAddress("MORPHO_VAULT_PROXY");

        vm.startBroadcast();
        address newImplementation = address(new MorphoVault());
        // Plain implementation swap: no re-initialization call.
        _upgrade("MorphoVault", proxy, newImplementation, "");
        vm.stopBroadcast();
    }
}
