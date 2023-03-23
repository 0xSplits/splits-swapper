// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";
import {FeedRegistryInterface} from "chainlink/interfaces/FeedRegistryInterface.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LibSort} from "solady/utils/LibSort.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";
import {TokenPair, ConvertedTokenPair, SortedConvertedTokenPair} from "src/utils/TokenPairs.sol";

/// @title Chainlink Oracle Implementation
/// @author 0xSplits
/// @notice An oracle clone-implementation using chainlink
contract ChainlinkOracleImpl is Owned, IOracle {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using TokenUtils for address;
    using LibSort for address[];

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    error Unauthorized();
    error StalePrice(AggregatorV3Interface priceFeed, uint256 ts);
    error NegativePrice(AggregatorV3Interface priceFeed, int256 p);

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct SetTokenOverrideParams {
        address token;
        address tokenOverride;
    }

    struct SetPairOverrideParams {
        TokenPair tp;
        PairOverride pairOverride;
    }

    struct PairOverride {
        uint32 staleAfter;
        uint32 scaledOfferFactor;
        AggregatorV3Interface[] path;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event SetDefaultStaleAfter(uint32 defaultStaleAfter);
    event SetDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor);
    event SetTokenOverride(SetTokenOverrideParams[] params);
    event SetPairOverride(SetPairOverrideParams[] params);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    /// @dev percentages measured in hundredths of basis points
    uint32 internal constant PERCENTAGE_SCALE = 100_00_00; // = 1e6 = 100%

    address public immutable chainlinkOracleFactory;
    FeedRegistryInterface public immutable clFeedRegistry;
    address public immutable weth9;
    address public immutable clETH;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// slot 0 - 4 bytes free

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    /// default period for chainlink price to be valid
    /// 4 bytes
    uint32 public defaultStaleAfter;

    /// default price scaling factor
    /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100% = no discount or premium
    /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
    /// 4 bytes
    uint32 public defaultScaledOfferFactor;

    /// slot 1 - 0 bytes free

    /// overrides for specific tokens
    /// 32 bytes
    mapping(address => address) public tokenOverrides;

    /// slot 2 - 0 bytes free

    /// overrides for specific token pairs
    /// 32 bytes
    mapping(address => mapping(address => PairOverride)) internal _pairOverrides;

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor(FeedRegistryInterface clFeedRegistry_, address weth9_, address clETH_) Owned(address(0)) {
        clFeedRegistry = clFeedRegistry_;
        weth9 = weth9_;
        clETH = clETH_;
        chainlinkOracleFactory = msg.sender;
    }

    function initializer(
        address owner_,
        uint32 defaultStaleAfter_,
        uint32 defaultScaledOfferFactor_,
        SetTokenOverrideParams[] calldata toParams,
        SetPairOverrideParams[] calldata poParams
    ) external {
        // only chainlinkOracleFactory may call `initializer`
        if (msg.sender != chainlinkOracleFactory) revert Unauthorized();

        owner = owner_;
        defaultStaleAfter = defaultStaleAfter_;
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
        emit OwnershipTransferred(address(0), owner_);

        _setTokenOverrides(toParams);
        _setPairOverrides(poParams);
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external - onlyOwner
    /// -----------------------------------------------------------------------

    /// set defaultStaleAfter
    function setDefaultStaleAfter(uint32 defaultStaleAfter_) external onlyOwner {
        defaultStaleAfter = defaultStaleAfter_;
        emit SetDefaultStaleAfter(defaultStaleAfter_);
    }

    /// set defaultScaledOfferFactor
    function setDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor_) external onlyOwner {
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
        emit SetDefaultScaledOfferFactor(defaultScaledOfferFactor_);
    }

    /// set token overrides
    function setTokenOverrides(SetTokenOverrideParams[] calldata params) external onlyOwner {
        _setTokenOverrides(params);
        emit SetTokenOverride(params);
    }

    /// set pair overrides
    function setPairOverrides(SetPairOverrideParams[] calldata params) external onlyOwner {
        _setPairOverrides(params);
        emit SetPairOverride(params);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - views
    /// -----------------------------------------------------------------------

    // TODO: array?
    /// get pair override for a token pair
    function getPairOverride(TokenPair calldata tp) external view returns (PairOverride memory) {
        return _getPairOverride(_convertAndSortTokenPair(tp));
    }

    /// get quote amounts for a set of trades
    function getQuoteAmounts(address quoteToken, BaseParams[] calldata bps)
        external
        view
        returns (uint256[] memory quoteAmounts)
    {
        uint256 length = bps.length;
        quoteAmounts = new uint256[](length);
        uint256 i;
        for (; i < length;) {
            quoteAmounts[i] = _getQuoteAmount(quoteToken, bps[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    /// get quote amount for a trade
    function _getQuoteAmount(address quoteToken, BaseParams calldata bp) internal view returns (uint256) {
        ConvertedTokenPair memory ctp = TokenPair({tokenA: bp.baseToken, tokenB: quoteToken})._convert(_convertToken);
        SortedConvertedTokenPair memory sctp = ctp._sort();

        // TODO: how does this handle the dynamic array?
        // I think it.... just doesn't?
        PairOverride memory po = _getPairOverride(sctp);
        if (po.staleAfter == 0) {
            po.staleAfter = defaultStaleAfter;
        }
        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = defaultScaledOfferFactor;
        }

        uint256 unscaledAmountToBeneficiary = uint256(bp.baseAmount);
        // skip oracle if converted tokens are equal
        // (can't return early, still need to adjust decimals)
        if (sctp.cToken0 != sctp.cToken1) {
            if (po.path.length == 0) {
                address[] memory intermediaryTokens = abi.decode(bp.data, (address[]));
                uint256 itLength = intermediaryTokens.length;
                po.path = new AggregatorV3Interface[](itLength+1);

                uint256 j;
                address base = ctp.cTokenA;
                address quote;
                for (; j < itLength;) {
                    quote = intermediaryTokens[j];
                    // reverts if feed not found
                    po.path[j] = clFeedRegistry.getFeed({base: base, quote: quote});
                    base = quote;
                    unchecked {
                        ++j;
                    }
                }
                quote = ctp.cTokenB;
                po.path[itLength] = clFeedRegistry.getFeed({base: base, quote: quote});
            } else if (ctp.cTokenA != sctp.cToken0) {
                // paths are stored from cToken0 to cToken1; reverse if necessary

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

                unchecked {
                    ++i;
                }
            }
        }

        uint8 baseDecimals = bp.baseToken._getDecimals();
        uint8 quoteDecimals = quoteToken._getDecimals();

        int256 decimalAdjustment = int256(uint256(quoteDecimals)) - int256(uint256(baseDecimals));
        if (decimalAdjustment > 0) {
            unscaledAmountToBeneficiary *= 10 ** uint256(decimalAdjustment);
        } else {
            unscaledAmountToBeneficiary /= 10 ** uint256(-decimalAdjustment);
        }

        return unscaledAmountToBeneficiary * po.scaledOfferFactor / PERCENTAGE_SCALE;
    }

    /// set token overrides
    function _setTokenOverrides(SetTokenOverrideParams[] calldata params) internal {
        uint256 length = params.length;
        uint256 i;
        for (; i < length;) {
            _setTokenOverride(params[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// set token override
    function _setTokenOverride(SetTokenOverrideParams calldata params) internal {
        tokenOverrides[params.token] = params.tokenOverride;
    }

    /// get pair override
    function _getPairOverride(SortedConvertedTokenPair memory sctp) internal view returns (PairOverride memory) {
        return _pairOverrides[sctp.cToken0][sctp.cToken1];
    }

    /// set pair overrides
    function _setPairOverrides(SetPairOverrideParams[] calldata params) internal {
        uint256 length = params.length;
        uint256 i;
        for (; i < length;) {
            _setPairOverride(params[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// set pair override
    function _setPairOverride(SetPairOverrideParams calldata params) internal {
        SortedConvertedTokenPair memory sctp = _convertAndSortTokenPair(params.tp);
        _pairOverrides[sctp.cToken0][sctp.cToken1] = params.pairOverride;
    }

    /// convert & sort tokens into canonical order
    function _convertAndSortTokenPair(TokenPair calldata tp) internal view returns (SortedConvertedTokenPair memory) {
        return tp._convert(_convertToken)._sort();
    }

    /// convert eth (0x0) to weth
    function _convertToken(address token) internal view returns (address) {
        return (token._isETH() || token == weth9) ? clETH : tokenOverrides[token];
    }
}
