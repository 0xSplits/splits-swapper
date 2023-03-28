// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {QuotePair} from "src/utils/QuotePair.sol";

/// @title Oracle interface
interface IOracle {
    struct QuoteParams {
        QuotePair quotePair;
        uint128 baseAmount;
        bytes data;
    }

    function getQuoteAmounts(QuoteParams[] calldata quoteParams_) external view returns (uint256[] memory);
}
