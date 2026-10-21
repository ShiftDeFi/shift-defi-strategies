// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StrategyTemplate} from "@shift-defi/core/StrategyTemplate.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {StrategyStateLib} from "@shift-defi/core/libraries/StrategyStateLib.sol";

import {AaveV3Supply} from "contracts/aave-v3/AaveV3Supply.sol";
import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {FluidSupply} from "contracts/fluid/FluidSupply.sol";
import {MorphoVault} from "contracts/morpho/MorphoVault.sol";
import {ICurveGauge} from "contracts/interfaces/ICurveGauge.sol";

import {UpgradeBase} from "script/upgrade/UpgradeBase.s.sol";
import {UpgradeStrategiesBase} from "script/upgrade/UpgradeStrategiesBase.s.sol";

import {BaseConfig} from "test/BaseConfig.sol";

/// @notice Exposes the upgrade scripts' internals so the tests run the exact calldata the Safes will sign.
contract UpgradeStrategiesHarness is UpgradeStrategiesBase {
    function exposed_checkProxyKinds(StrategyProxies memory proxies) external view {
        _checkProxyKinds(proxies);
    }

    function exposed_deployImplementations(StrategyProxies memory proxies) external returns (ProxyUpgrade[] memory) {
        return _deployImplementations(proxies);
    }

    function exposed_upgradeCalls(
        address owner,
        ProxyUpgrade[] memory upgrades
    ) external view returns (address[] memory, bytes[] memory) {
        return _upgradeCalls(owner, upgrades);
    }

    function exposed_prepareTimelockBatch(
        address timelock,
        ProxyUpgrade[] memory upgrades,
        bytes32 salt
    ) external view returns (TimelockBatch memory) {
        return _prepareTimelockBatch(timelock, upgrades, salt);
    }

    function exposed_prepareSafeBatch(
        address safe,
        address multiSend,
        ProxyUpgrade[] memory upgrades
    ) external view returns (SafeBatch memory) {
        return _prepareSafeBatch(safe, multiSend, upgrades);
    }
}

/// @notice Simulates the batch upgrade of the live strategy proxies of one chain against a fork of its current
///         state, and checks the upgraded strategies keep their state and keep working.
/// @dev Live, unpinned fork on purpose: the point is to rehearse the upgrade against today's state. Does not
///      reuse `EthContext`, whose setup rewires the live `PriceOracleAggregator` and would skew the NAVs that
///      are compared before and after the upgrade. How the upgrade is executed depends on who owns the
///      `ProxyAdmin`s, see `LiveTimelockUpgradeBase` and `LiveSafeUpgradeBase`.
abstract contract LiveUpgradeBase is BaseConfig {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using StrategyStateLib for uint256;

    enum Kind {
        CurveGauge,
        MorphoVault,
        FluidSupply,
        AaveV3Supply
    }

    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");
    bytes32 internal constant UNDERLYING_ASSETS_STATE_ID = keccak256("UNDERLYING_ASSETS_STATE_ID");
    bytes32 internal constant CURVE_LP_STATE_ID = keccak256("CURVE_LP_STATE_ID");
    bytes32 internal constant CURVE_GAUGE_STATE_ID = keccak256("CURVE_GAUGE_STATE_ID");
    bytes32 internal constant MORPHO_VAULT_STATE_ID = keccak256("MORPHO_VAULT_STATE_ID");
    bytes32 internal constant FLUID_SUPPLY_STATE_ID = keccak256("FLUID_SUPPLY_STATE_ID");
    bytes32 internal constant AAVE_RESERVE_SUPPLIED_STATE_ID = keccak256("AAVE_RESERVE_SUPPLIED_STATE_ID");

    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%
    uint256 internal constant ROUND_TRIP_SHARE = 10 * ONE_PCT;
    uint256 internal constant MORPHO_DONATION = 1_000; // whole tokens

    UpgradeStrategiesHarness internal upgrader;

    /// @dev Proxies per strategy type; `allProxies` lists them in the order the batch upgrades them.
    UpgradeStrategiesBase.StrategyProxies internal proxies;
    address[] internal allProxies;
    mapping(address proxy => Kind) internal kindOf;

    /// @dev `foundry.toml` RPC alias of the chain to fork.
    function _rpcAlias() internal pure virtual returns (string memory);

    /// @dev The live strategy container all proxies of this chain are registered in.
    function _strategyContainer() internal pure virtual returns (address);

    /// @dev Fills `proxies` with the live proxies of this chain.
    function _setUpProxies() internal virtual;

    /// @dev Account owning every proxy's `ProxyAdmin`.
    function _upgrader() internal pure virtual returns (address);

    /// @dev Executes the batch upgrading every proxy right away, as the `ProxyAdmin` owner would.
    function _applyUpgrade(UpgradeBase.ProxyUpgrade[] memory upgrades) internal virtual;

    function setUp() public virtual override {
        super.setUp();
        vm.createSelectFork(vm.rpcUrl(_rpcAlias()));

        _setUpProxies();
        _register(proxies.curveGauge, Kind.CurveGauge);
        _register(proxies.morphoVault, Kind.MorphoVault);
        _register(proxies.fluidSupply, Kind.FluidSupply);
        _register(proxies.aaveV3Supply, Kind.AaveV3Supply);

        upgrader = new UpgradeStrategiesHarness();
        vm.label(_upgrader(), "UPGRADER");
        vm.label(_strategyContainer(), "STRATEGY_CONTAINER");
    }

    /* Tests */

    function testRevert_CheckProxyKinds_MislistedProxy() public {
        for (uint256 i = 0; i < allProxies.length; ++i) {
            for (uint8 k = 0; k <= uint8(type(Kind).max); ++k) {
                if (Kind(k) == kindOf[allProxies[i]]) continue;

                UpgradeStrategiesBase.StrategyProxies memory mislisted = _singleProxyList(Kind(k), allProxies[i]);
                vm.expectRevert(
                    bytes(
                        string.concat(
                            "UpgradeStrategies: not a ",
                            _kindName(Kind(k)),
                            " proxy: ",
                            vm.toString(allProxies[i])
                        )
                    )
                );
                upgrader.exposed_checkProxyKinds(mislisted);
            }
        }
    }

    function testRevert_UpgradeCalls_NotOwnedByUpgrader() public {
        UpgradeBase.ProxyUpgrade[] memory upgrades = _deployUpgrade();
        vm.expectRevert(bytes("UpgradeBase: ProxyAdmin is not owned by the upgrader"));
        upgrader.exposed_upgradeCalls(makeAddr("NOT_THE_UPGRADER"), upgrades);
    }

    function test_Upgrade_PreservesStrategyViews() public {
        bytes[][] memory viewsBefore = new bytes[][](allProxies.length);
        for (uint256 i = 0; i < allProxies.length; ++i) {
            viewsBefore[i] = _snapshotViews(allProxies[i]);
        }

        _upgrade();

        for (uint256 i = 0; i < allProxies.length; ++i) {
            bytes[] memory viewsAfter = _snapshotViews(allProxies[i]);
            assertEq(viewsAfter.length, viewsBefore[i].length);
            for (uint256 j = 0; j < viewsAfter.length; ++j) {
                (bool successBefore, bytes memory dataBefore) = abi.decode(viewsBefore[i][j], (bool, bytes));
                // Getter missing from the old implementation (e.g. `stateBitmask` before core 0.7.0)
                if (!successBefore && dataBefore.length == 0) continue;
                assertEq(
                    viewsAfter[j],
                    viewsBefore[i][j],
                    string.concat(vm.getLabel(allProxies[i]), " view #", vm.toString(j))
                );
            }
        }
    }

    /// @dev Core 0.7.1 rejects token states that are also protocol or target states, but only when registering
    ///      them: states registered by older implementations must already satisfy it.
    function test_Upgrade_StoredStatesSatisfyCurrentCore() public {
        _upgrade();

        for (uint256 i = 0; i < allProxies.length; ++i) {
            bytes32[] memory expectedStateIds = _knownStateIds(kindOf[allProxies[i]]);
            bytes32[] memory stateIds = IStrategyTemplate(allProxies[i]).getStateIds();
            assertEq(stateIds, expectedStateIds, vm.getLabel(allProxies[i]));

            for (uint256 j = 0; j < stateIds.length; ++j) {
                uint256 bitmask = IStrategyTemplate(allProxies[i]).stateBitmask(stateIds[j]);
                assertNotEq(bitmask, 0);
                assertFalse(bitmask.isTokenState() && (bitmask.isTargetState() || bitmask.isProtocolState()));
            }
        }
    }

    function test_Upgrade_HarvestFromContainer() public {
        _upgrade();
        vm.warp(block.timestamp + 1 hours);

        for (uint256 i = 0; i < allProxies.length; ++i) {
            address proxy = allProxies[i];
            Kind kind = kindOf[proxy];
            IStrategyTemplate strategy = IStrategyTemplate(proxy);
            uint256 navBefore = strategy.currentStateNav();
            bool aaveHasIncome = kind == Kind.AaveV3Supply &&
                _aTokenBalance(proxy) > AaveV3Supply(proxy).lastReserveATokenBalance();

            vm.prank(_strategyContainer());
            strategy.harvest();

            // Reinvested rewards can raise the NAV; only the fee may lower it
            assertGe(
                strategy.currentStateNav(),
                navBefore - navBefore.mulDiv(NAV_TOLERANCE_PCT, MAX_BPS),
                vm.getLabel(proxy)
            );
            if (kind == Kind.MorphoVault) {
                assertEq(MorphoVault(proxy).lastAssetsValue(), _morphoAssetsValue(proxy));
            } else if (kind == Kind.FluidSupply) {
                IERC4626 fToken = IERC4626(FluidSupply(proxy).fToken());
                assertEq(FluidSupply(proxy).lastAssetsValue(), fToken.convertToAssets(fToken.balanceOf(proxy)));
            } else if (kind == Kind.CurveGauge) {
                assertEq(
                    CurveGauge(proxy).lastStoredGaugeBalance(),
                    IERC20(CurveGauge(proxy).gauge()).balanceOf(proxy)
                );
            } else if (aaveHasIncome) {
                assertEq(AaveV3Supply(proxy).lastReserveATokenBalance(), _aTokenBalance(proxy));
            }
        }
    }

    /// @dev Reinvesting idle underlying on harvest used to leave `lastAssetsValue` at the pre-fee value.
    function test_Upgrade_FixesMorphoFeeBaseline() public {
        UpgradeBase.ProxyUpgrade[] memory upgrades = _deployUpgrade();
        address[] memory morphoVaults = proxies.morphoVault;

        uint256 snapshot = vm.snapshotState();
        for (uint256 i = 0; i < morphoVaults.length; ++i) {
            if (IStrategyTemplate(morphoVaults[i]).currentStateId() != MORPHO_VAULT_STATE_ID) continue;
            _donateAndHarvest(morphoVaults[i]);
            assertGt(MorphoVault(morphoVaults[i]).lastAssetsValue(), _morphoAssetsValue(morphoVaults[i]));
        }
        vm.revertToState(snapshot);

        _applyUpgrade(upgrades);
        for (uint256 i = 0; i < morphoVaults.length; ++i) {
            if (IStrategyTemplate(morphoVaults[i]).currentStateId() != MORPHO_VAULT_STATE_ID) continue;
            _donateAndHarvest(morphoVaults[i]);
            assertEq(MorphoVault(morphoVaults[i]).lastAssetsValue(), _morphoAssetsValue(morphoVaults[i]));
        }
    }

    function test_Upgrade_ExitAndReenterFromContainer() public {
        _upgrade();

        for (uint256 i = 0; i < allProxies.length; ++i) {
            IStrategyTemplate strategy = IStrategyTemplate(allProxies[i]);
            bytes32 stateBefore = strategy.currentStateId();
            uint256 navBefore = strategy.currentStateNav();

            (uint256[] memory amounts, uint256 incomingNav) = _exitToContainer(allProxies[i], ROUND_TRIP_SHARE);
            uint256 minNavDelta = _minEnterNavDelta(strategy, incomingNav);

            vm.prank(_strategyContainer());
            strategy.enter(amounts, minNavDelta);

            assertEq(strategy.currentStateId(), stateBefore);
            assertApproxEqRel(strategy.currentStateNav(), navBefore, NAV_TOLERANCE_PCT, vm.getLabel(allProxies[i]));
        }
    }

    /* Helpers */

    /// @dev Checks every proxy's type and deploys its dedicated implementation, exactly as the scripts do.
    function _deployUpgrade() internal returns (UpgradeBase.ProxyUpgrade[] memory upgrades) {
        upgrader.exposed_checkProxyKinds(proxies);
        upgrades = upgrader.exposed_deployImplementations(proxies);
    }

    function _upgrade() internal {
        _applyUpgrade(_deployUpgrade());
    }

    /// @dev Every proxy points at its own new implementation.
    function _assertUpgraded(
        UpgradeBase.ProxyUpgrade[] memory upgrades,
        address[] memory oldImplementations
    ) internal view {
        assertEq(upgrades.length, allProxies.length);
        for (uint256 i = 0; i < upgrades.length; ++i) {
            assertEq(upgrades[i].proxy, allProxies[i]);
            assertEq(_implementationOf(upgrades[i].proxy), upgrades[i].newImplementation);
            assertNotEq(upgrades[i].newImplementation, oldImplementations[i]);
            for (uint256 j = 0; j < i; ++j) {
                assertNotEq(upgrades[i].newImplementation, upgrades[j].newImplementation, "shared implementation");
            }
        }
    }

    /// @dev Exits `share` of the strategy to the container and pulls the released funds into it, ready to be
    ///      entered again. Input and output tokens are the same list on every live strategy.
    function _exitToContainer(
        address proxy,
        uint256 share
    ) internal returns (uint256[] memory amounts, uint256 incomingNav) {
        IStrategyTemplate strategy = IStrategyTemplate(proxy);
        address container = _strategyContainer();
        assertEq(strategy.getInputTokens(), strategy.getOutputTokens());

        uint256 expectedNavDelta = strategy.currentStateNav().mulDiv(share, MAX_BPS);
        uint256 maxNavDelta = expectedNavDelta.mulDiv(MAX_BPS + StrategyTemplate(proxy).exitMaxSlippage(), MAX_BPS);

        address[] memory tokens;
        vm.prank(container);
        (tokens, amounts) = strategy.exit(share, maxNavDelta);

        vm.startPrank(container);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (amounts[i] == 0) continue;
            IERC20(tokens[i]).safeTransferFrom(proxy, container, amounts[i]);
            IERC20(tokens[i]).forceApprove(proxy, amounts[i]);
            incomingNav += strategy.getTokenAmountInNotion(tokens[i], amounts[i]);
        }
        vm.stopPrank();
    }

    /// @dev Loosest `minNavDelta` the template accepts for `incomingNav`.
    function _minEnterNavDelta(IStrategyTemplate strategy, uint256 incomingNav) internal view returns (uint256) {
        return incomingNav - incomingNav.mulDiv(StrategyTemplate(address(strategy)).enterMaxSlippage(), MAX_BPS);
    }

    function _donateAndHarvest(address proxy) internal {
        address underlying = MorphoVault(proxy).underlyingAsset();
        deal(underlying, proxy, MORPHO_DONATION * 10 ** IERC20Metadata(underlying).decimals());
        vm.prank(_strategyContainer());
        IStrategyTemplate(proxy).harvest();
    }

    function _morphoAssetsValue(address proxy) internal view returns (uint256) {
        IERC4626 morphoVault = IERC4626(MorphoVault(proxy).morphoVault());
        return morphoVault.convertToAssets(morphoVault.balanceOf(proxy));
    }

    function _aTokenBalance(address proxy) internal view returns (uint256) {
        return IERC20(AaveV3Supply(proxy).reserveAToken()).balanceOf(proxy);
    }

    /// @dev Raw results of every getter whose value depends on the strategy's storage layout. The state ids come
    ///      from the strategy type rather than `getStateIds()`, which implementations built on core < 0.7.0 lack.
    function _snapshotViews(address proxy) internal view returns (bytes[] memory results) {
        Kind kind = kindOf[proxy];
        bytes32[] memory stateIds = _knownStateIds(kind);
        address[] memory inputTokens = IStrategyTemplate(proxy).getInputTokens();
        bytes[] memory kindCalls = _kindViewCalls(kind);

        bytes[] memory calls = new bytes[](10 + 2 * stateIds.length + kindCalls.length);
        uint256 n;
        calls[n++] = abi.encodeCall(IStrategyTemplate.currentStateId, ());
        calls[n++] = abi.encodeCall(IStrategyTemplate.currentStateNav, ());
        calls[n++] = abi.encodeCall(IStrategyTemplate.isNavResolutionMode, ());
        calls[n++] = abi.encodeCall(IStrategyTemplate.getStateIds, ());
        calls[n++] = abi.encodeCall(IStrategyTemplate.getInputTokens, ());
        calls[n++] = abi.encodeCall(IStrategyTemplate.getOutputTokens, ());
        calls[n++] = abi.encodeWithSignature("enterMaxSlippage()");
        calls[n++] = abi.encodeWithSignature("exitMaxSlippage()");
        calls[n++] = abi.encodeWithSignature("emergencyExitMaxSlippage()");
        // Reads `_strategyContainer` (price oracle) and `_notion`
        calls[n++] = abi.encodeCall(IStrategyTemplate.getTokenAmountInNotion, (inputTokens[0], 1e6));
        for (uint256 i = 0; i < stateIds.length; ++i) {
            calls[n++] = abi.encodeCall(IStrategyTemplate.stateBitmask, (stateIds[i]));
            calls[n++] = abi.encodeCall(IStrategyTemplate.stateNav, (stateIds[i]));
        }
        for (uint256 i = 0; i < kindCalls.length; ++i) {
            calls[n++] = kindCalls[i];
        }

        results = new bytes[](n);
        for (uint256 i = 0; i < n; ++i) {
            (bool success, bytes memory data) = proxy.staticcall(calls[i]);
            results[i] = abi.encode(success, data);
        }
    }

    function _kindViewCalls(Kind kind) internal pure returns (bytes[] memory calls) {
        if (kind == Kind.CurveGauge) {
            calls = new bytes[](6);
            calls[0] = abi.encodeCall(ICurveGauge.gauge, ());
            calls[1] = abi.encodeCall(ICurveGauge.lpToken, ());
            calls[2] = abi.encodeCall(ICurveGauge.underlyingAsset0, ());
            calls[3] = abi.encodeCall(ICurveGauge.underlyingAsset1, ());
            calls[4] = abi.encodeCall(ICurveGauge.lastStoredVirtualPrice, ());
            calls[5] = abi.encodeCall(ICurveGauge.lastStoredGaugeBalance, ());
        } else if (kind == Kind.MorphoVault) {
            calls = new bytes[](5);
            calls[0] = abi.encodeWithSignature("morphoVault()");
            calls[1] = abi.encodeWithSignature("underlyingAsset()");
            calls[2] = abi.encodeWithSignature("merkleDistributor()");
            calls[3] = abi.encodeWithSignature("lastAssetsValue()");
            calls[4] = abi.encodeWithSignature("getRewardTokens()");
        } else if (kind == Kind.FluidSupply) {
            calls = new bytes[](7);
            calls[0] = abi.encodeWithSignature("fToken()");
            calls[1] = abi.encodeWithSignature("underlyingAsset()");
            calls[2] = abi.encodeWithSignature("lastAssetsValue()");
            calls[3] = abi.encodeWithSignature("merkleDistributor()");
            calls[4] = abi.encodeWithSignature("merkleRewardToken()");
            calls[5] = abi.encodeWithSignature("fluidNav()");
            calls[6] = abi.encodeWithSignature("underlyingAssetNav()");
        } else {
            calls = new bytes[](6);
            calls[0] = abi.encodeWithSignature("pool()");
            calls[1] = abi.encodeWithSignature("reserveAsset()");
            calls[2] = abi.encodeWithSignature("reserveAToken()");
            calls[3] = abi.encodeWithSignature("lastReserveATokenBalance()");
            calls[4] = abi.encodeWithSignature("underlyingAssetNav()");
            calls[5] = abi.encodeWithSignature("aaveReserveSuppliedNav()");
        }
    }

    /// @dev State ids in registration order, as `getStateIds()` returns them.
    function _knownStateIds(Kind kind) internal pure returns (bytes32[] memory stateIds) {
        if (kind == Kind.CurveGauge) {
            stateIds = new bytes32[](3);
            stateIds[0] = UNDERLYING_ASSETS_STATE_ID;
            stateIds[1] = CURVE_LP_STATE_ID;
            stateIds[2] = CURVE_GAUGE_STATE_ID;
            return stateIds;
        }
        stateIds = new bytes32[](2);
        stateIds[0] = UNDERLYING_ASSET_STATE_ID;
        if (kind == Kind.MorphoVault) {
            stateIds[1] = MORPHO_VAULT_STATE_ID;
        } else if (kind == Kind.FluidSupply) {
            stateIds[1] = FLUID_SUPPLY_STATE_ID;
        } else {
            stateIds[1] = AAVE_RESERVE_SUPPLIED_STATE_ID;
        }
    }

    function _kindName(Kind kind) internal pure returns (string memory) {
        if (kind == Kind.CurveGauge) return "CurveGauge";
        if (kind == Kind.MorphoVault) return "MorphoVault";
        if (kind == Kind.FluidSupply) return "FluidSupply";
        return "AaveV3Supply";
    }

    function _singleProxyList(
        Kind kind,
        address proxy
    ) internal pure returns (UpgradeStrategiesBase.StrategyProxies memory list) {
        address[] memory single = new address[](1);
        single[0] = proxy;
        if (kind == Kind.CurveGauge) list.curveGauge = single;
        else if (kind == Kind.MorphoVault) list.morphoVault = single;
        else if (kind == Kind.FluidSupply) list.fluidSupply = single;
        else list.aaveV3Supply = single;
    }

    function _register(address[] storage kindProxies, Kind kind) private {
        for (uint256 i = 0; i < kindProxies.length; ++i) {
            allProxies.push(kindProxies[i]);
            kindOf[kindProxies[i]] = kind;
            vm.label(kindProxies[i], string.concat(_kindName(kind), "#", vm.toString(i)));
        }
    }

    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    function _implementationsOf(address[] memory proxyList) internal view returns (address[] memory implementations) {
        implementations = new address[](proxyList.length);
        for (uint256 i = 0; i < proxyList.length; ++i) {
            implementations[i] = _implementationOf(proxyList[i]);
        }
    }

    /// @dev Low-level call that bubbles up the revert reason.
    function _call(address target, bytes memory data) internal {
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }
}
