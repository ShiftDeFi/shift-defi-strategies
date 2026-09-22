// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapAdapter} from "@shift-defi/core/interfaces/ISwapAdapter.sol";

/// @notice Minimal WMON -> USDC swap adapter for tests where no real predefined-swap adapter is
///         available on the forked chain. Pulls WMON in and pays USDC out of its own pre-funded balance
///         at a fixed rate - no pool, no price discovery, just enough to exercise a strategy's
///         swap-and-reinvest harvest path deterministically.
contract MockWmonUsdcSwapAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    error UnsupportedTokenPair(address tokenIn, address tokenOut);

    address public immutable WMON;
    address public immutable USDC;

    /// @dev USDC (6 decimals) paid out per 1e18 WMON (18 decimals), e.g. 2e6 = 2 USDC per WMON.
    uint256 public immutable USDC_PER_WMON;

    constructor(address _wmon, address _usdc, uint256 _usdcPerWmon) {
        WMON = _wmon;
        USDC = _usdc;
        USDC_PER_WMON = _usdcPerWmon;
    }

    /// @inheritdoc ISwapAdapter
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes memory data
    ) external payable override {
        uint256 amountOut = previewSwap(tokenIn, tokenOut, amountIn, data);
        require(amountOut >= minAmountOut, SlippageCheckFailed(tokenOut, amountOut, minAmountOut));

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function previewSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory
    ) public view override returns (uint256 amountOut) {
        require(tokenIn == WMON && tokenOut == USDC, UnsupportedTokenPair(tokenIn, tokenOut));
        return (amountIn * USDC_PER_WMON) / 1e18;
    }
}
