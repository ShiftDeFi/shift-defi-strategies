// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiveSafeUpgradeBase} from "test/upgrade/LiveSafeUpgradeBase.t.sol";

/// @notice Dev vault 0xB6Fa60AF402cd2810a68fC6b2F6Ce66C3d7233C4 (Ethereum), Arbitrum strategies behind its
///         ContainerPrincipal 0x760CAEc1c6fDFE48463f420E9539f3CF92D61D3C.
contract LiveUpgradeDevVaultArbitrumTest is LiveSafeUpgradeBase {
    // Dev Safe owning every dev strategy `ProxyAdmin`, same address on every chain
    address internal constant DEV_SAFE = 0x7705f76663e83354aBD38cbAdCCB5eaeA569c6cB;

    address internal constant CONTAINER_AGENT = 0x0Cad92E66B208eeD823bBD8Ff070c845f6C19DBF;

    address internal constant AAVE_V3_SUPPLY_USDC = 0xc77458a2ebf671bB44Ff35E300595f93C4D8fd5a;
    address internal constant AAVE_V3_SUPPLY_USDT = 0xB093e57812A919FDd35b187eF6E312De7Cdf0A8d;

    function _rpcAlias() internal pure override returns (string memory) {
        return "arbitrum";
    }

    function _strategyContainer() internal pure override returns (address) {
        return CONTAINER_AGENT;
    }

    function _upgrader() internal pure override returns (address) {
        return DEV_SAFE;
    }

    function _setUpProxies() internal override {
        proxies.aaveV3Supply.push(AAVE_V3_SUPPLY_USDC);
        proxies.aaveV3Supply.push(AAVE_V3_SUPPLY_USDT);
    }
}
