// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";
import {FeedRegistryInterface} from "chainlink/interfaces/FeedRegistryInterface.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LibSort} from "solady/utils/LibSort.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";
import {QuotePair, ConvertedQuotePair, SortedConvertedQuotePair} from "src/utils/QuotePair.sol";

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
    error StalePrice(AggregatorV3Interface priceFeed, uint256 timestamp);
    error NegativePrice(AggregatorV3Interface priceFeed, int256 price);

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct SetTokenOverrideParams {
        address token;
        address tokenOverride;
    }

    struct SetPairOverrideParams {
        QuotePair qp;
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
    uint32 public $defaultStaleAfter;

    /// default price scaling factor
    /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100% = no discount or premium
    /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
    /// 4 bytes
    uint32 public $defaultScaledOfferFactor;

    /// slot 1 - 0 bytes free

    /// overrides for specific tokens
    /// 32 bytes
    mapping(address => address) public $tokenOverrides;

    /// slot 2 - 0 bytes free

    /// overrides for specific token pairs
    /// 32 bytes
    mapping(address => mapping(address => PairOverride)) internal $_pairOverrides;

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
        SetTokenOverrideParams[] calldata toParams_,
        SetPairOverrideParams[] calldata poParams_
    ) external {
        // only chainlinkOracleFactory may call `initializer`
        if (msg.sender != chainlinkOracleFactory) revert Unauthorized();

        owner = owner_;
        $defaultStaleAfter = defaultStaleAfter_;
        $defaultScaledOfferFactor = defaultScaledOfferFactor_;
        emit OwnershipTransferred(address(0), owner_);

        _setTokenOverrides(toParams_);
        _setPairOverrides(poParams_);
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
        $defaultStaleAfter = defaultStaleAfter_;
        emit SetDefaultStaleAfter(defaultStaleAfter_);
    }

    /// set defaultScaledOfferFactor
    function setDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor_) external onlyOwner {
        $defaultScaledOfferFactor = defaultScaledOfferFactor_;
        emit SetDefaultScaledOfferFactor(defaultScaledOfferFactor_);
    }

    /// set token overrides
    function setTokenOverrides(SetTokenOverrideParams[] calldata params_) external onlyOwner {
        _setTokenOverrides(params_);
        emit SetTokenOverride(params_);
    }

    /// set pair overrides
    function setPairOverrides(SetPairOverrideParams[] calldata params_) external onlyOwner {
        _setPairOverrides(params_);
        emit SetPairOverride(params_);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - views
    /// -----------------------------------------------------------------------

    // TODO: array?
    /// get pair override for a token pair
    function getPairOverride(QuotePair calldata quotePair_) external view returns (PairOverride memory) {
        return _getPairOverride(_convertAndSortQuotePair(quotePair_));
    }

    /// get quote amounts for a set of trades
    function getQuoteAmounts(QuoteParams[] calldata qps_) external view returns (uint256[] memory quoteAmounts) {
        uint256 length = qps_.length;
        quoteAmounts = new uint256[](length);
        for (uint256 i; i < length;) {
            quoteAmounts[i] = _getQuoteAmount(qps_[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    /// set token overrides
    function _setTokenOverrides(SetTokenOverrideParams[] calldata params_) internal {
        uint256 length = params_.length;
        for (uint256 i; i < length;) {
            _setTokenOverride(params_[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// set token override
    function _setTokenOverride(SetTokenOverrideParams calldata params_) internal {
        $tokenOverrides[params_.token] = params_.tokenOverride;
    }

    /// set pair overrides
    function _setPairOverrides(SetPairOverrideParams[] calldata params_) internal {
        uint256 length = params_.length;
        for (uint256 i; i < length;) {
            _setPairOverride(params_[i]);
            unchecked {
                ++i;
            }
        }
    }

    // TODO: since pairOverride.path order matters (from cToken0 to cToken1), may either want to:
    // require pair to be sorted OR
    // reverse array if pair is unsorted

    /// set pair override
    function _setPairOverride(SetPairOverrideParams calldata params_) internal {
        SortedConvertedQuotePair memory scqp = _convertAndSortQuotePair(params_.qp);
        $_pairOverrides[scqp.cToken0][scqp.cToken1] = params_.pairOverride;
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal - views
    /// -----------------------------------------------------------------------

    /// get quote amount for a trade
    function _getQuoteAmount(QuoteParams calldata quoteParams_) internal view returns (uint256) {
        ConvertedQuotePair memory cqp = quoteParams_.quotePair._convert(_convertToken);
        SortedConvertedQuotePair memory scqp = cqp._sort();

        // TODO: make sure this copies po.path to memory
        PairOverride memory po = _getPairOverride(scqp);
        if (po.staleAfter == 0) {
            po.staleAfter = $defaultStaleAfter;
        }
        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = $defaultScaledOfferFactor;
        }

        // TODO: make sure this just creates a pointer
        AggregatorV3Interface[] memory path = po.path;
        uint256 unscaledAmountToBeneficiary = uint256(quoteParams_.baseAmount);
        // skip oracle if converted tokens are equal
        // (can't return early, still need to adjust decimals)
        if (scqp.cToken0 != scqp.cToken1) {
            if (path.length == 0) {
                path = _getPathFromQuoteParams(quoteParams_, cqp);
            } else if (cqp.cBase != scqp.cToken0) {
                // paths are stored from cToken0 to cToken1; reverse if cBase == cToken1
                _reverse(path);
            }

            unscaledAmountToBeneficiary = _scaleAmountByFeeds(unscaledAmountToBeneficiary, path, po.staleAfter);
        }

        unscaledAmountToBeneficiary = _adjustDecimals(unscaledAmountToBeneficiary, quoteParams_);
        return unscaledAmountToBeneficiary * po.scaledOfferFactor / PERCENTAGE_SCALE;
    }

    /// get pair override
    function _getPairOverride(SortedConvertedQuotePair memory scqp_) internal view returns (PairOverride memory) {
        return $_pairOverrides[scqp_.cToken0][scqp_.cToken1];
    }

    /// convert & sort tokens into canonical order
    function _convertAndSortQuotePair(QuotePair calldata quotePair_)
        internal
        view
        returns (SortedConvertedQuotePair memory)
    {
        return quotePair_._convert(_convertToken)._sort();
    }

    /// convert eth (0x0) to weth
    function _convertToken(address token_) internal view returns (address) {
        return (token_._isETH() || token_ == weth9) ? clETH : $tokenOverrides[token_];
    }

    // TODO figure out array pointers here
    /// TODO
    function _getPathFromQuoteParams(QuoteParams calldata quoteParams_, ConvertedQuotePair memory cqp)
        internal
        view
        returns (AggregatorV3Interface[] memory path)
    {
        address[] memory intermediaryTokens = abi.decode(quoteParams_.data, (address[]));
        uint256 itLength = intermediaryTokens.length;
        path = new AggregatorV3Interface[](itLength+1);

        address base = cqp.cBase;
        address quote;
        for (uint256 i; i < itLength;) {
            quote = intermediaryTokens[i];
            // reverts if feed not found
            path[i] = clFeedRegistry.getFeed({base: base, quote: quote});
            base = quote;
            unchecked {
                ++i;
            }
        }
        quote = cqp.cQuote;
        path[itLength] = clFeedRegistry.getFeed({base: base, quote: quote});
    }

    /// reverse AggregatorV3Interface[] in-memory
    function _reverse(AggregatorV3Interface[] memory path_) internal pure {
        address[] memory casted;
        /// @solidity memory-safe-assembly
        assembly {
            casted := path_
        }
        // happens in-memory; reverses path
        casted.reverse();
    }

    function _scaleAmountByFeeds(
        uint256 unscaledAmountToBeneficiary_,
        AggregatorV3Interface[] memory path_,
        uint32 staleAfter_
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFeed;
        int256 answer;
        uint256 updatedAt;
        uint8 priceDecimals;
        uint256 length = path_.length;
        for (uint256 i; i < length;) {
            priceFeed = path_[i];

            (
                , /* uint80 roundId, */
                answer,
                , /* uint256 startedAt, */
                updatedAt,
                /* uint80 answeredInRound */
            ) = priceFeed.latestRoundData();

            if (updatedAt < block.timestamp - staleAfter_) {
                revert StalePrice(priceFeed, updatedAt);
            }
            if (answer < 0) {
                revert NegativePrice(priceFeed, answer);
            }

            priceDecimals = priceFeed.decimals();
            unscaledAmountToBeneficiary_ = unscaledAmountToBeneficiary_ * uint256(answer) / 10 ** uint256(priceDecimals);

            unchecked {
                ++i;
            }
        }
        return unscaledAmountToBeneficiary_;
    }

    function _adjustDecimals(uint256 unscaledAmountToBeneficiary_, QuoteParams calldata quoteParams_)
        internal
        view
        returns (uint256)
    {
        uint8 baseDecimals = quoteParams_.quotePair.base._getDecimals();
        uint8 quoteDecimals = quoteParams_.quotePair.quote._getDecimals();

        int256 decimalAdjustment = int256(uint256(quoteDecimals)) - int256(uint256(baseDecimals));
        if (decimalAdjustment > 0) {
            return unscaledAmountToBeneficiary_ * 10 ** uint256(decimalAdjustment);
        }
        return unscaledAmountToBeneficiary_ / 10 ** uint256(-decimalAdjustment);
    }
}
