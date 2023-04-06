// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {SwapperFactory} from "../SwapperFactory.sol";
import {SwapperImpl} from "../SwapperImpl.sol";

/// @title Swapper Callback Validation
/// @author 0xSplits
/// @notice Helper library for contracts calling Swapper#flash
/// @dev inspired by UniswapV3's CallbackValidation
library SwapperCallbackValidation {
    /// Returns whether a given swapper address is valid
    /// @param factory_ Address of SwapperFactory
    /// @param swapper_ Address of swapper to validate
    /// @return valid Boolean of whether swapper address is valid
    function verifyCallback(SwapperFactory factory_, SwapperImpl swapper_) internal view returns (bool valid) {
        return factory_.$isSwapper(swapper_);
    }
}
