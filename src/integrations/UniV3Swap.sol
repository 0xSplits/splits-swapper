// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IWETH9} from "splits-utils/interfaces/external/IWETH9.sol";
import {OracleImpl} from "splits-oracle/OracleImpl.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TokenUtils} from "splits-utils/TokenUtils.sol";

import {ISwapperFlashCallback} from "../interfaces/ISwapperFlashCallback.sol";
import {SwapperCallbackValidation} from "../peripherals/SwapperCallbackValidation.sol";
import {SwapperImpl} from "../SwapperImpl.sol";
import {SwapperFactory} from "../SwapperFactory.sol";

/// @title Integration contract for Swapper & Uniswap V3
/// @author 0xSplits
/// @notice Used by EOAs & simple bots to execute swapper#flash with uniswap v3
/// This contract uses token = address(0) to refer to ETH.
contract UniV3Swap is ISwapperFlashCallback {
    using SwapperCallbackValidation for SwapperFactory;
    using SafeTransferLib for address;
    using TokenUtils for address;

    error Unauthorized();
    error InsufficientFunds();

    struct InitFlashParams {
        OracleImpl.QuoteParams[] quoteParams;
        FlashCallbackData flashCallbackData;
    }

    struct FlashCallbackData {
        ISwapRouter.ExactInputParams[] exactInputParams;
        address excessRecipient;
    }

    SwapperFactory public immutable swapperFactory;
    ISwapRouter public immutable swapRouter;
    IWETH9 public immutable weth9;

    constructor(SwapperFactory swapperFactory_, ISwapRouter swapRouter_, IWETH9 weth9_) {
        swapperFactory = swapperFactory_;
        swapRouter = swapRouter_;
        weth9 = weth9_;
    }

    /// receive from weth9
    receive() external payable {}

    /// begin swapper#flash
    /// @dev trade may pay eth & include the extra weth in params_.exactInputParams to make up for oracle shortfall
    /// if swapper incentives are insufficient and they still want to push funds to beneficiary
    /// Recipient in params_.exactInputParams should always be _this_ contract so it can handle
    /// the approval / payback for swapper
    function initFlash(SwapperImpl swapper, InitFlashParams calldata params_) external payable {
        swapper.flash(params_.quoteParams, abi.encode(params_.flashCallbackData));
    }

    /// swapper#flash callback
    /// @dev by end of function if tokenToBeneficiary_ is eth, must have sent amountToBeneficiary_
    /// to swapper#payback. Otherwise, must approve swapper to transferFrom amountToBeneficiary_
    function swapperFlashCallback(address tokenToBeneficiary_, uint256 amountToBeneficiary_, bytes calldata data_)
        external
    {
        SwapperImpl swapper = SwapperImpl(msg.sender);
        if (!swapperFactory.verifyCallback(swapper)) {
            revert Unauthorized();
        }

        uint256 ethBalance = address(this).balance;
        if (!tokenToBeneficiary_._isETH() && ethBalance != 0) {
            weth9.deposit{value: ethBalance}();
        }

        FlashCallbackData memory flashCallbackData = abi.decode(data_, (FlashCallbackData));

        ISwapRouter.ExactInputParams[] memory exactInputParams = flashCallbackData.exactInputParams;
        uint256 totalOut;
        uint256 length = exactInputParams.length;
        for (uint256 i; i < length;) {
            ISwapRouter.ExactInputParams memory eip = exactInputParams[i];
            totalOut += swapRouter.exactInput(eip);

            unchecked {
                ++i;
            }
        }

        if (totalOut < amountToBeneficiary_) revert InsufficientFunds();

        address excessRecipient = flashCallbackData.excessRecipient;
        if (tokenToBeneficiary_._isETH()) {
            // withdraw weth from uni swaps to eth
            uint256 weth9Balance = weth9.balanceOf(address(this));
            weth9.withdraw(weth9Balance);

            // send req'd amt to swapper#payback
            swapper.payback{value: amountToBeneficiary_}();

            // xfr excess out
            ethBalance = address(this).balance;
            if (ethBalance != 0) {
                excessRecipient.safeTransferETH(ethBalance);
            }
        } else {
            // approve swapper to xfr req'd amt out
            tokenToBeneficiary_.safeApprove(msg.sender, amountToBeneficiary_);

            // xfr excess out
            uint256 excessBalance = ERC20(tokenToBeneficiary_).balanceOf(address(this)) - amountToBeneficiary_;
            if (excessBalance > 0) {
                tokenToBeneficiary_.safeTransfer(excessRecipient, excessBalance);
            }
        }
    }
}
