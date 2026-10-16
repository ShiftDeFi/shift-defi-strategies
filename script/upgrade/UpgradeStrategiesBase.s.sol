// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3Supply} from "contracts/aave-v3/AaveV3Supply.sol";
import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {FluidSupply} from "contracts/fluid/FluidSupply.sol";
import {MorphoVault} from "contracts/morpho/MorphoVault.sol";
import {UpgradeBase} from "./UpgradeBase.s.sol";

/// @notice Shared logic of the batch upgrade scripts: reads the proxies to upgrade per strategy type, checks
///         each proxy really is of the type it is listed under and deploys a dedicated implementation for it
///         (implementations are never shared between proxies).
/// @dev Env vars, all optional comma-separated proxy lists:
///        - CURVE_GAUGE_PROXIES, MORPHO_VAULT_PROXIES, FLUID_SUPPLY_PROXIES, AAVE_V3_SUPPLY_PROXIES.
abstract contract UpgradeStrategiesBase is UpgradeBase {
    struct StrategyProxies {
        address[] curveGauge;
        address[] morphoVault;
        address[] fluidSupply;
        address[] aaveV3Supply;
    }

    function _readStrategyProxies() internal view returns (StrategyProxies memory proxies) {
        address[] memory none = new address[](0);
        proxies.curveGauge = vm.envOr("CURVE_GAUGE_PROXIES", ",", none);
        proxies.morphoVault = vm.envOr("MORPHO_VAULT_PROXIES", ",", none);
        proxies.fluidSupply = vm.envOr("FLUID_SUPPLY_PROXIES", ",", none);
        proxies.aaveV3Supply = vm.envOr("AAVE_V3_SUPPLY_PROXIES", ",", none);
    }

    /// @notice Rejects any proxy listed under the wrong strategy type, which would brick it once upgraded.
    /// @dev Each type is recognised by a getter only it exposes. `AaveV3SupplyWithMerkle` also exposes `pool()`,
    ///      so an Aave proxy must additionally not expose `merkleDistributor()`.
    function _checkProxyKinds(StrategyProxies memory proxies) internal view {
        for (uint256 i = 0; i < proxies.curveGauge.length; ++i) {
            _requireAddressGetter(proxies.curveGauge[i], "gauge()", "CurveGauge");
        }
        for (uint256 i = 0; i < proxies.morphoVault.length; ++i) {
            _requireAddressGetter(proxies.morphoVault[i], "morphoVault()", "MorphoVault");
        }
        for (uint256 i = 0; i < proxies.fluidSupply.length; ++i) {
            _requireAddressGetter(proxies.fluidSupply[i], "fToken()", "FluidSupply");
        }
        for (uint256 i = 0; i < proxies.aaveV3Supply.length; ++i) {
            _requireAddressGetter(proxies.aaveV3Supply[i], "pool()", "AaveV3Supply");
            _requireNoGetter(proxies.aaveV3Supply[i], "merkleDistributor()", "AaveV3Supply");
        }
    }

    /// @notice Deploys one new implementation per proxy.
    function _deployImplementations(StrategyProxies memory proxies) internal returns (ProxyUpgrade[] memory upgrades) {
        upgrades = new ProxyUpgrade[](
            proxies.curveGauge.length +
                proxies.morphoVault.length +
                proxies.fluidSupply.length +
                proxies.aaveV3Supply.length
        );
        uint256 n;

        for (uint256 i = 0; i < proxies.curveGauge.length; ++i) {
            upgrades[n++] = ProxyUpgrade("CurveGauge", proxies.curveGauge[i], address(new CurveGauge()));
        }
        for (uint256 i = 0; i < proxies.morphoVault.length; ++i) {
            upgrades[n++] = ProxyUpgrade("MorphoVault", proxies.morphoVault[i], address(new MorphoVault()));
        }
        for (uint256 i = 0; i < proxies.fluidSupply.length; ++i) {
            upgrades[n++] = ProxyUpgrade("FluidSupply", proxies.fluidSupply[i], address(new FluidSupply()));
        }
        for (uint256 i = 0; i < proxies.aaveV3Supply.length; ++i) {
            upgrades[n++] = ProxyUpgrade("AaveV3Supply", proxies.aaveV3Supply[i], address(new AaveV3Supply()));
        }
    }

    function _requireAddressGetter(address proxy, string memory getter, string memory kind) private view {
        (bool success, bytes memory data) = proxy.staticcall(abi.encodeWithSignature(getter));
        require(
            success && data.length == 32 && abi.decode(data, (address)) != address(0),
            string.concat("UpgradeStrategies: not a ", kind, " proxy: ", vm.toString(proxy))
        );
    }

    function _requireNoGetter(address proxy, string memory getter, string memory kind) private view {
        (bool success, ) = proxy.staticcall(abi.encodeWithSignature(getter));
        require(!success, string.concat("UpgradeStrategies: not a ", kind, " proxy: ", vm.toString(proxy)));
    }
}
