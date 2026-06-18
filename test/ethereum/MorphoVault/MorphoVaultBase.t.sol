// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IStrategyTemplate} from "@shift-defi/core/interfaces/IStrategyTemplate.sol";
import {Common} from "@shift-defi/core/libraries/Common.sol";

import {MorphoVault} from "contracts/morpho/MorphoVault.sol";

import {EthContext} from "test/ethereum/EthContext.t.sol";

abstract contract MorphoVaultBase is EthContext {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IStrategyTemplate internal morphoVaultStrategy;
    address internal underlyingAsset;
    address internal morphoVault;

    uint256 internal constant ENTER_AMOUNT = 100_000;
    uint256 internal constant NAV_TOLERANCE_PCT = 2e14; // 0.02%
    uint256 internal constant NAV_TOLERANCE_PCT_LOW = 1e8; // 0.000001%

    uint256 internal constant ENTER_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EXIT_MAX_SLIPPAGE = 5e16; // 5%
    uint256 internal constant EMERGENCY_EXIT_MAX_SLIPPAGE = 5e16; // 5%

    MorphoVault.SlippageParams internal SLIPPAGE_PARAMS =
        MorphoVault.SlippageParams({
            enterMaxSlippage: ENTER_MAX_SLIPPAGE,
            exitMaxSlippage: EXIT_MAX_SLIPPAGE,
            emergencyExitMaxSlippage: EMERGENCY_EXIT_MAX_SLIPPAGE
        });

    bytes32 internal constant UNDERLYING_ASSET_STATE_ID = keccak256("UNDERLYING_ASSET_STATE_ID");
    bytes32 internal constant MORPHO_VAULT_STATE_ID = keccak256("MORPHO_VAULT_STATE_ID");

    function setUp() public virtual override {
        super.setUp();

        address implementation = address(new MorphoVault());
        morphoVaultStrategy = IStrategyTemplate(
            _proxify(
                implementation,
                abi.encodeWithSelector(
                    MorphoVault.initialize.selector,
                    mockStrategyContainer,
                    roles.defaultAdmin,
                    roles.merkleClaimer,
                    morphoVault,
                    MORPHO_MERKLE_DISTRIBUTOR,
                    new address[](0),
                    SLIPPAGE_PARAMS
                )
            )
        );

        underlyingAsset = IERC4626(morphoVault).asset();

        vm.label(address(morphoVaultStrategy), "MORPHO_VAULT_STRATEGY");

        address[] memory inputTokens = new address[](1);
        inputTokens[0] = underlyingAsset;

        _addStrategy(address(morphoVaultStrategy), inputTokens, inputTokens);
    }

    function _enterStrategy() internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(underlyingAsset).decimals());

        deal(underlyingAsset, mockStrategyContainer, amounts[0], true);

        vm.startPrank(mockStrategyContainer);
        IERC20(underlyingAsset).forceApprove(address(morphoVaultStrategy), type(uint256).max);

        uint256 minNavDelta = (morphoVaultStrategy.getTokenAmountInNotion(underlyingAsset, amounts[0]) *
            (MAX_BPS - ENTER_MAX_SLIPPAGE + ONE_PCT)) / MAX_BPS;
        morphoVaultStrategy.enter(amounts, minNavDelta);

        vm.stopPrank();
    }

    function test_EnterTarget() public {
        _enterStrategy();

        assertApproxEqRel(
            IStrategyTemplate(morphoVaultStrategy).stateNav(MORPHO_VAULT_STATE_ID),
            Common.toUnifiedDecimalsUint8(
                underlyingAsset,
                ENTER_AMOUNT * 10 ** uint256(IERC20Metadata(underlyingAsset).decimals())
            ),
            NAV_TOLERANCE_PCT,
            "test_EnterTarget: Morpho Vault NAV"
        );
    }

    function test_Harvest() public {
        _enterStrategy();

        vm.warp(block.timestamp + 100 minutes);
        vm.roll(block.number + 100);

        uint256 treasuryBalanceBefore = IERC20(underlyingAsset).balanceOf(treasury);

        vm.startPrank(mockStrategyContainer);
        morphoVaultStrategy.harvest();
        vm.stopPrank();

        uint256 treasuryBalanceAfter = IERC20(underlyingAsset).balanceOf(treasury);
        assertGe(treasuryBalanceAfter, treasuryBalanceBefore, "test_Harvest: no treasury rewards");
    }

    function test_ExitTarget_Partial() public {
        _enterStrategy();

        uint256 morphoVaultNavBefore = morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID);
        uint256 partialShare = MAX_BPS / 2;
        uint256 maxNavDelta = morphoVaultNavBefore.mulDiv(partialShare, MAX_BPS);

        vm.prank(mockStrategyContainer);
        morphoVaultStrategy.exit(partialShare, maxNavDelta);

        uint256 morphoVaultNavAfter = morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID);
        assertApproxEqRel(
            morphoVaultNavAfter,
            morphoVaultNavBefore - maxNavDelta,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Morpho Vault NAV"
        );

        uint256 underlyingAssetNav = morphoVaultStrategy.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertApproxEqRel(
            underlyingAssetNav,
            morphoVaultNavBefore - morphoVaultNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Underlying Asset NAV"
        );

        uint256 exitedAmount = IERC20(underlyingAsset).balanceOf(address(morphoVaultStrategy));
        assertApproxEqRel(
            Common.toUnifiedDecimalsUint8(underlyingAsset, exitedAmount),
            morphoVaultNavBefore - morphoVaultNavAfter,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Partial: Exited Amount"
        );
    }

    function test_ExitTarget_Full() public {
        _enterStrategy();

        uint256 morphoVaultNavBefore = morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID);
        uint256 maxNavDelta = morphoVaultNavBefore;

        vm.prank(mockStrategyContainer);
        morphoVaultStrategy.exit(MAX_BPS, maxNavDelta);

        uint256 morphoVaultNavAfter = morphoVaultStrategy.stateNav(MORPHO_VAULT_STATE_ID);
        assertEq(morphoVaultNavAfter, 0, "test_ExitTarget_Full: Morpho Vault NAV");

        uint256 underlyingAssetNav = morphoVaultStrategy.stateNav(UNDERLYING_ASSET_STATE_ID);
        assertApproxEqRel(
            underlyingAssetNav,
            morphoVaultNavBefore,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Full: Underlying Asset NAV"
        );

        uint256 exitedAmount = IERC20(underlyingAsset).balanceOf(address(morphoVaultStrategy));
        assertApproxEqRel(
            Common.toUnifiedDecimalsUint8(underlyingAsset, exitedAmount),
            morphoVaultNavBefore,
            NAV_TOLERANCE_PCT,
            "test_ExitTarget_Full: Exited Amount"
        );
    }
}
