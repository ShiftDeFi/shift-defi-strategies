// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployBase} from "./DeployBase.s.sol";
import {AaveV3SupplyWithMerkle} from "contracts/aave-v3/AaveV3SupplyWithMerkle.sol";
import {IAaveV3Supply} from "contracts/interfaces/IAaveV3Supply.sol";

contract DeployAaveSupplyWithMerkle is DeployBase {
    address public defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
    address public merkleClaimer = vm.envAddress("MERKLE_CLAIMER");
    address public pool = vm.envAddress("AAVE_V3_POOL");
    address public reserveAsset = vm.envAddress("AAVE_RESERVE_ASSET");
    address public merkleDistributor = vm.envAddress("AAVE_MERKLE_DISTRIBUTOR");
    address public strategyContainer = vm.envAddress("STRATEGY_CONTAINER");

    uint256 public constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 public constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    function run() public {
        _readRolesFromEnv();

        // Optional, comma-separated list of reward tokens. Defaults to none.
        address[] memory rewardTokens = vm.envOr("AAVE_REWARD_TOKENS", ",", new address[](0));

        IAaveV3Supply.SlippageParams memory slippageParams = IAaveV3Supply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

        vm.startBroadcast();
        address implementation = address(new AaveV3SupplyWithMerkle());
        address proxy = _proxifyWithSalt(
            implementation,
            abi.encodeWithSelector(
                AaveV3SupplyWithMerkle.initialize.selector,
                strategyContainer,
                defaultAdmin,
                merkleClaimer,
                pool,
                reserveAsset,
                merkleDistributor,
                rewardTokens,
                slippageParams
            )
        );
        vm.stopBroadcast();
    }
}
