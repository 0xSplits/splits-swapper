// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";

import {ISwapperOracle} from "src/interfaces/ISwapperOracle.sol";
import {Swapper} from "src/Swapper.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";

/// @title Oracle for Swapper#flash
/// @notice TODO
/// @dev To be used exclusively via delegateCall from Swapper. Must use explicit
/// storage bucket to avoid overlap with native Swapper storage & other past or
/// future oracles if owner chooses to update
/// Uses string reverts to bubble up properly
contract SwapperOracleUniV3Naive is ISwapperOracle {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    error UnsupportedFile();
    error Pool_DoesNotExist();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    /// OracleStorage is explicitly stored in slot STORAGE_SLOT (= n in below comments)
    struct OracleStorage {
        //////
        ////// Slot n
        //////

        /// fee for default-whitelisted pools
        /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100%;
        /// fee = 30_00 = 0.3% is the uniswap default
        /// unless overriden, flash will revert if a non-permitted pool fee is used
        /// 3 bytes
        uint24 defaultFee;
        /// twap duration for default-whitelisted pools
        /// @dev unless overriden, flash will revert if zero
        /// 4 bytes
        uint32 defaultPeriod;
        /// scaling factor to oracle pricing for default-whitelisted pools to
        /// incentivize traders
        /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100% = no discount or premium
        /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
        /// 4 bytes
        uint32 defaultScaledOfferFactor;
        /// 21 bytes free

        //////
        ////// Slot n+1
        //////

        /// owner overrides for uniswap v3 oracle params
        /// 32 bytes
        mapping(address => mapping(address => PoolOverride)) _poolOverrides;
    }

    /// 0 bytes free

    enum FileType {
        NotSupported,
        DefaultFee,
        DefaultPeriod,
        DefaultScaledOfferFactor,
        PoolOverride
    }

    struct SetPoolOverrideParams {
        address tokenA;
        address tokenB;
        PoolOverride poolOverride;
    }

    struct PoolOverride {
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
    // TODO: hard-code hash & update oracleStorage
    bytes32 internal constant STORAGE_SLOT = keccak256("splits.swapper.uni-v3.naive.storage");

    IUniswapV3Factory public immutable uniswapV3Factory;
    address public immutable weth9;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    function _oracleStorage() internal pure returns (OracleStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

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

        OracleStorage storage s = _oracleStorage();
        if (what == FileType.DefaultFee) {
            s.defaultFee = abi.decode(data, (uint24));
        } else if (what == FileType.DefaultPeriod) {
            s.defaultPeriod = abi.decode(data, (uint32));
        } else if (what == FileType.DefaultScaledOfferFactor) {
            s.defaultScaledOfferFactor = abi.decode(data, (uint32));
        } else if (what == FileType.PoolOverride) {
            _setPoolOverride(s, abi.decode(data, (SetPoolOverrideParams)));
        } else {
            revert UnsupportedFile();
        }
    }

    /// get oracle storage
    function getFile(File calldata incoming) external view returns (bytes memory b) {
        FileType what = FileType(IFileType.unwrap(incoming.what));

        OracleStorage storage s = _oracleStorage();
        if (what == FileType.DefaultFee) {
            b = abi.encode(s.defaultFee);
        } else if (what == FileType.DefaultPeriod) {
            b = abi.encode(s.defaultPeriod);
        } else if (what == FileType.DefaultScaledOfferFactor) {
            b = abi.encode(s.defaultScaledOfferFactor);
        } else if (what == FileType.PoolOverride) {
            (address tokenA, address tokenB) = abi.decode(incoming.data, (address, address));
            b = abi.encode(_getPoolOverrides(s, tokenA, tokenB));
        } else {
            revert UnsupportedFile();
        }
    }

    /// get amounts to beneficiary for a set of trades
    function getAmountsToBeneficiary(
        address tokenToBeneficiary,
        Swapper.TradeParams[] calldata tradeParams,
        bytes calldata
    ) external view returns (uint256[] memory amountsToBeneficiary) {
        OracleStorage storage s = _oracleStorage();
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
        address tokenToTrader = tradeParams.token;
        uint128 amountToTrader = tradeParams.amount;

        (address token0, address token1) = _sortTokens(_tokenToBeneficiary, tradeParams.token);
        PoolOverride memory po = s._poolOverrides[token0][token1];
        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = s.defaultScaledOfferFactor;
        }

        if (token0 == token1) {
            // no oracle necessary
            return amountToTrader * po.scaledOfferFactor / PERCENTAGE_SCALE;
        }

        if (po.fee == 0) {
            po.fee = s.defaultFee;
        }
        if (po.period == 0) {
            po.period = s.defaultPeriod;
        }

        address pool = uniswapV3Factory.getPool(token0, token1, po.fee);
        if (pool == address(0)) {
            revert Pool_DoesNotExist();
        }

        // reverts if period is zero or > oldest observation
        (int24 arithmeticMeanTick,) = OracleLibrary.consult({pool: pool, secondsAgo: po.period});

        uint256 unscaledAmountToBeneficiary = OracleLibrary.getQuoteAtTick({
            tick: arithmeticMeanTick,
            baseAmount: amountToTrader,
            baseToken: tokenToTrader,
            quoteToken: _tokenToBeneficiary
        });

        return unscaledAmountToBeneficiary * po.scaledOfferFactor / PERCENTAGE_SCALE;
    }

    /// set pool overrides
    function _setPoolOverride(OracleStorage storage s, SetPoolOverrideParams memory params) internal {
        (address token0, address token1) = _sortTokens(params.tokenA, params.tokenB);
        s._poolOverrides[token0][token1] = params.poolOverride;
    }

    /// get pool overrides
    function _getPoolOverrides(OracleStorage storage s, address tokenA, address tokenB)
        internal
        view
        returns (PoolOverride memory)
    {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        return s._poolOverrides[token0][token1];
    }

    /// sort tokens into canonical order
    function _sortTokens(address tokenA, address tokenB) internal view returns (address token0, address token1) {
        token0 = tokenA.isETH() ? weth9 : tokenA;
        token1 = tokenB.isETH() ? weth9 : tokenB;
        if (token0 > token1) (token0, token1) = (token1, token0);
    }
}
