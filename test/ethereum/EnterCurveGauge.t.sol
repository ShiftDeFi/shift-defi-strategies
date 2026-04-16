// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CurveGaugePyusdUsdc} from "contracts/curve-gauge/CurveGaugePyusdUsdc.sol";
import {CurveGauge} from "contracts/curve-gauge/CurveGauge.sol";
import {EthContext} from "./EthContext.t.sol";

import {IVault} from "@shift-defi/core/interfaces/IVault.sol";
import {IContainerLocal} from "@shift-defi/core/interfaces/IContainerLocal.sol";
import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";
import {console2 as console} from "forge-std/console2.sol";

contract EnterCurveGaugePyusdUsdcTest is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    address internal curveGaugePyusdUsdc;
    uint256 internal constant ENTER_AMOUNT = 10_000 * 1e6;

    function _logGasUsage(string memory label, uint256 gasBefore) internal view {
        console.log(string.concat(label, " gas used:"), gasBefore - gasleft());
    }

    function setUp() public override {
        super.setUp();

        address implementation = address(new CurveGaugePyusdUsdc());
        curveGaugePyusdUsdc = _proxify(
            implementation,
            abi.encodeWithSelector(CurveGauge.initialize.selector, STRATEGY_CONTAINER, CURVE_GAUGE_PYUSD_USDC)
        );

        vm.label(curveGaugePyusdUsdc, "CURVE_GAUGE_PYUSD_USDC");

        address[] memory inputTokens = new address[](2);
        inputTokens[0] = PYUSD;
        inputTokens[1] = USDC;
        _addStrategy(address(curveGaugePyusdUsdc), inputTokens, inputTokens);

        deal(USDC, users.alice, ENTER_AMOUNT);

        vm.startPrank(roles.configurator);
        IVault(VAULT).setMaxDepositBatchSize(ENTER_AMOUNT * 10);
        IVault(VAULT).setMaxDepositAmount(ENTER_AMOUNT);
        vm.stopPrank();
    }

    function test_EnterGauge() public {
        vm.startPrank(users.alice);
        IERC20(USDC).safeIncreaseAllowance(VAULT, ENTER_AMOUNT);
        IVault(VAULT).deposit(ENTER_AMOUNT, users.alice);
        vm.stopPrank();

        address pool = ILiquidityGaugeV6(CURVE_GAUGE_PYUSD_USDC).lp_token();
        uint256[] memory balances = ICurveStableSwapNG(pool).get_balances();
        uint256 totalReserve = balances[0] + balances[1];
        uint256 inputAmountUsdc = ENTER_AMOUNT.mulDiv(balances[0], totalReserve);
        uint256 inputAmountPyusd = ENTER_AMOUNT.mulDiv(balances[1], totalReserve);

        deal(PYUSD, STRATEGY_CONTAINER, inputAmountPyusd);

        // uint256 amountUsdcToSwap = ENTER_AMOUNT - inputAmountUsdc;
        // ISwapRouter.SwapInstruction[] memory swapInstructions = new ISwapRouter.SwapInstruction[](1);
        // swapInstructions[0] = ISwapRouter.SwapInstruction({
        //     adapter: PYUSD_USDC_ADAPTER,
        //     tokenIn: USDC,
        //     tokenOut: PYUSD,
        //     amountIn: amountUsdcToSwap,
        //     minAmountOut: 0,
        //     payload: ""
        // });

        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = inputAmountPyusd;
        inputAmounts[1] = inputAmountUsdc;
        uint256 gasBefore;
        vm.startPrank(roles.operator);
        gasBefore = gasleft();
        IVault(VAULT).startDepositBatchProcessing();
        _logGasUsage("IVault.startDepositBatchProcessing", gasBefore);
        // IContainer(STRATEGY_CONTAINER).prepareLiquidity(swapInstructions);
        gasBefore = gasleft();
        IContainerLocal(STRATEGY_CONTAINER).enterStrategy(address(curveGaugePyusdUsdc), inputAmounts, 0);
        _logGasUsage("IContainerLocal.enterStrategy", gasBefore);
        gasBefore = gasleft();
        IContainerLocal(STRATEGY_CONTAINER).reportDeposit();
        _logGasUsage("IContainerLocal.reportDeposit", gasBefore);
        gasBefore = gasleft();
        IVault(VAULT).resolveDepositBatch();
        _logGasUsage("IVault.resolveDepositBatch", gasBefore);
        vm.stopPrank();

        vm.prank(users.alice);
        gasBefore = gasleft();
        IVault(VAULT).claimDeposit(1, users.alice);
        _logGasUsage("IVault.claimDeposit", gasBefore);
    }
}
