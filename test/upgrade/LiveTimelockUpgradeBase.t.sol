// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {UpgradeBase} from "script/upgrade/UpgradeBase.s.sol";

import {LiveUpgradeBase} from "./LiveUpgradeBase.t.sol";

/// @notice Live upgrade rehearsal for proxies whose `ProxyAdmin`s are owned by the Shift `TimelockController`.
abstract contract LiveTimelockUpgradeBase is LiveUpgradeBase {
    using Math for uint256;

    /// @notice An upgrade batch the proposer Safe already scheduled on chain.
    /// @dev `newImplementations` follows the order of `allProxies`, which is the order of the scheduled calls.
    struct ScheduledUpgrade {
        bytes32 operationId;
        bytes32 salt;
        address[] newImplementations;
    }

    // Shift governance, deployed at the same addresses on every chain
    address internal constant TIMELOCK = 0x94e67cbE0917c04237bA9a48DA2519F103D6e0d9;
    address internal constant PROPOSER_SAFE = 0x82a9993322f34bf45C89853c460DFe3c365414b8;
    address internal constant EXECUTOR_SAFE = 0x4cC8D45644eCCD8cA77DBF3A8E3eE2dBf4596983;

    function _upgrader() internal pure override returns (address) {
        return TIMELOCK;
    }

    /// @dev The batch scheduled on this chain's timelock; tests built on it skip when `operationId` is zero.
    function _scheduledUpgrade() internal pure virtual returns (ScheduledUpgrade memory scheduled) {}

    /// @dev Applies the batch payloads as the timelock, skipping the delay so the fork's oracles stay fresh.
    function _applyUpgrade(UpgradeBase.ProxyUpgrade[] memory upgrades) internal override {
        UpgradeBase.TimelockBatch memory batch = upgrader.exposed_prepareTimelockBatch(TIMELOCK, upgrades, bytes32(0));
        for (uint256 i = 0; i < batch.targets.length; ++i) {
            vm.prank(TIMELOCK);
            _call(batch.targets[i], batch.payloads[i]);
        }
    }

    function test_TimelockBatch_UpgradesEveryProxy() public {
        address[] memory oldImplementations = _implementationsOf(allProxies);
        UpgradeBase.ProxyUpgrade[] memory upgrades = _deployUpgrade();
        UpgradeBase.TimelockBatch memory batch = upgrader.exposed_prepareTimelockBatch(TIMELOCK, upgrades, bytes32(0));
        TimelockController timelock = TimelockController(payable(TIMELOCK));

        assertEq(batch.delay, timelock.getMinDelay());

        vm.prank(PROPOSER_SAFE);
        _call(TIMELOCK, batch.scheduleCalldata);
        assertTrue(timelock.isOperationPending(batch.operationId));

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                batch.operationId,
                bytes32(1 << uint8(TimelockController.OperationState.Ready))
            )
        );
        vm.prank(EXECUTOR_SAFE);
        timelock.executeBatch(batch.targets, batch.values, batch.payloads, bytes32(0), batch.salt);

        vm.warp(block.timestamp + batch.delay);
        vm.prank(EXECUTOR_SAFE);
        _call(TIMELOCK, batch.executeCalldata);
        assertTrue(timelock.isOperationDone(batch.operationId));

        _assertUpgraded(upgrades, oldImplementations);
    }

    /// @dev After the scheduled upgrade, every allocated strategy is emergency exited to its token state, where
    ///      the container must still be able to exit from and enter into it.
    function test_ScheduledUpgrade_TokenStateExitAndEnterAfterEmergencyExit() public {
        _executeScheduledUpgrade();

        for (uint256 i = 0; i < allProxies.length; ++i) {
            address proxy = allProxies[i];
            IStrategyTemplate strategy = IStrategyTemplate(proxy);
            // Decommissioned strategy: nothing to exit
            if (strategy.currentStateId() == bytes32(0)) continue;
            bytes32 tokenStateId = _knownStateIds(kindOf[proxy])[0];

            _emergencyExitFully(proxy, tokenStateId);
            uint256 tokenStateNav = strategy.currentStateNav();
            assertGt(tokenStateNav, 0, vm.getLabel(proxy));

            (uint256[] memory amounts, uint256 incomingNav) = _exitToContainer(proxy, ROUND_TRIP_SHARE);
            assertEq(strategy.currentStateId(), tokenStateId);
            assertApproxEqRel(
                strategy.currentStateNav(),
                tokenStateNav - tokenStateNav.mulDiv(ROUND_TRIP_SHARE, MAX_BPS),
                NAV_TOLERANCE_PCT,
                vm.getLabel(proxy)
            );

            uint256 minNavDelta = _minEnterNavDelta(strategy, incomingNav);
            vm.prank(_strategyContainer());
            (, bool hasRemainder, ) = strategy.enter(amounts, minNavDelta);
            assertFalse(hasRemainder);
            assertEq(strategy.currentStateId(), tokenStateId);
            assertApproxEqRel(strategy.currentStateNav(), tokenStateNav, NAV_TOLERANCE_PCT, vm.getLabel(proxy));
            _assertNothingInProtocol(proxy, tokenStateId);

            _exitToContainer(proxy, MAX_BPS);
            assertEq(strategy.currentStateId(), bytes32(0));
            assertEq(strategy.stateNav(tokenStateId), 0, vm.getLabel(proxy));
        }
    }

    /// @dev Rebuilds the scheduled batch from its implementations, checks it is the operation scheduled on chain
    ///      and executes it as the executor Safe. Skips the execution if it already happened.
    function _executeScheduledUpgrade() internal {
        ScheduledUpgrade memory scheduled = _scheduledUpgrade();
        vm.skip(scheduled.operationId == bytes32(0));
        assertEq(scheduled.newImplementations.length, allProxies.length);

        UpgradeBase.ProxyUpgrade[] memory upgrades = new UpgradeBase.ProxyUpgrade[](allProxies.length);
        for (uint256 i = 0; i < allProxies.length; ++i) {
            upgrades[i] = UpgradeBase.ProxyUpgrade(
                _kindName(kindOf[allProxies[i]]),
                allProxies[i],
                scheduled.newImplementations[i]
            );
        }

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        if (!timelock.isOperationDone(scheduled.operationId)) {
            (address[] memory targets, bytes[] memory payloads) = upgrader.exposed_upgradeCalls(TIMELOCK, upgrades);
            uint256[] memory values = new uint256[](targets.length);
            assertEq(
                timelock.hashOperationBatch(targets, values, payloads, bytes32(0), scheduled.salt),
                scheduled.operationId,
                "batch differs from the scheduled operation"
            );
            assertTrue(timelock.isOperationPending(scheduled.operationId), "operation not scheduled");

            uint256 readyAt = timelock.getTimestamp(scheduled.operationId);
            if (block.timestamp < readyAt) vm.warp(readyAt);

            address[] memory oldImplementations = _implementationsOf(allProxies);
            vm.prank(EXECUTOR_SAFE);
            timelock.executeBatch(targets, values, payloads, bytes32(0), scheduled.salt);
            assertTrue(timelock.isOperationDone(scheduled.operationId));
            _assertUpgraded(upgrades, oldImplementations);
        }

        for (uint256 i = 0; i < allProxies.length; ++i) {
            assertEq(_implementationOf(allProxies[i]), scheduled.newImplementations[i]);
        }
    }

    /// @dev Emergency exits the whole position to `toStateId` with the loosest slippage the template accepts.
    function _emergencyExitFully(address proxy, bytes32 toStateId) internal {
        IStrategyTemplate strategy = IStrategyTemplate(proxy);
        uint256 expectedNavDelta = strategy.currentStateNav();
        uint256 minNavDelta = expectedNavDelta -
            expectedNavDelta.mulDiv(StrategyTemplate(proxy).emergencyExitMaxSlippage(), MAX_BPS);

        vm.mockCall(
            _strategyContainer(),
            abi.encodeCall(IAccessControl.hasRole, (EMERGENCY_EXECUTOR_ROLE, roles.emergencyExecutor)),
            abi.encode(true)
        );
        vm.prank(roles.emergencyExecutor);
        strategy.emergencyExit(toStateId, MAX_BPS, minNavDelta);

        // A failed exit leaves the strategy in its state, in NAV resolution mode
        assertEq(strategy.currentStateId(), toStateId, string.concat(vm.getLabel(proxy), ": emergency exit failed"));
        assertFalse(strategy.isNavResolutionMode());
        assertGe(strategy.currentStateNav(), minNavDelta);
    }

    function _assertNothingInProtocol(address proxy, bytes32 tokenStateId) internal view {
        bytes32[] memory stateIds = IStrategyTemplate(proxy).getStateIds();
        for (uint256 i = 0; i < stateIds.length; ++i) {
            if (stateIds[i] == tokenStateId) continue;
            assertEq(IStrategyTemplate(proxy).stateNav(stateIds[i]), 0, vm.getLabel(proxy));
        }
    }
}
