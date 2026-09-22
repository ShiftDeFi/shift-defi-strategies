// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Deploys a new `CurveGauge` implementation and either executes the upgrade (EXECUTE_UPGRADE=true,
///         EOA admin) or prints the multisig calldata for it (default).
contract UpgradeCurveGauge is UpgradeBase {
    function run() public {
        address proxy = vm.envAddress("CURVE_GAUGE_PROXY");

        vm.startBroadcast();
        address newImplementation = address(new CurveGauge());
        // Plain implementation swap: no re-initialization call.
        _upgrade("CurveGauge", proxy, newImplementation, "");
        vm.stopBroadcast();
    }
}
