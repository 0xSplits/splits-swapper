// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

using {_convert} for QuotePair global;
using {_sort} for ConvertedQuotePair global;

struct QuotePair {
    address base;
    address quote;
}

struct ConvertedQuotePair {
    address cBase;
    address cQuote;
}

struct SortedConvertedQuotePair {
    address cToken0;
    address cToken1;
}

function _convert(QuotePair calldata tp, function (address) internal view returns (address) convert)
    view
    returns (ConvertedQuotePair memory)
{
    return ConvertedQuotePair({cBase: convert(tp.base), cQuote: convert(tp.quote)});
}

function _sort(ConvertedQuotePair memory ctp) pure returns (SortedConvertedQuotePair memory) {
    return (ctp.cBase > ctp.cQuote)
        ? SortedConvertedQuotePair({cToken0: ctp.cQuote, cToken1: ctp.cBase})
        : SortedConvertedQuotePair({cToken0: ctp.cBase, cToken1: ctp.cQuote});
}
