// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {OwnableImpl} from "src/utils/OwnableImpl.sol";

// TODO: execution via signatures?
// see https://eips.ethereum.org/EIPS/eip-6551
// https://docs.openzeppelin.com/contracts/4.x/api/utils#SignatureChecker
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.2/contracts/utils/cryptography/SignatureChecker.sol
// https://www.google.com/search?q=import+openzeppelin+with+foundry&rlz=1C5CHFA_enUS886US886&oq=import+openzeppelin+with+fo&aqs=chrome.1.69i57j33i160l5j33i299l3j33i22i29i30.4939j0j1&sourceid=chrome&ie=UTF-8

/// @title WalletImpl
/// @author 0xSplits
/// @notice Bare bones smart wallet functionality
abstract contract WalletImpl is OwnableImpl {
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    event ExecCalls(Call[] calls);

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// slot 0 - 12 bytes free

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor() {}

    function __initWallet(address owner_) internal {
        OwnableImpl.__initOwnable(owner_);
    }

    /// -----------------------------------------------------------------------
    /// functions - external & public - onlyOwner
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
            (success, returnData[i]) = calli.to.call{value: calli.value}(calli.data);
            require(success, string(returnData[i]));

            unchecked {
                ++i;
            }
        }

        emit ExecCalls(calls_);
    }
}
