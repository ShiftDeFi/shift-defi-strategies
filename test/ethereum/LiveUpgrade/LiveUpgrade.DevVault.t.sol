// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiveSafeUpgradeBase} from "test/upgrade/LiveSafeUpgradeBase.t.sol";

/// @notice Dev vault 0xB6Fa60AF402cd2810a68fC6b2F6Ce66C3d7233C4, Ethereum strategies.
contract LiveUpgradeDevVaultEthereumTest is LiveSafeUpgradeBase {
    // Dev Safe owning every dev strategy `ProxyAdmin`, same address on every chain
    address internal constant DEV_SAFE = 0x7705f76663e83354aBD38cbAdCCB5eaeA569c6cB;

    address internal constant CONTAINER_LOCAL = 0x866AD6eD87C2A0AB43B498c3a92e383B466407fb;

    address internal constant CURVE_GAUGE_PYUSD = 0x7E50e51978D44059d94fB2c090D56F87dDde7B03;
    address internal constant MORPHO_VAULT_RLUSD = 0x58f3FDd340Fe6EafBC9448C062337BD84153a273;
    address internal constant FLUID_SUPPLY_USDT = 0x0F6F578A9DFE900902A0b35fb2fFFA84307cfB9d;

    function _rpcAlias() internal pure override returns (string memory) {
        return "ethereum";
    }

    function _strategyContainer() internal pure override returns (address) {
        return CONTAINER_LOCAL;
    }

    function _upgrader() internal pure override returns (address) {
        return DEV_SAFE;
    }

    function _setUpProxies() internal override {
        proxies.curveGauge.push(CURVE_GAUGE_PYUSD);
        proxies.morphoVault.push(MORPHO_VAULT_RLUSD);
        proxies.fluidSupply.push(FLUID_SUPPLY_USDT);
    }
}
