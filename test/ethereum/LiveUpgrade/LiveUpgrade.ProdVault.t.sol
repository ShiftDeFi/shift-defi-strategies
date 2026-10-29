// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiveTimelockUpgradeBase} from "test/upgrade/LiveTimelockUpgradeBase.t.sol";

/// @notice Prod vault 0x1d71c888961c4600cF0E31F6196b4dA7fE72e4B3, Ethereum strategies.
contract LiveUpgradeProdVaultEthereumTest is LiveTimelockUpgradeBase {
    address internal constant CONTAINER_LOCAL = 0xABa01d24E219f1B15c2207bd316Bd3850EAF9850;

    address internal constant CURVE_GAUGE_PYUSD = 0xaB1c0A644924E88b7df83831853a842cf5c3B060;
    address internal constant CURVE_GAUGE_RLUSD = 0x93e0616F088e4eb317221Ba13B4dD1E85d58c027;
    address internal constant MORPHO_VAULT_PYUSD = 0xEb86a4dBD82f5a8D0BB90703ED26EA6915cEcD74;
    address internal constant MORPHO_VAULT_RLUSD = 0x84FAdE80376Dfc7F190D7D48acddBcCaA538EA5B;

    function _rpcAlias() internal pure override returns (string memory) {
        return "ethereum";
    }

    function _strategyContainer() internal pure override returns (address) {
        return CONTAINER_LOCAL;
    }

    function _setUpProxies() internal override {
        proxies.curveGauge.push(CURVE_GAUGE_PYUSD);
        proxies.curveGauge.push(CURVE_GAUGE_RLUSD);
        proxies.morphoVault.push(MORPHO_VAULT_PYUSD);
        proxies.morphoVault.push(MORPHO_VAULT_RLUSD);
    }

    /// @dev Scheduled in tx 0xed3bdcc515edecce76bbaeccb638a9f26c879b0f66263650da496f1094ad0ede.
    function _scheduledUpgrade() internal pure override returns (ScheduledUpgrade memory scheduled) {
        scheduled.operationId = 0xc8f903b47d6b5e2daf049d078331adb84aa91aa52fb5a7bcd358257cb5829b2c;
        scheduled.salt = 0xeca792d0e615adb461ec704bd502d279f12d04ef9a44eb5a1ca3fc3f9bec8dde;
        scheduled.newImplementations = new address[](4);
        scheduled.newImplementations[0] = 0xE7c0917035D9613a23457076bE1D96f59E749aD1;
        scheduled.newImplementations[1] = 0x53E5b716010421A7a0677b005dD8EA50e70315Fb;
        scheduled.newImplementations[2] = 0xE8328E3f189F02Cd9bC4Ab76810d3Ec6827A1563;
        scheduled.newImplementations[3] = 0xdC57F86851640184547Fe1E23e230F2bE2819543;
    }
}
