// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

using {_convert} for TokenPair global;
using {_sort} for ConvertedTokenPair global;

struct TokenPair {
    address tokenA;
    address tokenB;
}

struct ConvertedTokenPair {
    address cTokenA;
    address cTokenB;
}

struct SortedConvertedTokenPair {
    address cToken0;
    address cToken1;
}

function _sort(ConvertedTokenPair memory ctp) pure returns (SortedConvertedTokenPair memory) {
    return (ctp.cTokenA > ctp.cTokenB)
        ? SortedConvertedTokenPair({cToken0: ctp.cTokenB, cToken1: ctp.cTokenA})
        : SortedConvertedTokenPair({cToken0: ctp.cTokenA, cToken1: ctp.cTokenB});
}

// TODO: use calldata
function _convert(TokenPair memory tp, function (address) internal view returns (address) convert)
    view
    returns (ConvertedTokenPair memory)
{
    return ConvertedTokenPair({cTokenA: convert(tp.tokenA), cTokenB: convert(tp.tokenB)});
}
