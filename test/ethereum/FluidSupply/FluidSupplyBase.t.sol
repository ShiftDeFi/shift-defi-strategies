// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {FluidSupply} from "contracts/fluid/FluidSupply.sol";
import {IFluidToken} from "contracts/dependencies/fluid/IFluidToken.sol";
import {IFluidSupply} from "contracts/interfaces/IFluidSupply.sol";

import {EthContext} from "test/ethereum/EthContext.t.sol";

abstract contract FluidSupplyBase is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal fluidSupply;
    address internal fToken;
    address internal underlyingAsset;

    uint256 internal constant ENTER_AMOUNT = 100_000;
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

    function setUp() public virtual override {
        super.setUp();

        underlyingAsset = IFluidToken(fToken).asset();

        address implementation = address(new FluidSupply());
        fluidSupply = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(
                    FluidSupply.initialize.selector,
                    mockStrategyContainer,
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

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(underlyingAsset).decimals());

        deal(underlyingAsset, mockStrategyContainer, amounts[0], true);

        vm.startPrank(mockStrategyContainer);
        IERC20(underlyingAsset).forceApprove(address(fluidSupply), type(uint256).max);

        uint256 minNavDelta = (fluidSupply.getTokenAmountInNotion(underlyingAsset, amounts[0]) *
            (MAX_BPS - ENTER_MAX_SLIPPAGE)) / MAX_BPS;
        fluidSupply.enter(amounts, minNavDelta);

        vm.stopPrank();
    }

    function test_EnterTarget() public {
        _enterStrategy();

        assertApproxEqRel(
            IStrategyTemplate(fluidSupply).stateNav(FLUID_SUPPLY_STATE_ID),
            Common.toUnifiedDecimalsUint8(
                underlyingAsset,
                ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(underlyingAsset).decimals())
            ),
            NAV_TOLERANCE_PCT,
            "test_EnterTarget: Fluid Supply NAV"
        );
    }

    function test_Harvest() public {
        _enterStrategy();

        deal(
            IFluidSupply(address(fluidSupply)).merkleRewardToken(),
            address(fluidSupply),
            1000 * 10 ** uint256(IERC20Metadata(IFluidSupply(address(fluidSupply)).merkleRewardToken()).decimals()),
            true
        );

        vm.warp(block.timestamp + 100 minutes);
        vm.roll(block.number + 100);

        uint256 treasuryBalanceBefore = IERC20(fToken).balanceOf(treasury);

        vm.startPrank(mockStrategyContainer);
        fluidSupply.harvest();
        vm.stopPrank();

        uint256 treasuryBalanceAfter = IERC20(fToken).balanceOf(treasury);
        assertGe(treasuryBalanceAfter, treasuryBalanceBefore, "test_Harvest: no treasury rewards");
    }

    function test_ExitTarget_Partial() public {
        _enterStrategy();

        uint256 fluidSupplyNavBefore = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 minNavDelta = fluidSupplyNavBefore.mulDiv(partialShare, MAX_BPS);

        vm.prank(mockStrategyContainer);
        fluidSupply.exit(partialShare, minNavDelta);

        uint256 fluidSupplyNavAfter = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        assertApproxEqRel(
            fluidSupplyNavAfter,
            fluidSupplyNavBefore - minNavDelta,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Fluid Supply NAV"
        );

        uint256 underlyingAssetNav = fluidSupply.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertApproxEqRel(
            underlyingAssetNav,
            fluidSupplyNavBefore - fluidSupplyNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Underlying Asset NAV"
        );

        uint256 exitedAmount = IERC20(underlyingAsset).balanceOf(address(fluidSupply));
        assertApproxEqRel(
            Common.toUnifiedDecimalsUint8(underlyingAsset, exitedAmount),
            fluidSupplyNavBefore - fluidSupplyNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Exited Amount"
        );
    }

    function test_ExitTarget_Full() public {
        _enterStrategy();

        uint256 fluidSupplyNavBefore = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        uint256 minNavDelta = fluidSupplyNavBefore;

        vm.prank(mockStrategyContainer);
        fluidSupply.exit(MAX_BPS, minNavDelta);

        uint256 fluidSupplyNavAfter = fluidSupply.stateNav(FLUID_SUPPLY_STATE_ID);
        assertEq(fluidSupplyNavAfter, 0, "test_ExitTarget_Full: Fluid Supply NAV");

        uint256 underlyingAssetNav = fluidSupply.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertEq(underlyingAssetNav, fluidSupplyNavBefore, "test_ExitTarget_Full: Underlying Asset NAV");

        uint256 exitedAmount = IERC20(underlyingAsset).balanceOf(address(fluidSupply));
        assertApproxEqRel(
            Common.toUnifiedDecimalsUint8(underlyingAsset, exitedAmount),
            fluidSupplyNavBefore,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Full: Exited Amount"
        );
    }
}
