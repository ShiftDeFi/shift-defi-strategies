// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployBase} from "./DeployBase.s.sol";
import {MorphoVault} from "contracts/morpho/MorphoVault.sol";

contract DeployMorphoVault is DeployBase {
    address public defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE");
    address public merkleClaimer = vm.envAddress("MERKLE_CLAIMER_ROLE");
    address public merkleDistributor = vm.envAddress("MORPHO_MERKLE_DISTRIBUTOR");
    address public morphoVault = vm.envAddress("MORPHO_VAULT");
    address public strategyContainer = vm.envAddress("STRATEGY_CONTAINER");

    uint256 public constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    function run() public {
        _readRolesFromEnv();

        // Optional, comma-separated list of reward tokens. Defaults to none.
        address[] memory rewardTokens = vm.envOr("MORPHO_REWARD_TOKENS", ",", new address[](0));

        MorphoVault.SlippageParams memory slippageParams = MorphoVault.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

        vm.startBroadcast();
        address implementation = address(new MorphoVault());
        address proxy = _proxifyWithSalt(
            implementation,
            abi.encodeWithSelector(
                MorphoVault.initialize.selector,
                strategyContainer,
                defaultAdmin,
                merkleClaimer,
                morphoVault,
                merkleDistributor,
                rewardTokens,
                slippageParams
            )
        );
        vm.stopBroadcast();
    }
}
