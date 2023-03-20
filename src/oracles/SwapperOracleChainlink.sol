// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";
import {FeedRegistryInterface} from "chainlink/interfaces/FeedRegistryInterface.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LibSort} from "solady/utils/LibSort.sol";

import {ISwapperOracle} from "src/interfaces/ISwapperOracle.sol";
import {Swapper} from "src/Swapper.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";

// TODO: should there be a struct for non-converted pairs?
// yet.. categories are raw, converted & unsorted, converted & sorted
// parse, don't validate
// parsing allows the compiler to tell the rest of the program that the values have been validated
// TODO: way to use libs to clean up code?

/// @title Chainlink Oracle for Swapper#flash
/// @author 0xSplits
/// @notice An oracle for Swapper#flash based on chainlink
contract SwapperOracleChainlink is ISwapperOracle {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using TokenUtils for address;
    using LibSort for address[];

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    /// from interface

    /* error UnsupportedFile(); */

    error StalePrice(AggregatorV3Interface priceFeed, uint256 ts);
    error NegativePrice(AggregatorV3Interface priceFeed, int256 p);

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct OracleStorage {
        /// -------------------------------------------------------------------
        /// Slot 0 - 24 bytes free
        /// -------------------------------------------------------------------

        /// default period for chainlink price to be valid
        /// 4 bytes
        uint32 defaultStaleAfter;
        /// default price scaling factor
        /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100% = no discount or premium
        /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
        /// 4 bytes
        uint32 defaultScaledOfferFactor;
        /// -------------------------------------------------------------------
        /// Slot 1 - 0 bytes free
        /// -------------------------------------------------------------------

        /// overrides for specific token pairs
        /// 32 bytes
        mapping(address => mapping(address => PairOverride)) _pairOverrides;
        /// -------------------------------------------------------------------
        /// Slot 2 - 0 bytes free
        /// -------------------------------------------------------------------

        /// overrides for specific tokens
        /// 32 bytes
        mapping(address => address) _tokenOverrides;
    }

    /// from interface

    /* @dev unwrap into enum in impl */
    /* type IFileType is uint8; */

    /* struct File { */
    /*     IFileType what; */
    /*     bytes data; */
    /* } */

    /* struct UnsortedTokenPair { */
    /*     address tokenA; */
    /*     address tokenB; */
    /* } */

    /* struct SortedTokenPair { */
    /*     address token0; */
    /*     address token1; */
    /* } */

    enum FileType {
        NotSupported,
        DefaultStaleAfter,
        DefaultScaledOfferFactor,
        PairOverride,
        TokenOverride
    }

    struct SetPairOverrideParams {
        UnsortedTokenPair utp;
        PairOverride pairOverride;
    }

    struct PairOverride {
        uint32 staleAfter;
        uint32 scaledOfferFactor;
        AggregatorV3Interface[] path;
    }

    struct SetTokenOverrideParams {
        address token;
        address tokenOverride;
    }

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    uint32 internal constant PERCENTAGE_SCALE = 100_00_00; // = 100%

    FeedRegistryInterface public immutable chainlinkRegistry;
    address public immutable weth9;
    address internal immutable clETH;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 0
    /// -----------------------------------------------------------------------

    /// mapping from Swapper address to its OracleStorage
    mapping(Swapper => OracleStorage) internal _oracleStorage;
    /// 32 bytes

    /// 0 bytes free

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(FeedRegistryInterface chainlinkRegistry_, address weth9_, address clETH_) {
        chainlinkRegistry = chainlinkRegistry_;
        weth9 = weth9_;
        clETH = clETH_;
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// update oracle storage
    function file(File calldata incoming) external {
        FileType what = FileType(IFileType.unwrap(incoming.what));
        bytes memory data = incoming.data;

        OracleStorage storage s = _oracleStorage[Swapper(payable(address(msg.sender)))];
        if (what == FileType.DefaultStaleAfter) {
            s.defaultStaleAfter = abi.decode(data, (uint32));
        } else if (what == FileType.DefaultScaledOfferFactor) {
            s.defaultScaledOfferFactor = abi.decode(data, (uint32));
        } else if (what == FileType.PairOverride) {
            _setPairOverride(s, abi.decode(data, (SetPairOverrideParams)));
        } else if (what == FileType.TokenOverride) {
            _setTokenOverride(s, abi.decode(data, (SetTokenOverrideParams)));
        } else {
            revert UnsupportedFile();
        }
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - views
    /// -----------------------------------------------------------------------

    /// get oracle storage
    function getFile(Swapper swapper, File calldata incoming) external view returns (bytes memory) {
        FileType what = FileType(IFileType.unwrap(incoming.what));

        OracleStorage storage s = _oracleStorage[swapper];
        if (what == FileType.DefaultStaleAfter) {
            return abi.encode(s.defaultStaleAfter);
        } else if (what == FileType.DefaultScaledOfferFactor) {
            return abi.encode(s.defaultScaledOfferFactor);
        } else if (what == FileType.PairOverride) {
            return abi.encode(_getPairOverride(s, abi.decode(incoming.data, (UnsortedTokenPair))));
        } else if (what == FileType.TokenOverride) {
            return abi.encode(_getTokenOverride(s, abi.decode(incoming.data, (address))));
        } else {
            revert UnsupportedFile();
        }
    }

    /// get OracleStorage for a specific swapper
    function getOracleDefaults(Swapper swapper)
        external
        view
        returns (uint32 defaultStaleAfter, uint32 defaultScaledOfferFactor)
    {
        OracleStorage storage s = _oracleStorage[swapper];

        defaultStaleAfter = s.defaultStaleAfter;
        defaultScaledOfferFactor = s.defaultScaledOfferFactor;
    }

    /// get PairOverride for a specific swapper & set of token pairs
    function getOraclePairOverride(Swapper swapper, UnsortedTokenPair[] calldata tps)
        external
        view
        returns (PairOverride[] memory pairOverrides)
    {
        uint256 length = tps.length;
        pairOverrides = new PairOverride[](length);

        OracleStorage storage s = _oracleStorage[swapper];
        uint256 i;
        for (; i < length;) {
            UnsortedTokenPair calldata utp = tps[i];
            pairOverrides[i] = _getPairOverride({s: s, utp: utp});
            unchecked {
                ++i;
            }
        }
    }

    /// get amounts to beneficiary for a set of trades
    function getAmountsToBeneficiary(
        Swapper swapper,
        address tokenToBeneficiary,
        Swapper.TradeParams[] calldata tradeParams
    ) external view returns (uint256[] memory amountsToBeneficiary) {
        OracleStorage storage s = _oracleStorage[swapper];
        uint256 length = tradeParams.length;
        amountsToBeneficiary = new uint256[](length);
        uint256 i;
        for (; i < length;) {
            amountsToBeneficiary[i] = _getAmountToBeneficiary(s, tokenToBeneficiary, tradeParams[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    /// get amount to beneficiary for a particular trade
    function _getAmountToBeneficiary(
        OracleStorage storage s,
        address tokenToBeneficiary,
        Swapper.TradeParams calldata tradeParams
    ) internal view returns (uint256) {
        address tokenToTrader = tradeParams.token;
        uint256 unscaledAmountToBeneficiary = uint256(tradeParams.amount);

        address cTTT = _convertToken(s, tokenToTrader);
        address cTTB = _convertToken(s, tokenToBeneficiary);

        SortedTokenPair memory stp = _sortTokens(UnsortedTokenPair({tokenA: cTTT, tokenB: cTTB}));
        // TODO: how well does this handle the dynamic array?
        PairOverride memory po = _getPairOverride(s, stp);
        if (po.staleAfter == 0) {
            po.staleAfter = s.defaultStaleAfter;
        }
        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = s.defaultScaledOfferFactor;
        }

        // skip oracle if stp.token0 == stp.token1
        // (can't return early, still need to adjust decimals)
        if (stp.token0 != stp.token1) {
            if (po.path.length == 0) {
                address[] memory intermediaryTokens = abi.decode(tradeParams.data, (address[]));
                uint256 itLength = intermediaryTokens.length;
                po.path = new AggregatorV3Interface[](itLength+1);

                uint256 j;
                address base = cTTT;
                address quote;
                for (; j < itLength;) {
                    quote = intermediaryTokens[j];
                    // reverts if feed not found
                    po.path[j] = chainlinkRegistry.getFeed({base: base, quote: quote});
                    base = quote;
                }
                quote = cTTB;
                po.path[itLength] = chainlinkRegistry.getFeed({base: base, quote: quote});
            } else if (cTTT != stp.token0) {
                address[] memory casted;
                AggregatorV3Interface[] memory p = po.path;
                /// @solidity memory-safe-assembly
                assembly {
                    casted := p
                }
                // happens in-memory; reverses po.path
                casted.reverse();
            }

            AggregatorV3Interface priceFeed;
            int256 answer;
            uint256 updatedAt;
            uint8 priceDecimals;
            uint256 i;
            uint256 length = po.path.length;
            for (; i < length;) {
                priceFeed = po.path[i];

                (
                    , /* uint80 roundId, */
                    answer,
                    , /* uint256 startedAt, */
                    updatedAt,
                    /* uint80 answeredInRound */
                ) = priceFeed.latestRoundData();

                if (updatedAt < block.timestamp - po.staleAfter) {
                    revert StalePrice(priceFeed, updatedAt);
                }
                if (answer < 0) {
                    revert NegativePrice(priceFeed, answer);
                }

                priceDecimals = priceFeed.decimals();
                unscaledAmountToBeneficiary =
                    unscaledAmountToBeneficiary * uint256(answer) / 10 ** uint256(priceDecimals);
            }
        }

        uint8 baseDecimals = tokenToTrader._getDecimals();
        uint8 quoteDecimals = tokenToBeneficiary._getDecimals();

        int256 decimalAdjustment = int256(uint256(quoteDecimals)) - int256(uint256(baseDecimals));
        if (decimalAdjustment > 0) {
            unscaledAmountToBeneficiary *= 10 ** uint256(decimalAdjustment);
        } else {
            unscaledAmountToBeneficiary /= 10 ** uint256(-decimalAdjustment);
        }

        return unscaledAmountToBeneficiary * po.scaledOfferFactor / PERCENTAGE_SCALE;
    }

    /// set pair overrides
    function _setPairOverride(OracleStorage storage s, SetPairOverrideParams memory params) internal {
        SortedTokenPair memory stp = _convertAndSortTokens(s, params.utp);
        s._pairOverrides[stp.token0][stp.token1] = params.pairOverride;
    }

    /// get pair overrides
    function _getPairOverride(OracleStorage storage s, UnsortedTokenPair memory utp)
        internal
        view
        returns (PairOverride memory)
    {
        return _getPairOverride(s, _convertAndSortTokens(s, utp));
    }

    /// get pair overrides
    function _getPairOverride(OracleStorage storage s, SortedTokenPair memory stp)
        internal
        view
        returns (PairOverride memory)
    {
        return s._pairOverrides[stp.token0][stp.token1];
    }

    /// set token overrides
    function _setTokenOverride(OracleStorage storage s, SetTokenOverrideParams memory params) internal {
        s._tokenOverrides[params.token] = params.tokenOverride;
    }

    /// get token overrides
    function _getTokenOverride(OracleStorage storage s, address token) internal view returns (address) {
        return s._tokenOverrides[token];
    }

    /// sort tokens into canonical order
    function _sortTokens(UnsortedTokenPair memory utp) internal pure returns (SortedTokenPair memory) {
        address tokenA = utp.tokenA;
        address tokenB = utp.tokenB;

        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        return SortedTokenPair({token0: tokenA, token1: tokenB});
    }

    /// convert eth (0x0) & weth to chainlink's ETH constant; otherwise check _tokenOverrides
    function _convertToken(OracleStorage storage s, address token) internal view returns (address) {
        return (token._isETH() || token == weth9) ? clETH : s._tokenOverrides[token];
    }

    /// convert & sort tokens into canonical order
    function _convertAndSortTokens(OracleStorage storage s, UnsortedTokenPair memory utp)
        internal
        view
        returns (SortedTokenPair memory)
    {
        return
            _sortTokens(UnsortedTokenPair({tokenA: _convertToken(s, utp.tokenA), tokenB: _convertToken(s, utp.tokenB)}));
    }
}
