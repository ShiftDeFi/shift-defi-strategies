// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MorphoVault} from "contracts/morpho/MorphoVault.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Deploys a new `MorphoVault` implementation and prepares the multisig calldata to point the
///         RLUSD strategy proxy at it. Only the implementation deployment is broadcast.
contract UpgradeMorphoVaultRlUsd is UpgradeBase {
    function run() public {
        address proxy = vm.envAddress("MORPHO_VAULT_RLUSD_PROXY");

        vm.startBroadcast();
        address newImplementation = address(new MorphoVault());
        vm.stopBroadcast();

        // Plain implementation swap: no re-initialization call.
        _prepareUpgradeCalldata("MorphoVault RLUSD", proxy, newImplementation, "");
    }
}
