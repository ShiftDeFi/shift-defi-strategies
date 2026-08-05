// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title UpgradeBase
/// @notice Shared logic for strategy implementation upgrades.
/// @dev The proxies are OpenZeppelin v5 `TransparentUpgradeableProxy` instances. Each proxy owns its own
///      `ProxyAdmin` contract, whose owner is the multisig. Because the multisig cannot broadcast from a Foundry
///      script, this base only broadcasts the new implementation deployment and then *prints* the calldata the
///      multisig has to execute on the `ProxyAdmin` to perform the upgrade. That upgrade transaction itself is
///      never broadcast from here.
abstract contract UpgradeBase is Script {
    /// @dev ERC-1967 admin storage slot: `bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)`.
    ///      The `ProxyAdmin` contract address for a transparent proxy is stored here.
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

    /// @notice Builds and prints the multisig calldata that upgrades `proxy` to `newImplementation`.
    /// @dev Assumes `newImplementation` has already been deployed. Does NOT broadcast anything.
    /// @param label Human-readable name of the strategy being upgraded (for logs).
    /// @param proxy The transparent proxy whose implementation should be upgraded.
    /// @param newImplementation The freshly deployed implementation the proxy should point to.
    /// @param reinitializeData Optional calldata forwarded to the new implementation during the upgrade
    ///        (empty for a plain implementation swap with no re-initialization).
    /// @return upgradeCalldata The calldata the multisig must send to the `ProxyAdmin`.
    function _prepareUpgradeCalldata(
        string memory label,
        address proxy,
        address newImplementation,
        bytes memory reinitializeData
    ) internal view returns (bytes memory upgradeCalldata) {
        require(proxy != address(0), "UpgradeBase: proxy is zero address");
        require(newImplementation != address(0), "UpgradeBase: implementation is zero address");

        address proxyAdmin = _proxyAdminOf(proxy);
        require(proxyAdmin != address(0), "UpgradeBase: proxy admin not found (is this a transparent proxy?)");

        upgradeCalldata = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(proxy), newImplementation, reinitializeData)
        );

        _logPlan(label, proxy, proxyAdmin, newImplementation, upgradeCalldata);
    }

    function _logPlan(
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
