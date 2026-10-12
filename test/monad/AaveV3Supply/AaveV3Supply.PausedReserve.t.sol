// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";

import {AaveV3Supply} from "contracts/aave-v3/AaveV3Supply.sol";
import {AaveV3SupplyWithMerkle} from "contracts/aave-v3/AaveV3SupplyWithMerkle.sol";
import {DataTypes} from "contracts/dependencies/aave-v3/DataTypes.sol";
import {IPool} from "contracts/dependencies/aave-v3/IPool.sol";
import {IAaveV3Supply} from "contracts/interfaces/IAaveV3Supply.sol";

import {MonadContext} from "test/monad/MonadContext.t.sol";

/// @notice A strategy already moved to its token state must keep exiting while the Aave reserve is paused, even if
///         someone donated aTokens to it: harvest runs before every exit and must not try to move those aTokens.
abstract contract AaveV3SupplyPausedReserveTest is MonadContext {
    using SafeERC20 for IERC20;

    IStrategyTemplate internal aaveSupplyStrategy;

    uint256 internal constant ENTER_AMOUNT = 100_000;
    uint256 internal constant DONATION_AMOUNT = 1_000;
    uint256 internal constant RESERVE_PAUSED_BIT = 1 << 60;

    uint256 internal constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    IAaveV3Supply.SlippageParams internal SLIPPAGE_PARAMS =
        IAaveV3Supply.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");
    bytes32 internal constant AAVE_RESERVE_SUPPLIED_STATE_ID = keccak256("AAVE_RESERVE_SUPPLIED_STATE_ID");

    function setUp() public virtual override {
        super.setUp();

        aaveSupplyStrategy = IStrategyTemplate(_deployStrategy());

        address[] memory inputTokens = new address[](1);
        inputTokens[0] = USDC;

        _addStrategy(address(aaveSupplyStrategy), inputTokens, inputTokens);
    }

    function _deployStrategy() internal virtual returns (address);

    function test_Harvest_TokenStateSkipsFeeWhileReservePaused() public {
        _enterStrategy();

        uint256 aaveNavBeforeExit = aaveSupplyStrategy.stateNav(AAVE_RESERVE_SUPPLIED_STATE_ID);
        vm.prank(roles.emergencyExecutor);
        aaveSupplyStrategy.emergencyExit(UNDERLYING_ASSET_STATE_ID, MAX_BPS, aaveNavBeforeExit);

        assertEq(
            aaveSupplyStrategy.currentStateId(),
            UNDERLYING_ASSET_STATE_ID,
            "test_Harvest_TokenStateSkipsFeeWhileReservePaused: strategy did not fully exit Aave"
        );

        _donateATokens();
        _pauseReserve();

        // Precondition: Aave rejects aToken transfers while the reserve is paused
        vm.prank(address(aaveSupplyStrategy));
        vm.expectRevert();
        IERC20(A_MON_USDC).transfer(treasury, 1);

        // Precondition: the donated aTokens keep accruing interest during the pause
        uint256 aTokenBalanceBeforeWarp = IERC20(A_MON_USDC).balanceOf(address(aaveSupplyStrategy));
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        assertGt(
            IERC20(A_MON_USDC).balanceOf(address(aaveSupplyStrategy)),
            aTokenBalanceBeforeWarp,
            "test_Harvest_TokenStateSkipsFeeWhileReservePaused: donated aTokens did not accrue interest"
        );

        uint256 treasuryATokenBalanceBefore = IERC20(A_MON_USDC).balanceOf(treasury);
        uint256 usdcBalanceBeforeExit = IERC20(USDC).balanceOf(address(aaveSupplyStrategy));
        uint256 maxNavDelta = aaveSupplyStrategy.stateNav(UNDERLYING_ASSET_STATE_ID);

        // The container harvests right before every exit
        vm.startPrank(mockStrategyContainer);
        aaveSupplyStrategy.harvest();
        (, uint256[] memory exitedAmounts) = aaveSupplyStrategy.exit(MAX_BPS, maxNavDelta);
        vm.stopPrank();

        assertEq(
            IERC20(A_MON_USDC).balanceOf(treasury),
            treasuryATokenBalanceBefore,
            "test_Harvest_TokenStateSkipsFeeWhileReservePaused: fee charged in token state"
        );
        assertEq(
            exitedAmounts[0],
            usdcBalanceBeforeExit,
            "test_Harvest_TokenStateSkipsFeeWhileReservePaused: USDC not fully exited"
        );
    }

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(USDC).decimals());

        deal(USDC, mockStrategyContainer, amounts[0], true);

        vm.startPrank(mockStrategyContainer);
        IERC20(USDC).forceApprove(address(aaveSupplyStrategy), type(uint256).max);

        uint256 minNavDelta = (aaveSupplyStrategy.getTokenAmountInNotion(USDC, amounts[0]) *
            (MAX_BPS - ENTER_MAX_SLIPPAGE + ONE_PCT)) / MAX_BPS;
        aaveSupplyStrategy.enter(amounts, minNavDelta);

        vm.stopPrank();
    }

    /// @dev Supplying on behalf of the strategy mints aTokens straight to it, like any third party could
    function _donateATokens() internal {
        address donor = makeAddr("ATOKEN_DONOR");
        uint256 donation = DONATION_AMOUNT * 10 ** uint256(IERC20Metadata(USDC).decimals());
        deal(USDC, donor, donation, true);

        vm.startPrank(donor);
        IERC20(USDC).forceApprove(AAVE_V3_POOL, donation);
        IPool(AAVE_V3_POOL).supply(USDC, donation, address(aaveSupplyStrategy), 0);
        vm.stopPrank();
    }

    /// @dev Sets the reserve's paused bit the same way `PoolConfigurator.setReservePause` does
    function _pauseReserve() internal {
        address poolConfigurator = IPool(AAVE_V3_POOL).ADDRESSES_PROVIDER().getPoolConfigurator();
        DataTypes.ReserveConfigurationMap memory configuration = IPool(AAVE_V3_POOL).getConfiguration(USDC);
        configuration.data |= RESERVE_PAUSED_BIT;

        vm.prank(poolConfigurator);
        IPool(AAVE_V3_POOL).setConfiguration(USDC, configuration);
    }
}

contract AaveV3SupplyUsdcPausedReserveTest is AaveV3SupplyPausedReserveTest {
    function _deployStrategy() internal override returns (address) {
        return
            _proxify(
                address(new AaveV3Supply()),
                abi.encodeWithSelector(
                    AaveV3Supply.initialize.selector,
                    mockStrategyContainer,
                    AAVE_V3_POOL,
                    USDC,
                    SLIPPAGE_PARAMS
                )
            );
    }
}

contract AaveV3SupplyWithMerkleUsdcPausedReserveTest is AaveV3SupplyPausedReserveTest {
    function _deployStrategy() internal override returns (address) {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = WMON;

        return
            _proxify(
                address(new AaveV3SupplyWithMerkle()),
                abi.encodeWithSelector(
                    AaveV3SupplyWithMerkle.initialize.selector,
                    mockStrategyContainer,
                    roles.defaultAdmin,
                    roles.merkleClaimer,
                    AAVE_V3_POOL,
                    USDC,
                    AAVE_MERKLE_DISTRIBUTOR,
                    rewardTokens,
                    SLIPPAGE_PARAMS
                )
            );
    }
}
