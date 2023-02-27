// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";
import {UniswapV3Pool} from "v3-core/UniswapV3Pool.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IWETH9} from "v3-periphery/interfaces/external/IWETH9.sol";

/// @title Swapper
/// @author 0xSplits
/// @notice TODO
/// @dev TODO
/// This contract uses token = address(0) to refer to ETH.
contract Swapper is Owned {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;

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
        bool delegate;
        uint256 value;
        bytes callData;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateSwapper(
        address indexed owner,
        address indexed beneficiary,
        bool paused,
        address tokenToBeneficiary,
        uint32 defaultScaledOfferFactor,
        uint32 defaultPeriod,
        SetPoolOverrideParams[] poolOverrideParams
    );

    event SetBeneficiary(address indexed beneficiary);
    event SetPaused(bool paused);
    event SetTokenToBeneficiary(address tokenToBeneficiary);
    event SetDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor);
    event SetDefaultPeriod(uint32 defaultPeriod);
    event SetPoolOverrides(SetPoolOverrideParams[] poolOverrideParams);

    event ExecCalls();

    event ReceiveETH(uint256 amount);
    event Forward(
        address indexed feeRecipient, uint256 amountToForwarder, address tokenToBeneficiary, uint256 amountToBeneficiary
    );
    event DirectSwap(
        address indexed trader, address tokenToTrader, uint128 amountToTrader, uint256 amountToBeneficiary
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    address internal constant ETH_ADDRESS = address(0);
    uint32 internal constant PERCENTAGE_SCALE = 100_00_00; // = 100%
    uint24 internal constant DEFAULT_FEE = 30_00; // = 0.3%

    IUniswapV3Factory public immutable uniswapV3Factory;
    ISwapRouter public immutable swapRouter;
    IWETH9 public immutable weth9;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// address to receive post-swap tokens
    address public beneficiary;

    /// token type to send beneficiary
    /// @dev 0x0 used for ETH
    address public tokenToBeneficiary;

    /// scaling factor to oracle pricing for default-whitelisted pools
    /// @notice offered to incentivize traders
    /// @dev PERCENTAGE_SCALE = 1e6 = 100% = no discount or premium
    /// 99_00_00 = 99% = 1% discount to oracle; 101_00_00 = 101% = 1% premium to oracle
    uint32 public defaultScaledOfferFactor;

    /// twap duration for default-whitelisted pools
    /// @dev if zero, directSwap will revert (unless pool overridden w non-zero period)
    uint32 public defaultPeriod;

    /// whether non-owner functions are paused
    bool public paused;

    /// owner overrides for uniswap v3 oracle params
    mapping(address => mapping(address => PoolOverride)) internal _poolOverrides;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(
        IUniswapV3Factory uniswapV3Factory_,
        ISwapRouter swapRouter_,
        IWETH9 weth9,
        address owner_,
        address beneficiary_,
        bool paused_,
        address tokenToBeneficiary_,
        uint32 defaultScaledOfferFactor_,
        uint32 defaultPeriod_,
        SetPoolOverrideParams[] poolOverrideParams
    ) Owned(owner_) {
        uniswapV3Factory = uniswapV3Factory_;
        swapRouter = swapRouter_;
        weth9 = weth9_;

        beneficiary = beneficiary_;
        paused = paused_;
        tokenToBeneficiary = tokenToBeneficiary_;
        defaultScaledOfferFactor = defaultScaledOfferFactor_;
        defaultPeriod = defaultPeriod_;

        for (uint256 i; i < poolOverrideParams.length;) {
            _setPoolOverride(poolOverrideParams[i]);

            unchecked {
                ++i;
            }
        }

        emit CreateSwapper({
            owner: owner_,
            beneficiary: beneficiary_,
            paused: paused_,
            tokenToBeneficiary: tokenToBeneficiary_,
            defaultScaledOfferFactor: defaultScaledOfferFactor_,
            defaultPeriod: defaultPeriod_,
            poolOverrideParams: poolOverrideParams
        });
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
    /// @dev 0x0 used for ETH
    function setTokenToBeneficiary(address tokenToBeneficiary_) external onlyOwner {
        tokenToBeneficiary = tokenToBeneficiary_;

        emit SetTokenToBeneficiary(tokenToBeneficiary_);
    }

    /// set default offer discount / premium
    /// @dev PERCENTAGE_SCALE = 1e6 = 100% = no discount / premium
    function setDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor_) external onlyOwner {
        defaultScaledOfferFactor = defaultScaledOfferFactor_;

        emit SetDefaultScaledOfferFactor(defaultScaledOfferFactor_);
    }

    /// set default twap period
    /// @dev if zero, directSwap will revert (unless pool overridden w non-zero period)
    function setDefaultPeriod(uint32 defaultPeriod_) external onlyOwner {
        defaultPeriod = defaultPeriod_;

        emit SetDefaultPeriod(defaultPeriod_);
    }

    /// set pool overrides
    function setPoolOverrides(SetPoolOverrideParams[] params) external onlyOwner {
        for (uint256 i; i < params.length;) {
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
        for (uint256 i; i < length;) {
            Call calli = calls[i];
            if (calli.delegate) {
                (success, returnData[i]) = calli.target.delegatecall(calli.callData);
            } else {
                (success, returnData[i]) = calli.target.call{value: calli.value}(calli.callData);
            }
            require(success, string(returnData[i]));

            unchecked {
                ++i;
            }
        }

        // TODO
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

    /// allows third parties to wrap eth balance if tokenToBeneficiary is not eth
    function wrapETH() external payable {
        if (paused) revert Paused();
        if (tokenToBeneficiary == ETH_ADDRESS) revert Invalid_TokenToBeneficiary();

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) weth9.deposit{value: ethBalance}();
    }

    /// allows third parties to unwrap weth balance if tokenToBeneficiary is not weth
    function unwrapETH() external payable {
        if (paused) revert Paused();
        if (tokenToBeneficiary == weth9) revert Invalid_TokenToBeneficiary();

        uint256 wethBalance = weth9.balanceOf(address(this));
        if (wethBalance > 0) weth9.withdraw(wethBalance);
    }

    /// incentivizes third parties to forward tokenToBeneficiary to beneficiary
    function forward(address feeRecipient) external payable {
        if (paused) revert Paused();

        address _tokenToBeneficiary = tokenToBeneficiary;
        (,, uint32 scaledOfferFactor) = getPoolOverrides(_tokenToBeneficiary, tokenToBeneficiary);
        if (scaledOfferFactor == 0) {
            scaledOfferFactor = defaultScaledOfferFactor;
        }

        bool ethToBeneficiary = (_tokenToBeneficiary == ETH_ADDRESS);
        uint256 unscaledAmountToBeneficiary =
            ethToBeneficiary ? address(this).balance : ERC20(_tokenToBeneficiary).balanceOf(address(this));
        uint256 amountToBeneficiary = unscaledAmountToBeneficiary * scaledOfferFactor / PERCENTAGE_SCALE;
        // reverts if scaledOfferFactor > PERCENTAGE_SCALE
        uint256 amountToForwarder = unscaledAmountToBeneficiary - amountToBeneficiary;

        if (ethToBeneficiary) {
            beneficiary.safeTransferETH(amountToBeneficiary);
            feeRecipient.safeTransferETH(amountToForwarder);
        } else {
            _tokenToBeneficiary.safeTransfer(beneficiary, amountToBeneficiary);
            _tokenToBeneficiary.safeTransfer(feeRecipient, amountToForwarder);
        }

        emit Forward(feeRecipient, amountToForwarder, _tokenToBeneficiary, amountToBeneficiary);
    }

    /// incentivizes third parties to withdraw tokenToTrader in return for sending tokenToBeneficiary to beneficiary
    function directSwap(address tokenToTrader, uint128 amountToTrader) external payable {
        if (paused) revert Paused();

        address _tokenToBeneficiary = tokenToBeneficiary;
        uint256 amountToBeneficiary = _getAmountToBeneficiary(_tokenToBeneficiary, tokenToTrader, amountToTrader);

        uint256 excessToBeneficiary;
        bool ethToBeneficiary = _tokenToBeneficiary == ETH_ADDRESS;
        if (ethToBeneficiary) {
            if (msg.value < amountToBeneficiary) {
                revert InsufficientFunds_FromTrader();
            }
            uint256 traderRefund = msg.value - amountToBeneficiary;

            // flush eth from trader & excess eth in contract to beneficiary
            uint256 ethBalance = address(this).balance;
            uint256 totalToBeneficiary = ethBalance - traderRefund;
            beneficiary.safeTransferETH(totalToBeneficiary);
            excessToBeneficiary = ethBalance - msg.value;

            // refund trader excess value
            if (traderRefund > 0) {
                // funds already sent to beneficiary; no re-entrancy risk
                msg.sender.safeTransferETH(traderRefund);
            }
        } else {
            address _beneficiary = beneficiary;
            _tokenToBeneficiary.safeTransferFrom(msg.sender, _beneficiary, amountToBeneficiary);

            // flush excess tokenToBeneficiary to beneficiary
            excessToBeneficiary = ERC20(tokenToBeneficiary).balanceOf(address(this));
            if (excessToBeneficiary > 0) {
                tokenToBeneficiary.safeTransfer(_beneficiary, excessToBeneficiary);
            }
        }

        bool ethToTrader = tokenToTrader == ETH_ADDRESS;
        if (ethToTrader) {
            msg.sender.safeTransferETH(amountToTrader);
        } else {
            tokenToTrader.safeTransfer(msg.sender, amountToTrader);
        }

        emit DirectSwap(
            msg.sender, tokenToTrader, amountToTrader, _tokenToBeneficiary, amountToBeneficiary, excessToBeneficiary
        );
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - views
    /// -----------------------------------------------------------------------

    /// get pool overrides
    function getPoolOverrides(address tokenA, address tokenB) public view returns (PoolOverride) {
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
        pure
        returns (address token0, address token1)
    {
        token0 = (tokenA == ETH_ADDRESS) ? weth9 : tokenA;
        token1 = (tokenB == ETH_ADDRESS) ? weth9 : tokenB;
        if (token0 > token1) (token0, token1) = (token1, token0);
    }

    /// get amount to beneficiary for a particular trade
    function _getAmountToBeneficiary(address _tokenToBeneficiary, address tokenToTrader, uint128 amountToTrader)
        internal
        view
        returns (uint256)
    {
        (address token0, address token1) = _getPoolOverrideParamHelper(_tokenToBeneficiary, tokenToTrader);
        (uint24 fee, uint32 period, uint32 scaledOfferFactor) = _poolOverrides[token0][token1];
        if (fee == 0) {
            fee = DEFAULT_FEE;
        }
        if (period == 0) {
            period = defaultPeriod;
        }
        if (scaledOfferFactor == 0) {
            scaledOfferFactor = defaultScaledOfferFactor;
        }

        address pool = uniswapV3Factory.getPool(token0, token1, fee);
        if (pool == address(0)) {
            revert Pool_DoesNotExist();
        }

        // reverts if period is zero or > oldest observation
        (int24 arithmeticMeanTick,) = OracleLibrary.consult({pool: pool, period: period});

        bool ethToTrader = tokenToTrader == ETH_ADDRESS;
        uint256 amountInContract = ethToTrader ? address(this).balance : ERC20(tokenToTrader).balanceOf(address(this));
        if (amountToTrader > amountInContract) {
            revert InsufficientFunds_InContract();
        }

        uint256 unscaledAmountToBeneficiary = OracleLibrary.getQuoteAtTick({
            tick: arithmeticMeanTick,
            baseAmount: amountToTrader,
            baseToken: tokenToTrader,
            quoteToken: _tokenToBeneficiary
        });

        return unscaledAmountToBeneficiary * scaledOfferFactor / PERCENTAGE_SCALE;
    }
}
