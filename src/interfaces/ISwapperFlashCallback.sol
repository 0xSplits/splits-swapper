// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Callback for Swapper#flash
/// @notice Any contract that calls Swapper#flash must implement this interface
/// @dev inspired by IUniswapV3FlashCallback
interface ISwapperFlashCallback {
    /// Called to `msg.sender` after transferring to the recipient from Swapper#flash.
    /// @dev In the implementation you must pay the beneficiary amountToBeneficiary of tokenToBeneficiary

    // TODO add library
    // https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/CallbackValidation.sol

    /// The caller of this method must be checked to be a Swapper deployed by the canonical SwapperFactory.

    /// This contract uses token = address(0) to refer to ETH.
    /// @param tokenToBeneficiary The token due to the beneficiary by the end of the flash
    /// @param amountToBeneficiary The amount of tokenToBeneficiary due to the beneficiary by the end of the flash
    /// @param data Any data passed through by the caller via the Swapper#flash call
    function swapperFlashCallback(address tokenToBeneficiary, uint256 amountToBeneficiary, bytes calldata data)
        external;
}
