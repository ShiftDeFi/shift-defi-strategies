// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title UpgradeBase
/// @notice Shared logic for strategy implementation upgrades.
/// @dev The proxies are OpenZeppelin v5 `TransparentUpgradeableProxy` instances. Each proxy owns its own
///      `ProxyAdmin` contract, and the upgrade is performed by the `ProxyAdmin` owner via
///      `ProxyAdmin.upgradeAndCall(proxy, impl, data)`.
///
///      Two operating modes, selected by the `EXECUTE_UPGRADE` env var (default: false):
///        - false (multisig admin): the new implementation is deployed and the exact `upgradeAndCall`
///          calldata is printed for the multisig (ProxyAdmin owner) to execute. The upgrade itself is
///          NOT broadcast from here.
///        - true (EOA admin owned by the broadcaster): the new implementation is deployed AND the upgrade
///          is executed in the same broadcast. Only valid when the broadcasting account owns the ProxyAdmin.
abstract contract UpgradeBase is Script {
    /// @dev ERC-1967 admin storage slot: `bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)`.
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev ERC-1967 implementation storage slot: `bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`.
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Reads the `ProxyAdmin` address that manages a transparent proxy from its ERC-1967 admin slot.
    function _proxyAdminOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    /// @notice Reads the current implementation address of a proxy from its ERC-1967 implementation slot.
    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    /// @notice Either executes the upgrade (EXECUTE_UPGRADE=true) or prints the multisig calldata.
    /// @dev Assumes `newImplementation` has already been deployed. When executing, this MUST be called
    ///      inside an active broadcast whose sender owns the proxy's `ProxyAdmin`.
    /// @param label Human-readable name of the strategy being upgraded (for logs).
    /// @param proxy The transparent proxy whose implementation should be upgraded.
    /// @param newImplementation The freshly deployed implementation the proxy should point to.
    /// @param reinitializeData Optional calldata forwarded to the new implementation during the upgrade
    ///        (empty for a plain implementation swap with no re-initialization).
    function _upgrade(
        string memory label,
        address proxy,
        address newImplementation,
        bytes memory reinitializeData
    ) internal {
        require(proxy != address(0), "UpgradeBase: proxy is zero address");
        require(newImplementation != address(0), "UpgradeBase: implementation is zero address");

        address proxyAdmin = _proxyAdminOf(proxy);
        require(proxyAdmin != address(0), "UpgradeBase: proxy admin not found (is this a transparent proxy?)");

        bytes memory upgradeCalldata = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(proxy), newImplementation, reinitializeData)
        );

        if (vm.envOr("EXECUTE_UPGRADE", false)) {
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(proxy),
                newImplementation,
                reinitializeData
            );
            _logExecuted(label, proxy, proxyAdmin, newImplementation);
        } else {
            _logCalldata(label, proxy, proxyAdmin, newImplementation, upgradeCalldata);
        }
    }

    function _logExecuted(
        string memory label,
        address proxy,
        address proxyAdmin,
        address newImplementation
    ) private view {
        console.log("==================================================================");
        console.log("Upgrade EXECUTED for:   %s", label);
        console.log("Proxy:                  %s", proxy);
        console.log("ProxyAdmin:             %s", proxyAdmin);
        console.log("New implementation:     %s", newImplementation);
        console.log("Implementation now:     %s", _implementationOf(proxy));
        console.log("==================================================================");
    }

    function _logCalldata(
        string memory label,
        address proxy,
        address proxyAdmin,
        address newImplementation,
        bytes memory upgradeCalldata
    ) private view {
        console.log("==================================================================");
        console.log("Upgrade prepared for:   %s", label);
        console.log("Proxy:                  %s", proxy);
        console.log("Current implementation: %s", _implementationOf(proxy));
        console.log("New implementation:     %s", newImplementation);
        console.log("------------------------------------------------------------------");
        console.log("MULTISIG TRANSACTION (NOT broadcast - execute via the multisig):");
        console.log("  to (ProxyAdmin):      %s", proxyAdmin);
        console.log("  value:                0");
        console.log("  data:");
        console.logBytes(upgradeCalldata);
        console.log("==================================================================");
    }
}
