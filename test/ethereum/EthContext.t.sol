// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ChainlinkOracleWrapper} from "@shift-defi/core/priceOracles/ChainlinkOracleWrapper.sol";

import {IPriceOracleAggregator} from "@shift-defi/core/interfaces/IPriceOracleAggregator.sol";
import {IChainlinkOracleWrapper} from "@shift-defi/core/interfaces/IChainlinkOracleWrapper.sol";
import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";

import {BaseConfig} from "test/BaseConfig.sol";

contract EthContext is BaseConfig {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;

    address internal constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant PYUSD_PRICE_FEED = 0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1;

    address internal constant VAULT = 0xB6Fa60AF402cd2810a68fC6b2F6Ce66C3d7233C4;
    address internal constant STRATEGY_CONTAINER = 0x866AD6eD87C2A0AB43B498c3a92e383B466407fb;
    address internal PYUSD_USDC_ADAPTER = 0x9059c7a9921fFF86Df6d16Cb02578BaeD5835397;
    address internal constant PRICE_ORACLE = 0x49C869B7A6f08564d126b695649bD0DDB73E4dCc;

    address internal constant DEFAULT_ADMIN = 0x7705f76663e83354aBD38cbAdCCB5eaeA569c6cB;

    uint256 private constant PRICE_ORACLE_UPDATE_INTERVAL = 2400 * 3600;
    uint256 internal constant MAX_BPS = 1e18;

    address internal constant CURVE_GAUGE_PYUSD_USDC = 0x9da75997624C697444958aDeD6790bfCa96Af19A;

    address internal treasury;

    function setUp() public virtual override {
        super.setUp();

        vm.label(USDC, "USDC");
        vm.label(PYUSD, "PYUSD");

        vm.label(USDC_PRICE_FEED, "USDC_PRICE_FEED");
        vm.label(PYUSD_PRICE_FEED, "PYUSD_PRICE_FEED");

        vm.label(VAULT, "VAULT");
        vm.label(STRATEGY_CONTAINER, "STRATEGY_CONTAINER");
        vm.label(PYUSD_USDC_ADAPTER, "PYUSD_USDC_ADAPTER");
        vm.label(PRICE_ORACLE, "PRICE_ORACLE_AGGREGATOR");

        vm.label(CURVE_GAUGE_PYUSD_USDC, "CURVE_GAUGE_PYUSD_USDC");

        roles.defaultAdmin = DEFAULT_ADMIN;
        _grantRoles();

        vm.label(roles.defaultAdmin, "DEFAULT_ADMIN");
        vm.label(roles.operator, "OPERATOR");
        vm.label(roles.containerManager, "CONTAINER_MANAGER");
        vm.label(roles.configurator, "CONFIGURATOR");
        vm.label(roles.tokenManager, "TOKEN_MANAGER");
        vm.label(roles.harvestManager, "HARVEST_MANAGER");
        vm.label(roles.reshufflingManager, "RESHUFFLING_MANAGER");
        vm.label(roles.reshufflingExecutor, "RESHUFFLING_EXECUTOR");
        vm.label(roles.emergencyPauser, "EMERGENCY_PAUSER");
        vm.label(roles.emergencyManager, "EMERGENCY_MANAGER");
        vm.label(roles.emergencyExecutor, "EMERGENCY_EXECUTOR");
        vm.label(roles.oracleManager, "ORACLE_MANAGER");

        vm.prank(roles.deployer);
        address chainlinkOracleWrapper = address(
            new ChainlinkOracleWrapper(roles.defaultAdmin, roles.oracleManager, PRICE_ORACLE_UPDATE_INTERVAL)
        );

        vm.startPrank(roles.oracleManager);
        IChainlinkOracleWrapper(chainlinkOracleWrapper).setChainlinkFeed(USDC, USDC_PRICE_FEED);
        IChainlinkOracleWrapper(chainlinkOracleWrapper).setChainlinkFeed(PYUSD, PYUSD_PRICE_FEED);

        IPriceOracleAggregator(PRICE_ORACLE).setPriceOracle(USDC, chainlinkOracleWrapper);
        IPriceOracleAggregator(PRICE_ORACLE).setPriceOracle(PYUSD, chainlinkOracleWrapper);
        vm.stopPrank();

        treasury = IStrategyContainer(STRATEGY_CONTAINER).treasury();
    }

    function _proxify(address implementation, bytes memory data) internal returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, address(this), data));
    }

    function _whitelistTokenIfNeeded(address token) internal {
        if (!IStrategyContainer(STRATEGY_CONTAINER).isTokenWhitelisted(token)) {
            vm.prank(roles.tokenManager);
            IStrategyContainer(STRATEGY_CONTAINER).whitelistToken(token);
        }
    }

    function _grantRoles() private {
        vm.startPrank(roles.defaultAdmin);
        IAccessControl(VAULT).grantRole(OPERATOR_ROLE, roles.operator);
        IAccessControl(VAULT).grantRole(CONTAINER_MANAGER_ROLE, roles.containerManager);
        IAccessControl(VAULT).grantRole(CONFIGURATOR_ROLE, roles.configurator);
        IAccessControl(VAULT).grantRole(RESHUFFLING_MANAGER_ROLE, roles.reshufflingManager);
        IAccessControl(VAULT).grantRole(RESHUFFLING_EXECUTOR_ROLE, roles.reshufflingExecutor);
        IAccessControl(VAULT).grantRole(EMERGENCY_PAUSER_ROLE, roles.emergencyPauser);
        IAccessControl(VAULT).grantRole(EMERGENCY_EXECUTOR_ROLE, roles.emergencyExecutor);
        IAccessControl(STRATEGY_CONTAINER).grantRole(OPERATOR_ROLE, roles.operator);
        IAccessControl(STRATEGY_CONTAINER).grantRole(CONTAINER_MANAGER_ROLE, roles.containerManager);
        IAccessControl(STRATEGY_CONTAINER).grantRole(CONFIGURATOR_ROLE, roles.configurator);
        IAccessControl(STRATEGY_CONTAINER).grantRole(TOKEN_MANAGER_ROLE, roles.tokenManager);
        IAccessControl(STRATEGY_CONTAINER).grantRole(HARVEST_MANAGER_ROLE, roles.harvestManager);
        IAccessControl(STRATEGY_CONTAINER).grantRole(RESHUFFLING_MANAGER_ROLE, roles.reshufflingManager);
        IAccessControl(STRATEGY_CONTAINER).grantRole(RESHUFFLING_EXECUTOR_ROLE, roles.reshufflingExecutor);
        IAccessControl(STRATEGY_CONTAINER).grantRole(EMERGENCY_PAUSER_ROLE, roles.emergencyPauser);
        IAccessControl(STRATEGY_CONTAINER).grantRole(EMERGENCY_MANAGER_ROLE, roles.emergencyManager);
        IAccessControl(STRATEGY_CONTAINER).grantRole(EMERGENCY_EXECUTOR_ROLE, roles.emergencyExecutor);
        IAccessControl(STRATEGY_CONTAINER).grantRole(ORACLE_MANAGER_ROLE, roles.oracleManager);
        IAccessControl(PRICE_ORACLE).grantRole(ORACLE_MANAGER_ROLE, roles.oracleManager);
        vm.stopPrank();
    }

    function _addStrategy(address strategy, address[] memory inputTokens, address[] memory outputTokens) internal {
        for (uint256 i = 0; i < inputTokens.length; ++i) {
            _whitelistTokenIfNeeded(inputTokens[i]);
        }
        for (uint256 i = 0; i < outputTokens.length; ++i) {
            _whitelistTokenIfNeeded(outputTokens[i]);
        }

        vm.prank(roles.reshufflingManager);
        IStrategyContainer(STRATEGY_CONTAINER).addStrategy(strategy, inputTokens, outputTokens);

        vm.prank(roles.reshufflingExecutor);
        IStrategyContainer(STRATEGY_CONTAINER).disableReshufflingMode();
    }
}
