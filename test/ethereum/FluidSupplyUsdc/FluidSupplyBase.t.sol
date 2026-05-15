// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {FluidSupply} from "contracts/fluid/FluidSupply.sol";

import {EthContext} from "test/ethereum/EthContext.t.sol";

abstract contract FluidSupplyBase is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal fluidSupply;

    uint256 internal constant ENTER_AMOUNT = 1_00_000_000_000; // 100k USDC
    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%
    uint256 internal constant NAV_TOLERANCE_PCT_LOW = 1e8; // 0.000001%

    uint256 internal constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    FluidSupply.SlippageParams internal SLIPPAGE_PARAMS =
        FluidSupply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");
    bytes32 internal constant FLUID_SUPPLY_STATE_ID = keccak256("FLUID_SUPPLY_STATE_ID");

    function setUp(address underlyingAsset, address fToken) public virtual {
        super.setUp();

        address implementation = address(new FluidSupply());
        fluidSupply = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(
                    FluidSupply.initialize.selector,
                    STRATEGY_CONTAINER,
                    roles.defaultAdmin,
                    roles.merkleClaimer,
                    fToken,
                    MERKLE_DISTRIBUTOR,
                    SLIPPAGE_PARAMS
                )
            )
        );

        vm.label(address(fluidSupply), "FLUID_SUPPLY");

        address[] memory inputTokens = new address[](1);
        inputTokens[0] = underlyingAsset;

        _addStrategy(address(fluidSupply), inputTokens, inputTokens);
    }
}
