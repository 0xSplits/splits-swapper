// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SwapperFactory.sol";
import "../Swapper.sol";

/// @title SwapperCallbackValidation
/// @author 0xSplits
/// @notice Helper library for any contracts calling Swapper#flash
/// @dev inspired by UniswapV3's CallbackValidation
library SwapperCallbackValidation {
    /// Returns whether a given swapper address is valid
    /// @param factory Address of SwapperFactory
    /// @param swapper Address of swapper to validate
    /// @return valid Boolean of whether swapper address is valid
    function verifyCallback(SwapperFactory factory, Swapper swapper) internal view returns (bool valid) {
        return factory.isSwapper(swapper);
    }
}
