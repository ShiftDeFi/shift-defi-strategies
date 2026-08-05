// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployBase} from "./DeployBase.s.sol";
import {AaveV3Supply} from "contracts/aave-v3/AaveV3Supply.sol";

contract DeployAaveSupply is DeployBase {
    address public pool = vm.envAddress("AAVE_V3_POOL");
    address public reserveAsset = vm.envAddress("AAVE_RESERVE_ASSET");
    address public strategyContainer = vm.envAddress("STRATEGY_CONTAINER");

    uint256 public constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    function run() public {
        _readRolesFromEnv();

        AaveV3Supply.SlippageParams memory slippageParams = AaveV3Supply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

        vm.startBroadcast();
        address implementation = address(new AaveV3Supply());
        address proxy = _proxifyWithSalt(
            implementation,
            abi.encodeWithSelector(
                AaveV3Supply.initialize.selector,
                strategyContainer,
                pool,
                reserveAsset,
                slippageParams
            )
        );
        vm.stopBroadcast();
    }
}
