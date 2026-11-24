// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployBase} from "./DeployBase.s.sol";
import {CompoundV3Supply} from "contracts/compound-v3/CompoundV3Supply.sol";
import {ICompoundV3Supply} from "contracts/interfaces/ICompoundV3Supply.sol";

contract DeployCompoundV3Supply is DeployBase {
    address public defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
    address public merkleClaimer = vm.envAddress("MERKLE_CLAIMER");
    address public merkleDistributor = vm.envAddress("COMPOUND_MERKLE_DISTRIBUTOR");
    address public comet = vm.envAddress("COMET");
    address public strategyContainer = vm.envAddress("STRATEGY_CONTAINER");

    uint256 public constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    function run() public {
        _readRolesFromEnv();

        // Optional, comma-separated list of reward tokens (e.g. COMP). Defaults to none.
        address[] memory rewardTokens = vm.envOr("COMPOUND_REWARD_TOKENS", ",", new address[](0));

        ICompoundV3Supply.SlippageParams memory slippageParams = ICompoundV3Supply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

        vm.startBroadcast();
        address implementation = address(new CompoundV3Supply());
        _proxifyWithSalt(
            implementation,
            abi.encodeWithSelector(
                CompoundV3Supply.initialize.selector,
                strategyContainer,
                defaultAdmin,
                merkleClaimer,
                comet,
                merkleDistributor,
                rewardTokens,
                slippageParams
            )
        );
        vm.stopBroadcast();
    }
}
