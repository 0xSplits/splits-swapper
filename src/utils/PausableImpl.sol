// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {OwnableImpl} from "src/utils/OwnableImpl.sol";

/// @title PausableImpl
/// @author 0xSplits
/// @notice Bare bones contract with pausable functions
abstract contract PausableImpl is OwnableImpl {
    error Paused();

    event SetPaused(bool paused);

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// slot 0 - 11 bytes free

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    bool public $paused;
    /// 1 byte

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor() {}

    function __initPausable(address owner_, bool paused_) internal {
        // TODO: check if compiler handles packing properly
        $paused = paused_;
        OwnableImpl.__initOwnable(owner_);
    }

    /// -----------------------------------------------------------------------
    /// modifiers
    /// -----------------------------------------------------------------------

    /// makes function pausable
    modifier pausable() {
        if ($paused) revert Paused();
        _;
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - onlyOwner
    /// -----------------------------------------------------------------------

    /// set paused
    function setPaused(bool paused_) external onlyOwner {
        $paused = paused_;
        emit SetPaused(paused_);
    }
}
