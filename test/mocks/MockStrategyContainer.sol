// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StrategyContainer} from "@shift-defi/core/StrategyContainer.sol";
import {IContainer} from "@shift-defi/core/interfaces/IContainer.sol";
import {IStrategyContainer} from "@shift-defi/core/interfaces/IStrategyContainer.sol";

contract MockStrategyContainer is StrategyContainer {
    function initialize(
        IContainer.ContainerInitParams memory containerInitParams,
        IStrategyContainer.StrategyContainerInitParams memory strategyContainerInitParams
    ) external initializer {
        __Container_init(containerInitParams);
        __StrategyContainer_init(strategyContainerInitParams);
    }

    function containerType() external pure override returns (IContainer.ContainerType) {
        return IContainer.ContainerType.Local;
    }

    function _getCurrentBatchType() internal view override returns (IStrategyContainer.CurrentBatchType) {
        // TODO: Implement
    }

    function addStrategy(
        address strategy,
        address[] calldata inputTokens,
        address[] calldata outputTokens
    ) external override {
        _addStrategy(strategy, inputTokens, outputTokens);
    }

    function removeStrategy(address strategy) external override {
        _removeStrategy(strategy);
    }
}
