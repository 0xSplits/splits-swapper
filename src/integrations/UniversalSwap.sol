// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IWETH9} from "splits-utils/interfaces/external/IWETH9.sol";
import {QuoteParams} from "splits-utils/LibQuotes.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TokenUtils} from "splits-utils/TokenUtils.sol";

import {ISwapperFlashCallback} from "../interfaces/ISwapperFlashCallback.sol";
import {SwapperImpl} from "../SwapperImpl.sol";

/// @title Universal Swap Integration
/// @author 0xSplits
/// @notice Used by EOAs & simple bots to execute `Swapper#flash` with any swap router
/// @dev This contract uses token = address(0) to refer to ETH.
contract UniversalSwap is ISwapperFlashCallback {
    using SafeTransferLib for address;
    using TokenUtils for address;

    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    struct FlashCallbackData {
        Call[] calls;
        address excessRecipient;
    }

    struct InitFlashParams {
        QuoteParams[] quoteParams;
        FlashCallbackData flashCallbackData;
    }

    IWETH9 public immutable weth9;

    constructor(IWETH9 weth9_) {
        weth9 = weth9_;
    }

    /// receive from weth9
    receive() external payable {}

    /// begin `Swapper#flash`
    /// @dev trader may pay ETH & include the extra WETH in `params_.exactInputParams` to make up
    /// for `Swapper#oracle` shortfall. If swapper incentives are insufficient and they still want to push
    /// funds to `beneficiary`. Recipient in `params_.exactInputParams` should always be _this_ contract
    /// so it can handle the approval / payback for Swapper
    function initFlash(SwapperImpl swapper, InitFlashParams calldata params_) external payable {
        swapper.flash(params_.quoteParams, abi.encode(params_.flashCallbackData));
    }

    /// `Swapper#flash` callback
    /// @dev by end of function if `tokenToBeneficiary_` is ETH, must have sent `amountToBeneficiary_`
    /// to `Swapper#payback`. Otherwise, must approve Swapper to transfer `amountToBeneficiary_`
    /// DO NOT HOLD FUNDS IN THIS CONTRACT WITHOUT ADDING PROPER VERIFICATION OF MSG.SENDER
    function swapperFlashCallback(address tokenToBeneficiary_, uint256 amountToBeneficiary_, bytes calldata data_)
        external
    {
        // decode flash callback data
        FlashCallbackData memory flashCallbackData = abi.decode(data_, (FlashCallbackData));

        // execute calls
        execCalls(flashCallbackData.calls);

        address excessRecipient = flashCallbackData.excessRecipient;
        if (tokenToBeneficiary_._isETH()) {
            // withdraw WETH from swaps to ETH
            uint256 weth9Balance = weth9.balanceOf(address(this));
            weth9.withdraw(weth9Balance);

            // send req'd amt to swapper#payback
            SwapperImpl(msg.sender).payback{value: amountToBeneficiary_}();

            // xfr excess out
            uint256 ethBalance = address(this).balance;
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

    function execCalls(Call[] memory _calls) internal {
        uint256 length = _calls.length;
        bytes[] memory returnData = new bytes[](length);

        bool success;
        for (uint256 i; i < length; ++i) {
            Call memory calli = _calls[i];

            (success, returnData[i]) = calli.to.call{value: calli.value}(calli.data);

            require(success, string(returnData[i]));
        }
    }
}
