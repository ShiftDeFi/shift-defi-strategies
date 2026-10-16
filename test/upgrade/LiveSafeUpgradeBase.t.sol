// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISafe} from "contracts/dependencies/safe/ISafe.sol";

import {UpgradeBase} from "script/upgrade/UpgradeBase.s.sol";

import {LiveUpgradeBase} from "./LiveUpgradeBase.t.sol";

/// @notice Live upgrade rehearsal for proxies whose `ProxyAdmin`s are owned by a Safe.
/// @dev The batch goes through the Safe's real `execTransaction`: `threshold` owners approve the exact
///      `safeTxHash` the script prints and sign with pre-validated signatures, so a wrong hash or a malformed
///      `MultiSendCallOnly` payload fails here exactly as it would on chain.
abstract contract LiveSafeUpgradeBase is LiveUpgradeBase {
    address internal constant MULTISEND_CALL_ONLY_V141 = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

    uint8 private constant SAFE_OPERATION_DELEGATECALL = 1;

    function _applyUpgrade(UpgradeBase.ProxyUpgrade[] memory upgrades) internal override {
        _execSafeBatch(upgrader.exposed_prepareSafeBatch(_upgrader(), MULTISEND_CALL_ONLY_V141, upgrades));
    }

    function test_SafeBatch_UpgradesEveryProxy() public {
        address[] memory oldImplementations = _implementationsOf(allProxies);
        UpgradeBase.ProxyUpgrade[] memory upgrades = _deployUpgrade();
        ISafe safe = ISafe(_upgrader());
        uint256 nonceBefore = safe.nonce();

        UpgradeBase.SafeBatch memory batch = upgrader.exposed_prepareSafeBatch(
            address(safe),
            MULTISEND_CALL_ONLY_V141,
            upgrades
        );
        assertEq(batch.nonce, nonceBefore);
        assertEq(batch.targets.length, allProxies.length);

        _execSafeBatch(batch);

        assertEq(safe.nonce(), nonceBefore + 1);
        _assertUpgraded(upgrades, oldImplementations);
    }

    function _execSafeBatch(UpgradeBase.SafeBatch memory batch) internal {
        ISafe safe = ISafe(_upgrader());
        address[] memory signers = _sortedSigners(safe);

        bytes memory signatures;
        for (uint256 i = 0; i < signers.length; ++i) {
            vm.prank(signers[i]);
            safe.approveHash(batch.safeTxHash);
            // Pre-validated signature: r = owner, s = 0, v = 1
            signatures = abi.encodePacked(signatures, uint256(uint160(signers[i])), bytes32(0), uint8(1));
        }

        bool success = safe.execTransaction(
            batch.multiSend,
            0,
            batch.data,
            SAFE_OPERATION_DELEGATECALL,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures
        );
        assertTrue(success, "Safe batch failed");
    }

    /// @dev `threshold` owners in ascending order, as the Safe requires signatures to be sorted.
    function _sortedSigners(ISafe safe) private view returns (address[] memory signers) {
        address[] memory owners = safe.getOwners();
        for (uint256 i = 1; i < owners.length; ++i) {
            address owner = owners[i];
            uint256 j = i;
            while (j > 0 && owners[j - 1] > owner) {
                owners[j] = owners[j - 1];
                --j;
            }
            owners[j] = owner;
        }

        signers = new address[](safe.getThreshold());
        for (uint256 i = 0; i < signers.length; ++i) {
            signers[i] = owners[i];
        }
    }
}
