// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

import {ISwapperFlashCallback} from "./interfaces/ISwapperFlashCallback.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";

/// @title Swapper
/// @author 0xSplits
/// @notice A contract to trustlessly & automatically convert multi-token
/// revenue into a single token & push to a beneficiary.
/// Please be aware, owner has _FULL CONTROL_ of the deployment.
// TODO: modular oracle
/// @dev This contract uses uniswap v3 as it's oracle. Be very careful to use
/// sensible defaults & overrides for desired behavior. Results may otherwise
/// result in catastrophic loss of funds.
/// This contract uses token = address(0) to refer to ETH.
contract Swapper is Owned {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    error Paused();
    error Invalid_TokenToBeneficiary();
    error InsufficientFunds_InContract();
    error InsufficientFunds_FromTrader();
    error Pool_DoesNotExist();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    // TODO
    /* struct ConstructorParams { */
    /*     IUniswapV3Factory uniswapV3Factory_, */
    /*     address owner; */
    /*     address beneficiary; */
    /*     bool paused; */
    /*     address tokenToBeneficiary; */
    /*     uint24 defaultFee; */
    /*     uint32 defaultPeriod; */
    /*     uint32 defaultScaledOfferFactor; */
    /*     Swapper.SetPoolOverrideParams[] poolOverrideParams; */
    /* } */

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

    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }

    struct TradeParams {
        address token;
        uint128 amount;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event SetBeneficiary(address indexed beneficiary);
    event SetPaused(bool paused);
    event SetTokenToBeneficiary(address tokenToBeneficiary);
    event SetDefaultFee(uint24 defaultFee);
    event SetDefaultPeriod(uint32 defaultPeriod);
    event SetDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor);
    event SetPoolOverrides(SetPoolOverrideParams[] poolOverrideParams);

    event ExecCalls();

    event ReceiveETH(uint256 amount);
    event PayBack(address indexed payer, uint256 amount);
    event Flash(
        address indexed trader,
        TradeParams[] tradeParams,
        address tokenToBeneficiary,
        uint256[] amountsToBeneficiary,
        uint256 excessToBeneficiary
    );

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

    /// Owned storage

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 1
    /// -----------------------------------------------------------------------

    /// address to receive post-swap tokens
    address public beneficiary;

    /// used to track eth payback in flash
    uint96 internal _payback;

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 2
    /// -----------------------------------------------------------------------

    /// token type to send beneficiary
    /// @dev 0x0 used for ETH
    address public tokenToBeneficiary;

    /// fee for default-whitelisted pools
    /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100%;
    /// fee = 30_00 = 0.3% is the uniswap default
    /// unless overriden, flash will revert if a non-permitted pool fee is used
    uint24 public defaultFee;

    /// twap duration for default-whitelisted pools
    /// @dev unless overriden, flash will revert if zero
    uint32 public defaultPeriod;

    /// scaling factor to oracle pricing for default-whitelisted pools to
    /// incentivize traders
    /// @dev PERCENTAGE_SCALE = 1e6 = 100_00_00 = 100% = no discount or premium
    /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
    uint32 public defaultScaledOfferFactor;

    /// whether non-owner functions are paused
    bool public paused;

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 3
    /// -----------------------------------------------------------------------

    /// owner overrides for uniswap v3 oracle params
    mapping(address => mapping(address => PoolOverride)) internal _poolOverrides;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(
        IUniswapV3Factory uniswapV3Factory_,
        address weth9_,
        address owner_,
        address beneficiary_,
        bool paused_,
        address tokenToBeneficiary_,
        uint24 defaultFee_,
        uint32 defaultPeriod_,
        uint32 defaultScaledOfferFactor_,
        SetPoolOverrideParams[] memory poolOverrideParams
    ) Owned(owner_) {
        uniswapV3Factory = uniswapV3Factory_;
        weth9 = weth9_;

        beneficiary = beneficiary_;

        // TODO: review SSTORE
        tokenToBeneficiary = tokenToBeneficiary_;
        defaultFee = defaultFee_;
        defaultPeriod = defaultPeriod_;
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
        paused = paused_;

        uint256 length = poolOverrideParams.length;
        uint256 i;
        for (; i < length;) {
            _setPoolOverride(poolOverrideParams[i]);

            unchecked {
                ++i;
            }
        }

        // event emitted by factory
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

    /// set paused
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;

        emit SetPaused(paused_);
    }

    /// set beneficiary
    function setBeneficiary(address beneficiary_) external onlyOwner {
        beneficiary = beneficiary_;

        emit SetBeneficiary(beneficiary_);
    }

    /// set token type to send beneficiary
    function setTokenToBeneficiary(address tokenToBeneficiary_) external onlyOwner {
        tokenToBeneficiary = tokenToBeneficiary_;

        emit SetTokenToBeneficiary(tokenToBeneficiary_);
    }

    /// set default pool fee
    function setDefaultFee(uint24 defaultFee_) external onlyOwner {
        defaultFee = defaultFee_;

        emit SetDefaultFee(defaultFee_);
    }

    /// set default twap period
    function setDefaultPeriod(uint32 defaultPeriod_) external onlyOwner {
        defaultPeriod = defaultPeriod_;

        emit SetDefaultPeriod(defaultPeriod_);
    }

    /// set default offer discount / premium
    function setDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor_) external onlyOwner {
        defaultScaledOfferFactor = defaultScaledOfferFactor_;

        emit SetDefaultScaledOfferFactor(defaultScaledOfferFactor_);
    }

    /// set pool overrides
    function setPoolOverrides(SetPoolOverrideParams[] calldata params) external onlyOwner {
        uint256 i;
        for (; i < params.length;) {
            _setPoolOverride(params[i]);

            unchecked {
                ++i;
            }
        }

        emit SetPoolOverrides(params);
    }

    /// allow owner to execute arbitrary calls from swapper
    function execCalls(Call[] calldata calls)
        external
        payable
        onlyOwner
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;
        uint256 length = calls.length;
        returnData = new bytes[](length);

        bool success;
        uint256 i;
        for (; i < length;) {
            // TODO: calldata vs memory?
            Call calldata calli = calls[i];
            (success, returnData[i]) = calli.target.call{value: calli.value}(calli.callData);
            require(success, string(returnData[i]));

            unchecked {
                ++i;
            }
        }

        // TODO: include calls?
        emit ExecCalls();
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - permissionless
    /// -----------------------------------------------------------------------

    /// emit event when receiving ETH
    /// @dev implemented w/i clone bytecode
    receive() external payable {
        emit ReceiveETH(msg.value);
    }

    /// allows flash to track eth payback to beneficiary
    /// @dev if used outside swapperFlashCallback, msg.sender may lose funds
    /// accumulates until next flash call
    function payback() external payable {
        _payback += msg.value.toUint96();

        emit PayBack(msg.sender, msg.value);
    }

    /// incentivizes third parties to withdraw tokens in return for sending tokenToBeneficiary to beneficiary
    function flash(TradeParams[] calldata tradeParams, bytes calldata data) external payable {
        // TODO: review SLOADs

        if (paused) revert Paused();

        address _tokenToBeneficiary = tokenToBeneficiary;
        uint256 amountToBeneficiary;
        uint256 length = tradeParams.length;
        uint256[] memory amountsToBeneficiary = new uint256[](length);
        {
            uint256 _amountToBeneficiary;
            uint128 amountToTrader;
            address tokenToTrader;
            uint256 i;
            for (; i < length;) {
                TradeParams calldata tp = tradeParams[i];
                tokenToTrader = tp.token;
                amountToTrader = tp.amount;

                // TODO: is error message worth the extra gas?
                if (amountToTrader > address(this).getBalance(tokenToTrader)) {
                    revert InsufficientFunds_InContract();
                }

                _amountToBeneficiary = _getAmountToBeneficiary(_tokenToBeneficiary, tokenToTrader, amountToTrader);
                amountsToBeneficiary[i] = _amountToBeneficiary;
                amountToBeneficiary += _amountToBeneficiary;

                if (tokenToTrader.isETH()) {
                    msg.sender.safeTransferETH(amountToTrader);
                } else {
                    tokenToTrader.safeTransfer(msg.sender, amountToTrader);
                }

                unchecked {
                    ++i;
                }
            }
        }

        ISwapperFlashCallback(msg.sender).swapperFlashCallback({
            tokenToBeneficiary: _tokenToBeneficiary,
            amountToBeneficiary: amountToBeneficiary,
            data: data
        });

        // TODO: review SLOADs
        address _beneficiary = beneficiary;
        uint256 excessToBeneficiary;
        if (_tokenToBeneficiary.isETH()) {
            if (_payback < amountToBeneficiary) {
                revert InsufficientFunds_FromTrader();
            }
            _payback = 0;

            // send eth to beneficiary
            uint256 ethBalance = address(this).balance;
            excessToBeneficiary = ethBalance - amountToBeneficiary;
            _beneficiary.safeTransferETH(ethBalance);
        } else {
            _tokenToBeneficiary.safeTransferFrom(msg.sender, _beneficiary, amountToBeneficiary);

            // flush excess tokenToBeneficiary to beneficiary
            excessToBeneficiary = ERC20(tokenToBeneficiary).balanceOf(address(this));
            if (excessToBeneficiary > 0) {
                tokenToBeneficiary.safeTransfer(_beneficiary, excessToBeneficiary);
            }
        }

        emit Flash(msg.sender, tradeParams, _tokenToBeneficiary, amountsToBeneficiary, excessToBeneficiary);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - views
    /// -----------------------------------------------------------------------

    /// get pool overrides
    function getPoolOverrides(address tokenA, address tokenB) public view returns (PoolOverride memory) {
        (address token0, address token1) = _getPoolOverrideParamHelper(tokenA, tokenB);
        return _poolOverrides[token0][token1];
    }

    /// get amount to beneficiary for a particular trade
    function getAmountToBeneficiary(address tokenToTrader, uint128 amountToTrader) public view returns (uint256) {
        address _tokenToBeneficiary = tokenToBeneficiary;
        return _getAmountToBeneficiary(_tokenToBeneficiary, tokenToTrader, amountToTrader);
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    /// set pool overrides
    function _setPoolOverride(SetPoolOverrideParams memory params) internal {
        (address token0, address token1) = _getPoolOverrideParamHelper(params.tokenA, params.tokenB);
        _poolOverrides[token0][token1] = params.poolOverride;
    }

    /// pool override param helper
    function _getPoolOverrideParamHelper(address tokenA, address tokenB)
        internal
        view
        returns (address token0, address token1)
    {
        token0 = tokenA.isETH() ? weth9 : tokenA;
        token1 = tokenB.isETH() ? weth9 : tokenB;
        if (token0 > token1) (token0, token1) = (token1, token0);
    }

    /// get amount to beneficiary for a particular trade
    function _getAmountToBeneficiary(address _tokenToBeneficiary, address tokenToTrader, uint128 amountToTrader)
        internal
        view
        returns (uint256)
    {
        (address token0, address token1) = _getPoolOverrideParamHelper(_tokenToBeneficiary, tokenToTrader);
        PoolOverride memory po = _poolOverrides[token0][token1];
        if (po.scaledOfferFactor == 0) {
            po.scaledOfferFactor = defaultScaledOfferFactor;
        }

        if (token0 == token1) {
            // no oracle necessary
            return amountToTrader * po.scaledOfferFactor / PERCENTAGE_SCALE;
        }

        if (po.fee == 0) {
            po.fee = defaultFee;
        }
        if (po.period == 0) {
            po.period = defaultPeriod;
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
}
