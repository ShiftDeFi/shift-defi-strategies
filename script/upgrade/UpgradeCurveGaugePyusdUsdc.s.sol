// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Deploys a new `CurveGauge` implementation and prepares the multisig calldata to point the
///         PYUSD/USDC strategy proxy at it. Only the implementation deployment is broadcast.
contract UpgradeCurveGaugePyusdUsdc is UpgradeBase {
    function run() public {
        address proxy = vm.envAddress("CURVE_GAUGE_PYUSD_USDC_PROXY");

        vm.startBroadcast();
        address newImplementation = address(new CurveGauge());
        vm.stopBroadcast();

        // Plain implementation swap: no re-initialization call.
        _prepareUpgradeCalldata("CurveGauge PYUSD/USDC", proxy, newImplementation, "");
    }
}
