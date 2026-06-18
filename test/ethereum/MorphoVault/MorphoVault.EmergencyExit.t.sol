// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MorphoVaultBase} from "./MorphoVaultBase.t.sol";

abstract contract MorphoVaultEmergencyExitTest is MorphoVaultBase {
    using Math for uint256;

    function test_EmergencyExit_ToUnderlyingAssets_FullExit() public {
        _enterStrategy();

        uint256 maxNavDelta = morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID);

        vm.startPrank(roles.emergencyExecutor);
        morphoVaultStrategy.emergencyExit(UNDERLYING_ASSET_STATE_ID, MAX_BPS, maxNavDelta);
        vm.stopPrank();

        assertApproxEqRel(
            morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID),
            0,
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Morpho Vault NAV"
        );

        assertApproxEqRel(
            morphoVaultStrategy.stateNav(UNDERLYING_ASSET_STATE_ID),
            maxNavDelta,
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_FullExit: Underlying Asset NAV"
        );
    }

    function test_EmergencyExit_ToUnderlyingAssets_PartialExit() public {
        _enterStrategy();

        uint256 targetStateNavBefore = morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID);

        uint256 partialShare = MAX_BPS / 2;
        uint256 maxNavDelta = targetStateNavBefore.mulDiv(partialShare - ONE_PCT / 100, MAX_BPS);

        vm.startPrank(roles.emergencyExecutor);
        morphoVaultStrategy.emergencyExit(UNDERLYING_ASSET_STATE_ID, partialShare, maxNavDelta);
        vm.stopPrank();

        assertApproxEqRel(
            morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID),
            targetStateNavBefore - maxNavDelta,
            NAV_TOLERANCE_PCT,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Morpho Vault NAV"
        );

        assertApproxEqRel(
            morphoVaultStrategy.stateNav(UNDERLYING_ASSET_STATE_ID),
            maxNavDelta,
            NAV_TOLERANCE_PCT * 2,
            "test_EmergencyExit_ToUnderlyingAssets_PartialExit: Underlying Asset NAV"
        );
    }
}
