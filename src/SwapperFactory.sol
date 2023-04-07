// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {OracleImpl} from "splits-oracle/OracleImpl.sol";
import {LibClone} from "splits-utils/LibClone.sol";

import {SwapperImpl} from "./SwapperImpl.sol";

/// @title Swapper Factory
/// @author 0xSplits
/// @notice Factory for creating & validating Swappers
/// @dev This contract uses token = address(0) to refer to ETH.
contract SwapperFactory {
    using LibClone for address;

    event CreateSwapper(SwapperImpl indexed swapper, CreateSwapperParams params);

    struct CreateSwapperParams {
        address owner;
        bool paused;
        address beneficiary;
        address tokenToBeneficiary;
        OracleParams oracleParams;
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

    function createSwapper(CreateSwapperParams calldata params_) external returns (SwapperImpl swapper) {
        OracleImpl oracle = params_.oracleParams._parseIntoOracle();

        swapper = SwapperImpl(payable(address(swapperImpl).clone()));
        swapper.initializer(
            SwapperImpl.InitParams({
                owner: params_.owner,
                paused: params_.paused,
                beneficiary: params_.beneficiary,
                tokenToBeneficiary: params_.tokenToBeneficiary,
                oracle: oracle
            })
        );
        $isSwapper[swapper] = true;

        emit CreateSwapper({swapper: swapper, params: params_});
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - view
    /// -----------------------------------------------------------------------

    function isSwapper(SwapperImpl swapper) external view returns (bool) {
        return $isSwapper[swapper];
    }
}
