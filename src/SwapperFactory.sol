// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {CreateOracleParams, IOracleFactory} from "splits-oracle/interfaces/IOracleFactory.sol";
import {OracleImpl} from "splits-oracle/OracleImpl.sol";
import {LibClone} from "splits-utils/LibClone.sol";

import {SwapperImpl} from "./SwapperImpl.sol";

// TODO: re-visit params / creating swapper+oracle
// harmonize w diversifier factory

/// @title Swapper Factory
/// @author 0xSplits
/// @notice Factory for creating & validating Swappers
/// @dev This contract uses token = address(0) to refer to ETH.
contract SwapperFactory {
    using LibClone for address;

    event CreateSwapper(SwapperImpl indexed swapper, SwapperImpl.InitParams params);

    struct CreateOracleAndSwapperParams {
        CreateOracleParams createOracle;
        SwapperImpl.InitParams initSwapper;
    }

    SwapperImpl public immutable swapperImpl;

    /// mapping of canonical swappers for flash callback validation
    mapping(SwapperImpl => bool) internal $isSwapper;

    constructor() {
        swapperImpl = new SwapperImpl();
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    function createSwapper(SwapperImpl.InitParams calldata params_) external returns (SwapperImpl) {
        return _createSwapper(params_);
    }

    /// @dev params_.initSwapper.oracle is overridden by newly created oracle
    function createOracleAndSwapper(CreateOracleAndSwapperParams calldata params_) external returns (SwapperImpl) {
        OracleImpl oracle = params_.createOracle.factory.createOracle(params_.createOracle.data);

        SwapperImpl.InitParams memory initSwapper = params_.initSwapper;
        initSwapper.oracle = oracle;
        return _createSwapper(initSwapper);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - view
    /// -----------------------------------------------------------------------

    function isSwapper(SwapperImpl swapper) external view returns (bool) {
        return $isSwapper[swapper];
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    function _createSwapper(SwapperImpl.InitParams memory params_) internal returns (SwapperImpl swapper) {
        swapper = SwapperImpl(payable(address(swapperImpl).clone()));
        swapper.initializer(params_);

        $isSwapper[swapper] = true;

        emit CreateSwapper({swapper: swapper, params: params_});
    }
}
