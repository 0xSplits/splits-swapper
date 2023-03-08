// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";

import {ISwapperOracle} from "src/interfaces/ISwapperOracle.sol";
import {Swapper} from "src/Swapper.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";

/// @title Naive UniV3 Oracle for Swapper#flash
/// @author 0xSplits
/// @notice An oracle for Swapper#flash based on UniswapV3 TWAP
contract SwapperOracleUniV3Naive is ISwapperOracle {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    /// from interface

    /* error UnsupportedFile(); */

    error Pool_DoesNotExist();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct OracleStorage {
        /// -------------------------------------------------------------------
        /// Slot 0 - 21 bytes free
        /// -------------------------------------------------------------------

        /// default uniswap pool fee
        /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100%;
        /// fee = 30_00 = 0.3% is the uniswap default
        /// unless overriden, flash will revert if a non-permitted pool fee is used
        /// 3 bytes
        uint24 defaultFee;
        /// default twap period
        /// @dev unless overriden, flash will revert if zero
        /// 4 bytes
        uint32 defaultPeriod;
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
        DefaultFee,
        DefaultPeriod,
        DefaultScaledOfferFactor,
        PairOverride
    }

    struct SetPairOverrideParams {
        UnsortedTokenPair utp;
        PairOverride pairOverride;
    }

    struct PairOverride {
        uint24 fee;
        uint32 period;
        uint32 scaledOfferFactor;
    }

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    uint32 internal constant PERCENTAGE_SCALE = 100_00_00; // = 100%

    IUniswapV3Factory public immutable uniswapV3Factory;
    address public immutable weth9;

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

    constructor(IUniswapV3Factory uniswapV3Factory_, address weth9_) {
        uniswapV3Factory = uniswapV3Factory_;
        weth9 = weth9_;
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
        if (what == FileType.DefaultFee) {
            s.defaultFee = abi.decode(data, (uint24));
        } else if (what == FileType.DefaultPeriod) {
            s.defaultPeriod = abi.decode(data, (uint32));
        } else if (what == FileType.DefaultScaledOfferFactor) {
            s.defaultScaledOfferFactor = abi.decode(data, (uint32));
        } else if (what == FileType.PairOverride) {
            _setPairOverride(s, abi.decode(data, (SetPairOverrideParams)));
        } else {
            revert UnsupportedFile();
        }
    }

    /// get oracle storage
    function getFile(Swapper swapper, File calldata incoming) external view returns (bytes memory) {
        FileType what = FileType(IFileType.unwrap(incoming.what));

        OracleStorage storage s = _oracleStorage[swapper];
        if (what == FileType.DefaultFee) {
            return abi.encode(s.defaultFee);
        } else if (what == FileType.DefaultPeriod) {
            return abi.encode(s.defaultPeriod);
        } else if (what == FileType.DefaultScaledOfferFactor) {
            return abi.encode(s.defaultScaledOfferFactor);
        } else if (what == FileType.PairOverride) {
            return abi.encode(_getPairOverrides(s, abi.decode(incoming.data, (UnsortedTokenPair))));
        } else {
            revert UnsupportedFile();
        }
    }

    /// get OracleStorage for a specific swapper
    function getOracleDefaults(Swapper swapper)
        external
        view
        returns (uint24 defaultFee, uint32 defaultPeriod, uint32 defaultScaledOfferFactor)
    {
        OracleStorage storage s = _oracleStorage[swapper];

        defaultFee = s.defaultFee;
        defaultPeriod = s.defaultPeriod;
        defaultScaledOfferFactor = s.defaultScaledOfferFactor;
    }

    /// get PairOverrides for a specific swapper & set of token pairs
    function getOraclePairOverrides(Swapper swapper, UnsortedTokenPair[] calldata tps)
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
            pairOverrides[i] = _getPairOverrides({s: s, utp: utp});
            unchecked {
                ++i;
            }
        }
    }

    /// get amounts to beneficiary for a set of trades
    function getAmountsToBeneficiary(
        Swapper swapper,
        address tokenToBeneficiary,
        Swapper.TradeParams[] calldata tradeParams,
        bytes calldata
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
        address _tokenToBeneficiary,
        Swapper.TradeParams calldata tradeParams
    ) internal view returns (uint256) {
        address tokenToTrader = _convertToken(tradeParams.token);
        address tokenToBeneficiary = _convertToken(_tokenToBeneficiary);
        uint128 amountToTrader = tradeParams.amount;

        SortedTokenPair memory stp = _sortTokens(UnsortedTokenPair({tokenA: tokenToBeneficiary, tokenB: tokenToTrader}));
        PairOverride memory po = _getPairOverrides(s, stp);
        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = s.defaultScaledOfferFactor;
        }

        if (stp.token0 == stp.token1) {
            // no oracle necessary
            return amountToTrader * po.scaledOfferFactor / PERCENTAGE_SCALE;
        }

        if (po.fee == 0) {
            po.fee = s.defaultFee;
        }
        if (po.period == 0) {
            po.period = s.defaultPeriod;
        }

        address pool = uniswapV3Factory.getPool(stp.token0, stp.token1, po.fee);
        if (pool == address(0)) {
            revert Pool_DoesNotExist();
        }

        // reverts if period is zero or > oldest observation
        (int24 arithmeticMeanTick,) = OracleLibrary.consult({pool: pool, secondsAgo: po.period});

        uint256 unscaledAmountToBeneficiary = OracleLibrary.getQuoteAtTick({
            tick: arithmeticMeanTick,
            baseAmount: amountToTrader,
            baseToken: tokenToTrader,
            quoteToken: tokenToBeneficiary
        });

        return unscaledAmountToBeneficiary * po.scaledOfferFactor / PERCENTAGE_SCALE;
    }

    /// set pair overrides
    function _setPairOverride(OracleStorage storage s, SetPairOverrideParams memory params) internal {
        SortedTokenPair memory stp = _convertAndSortTokens(params.utp);
        s._pairOverrides[stp.token0][stp.token1] = params.pairOverride;
    }

    /// get pair overrides
    function _getPairOverrides(OracleStorage storage s, UnsortedTokenPair memory utp)
        internal
        view
        returns (PairOverride memory)
    {
        return _getPairOverrides(s, _convertAndSortTokens(utp));
    }

    /// get pair overrides
    function _getPairOverrides(OracleStorage storage s, SortedTokenPair memory stp)
        internal
        view
        returns (PairOverride memory)
    {
        return s._pairOverrides[stp.token0][stp.token1];
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

    /// convert eth (0x0) to weth
    function _convertToken(address token) internal view returns (address) {
        return token.isETH() ? weth9 : token;
    }

    /// convert & sort tokens into canonical order
    function _convertAndSortTokens(UnsortedTokenPair memory utp) internal view returns (SortedTokenPair memory) {
        return _sortTokens(UnsortedTokenPair({tokenA: _convertToken(utp.tokenA), tokenB: _convertToken(utp.tokenB)}));
    }
}
