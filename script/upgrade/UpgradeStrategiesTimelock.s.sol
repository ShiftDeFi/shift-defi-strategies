// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeStrategiesBase} from "./UpgradeStrategiesBase.s.sol";

/// @notice Upgrades a set of strategy proxies on one chain through their `TimelockController` in a single
///         atomic batch.
/// @dev Deploys a dedicated implementation for every proxy, then prints the `scheduleBatch` calldata for the
///      timelock proposer and the `executeBatch` calldata for the timelock executor. Nothing but the
///      implementation deployments is broadcast.
///
///      Env vars:
///        - UPGRADE_TIMELOCK: the `TimelockController` owning every proxy's `ProxyAdmin`;
///        - TIMELOCK_SALT:    timelock operation salt (optional, default zero);
///        - the proxy lists read by `UpgradeStrategiesBase`.
contract UpgradeStrategiesTimelock is UpgradeStrategiesBase {
    function run() public {
        address timelock = vm.envAddress("UPGRADE_TIMELOCK");
        bytes32 salt = vm.envOr("TIMELOCK_SALT", bytes32(0));
        StrategyProxies memory proxies = _readStrategyProxies();

        _checkProxyKinds(proxies);

        vm.startBroadcast();
        ProxyUpgrade[] memory upgrades = _deployImplementations(proxies);
        vm.stopBroadcast();

        _logTimelockBatch(timelock, upgrades, _prepareTimelockBatch(timelock, upgrades, salt));
    }
}
