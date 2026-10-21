// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {MorphoVault} from "contracts/morpho/MorphoVault.sol";

import {LiveTimelockUpgradeBase} from "test/upgrade/LiveTimelockUpgradeBase.t.sol";

/// @notice Prod vault 0x1d71c888961c4600cF0E31F6196b4dA7fE72e4B3, Ethereum strategies.
contract LiveUpgradeProdVaultEthereumTest is LiveTimelockUpgradeBase {
    using Math for uint256;

    address internal constant CONTAINER_LOCAL = 0xABa01d24E219f1B15c2207bd316Bd3850EAF9850;

    address internal constant CURVE_GAUGE_PYUSD = 0xaB1c0A644924E88b7df83831853a842cf5c3B060;
    address internal constant CURVE_GAUGE_RLUSD = 0x93e0616F088e4eb317221Ba13B4dD1E85d58c027;
    address internal constant MORPHO_VAULT_PYUSD = 0xEb86a4dBD82f5a8D0BB90703ED26EA6915cEcD74;
    address internal constant MORPHO_VAULT_RLUSD = 0x84FAdE80376Dfc7F190D7D48acddBcCaA538EA5B;

    function _rpcAlias() internal pure override returns (string memory) {
        return "ethereum";
    }

    function _strategyContainer() internal pure override returns (address) {
        return CONTAINER_LOCAL;
    }

    function _setUpProxies() internal override {
        proxies.curveGauge.push(CURVE_GAUGE_PYUSD);
        proxies.curveGauge.push(CURVE_GAUGE_RLUSD);
        proxies.morphoVault.push(MORPHO_VAULT_PYUSD);
        proxies.morphoVault.push(MORPHO_VAULT_RLUSD);
    }

    /// @dev Core 0.7.0 routed an enter into a token state to `_enterState`, which has no such state.
    function test_MorphoRlusd_TokenStateEnterRevertsBeforeUpgrade() public {
        _requireRlusdParked();
        IStrategyTemplate strategy = IStrategyTemplate(MORPHO_VAULT_RLUSD);

        (uint256[] memory amounts, uint256 incomingNav) = _exitToContainer(MORPHO_VAULT_RLUSD, ROUND_TRIP_SHARE);
        uint256 minNavDelta = _minEnterNavDelta(strategy, incomingNav);

        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, UNDERLYING_ASSET_STATE_ID));
        vm.prank(CONTAINER_LOCAL);
        strategy.enter(amounts, minNavDelta);
    }

    function test_MorphoRlusd_TokenStateEnterKeepsFundsIdleAfterUpgrade() public {
        _requireRlusdParked();
        IStrategyTemplate strategy = IStrategyTemplate(MORPHO_VAULT_RLUSD);
        address rlusd = MorphoVault(MORPHO_VAULT_RLUSD).underlyingAsset();
        uint256 idleBefore = IERC20(rlusd).balanceOf(MORPHO_VAULT_RLUSD);

        _upgrade();

        (uint256[] memory amounts, uint256 incomingNav) = _exitToContainer(MORPHO_VAULT_RLUSD, ROUND_TRIP_SHARE);
        uint256 minNavDelta = _minEnterNavDelta(strategy, incomingNav);

        vm.prank(CONTAINER_LOCAL);
        (, bool hasRemainder, ) = strategy.enter(amounts, minNavDelta);

        assertFalse(hasRemainder);
        assertEq(strategy.currentStateId(), UNDERLYING_ASSET_STATE_ID);
        assertEq(IERC20(rlusd).balanceOf(MORPHO_VAULT_RLUSD), idleBefore);
        assertEq(IERC20(MorphoVault(MORPHO_VAULT_RLUSD).morphoVault()).balanceOf(MORPHO_VAULT_RLUSD), 0);
    }

    function test_MorphoRlusd_ReenterVaultAfterUpgrade() public {
        _requireRlusdParked();
        IStrategyTemplate strategy = IStrategyTemplate(MORPHO_VAULT_RLUSD);
        uint256 idleNav = strategy.currentStateNav();

        _upgrade();

        vm.mockCall(
            CONTAINER_LOCAL,
            abi.encodeCall(IAccessControl.hasRole, (EMERGENCY_MANAGER_ROLE, roles.emergencyManager)),
            abi.encode(true)
        );
        vm.prank(roles.emergencyManager);
        MorphoVault(MORPHO_VAULT_RLUSD).reenterToState(
            MORPHO_VAULT_STATE_ID,
            idleNav - idleNav.mulDiv(NAV_TOLERANCE_PCT, MAX_BPS)
        );

        assertEq(strategy.currentStateId(), MORPHO_VAULT_STATE_ID);
        assertEq(IERC20(MorphoVault(MORPHO_VAULT_RLUSD).underlyingAsset()).balanceOf(MORPHO_VAULT_RLUSD), 0);
        assertApproxEqRel(strategy.currentStateNav(), idleNav, NAV_TOLERANCE_PCT);
        assertEq(MorphoVault(MORPHO_VAULT_RLUSD).lastAssetsValue(), _morphoAssetsValue(MORPHO_VAULT_RLUSD));
    }

    /// @dev These tests rehearse the current live situation; skip them once rlusd is back in the vault.
    function _requireRlusdParked() internal {
        vm.skip(IStrategyTemplate(MORPHO_VAULT_RLUSD).currentStateId() != UNDERLYING_ASSET_STATE_ID);
    }
}
