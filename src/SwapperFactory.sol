// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

import {Swapper} from "./Swapper.sol";

/// @title SwapperFactory
/// @author 0xSplits
/// @notice Factory for creating & validating Swappers
/// @dev This contract uses token = address(0) to refer to ETH.
contract SwapperFactory {
    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct CreateSwapperParams {
        address owner;
        address beneficiary;
        bool paused;
        address tokenToBeneficiary;
        uint24 defaultFee;
        uint32 defaultPeriod;
        uint32 defaultScaledOfferFactor;
        Swapper.SetPoolOverrideParams[] poolOverrideParams;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateSwapper(Swapper indexed swapper, CreateSwapperParams params);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    IUniswapV3Factory public immutable uniswapV3Factory;
    address public immutable weth9;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// mapping of canonical swappers for flash callback validation
    mapping(Swapper => bool) public isSwapper;

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

    function createSwapper(CreateSwapperParams calldata params) external returns (Swapper swapper) {
        swapper = new Swapper({
            uniswapV3Factory_: uniswapV3Factory,
            weth9_: weth9,
            owner_: params.owner,
            beneficiary_: params.beneficiary,
            paused_: params.paused,
            tokenToBeneficiary_: params.tokenToBeneficiary,
            defaultFee_: params.defaultFee,
            defaultPeriod_: params.defaultPeriod,
            defaultScaledOfferFactor_: params.defaultScaledOfferFactor,
            poolOverrideParams: params.poolOverrideParams
        });

        isSwapper[swapper] = true;

        emit CreateSwapper({swapper: swapper, params: params});
    }
}
