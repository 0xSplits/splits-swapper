// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Oracle interface
interface IOracle {
    struct QuoteParams {
        address baseToken;
        uint128 baseAmount;
        address quoteToken;
        bytes data;
    }

    function getQuoteAmounts(QuoteParams[] calldata qps_) external view returns (uint256[] memory);
}
