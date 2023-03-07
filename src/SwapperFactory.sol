// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

import {ISwapperOracle} from "src/interfaces/ISwapperOracle.sol";
import {Swapper} from "src/Swapper.sol";

/// @title SwapperFactory
/// @author 0xSplits
/// @notice Factory for creating & validating Swappers
/// @dev This contract uses token = address(0) to refer to ETH.
contract SwapperFactory {
    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateSwapper(Swapper indexed swapper, address owner, bool paused, Swapper.File[] files);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// mapping of canonical swappers for flash callback validation
    mapping(Swapper => bool) public isSwapper;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor() {}

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    function createSwapper(address owner_, bool paused_, Swapper.File[] calldata init)
        external
        returns (Swapper swapper)
    {
        // TODO: gas test vs clone
        swapper = new Swapper({
            owner_: owner_,
            paused_: paused_,
            files: init
        });

        isSwapper[swapper] = true;

        emit CreateSwapper({swapper: swapper, owner: owner_, paused: paused_, files: init});
    }
}
