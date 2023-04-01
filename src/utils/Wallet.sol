// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";

/// @title Wallet
/// @author 0xSplits
/// @notice Bare bones smart wallet functionality
contract Wallet is Owned {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    event ExecCalls(Call[] calls);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// slot 0 - 12 bytes free

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor(address owner_) Owned(owner_) {}

    function initializer(address owner_) internal {
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// allow owner to execute arbitrary calls from swapper
    function execCalls(Call[] calldata calls_)
        external
        payable
        onlyOwner
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;
        uint256 length = calls_.length;
        returnData = new bytes[](length);

        bool success;
        for (uint256 i; i < length;) {
            Call calldata calli = calls_[i];
            (success, returnData[i]) = calli.target.call{value: calli.value}(calli.data);
            require(success, string(returnData[i]));

            unchecked {
                ++i;
            }
        }

        emit ExecCalls(calls_);
    }
}
