// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployBase} from "./DeployBase.s.sol";
import {FluidSupply} from "contracts/fluid/FluidSupply.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployFluidSupplyUsdt is DeployBase {
    address public defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE");
    address public merkleClaimer = vm.envAddress("MERKLE_CLAIMER_ROLE");
    address public merkleDistributor = vm.envAddress("FLUID_MERKLE_DISTRIBUTOR");
    address public fToken = vm.envAddress("F_TOKEN_USDT");
    address public strategyContainer = vm.envAddress("STRATEGY_CONTAINER");

    uint256 public constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    function run() public {
        _readRolesFromEnv();

        FluidSupply.SlippageParams memory slippageParams = FluidSupply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

        vm.startBroadcast();
        address implementation = address(new FluidSupply());
        address proxy = _proxifyWithSalt(
            implementation,
            abi.encodeWithSelector(
                FluidSupply.initialize.selector,
                strategyContainer,
                defaultAdmin,
                merkleClaimer,
                fToken,
                merkleDistributor,
                slippageParams
            )
        );
        vm.stopBroadcast();
    }
}
