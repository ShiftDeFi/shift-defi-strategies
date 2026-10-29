// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiveTimelockUpgradeBase} from "test/upgrade/LiveTimelockUpgradeBase.t.sol";

/// @notice Prod vault 0x1d71c888961c4600cF0E31F6196b4dA7fE72e4B3 (Ethereum), Base strategies.
contract LiveUpgradeProdVaultBaseTest is LiveTimelockUpgradeBase {
    address internal constant CONTAINER_AGENT = 0x0F3dA7758e87D22533aD369D3AB86FbE2AC5954f;

    address internal constant MORPHO_VAULT_USDC = 0xb1c4f3f592845274E61C4de3D6B3bF7efF7a6cf8;

    function _rpcAlias() internal pure override returns (string memory) {
        return "base";
    }

    function _strategyContainer() internal pure override returns (address) {
        return CONTAINER_AGENT;
    }

    function _setUpProxies() internal override {
        proxies.morphoVault.push(MORPHO_VAULT_USDC);
    }

    /// @dev Scheduled in tx 0x07bdb8fde2fdcdcdcf7c5125334568b95daa1762960604910f9fc72cc47f7a4a.
    function _scheduledUpgrade() internal pure override returns (ScheduledUpgrade memory scheduled) {
        scheduled.operationId = 0x00cc1aa0483b77e5ac3d51e10cff2a3ce4e9172e857b3c318b4a8bf9ad344ddc;
        scheduled.newImplementations = new address[](1);
        scheduled.newImplementations[0] = 0x6d58B4296a5F3fE2957727a04eb5fd0d1F7a60Ec;
    }
}
