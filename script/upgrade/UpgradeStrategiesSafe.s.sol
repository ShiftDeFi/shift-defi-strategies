// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeStrategiesBase} from "./UpgradeStrategiesBase.s.sol";

/// @notice Upgrades a set of strategy proxies on one chain through the Safe owning their `ProxyAdmin`s, in a
///         single atomic Safe transaction.
/// @dev Deploys a dedicated implementation for every proxy, then prints the Safe transaction (a DELEGATECALL to
///      `MultiSendCallOnly`) and its `safeTxHash` at the Safe's current nonce. Nothing but the implementation
///      deployments is broadcast.
///
///      Env vars:
///        - UPGRADE_SAFE:        the Safe owning every proxy's `ProxyAdmin`;
///        - MULTISEND_CALL_ONLY: `MultiSendCallOnly` singleton for the Safe's version (optional, default: the
///                               canonical v1.4.1 deployment);
///        - the proxy lists read by `UpgradeStrategiesBase`.
contract UpgradeStrategiesSafe is UpgradeStrategiesBase {
    address internal constant MULTISEND_CALL_ONLY_V141 = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

    function run() public {
        address safe = vm.envAddress("UPGRADE_SAFE");
        address multiSend = vm.envOr("MULTISEND_CALL_ONLY", MULTISEND_CALL_ONLY_V141);
        StrategyProxies memory proxies = _readStrategyProxies();

        _checkProxyKinds(proxies);

        vm.startBroadcast();
        ProxyUpgrade[] memory upgrades = _deployImplementations(proxies);
        vm.stopBroadcast();

        _logSafeBatch(safe, upgrades, _prepareSafeBatch(safe, multiSend, upgrades));
    }
}
