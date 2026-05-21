// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ChainlinkOracleWrapper} from "@shift-defi/core/priceOracles/ChainlinkOracleWrapper.sol";

import {IContainer} from "@shift-defi/core/interfaces/IContainer.sol";
import {IPriceOracleAggregator} from "@shift-defi/core/interfaces/IPriceOracleAggregator.sol";
import {IChainlinkOracleWrapper} from "@shift-defi/core/interfaces/IChainlinkOracleWrapper.sol";
import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";

import {BaseConfig} from "test/BaseConfig.sol";
import {MockStrategyContainer} from "test/mocks/MockStrategyContainer.sol";

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract EthContext is BaseConfig {
    using stdStorage for StdStorage;

    // Shift core contracts
    address internal constant VAULT = 0xB6Fa60AF402cd2810a68fC6b2F6Ce66C3d7233C4;
    address internal constant SWAP_ROUTER = 0x2E275e8D4bA74566FB5DF2C5BC72D1e661d3703B;
    address internal constant RESHUFFLING_GATEWAY = 0x3B90634186FEf9A6Ea235A70C5654c0B7E1cef94;
    address internal constant PRICE_ORACLE_AGGREGATOR = 0xFa1580b57168397162A3FA07a36234b06E42A626;

    // Shift roles
    address internal constant DEFAULT_ADMIN = 0x7705f76663e83354aBD38cbAdCCB5eaeA569c6cB;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant RLUSD = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;

    address internal constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant PYUSD_PRICE_FEED = 0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1;
    address internal constant RLUSD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    address internal PYUSD_USDC_ADAPTER = 0x9059c7a9921fFF86Df6d16Cb02578BaeD5835397;

    address internal constant CURVE_GAUGE_PYUSD_USDC = 0x9da75997624C697444958aDeD6790bfCa96Af19A;
    address internal constant CURVE_GAUGE_RLUSD_USDC = 0xFc3212Bd9Ad9A28Da6B2bd50a2918969C126894F;
    // Morpho addresses
    address internal constant MORPHO_SENTORA_PYUSD = 0xb576765fB15505433aF24FEe2c0325895C559FB2;

    // Fluid addresses
    address internal constant F_USDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
    address internal constant MERKLE_DISTRIBUTOR = 0x7060FE0Dd3E31be01EFAc6B28C8D38018fD163B0;

    function setUp() public virtual override {
        super.setUp();

        vm.label(USDC, "USDC");
        vm.label(PYUSD, "PYUSD");
        vm.label(RLUSD, "RLUSD");

        vm.label(USDC_PRICE_FEED, "USDC_PRICE_FEED");
        vm.label(PYUSD_PRICE_FEED, "PYUSD_PRICE_FEED");
        vm.label(RLUSD_PRICE_FEED, "RLUSD_PRICE_FEED");

        vm.label(PYUSD_USDC_ADAPTER, "PYUSD_USDC_ADAPTER");
        vm.label(PRICE_ORACLE_AGGREGATOR, "PRICE_ORACLE_AGGREGATOR");

        vm.label(CURVE_GAUGE_PYUSD_USDC, "CURVE_GAUGE_PYUSD_USDC");
        vm.label(CURVE_GAUGE_RLUSD_USDC, "CURVE_GAUGE_RLUSD_USDC");

        roles.defaultAdmin = DEFAULT_ADMIN;

        _deployMockStrategyContainer();
        _grantRoles();

        vm.prank(roles.deployer);
        address chainlinkOracleWrapper = address(
            new ChainlinkOracleWrapper(roles.defaultAdmin, roles.oracleManager, PRICE_ORACLE_UPDATE_INTERVAL)
        );

        vm.startPrank(roles.oracleManager);
        IChainlinkOracleWrapper(chainlinkOracleWrapper).setChainlinkFeed(USDC, USDC_PRICE_FEED);
        IChainlinkOracleWrapper(chainlinkOracleWrapper).setChainlinkFeed(PYUSD, PYUSD_PRICE_FEED);
        IChainlinkOracleWrapper(chainlinkOracleWrapper).setChainlinkFeed(RLUSD, RLUSD_PRICE_FEED);

        IPriceOracleAggregator(PRICE_ORACLE_AGGREGATOR).setPriceOracle(USDC, chainlinkOracleWrapper);
        IPriceOracleAggregator(PRICE_ORACLE_AGGREGATOR).setPriceOracle(PYUSD, chainlinkOracleWrapper);
        IPriceOracleAggregator(PRICE_ORACLE_AGGREGATOR).setPriceOracle(RLUSD, chainlinkOracleWrapper);
        vm.stopPrank();
    }

    function _proxify(address implementation, bytes memory data) internal returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, address(this), data));
    }

    function _deployMockStrategyContainer() internal {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: VAULT,
            notion: USDC,
            emergencyPauser: roles.emergencyPauser,
            tokenManager: roles.tokenManager,
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            swapRouter: SWAP_ROUTER
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
                reshufflingGateway: RESHUFFLING_GATEWAY,
                treasury: treasury,
                feePct: 10 * ONE_PCT,
                priceOracle: PRICE_ORACLE_AGGREGATOR
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
        IAccessControl(PRICE_ORACLE_AGGREGATOR).grantRole(ORACLE_MANAGER_ROLE, roles.oracleManager);
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
