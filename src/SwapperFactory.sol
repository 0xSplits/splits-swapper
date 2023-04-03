// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {LibClone} from "splits-utils/LibClone.sol";
import {IOracle, IOracleFactory} from "splits-oracle/interfaces/IOracleFactory.sol";

import {SwapperImpl} from "src/SwapperImpl.sol";

/// @title Swapper Factory
/// @author 0xSplits
/// @notice Factory for creating & validating Swappers
/// @dev This contract uses token = address(0) to refer to ETH.
contract SwapperFactory {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using LibClone for address;

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateSwapper(SwapperImpl indexed swapper, SwapperImpl.InitParams params);

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct CreateOracleAndSwapperParams {
        CreateOracleParams createOracle;
        SwapperImpl.InitParams initSwapper;
    }

    struct CreateOracleParams {
        IOracleFactory factory;
        bytes data;
    }

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    SwapperImpl public immutable swapperImpl;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// mapping of canonical swappers for flash callback validation
    mapping(SwapperImpl => bool) public $isSwapper;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor() {
        swapperImpl = new SwapperImpl();
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    function createSwapper(SwapperImpl.InitParams calldata params_) external returns (SwapperImpl) {
        return _createSwapper(params_);
    }

    /// @dev params_.initSwapper.oracle is overridden by newly created oracle
    function createOracleAndSwapper(CreateOracleAndSwapperParams calldata params_) external returns (SwapperImpl) {
        IOracle oracle = params_.createOracle.factory.createOracle(params_.createOracle.data);

        SwapperImpl.InitParams memory initSwapper = params_.initSwapper;
        initSwapper.oracle = oracle;
        return _createSwapper(initSwapper);
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
