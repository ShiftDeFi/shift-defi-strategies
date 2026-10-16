// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ISafe} from "contracts/dependencies/safe/ISafe.sol";

/// @title UpgradeBase
/// @notice Shared logic for strategy implementation upgrades.
/// @dev The proxies are OpenZeppelin v5 `TransparentUpgradeableProxy` instances. Each proxy owns its own
///      `ProxyAdmin` contract, and the upgrade is performed by the `ProxyAdmin` owner via
///      `ProxyAdmin.upgradeAndCall(proxy, impl, data)`.
///
///      Single-proxy upgrades (`_upgrade`) have two operating modes, selected by the `EXECUTE_UPGRADE` env
///      var (default: false):
///        - false (multisig admin): the new implementation is deployed and the exact `upgradeAndCall`
///          calldata is printed for the multisig (ProxyAdmin owner) to execute. The upgrade itself is
///          NOT broadcast from here.
///        - true (EOA admin owned by the broadcaster): the new implementation is deployed AND the upgrade
///          is executed in the same broadcast. Only valid when the broadcasting account owns the ProxyAdmin.
///
///      Several proxies can instead be upgraded in one atomic batch by whoever owns their `ProxyAdmin`s:
///        - a `TimelockController` (`_prepareTimelockBatch`): one timelock operation, with the `scheduleBatch`
///          calldata for the proposer and the `executeBatch` calldata for the executor;
///        - a Safe (`_prepareSafeBatch`): one Safe transaction delegatecalling `MultiSendCallOnly`.
abstract contract UpgradeBase is Script {
    uint8 internal constant SAFE_OPERATION_CALL = 0;
    uint8 internal constant SAFE_OPERATION_DELEGATECALL = 1;

    /// @notice A single proxy upgrade inside a batch.
    struct ProxyUpgrade {
        string label;
        address proxy;
        address newImplementation;
    }

    /// @notice A timelock operation upgrading several proxies at once, with the calldata for both of its steps.
    struct TimelockBatch {
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bytes32 salt;
        uint256 delay;
        bytes32 operationId;
        bytes scheduleCalldata;
        bytes executeCalldata;
    }

    /// @notice A Safe transaction upgrading several proxies at once through `MultiSendCallOnly`.
    struct SafeBatch {
        address[] targets;
        bytes[] payloads;
        address multiSend;
        bytes data;
        uint256 nonce;
        bytes32 safeTxHash;
    }

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

    /// @notice Builds the timelock operation that upgrades every proxy in `upgrades` in one atomic batch.
    /// @dev One `ProxyAdmin.upgradeAndCall(proxy, impl, "")` call per proxy, no predecessor, `delay` set to the
    ///      timelock's current minimum delay. Every proxy's `ProxyAdmin` must be owned by `timelock`, and the
    ///      operation must not already exist (use a different `salt` to re-propose the same upgrades).
    /// @param timelock The `TimelockController` owning the proxies' `ProxyAdmin`s.
    /// @param upgrades The proxies to upgrade and their freshly deployed implementations.
    /// @param salt Timelock operation salt.
    function _prepareTimelockBatch(
        address timelock,
        ProxyUpgrade[] memory upgrades,
        bytes32 salt
    ) internal view returns (TimelockBatch memory batch) {
        require(timelock != address(0), "UpgradeBase: timelock is zero address");

        (batch.targets, batch.payloads) = _upgradeCalls(timelock, upgrades);
        batch.values = new uint256[](upgrades.length);

        TimelockController timelockController = TimelockController(payable(timelock));
        batch.salt = salt;
        batch.delay = timelockController.getMinDelay();
        batch.operationId = timelockController.hashOperationBatch(
            batch.targets,
            batch.values,
            batch.payloads,
            bytes32(0),
            salt
        );
        require(
            !timelockController.isOperation(batch.operationId),
            "UpgradeBase: timelock operation already exists (change the salt)"
        );

        batch.scheduleCalldata = abi.encodeCall(
            TimelockController.scheduleBatch,
            (batch.targets, batch.values, batch.payloads, bytes32(0), salt, batch.delay)
        );
        batch.executeCalldata = abi.encodeCall(
            TimelockController.executeBatch,
            (batch.targets, batch.values, batch.payloads, bytes32(0), salt)
        );
    }

    /// @notice Builds the Safe transaction that upgrades every proxy in `upgrades` in one atomic batch.
    /// @dev One `ProxyAdmin.upgradeAndCall(proxy, impl, "")` call per proxy, packed into a single
    ///      `MultiSendCallOnly.multiSend` that the Safe executes as a DELEGATECALL. Every proxy's `ProxyAdmin`
    ///      must be owned by `safe`. `safeTxHash` is computed at the Safe's current nonce with no gas refund,
    ///      matching what the Safe UI shows for a transaction proposed with this exact data.
    /// @param safe The Safe owning the proxies' `ProxyAdmin`s.
    /// @param multiSend The `MultiSendCallOnly` singleton matching the Safe's version.
    /// @param upgrades The proxies to upgrade and their freshly deployed implementations.
    function _prepareSafeBatch(
        address safe,
        address multiSend,
        ProxyUpgrade[] memory upgrades
    ) internal view returns (SafeBatch memory batch) {
        require(safe != address(0), "UpgradeBase: safe is zero address");
        require(multiSend.code.length > 0, "UpgradeBase: MultiSendCallOnly has no code");

        (batch.targets, batch.payloads) = _upgradeCalls(safe, upgrades);

        bytes memory packedTransactions;
        for (uint256 i = 0; i < batch.targets.length; ++i) {
            packedTransactions = abi.encodePacked(
                packedTransactions,
                SAFE_OPERATION_CALL,
                batch.targets[i],
                uint256(0),
                batch.payloads[i].length,
                batch.payloads[i]
            );
        }

        batch.multiSend = multiSend;
        batch.data = abi.encodeWithSignature("multiSend(bytes)", packedTransactions);
        batch.nonce = ISafe(safe).nonce();
        batch.safeTxHash = ISafe(safe).getTransactionHash(
            multiSend,
            0,
            batch.data,
            SAFE_OPERATION_DELEGATECALL,
            0,
            0,
            0,
            address(0),
            address(0),
            batch.nonce
        );
    }

    /// @notice One `ProxyAdmin.upgradeAndCall(proxy, impl, "")` call per upgrade, validated against `owner`.
    /// @dev Rejects an empty batch, a duplicated proxy, an implementation without code and any proxy whose
    ///      `ProxyAdmin` is not owned by `owner` (the account that will execute the calls).
    function _upgradeCalls(
        address owner,
        ProxyUpgrade[] memory upgrades
    ) internal view returns (address[] memory targets, bytes[] memory payloads) {
        uint256 length = upgrades.length;
        require(length > 0, "UpgradeBase: nothing to upgrade");

        targets = new address[](length);
        payloads = new bytes[](length);

        for (uint256 i = 0; i < length; ++i) {
            ProxyUpgrade memory upgrade = upgrades[i];
            require(upgrade.proxy != address(0), "UpgradeBase: proxy is zero address");
            require(upgrade.newImplementation.code.length > 0, "UpgradeBase: implementation has no code");
            for (uint256 j = 0; j < i; ++j) {
                require(upgrades[j].proxy != upgrade.proxy, "UpgradeBase: duplicate proxy in batch");
            }

            address proxyAdmin = _proxyAdminOf(upgrade.proxy);
            require(proxyAdmin != address(0), "UpgradeBase: proxy admin not found (is this a transparent proxy?)");
            require(ProxyAdmin(proxyAdmin).owner() == owner, "UpgradeBase: ProxyAdmin is not owned by the upgrader");

            targets[i] = proxyAdmin;
            payloads[i] = abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (ITransparentUpgradeableProxy(upgrade.proxy), upgrade.newImplementation, "")
            );
        }
    }

    /// @notice Prints the upgrades in `batch` and the two timelock transactions (proposer, then executor).
    function _logTimelockBatch(
        address timelock,
        ProxyUpgrade[] memory upgrades,
        TimelockBatch memory batch
    ) internal view {
        console.log("==================================================================");
        console.log("Timelock batch upgrade: %s proxies", upgrades.length);
        _logUpgrades(upgrades, batch.targets);
        console.log("------------------------------------------------------------------");
        console.log("Timelock:               %s", timelock);
        console.log("Operation id:");
        console.logBytes32(batch.operationId);
        console.log("Salt:");
        console.logBytes32(batch.salt);
        console.log("Delay (seconds):        %s", batch.delay);
        console.log("------------------------------------------------------------------");
        console.log("1) PROPOSER transaction (scheduleBatch):");
        console.log("  to (Timelock):        %s", timelock);
        console.log("  value:                0");
        console.log("  data:");
        console.logBytes(batch.scheduleCalldata);
        console.log("------------------------------------------------------------------");
        console.log("2) EXECUTOR transaction (executeBatch), once the delay has passed:");
        console.log("  to (Timelock):        %s", timelock);
        console.log("  value:                0");
        console.log("  data:");
        console.logBytes(batch.executeCalldata);
        console.log("==================================================================");
    }

    /// @notice Prints the upgrades in `batch` and the single Safe transaction executing all of them.
    function _logSafeBatch(address safe, ProxyUpgrade[] memory upgrades, SafeBatch memory batch) internal view {
        console.log("==================================================================");
        console.log("Safe batch upgrade: %s proxies", upgrades.length);
        _logUpgrades(upgrades, batch.targets);
        console.log("------------------------------------------------------------------");
        console.log("SAFE transaction (MultiSendCallOnly batch):");
        console.log("  Safe:                 %s", safe);
        console.log("  to (MultiSend):       %s", batch.multiSend);
        console.log("  value:                0");
        console.log("  operation:            1 (DELEGATECALL)");
        console.log("  nonce:                %s", batch.nonce);
        console.log("  safeTxHash (at this nonce, no gas refund):");
        console.logBytes32(batch.safeTxHash);
        console.log("  data:");
        console.logBytes(batch.data);
        console.log("==================================================================");
    }

    function _logUpgrades(ProxyUpgrade[] memory upgrades, address[] memory proxyAdmins) private view {
        for (uint256 i = 0; i < upgrades.length; ++i) {
            console.log("------------------------------------------------------------------");
            console.log("[%s] %s", i, upgrades[i].label);
            console.log("  Proxy:                  %s", upgrades[i].proxy);
            console.log("  ProxyAdmin:             %s", proxyAdmins[i]);
            console.log("  Current implementation: %s", _implementationOf(upgrades[i].proxy));
            console.log("  New implementation:     %s", upgrades[i].newImplementation);
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
