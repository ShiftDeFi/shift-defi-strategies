// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {SwapRouter} from "@shift-defi/core/SwapRouter.sol";
import {PriceOracleAggregator} from "@shift-defi/core/PriceOracleAggregator.sol";
import {ChainlinkOracleWrapper} from "@shift-defi/core/priceOracles/ChainlinkOracleWrapper.sol";

import {IContainer} from "@shift-defi/core/interfaces/IContainer.sol";
import {IPriceOracleAggregator} from "@shift-defi/core/interfaces/IPriceOracleAggregator.sol";
import {IChainlinkOracleWrapper} from "@shift-defi/core/interfaces/IChainlinkOracleWrapper.sol";
import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";
import {ISwapRouter} from "@shift-defi/core/interfaces/ISwapRouter.sol";

import {BaseConfig} from "test/BaseConfig.sol";
import {MockStrategyContainer} from "test/mocks/MockStrategyContainer.sol";
import {MockWmonUsdcSwapAdapter} from "test/mocks/MockWmonUsdcSwapAdapter.sol";

/// @notice Shared Monad mainnet-fork context, run against the local anvil fork at `monad_local`
///         (http://localhost:8545 - see foundry.toml). Unlike `EthContext`, none of the core Shift
///         contracts (SwapRouter, StrategyContainer, PriceOracleAggregator) are live on Monad yet, so
///         this context deploys fresh instances of each rather than pointing at production addresses.
/// @dev The WMON -> USDC predefined-swap adapter is resolved via `_resolveWmonUsdcSwapAdapter`: if
///      `WMON_USDC_SWAP_ADAPTER` is set in the environment, that address is used directly (e.g. the real
///      `UniswapV3SwapRouter02` adapter deployed and whitelisted on a given fork by shift-defi-swap-adapters'
///      `Deploy.s.sol` / `WhitelistWmonUsdc.s.sol` broadcasts). Otherwise a `MockWmonUsdcSwapAdapter` is
///      deployed and pre-funded with USDC, so the suite still exercises a real (if not real-liquidity)
///      `_swapToInputTokens(WMON, USDC, ...)` swap rather than a no-op on a fork where no adapter exists.
abstract contract MonadContext is BaseConfig {
    // Real Monad mainnet addresses (see entry-exit-design/AaveV3MonadUSDC.md)
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address internal constant USDC_PRICE_FEED = 0x6789f81a983AfE7bd4C2a557c27084Ab705e56AB;

    address internal constant AAVE_V3_POOL = 0x69a5F9AD4f96ebf0a0C792dD42a01cC5C0102fef;
    address internal constant A_MON_USDC = 0x35a73BAcb179d3740395A3ceCc87FF2e581d6042;
    address internal constant AAVE_MERKLE_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;

    uint24 internal constant WMON_USDC_FEE = 3000;
    uint256 internal constant MOCK_USDC_PER_WMON = 2e6; // 2 USDC per WMON, 6 decimals
    uint256 internal constant MOCK_ADAPTER_USDC_LIQUIDITY = 10_000_000 * 10 ** 6;

    address internal priceOracleAggregator;
    address internal swapRouter;

    function setUp() public virtual override {
        super.setUp();

        vm.createSelectFork(vm.rpcUrl("monad"));

        vm.label(USDC, "USDC");
        vm.label(USDC_PRICE_FEED, "USDC_PRICE_FEED");
        vm.label(AAVE_V3_POOL, "AAVE_V3_POOL");
        vm.label(A_MON_USDC, "A_MON_USDC");
        vm.label(AAVE_MERKLE_DISTRIBUTOR, "AAVE_MERKLE_DISTRIBUTOR");
        vm.label(WMON, "WMON");

        _deployPriceOracleAggregator();
        _deploySwapRouter();
        _deployMockStrategyContainer();
        _grantRoles();
    }

    function _proxify(address implementation, bytes memory data) internal returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, address(this), data));
    }

    function _deployPriceOracleAggregator() private {
        priceOracleAggregator = _proxify(
            address(new PriceOracleAggregator()),
            abi.encodeWithSelector(PriceOracleAggregator.initialize.selector, roles.defaultAdmin, roles.oracleManager)
        );
        vm.label(priceOracleAggregator, "PRICE_ORACLE_AGGREGATOR");

        address chainlinkOracleWrapper = address(
            new ChainlinkOracleWrapper(roles.defaultAdmin, roles.oracleManager, PRICE_ORACLE_UPDATE_INTERVAL)
        );
        vm.label(chainlinkOracleWrapper, "CHAINLINK_ORACLE_WRAPPER");

        vm.startPrank(roles.oracleManager);
        IChainlinkOracleWrapper(chainlinkOracleWrapper).setChainlinkFeed(USDC, USDC_PRICE_FEED);
        IPriceOracleAggregator(priceOracleAggregator).setPriceOracle(USDC, chainlinkOracleWrapper);
        vm.stopPrank();
    }

    function _deploySwapRouter() private {
        address whitelistManager = makeAddr("SWAP_ROUTER_WHITELIST_MANAGER");

        swapRouter = _proxify(
            address(new SwapRouter()),
            abi.encodeWithSelector(SwapRouter.initialize.selector, roles.defaultAdmin, whitelistManager)
        );
        vm.label(swapRouter, "SWAP_ROUTER");

        address adapter = _resolveWmonUsdcSwapAdapter();
        bytes memory path = abi.encodePacked(WMON, WMON_USDC_FEE, USDC);

        vm.startPrank(whitelistManager);
        ISwapRouter(swapRouter).whitelistSwapAdapter(adapter);
        ISwapRouter(swapRouter).setPredefinedSwapParameters(WMON, USDC, adapter, path);
        vm.stopPrank();
    }

    /// @dev Uses `WMON_USDC_SWAP_ADAPTER` from the environment if set (a real adapter already deployed and
    ///      whitelisted on the target fork); otherwise deploys and funds `MockWmonUsdcSwapAdapter` so the
    ///      suite still exercises a real swap rather than silently no-opping on a fork with no adapter.
    function _resolveWmonUsdcSwapAdapter() private returns (address) {
        address configured = vm.envOr("WMON_USDC_SWAP_ADAPTER", address(0));
        if (configured != address(0)) {
            vm.label(configured, "WMON_USDC_SWAP_ADAPTER");
            return configured;
        }

        address mockAdapter = address(new MockWmonUsdcSwapAdapter(WMON, USDC, MOCK_USDC_PER_WMON));
        deal(USDC, mockAdapter, MOCK_ADAPTER_USDC_LIQUIDITY, true);
        vm.label(mockAdapter, "MOCK_WMON_USDC_SWAP_ADAPTER");
        return mockAdapter;
    }

    function _deployMockStrategyContainer() private {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: makeAddr("VAULT"),
            notion: USDC,
            emergencyPauser: roles.emergencyPauser,
            tokenManager: roles.tokenManager,
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            swapRouter: swapRouter
        });

        IStrategyContainer.StrategyContainerInitParams memory strategyContainerInitParams = IStrategyContainer
            .StrategyContainerInitParams({
                roleAddresses: IStrategyContainer.RoleAddresses({
                    strategyManager: roles.strategyManager,
                    harvestManager: roles.harvestManager,
                    reshufflingManager: roles.reshufflingManager,
                    reshufflingExecutor: roles.reshufflingExecutor,
                    emergencyManager: roles.emergencyManager,
                    emergencyExecutor: roles.emergencyExecutor
                }),
                reshufflingGateway: makeAddr("RESHUFFLING_GATEWAY"),
                treasury: treasury,
                feePct: 10 * ONE_PCT,
                priceOracle: priceOracleAggregator
            });

        mockStrategyContainer = _proxify(
            address(new MockStrategyContainer()),
            abi.encodeWithSelector(
                MockStrategyContainer.initialize.selector,
                containerInitParams,
                strategyContainerInitParams
            )
        );
    }

    function _whitelistTokenIfNeeded(address token) internal {
        if (!IStrategyContainer(mockStrategyContainer).isTokenWhitelisted(token)) {
            vm.prank(roles.tokenManager);
            IStrategyContainer(mockStrategyContainer).whitelistToken(token);
        }
    }

    function _grantRoles() private {
        vm.startPrank(roles.defaultAdmin);
        IAccessControl(mockStrategyContainer).grantRole(OPERATOR_ROLE, roles.operator);
        IAccessControl(mockStrategyContainer).grantRole(CONTAINER_MANAGER_ROLE, roles.containerManager);
        IAccessControl(mockStrategyContainer).grantRole(CONFIGURATOR_ROLE, roles.configurator);
        IAccessControl(mockStrategyContainer).grantRole(TOKEN_MANAGER_ROLE, roles.tokenManager);
        IAccessControl(mockStrategyContainer).grantRole(HARVEST_MANAGER_ROLE, roles.harvestManager);
        IAccessControl(mockStrategyContainer).grantRole(RESHUFFLING_MANAGER_ROLE, roles.reshufflingManager);
        IAccessControl(mockStrategyContainer).grantRole(RESHUFFLING_EXECUTOR_ROLE, roles.reshufflingExecutor);
        IAccessControl(mockStrategyContainer).grantRole(EMERGENCY_PAUSER_ROLE, roles.emergencyPauser);
        IAccessControl(mockStrategyContainer).grantRole(EMERGENCY_MANAGER_ROLE, roles.emergencyManager);
        IAccessControl(mockStrategyContainer).grantRole(EMERGENCY_EXECUTOR_ROLE, roles.emergencyExecutor);
        IAccessControl(mockStrategyContainer).grantRole(ORACLE_MANAGER_ROLE, roles.oracleManager);
        IAccessControl(priceOracleAggregator).grantRole(ORACLE_MANAGER_ROLE, roles.oracleManager);
        vm.stopPrank();
    }

    function _addStrategy(address strategy, address[] memory inputTokens, address[] memory outputTokens) internal {
        for (uint256 i = 0; i < inputTokens.length; ++i) {
            _whitelistTokenIfNeeded(inputTokens[i]);
        }
        for (uint256 i = 0; i < outputTokens.length; ++i) {
            _whitelistTokenIfNeeded(outputTokens[i]);
        }

        if (!IStrategyContainer(mockStrategyContainer).isReshuffling()) {
            vm.prank(roles.reshufflingManager);
            IStrategyContainer(mockStrategyContainer).enableReshufflingMode();
        }

        vm.prank(roles.reshufflingManager);
        IStrategyContainer(mockStrategyContainer).addStrategy(strategy, inputTokens, outputTokens);

        vm.prank(roles.reshufflingExecutor);
        IStrategyContainer(mockStrategyContainer).disableReshufflingMode();
    }
}
