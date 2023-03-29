// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {LibClone} from "solady/utils/LibClone.sol";
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

    struct InitOracleAndSwapperParams {
        InitOracleParams initOracle;
        InitSwapperWithoutOracleParams initSwapper;
    }

    struct InitOracleParams {
        IOracleFactory factory;
        bytes data;
    }

    struct InitSwapperWithoutOracleParams {
        address owner;
        bool paused;
        address beneficiary;
        address tokenToBeneficiary;
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

    function createOracleAndSwapper(InitOracleAndSwapperParams calldata params_) external returns (SwapperImpl) {
        IOracle oracle = params_.initOracle.factory.createOracle(params_.initOracle.data);

        SwapperImpl.InitParams memory initSwapper = SwapperImpl.InitParams({
            owner: params_.initSwapper.owner,
            paused: params_.initSwapper.paused,
            beneficiary: params_.initSwapper.beneficiary,
            tokenToBeneficiary: params_.initSwapper.tokenToBeneficiary,
            oracle: oracle
        });
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
