// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";
import {TokenPair, ConvertedTokenPair, SortedConvertedTokenPair} from "src/utils/TokenPairs.sol";

/// @title UniV3 Oracle Implementation
/// @author 0xSplits
/// @notice An oracle clone-implementation using UniswapV3 TWAP
contract UniV3OracleImpl is Owned, IOracle {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    error Unauthorized();
    error Pool_DoesNotExist();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct SetPairOverrideParams {
        TokenPair tp;
        PairOverride pairOverride;
    }

    struct PairOverride {
        uint24 fee;
        uint32 period;
        uint32 scaledOfferFactor;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event SetDefaultFee(uint24 defaultFee);
    event SetDefaultPeriod(uint32 defaultPeriod);
    event SetDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor);
    event SetPairOverride(SetPairOverrideParams[] params);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    uint32 internal constant PERCENTAGE_SCALE = 100_00_00; // = 100%

    address public immutable uniV3OracleFactory;
    IUniswapV3Factory public immutable uniswapV3Factory;
    address public immutable weth9;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// slot 0 - 1 byte free

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    /// default uniswap pool fee
    /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100%;
    /// fee = 30_00 = 0.3% is the uniswap default
    /// unless overriden, getQuoteAmounts will revert if a non-permitted pool fee is used
    /// 3 bytes
    uint24 public defaultFee;

    /// default twap period
    /// @dev unless overriden, getQuoteAmounts will revert if zero
    /// 4 bytes
    uint32 public defaultPeriod;

    /// default price scaling factor
    /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100% = no discount or premium
    /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
    /// 4 bytes
    uint32 public defaultScaledOfferFactor;

    /// slot 1 - 0 bytes free

    /// overrides for specific token pairs
    /// 32 bytes
    mapping(address => mapping(address => PairOverride)) internal _pairOverrides;

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor(IUniswapV3Factory uniswapV3Factory_, address weth9_) Owned(address(0)) {
        uniswapV3Factory = uniswapV3Factory_;
        weth9 = weth9_;
        uniV3OracleFactory = msg.sender;
    }

    function initializer(
        address owner_,
        uint24 defaultFee_,
        uint32 defaultPeriod_,
        uint32 defaultScaledOfferFactor_,
        SetPairOverrideParams[] calldata poParams
    ) external {
        // only uniV3OracleFactory may call `initializer`
        if (msg.sender != uniV3OracleFactory) revert Unauthorized();

        owner = owner_;
        defaultFee = defaultFee_;
        defaultPeriod = defaultPeriod_;
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
        emit OwnershipTransferred(address(0), owner_);

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

    /// set defaultFee
    function setDefaultFee(uint24 defaultFee_) external onlyOwner {
        defaultFee = defaultFee_;
        emit SetDefaultFee(defaultFee_);
    }

    /// set defaultPeriod
    function setDefaultPeriod(uint32 defaultPeriod_) external onlyOwner {
        defaultPeriod = defaultPeriod_;
        emit SetDefaultPeriod(defaultPeriod_);
    }

    /// set defaultScaledOfferFactor
    function setDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor_) external onlyOwner {
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
        emit SetDefaultScaledOfferFactor(defaultScaledOfferFactor_);
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
        PairOverride memory po = _getPairOverride(sctp);

        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = defaultScaledOfferFactor;
        }

        // skip oracle if converted tokens are equal
        if (sctp.cToken0 == sctp.cToken1) {
            return bp.baseAmount * po.scaledOfferFactor / PERCENTAGE_SCALE;
        }

        if (po.fee == 0) {
            po.fee = defaultFee;
        }
        if (po.period == 0) {
            po.period = defaultPeriod;
        }

        address pool = uniswapV3Factory.getPool(sctp.cToken0, sctp.cToken1, po.fee);
        if (pool == address(0)) {
            revert Pool_DoesNotExist();
        }

        // reverts if period is zero or > oldest observation
        (int24 arithmeticMeanTick,) = OracleLibrary.consult({pool: pool, secondsAgo: po.period});

        uint256 unscaledAmountToBeneficiary = OracleLibrary.getQuoteAtTick({
            tick: arithmeticMeanTick,
            baseAmount: bp.baseAmount,
            baseToken: ctp.cTokenA,
            quoteToken: ctp.cTokenB
        });

        return unscaledAmountToBeneficiary * po.scaledOfferFactor / PERCENTAGE_SCALE;
    }

    /// get pair overrides
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
        return token._isETH() ? weth9 : token;
    }
}
