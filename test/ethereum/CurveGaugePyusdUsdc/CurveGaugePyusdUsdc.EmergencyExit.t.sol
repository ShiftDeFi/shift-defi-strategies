// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@shift-defi/core/interfaces/IVault.sol";
import {IContainerLocal} from "@shift-defi/core/interfaces/IContainerLocal.sol";
import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {ICurveStableSwapNG} from "contracts/dependencies/curve/ICurveStableSwapNG.sol";
import {ILiquidityGaugeV6} from "contracts/dependencies/curve/ILiquidityGaugeV6.sol";

import {CurveGaugePyusdUsdcBase} from "./CurveGaugePyusdUsdc.t.sol";

contract CurveGaugePyusdUsdcEmergencyExitTest is CurveGaugePyusdUsdcBase {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();

        deal(USDC, users.alice, ENTER_AMOUNT);

        vm.startPrank(roles.configurator);
        IVault(VAULT).setMaxDepositBatchSize(ENTER_AMOUNT * 10);
        IVault(VAULT).setMaxDepositAmount(ENTER_AMOUNT);

        vm.stopPrank();
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

        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = inputAmountPyusd;
        inputAmounts[1] = inputAmountUsdc;

        uint256 minAsset0Delta = inputAmountUsdc.mulDiv(MAX_BPS - ENTER_MAX_SLIPPAGE / 2, MAX_BPS);
        uint256 minAsset1Delta = inputAmountPyusd.mulDiv(MAX_BPS - ENTER_MAX_SLIPPAGE / 2, MAX_BPS);

        uint256 minNavDelta0 = curveGaugePyusdUsdc.getTokenAmountInNotion(USDC, minAsset0Delta);
        uint256 minNavDelta1 = curveGaugePyusdUsdc.getTokenAmountInNotion(PYUSD, minAsset1Delta);

        _setVaultStatus(IVault.VaultStatus.Idle);

        (address[] memory containers, uint256[] memory containerWeights) = IVault(VAULT).getContainers();

        for (uint256 i = 0; i < containers.length; ++i) {
            if (containers[i] == STRATEGY_CONTAINER) {
                containerWeights[i] = MAX_CONTAINER_WEIGHT;
            } else {
                containerWeights[i] = 0;
            }
        }

        // Sort containers and weights. Sort key is containers[i] < containers[i+1]
        for (uint256 i = 0; i < containers.length; ++i) {
            for (uint256 j = i + 1; j < containers.length; ++j) {
                if (containers[j] < containers[i]) {
                    // Swap containers
                    address tempContainer = containers[i];
                    containers[i] = containers[j];
                    containers[j] = tempContainer;
                    // Swap corresponding weights
                    uint256 tempWeight = containerWeights[i];
                    containerWeights[i] = containerWeights[j];
                    containerWeights[j] = tempWeight;
                }
            }
        }

        vm.prank(roles.reshufflingManager);
        IVault(VAULT).enableReshufflingMode();

        vm.prank(roles.containerManager);
        IVault(VAULT).setContainerWeights(containers, containerWeights);

        vm.prank(roles.reshufflingExecutor);
        IVault(VAULT).disableReshufflingMode();

        vm.startPrank(roles.operator);
        IVault(VAULT).startDepositBatchProcessing();

        // TODO: Implement batch swap
        // IContainer(STRATEGY_CONTAINER).prepareLiquidity(swapInstructions);

        IContainerLocal(STRATEGY_CONTAINER).enterStrategy(
            address(curveGaugePyusdUsdc),
            inputAmounts,
            minNavDelta0 + minNavDelta1
        );
        _setContainerLocalStatus(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered);

        IContainerLocal(STRATEGY_CONTAINER).reportDeposit();
        IVault(VAULT).resolveDepositBatch();
        vm.stopPrank();

        vm.prank(users.alice);
        IVault(VAULT).claimDeposit(1, users.alice);
    }

    function test_EmergencyExit_ToCurveLp() public {
        uint256 stateNav = IStrategyTemplate(curveGaugePyusdUsdc).stateNav(CURVE_GAUGE_STATE_ID);
        vm.startPrank(roles.emergencyExecutor);
        curveGaugePyusdUsdc.emergencyExit(CURVE_LP_STATE_ID, MAX_BPS, stateNav);
        vm.stopPrank();
    }
}
