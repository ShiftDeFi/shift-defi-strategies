// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployCurveGaugePyusdUsdc is DeployBase {
    address public strategyContainer;
    address public curveGauge;
    uint256 public constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    function run() public {
        _readRolesFromEnv();

        strategyContainer = vm.envAddress("STRATEGY_CONTAINER");
        curveGauge = vm.envAddress("CURVE_GAUGE_PYUSD_USDC");

        vm.startBroadcast();
        address implementation = address(new CurveGauge());
        address proxy = _proxifyWithSalt(
            implementation,
            abi.encodeWithSelector(
                CurveGauge.initialize.selector,
                strategyContainer,
                curveGauge,
                ENTER_MAX_SLIPPAGE,
                EXIT_MAX_SLIPPAGE,
                EMERGENCY_EXIT_MAX_SLIPPAGE
            )
        );
        vm.stopBroadcast();
    }
}
