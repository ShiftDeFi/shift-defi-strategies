// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {UpgradeBase} from "script/upgrade/UpgradeBase.s.sol";

import {LiveUpgradeBase} from "./LiveUpgradeBase.t.sol";

/// @notice Live upgrade rehearsal for proxies whose `ProxyAdmin`s are owned by the Shift `TimelockController`.
abstract contract LiveTimelockUpgradeBase is LiveUpgradeBase {
    // Shift governance, deployed at the same addresses on every chain
    address internal constant TIMELOCK = 0x94e67cbE0917c04237bA9a48DA2519F103D6e0d9;
    address internal constant PROPOSER_SAFE = 0x82a9993322f34bf45C89853c460DFe3c365414b8;
    address internal constant EXECUTOR_SAFE = 0x4cC8D45644eCCD8cA77DBF3A8E3eE2dBf4596983;

    function _upgrader() internal pure override returns (address) {
        return TIMELOCK;
    }

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
}
