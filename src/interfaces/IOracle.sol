// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

// TODO: should this be an abstract contract?

/// @title Oracle interface
interface IOracle {
    struct BaseParams {
        address baseToken;
        uint128 baseAmount;
        bytes data;
    }

    // TODO: flip quote / base order? allow quote as array?
    function getQuoteAmounts(address quoteToken, BaseParams[] calldata baseParams)
        external
        view
        returns (uint256[] memory);
}
