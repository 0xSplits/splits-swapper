// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {IOracleFactory} from "src/interfaces/IOracleFactory.sol";
import {Swapper} from "src/Swapper.sol";

/// @title SwapperFactory
/// @author 0xSplits
/// @notice Factory for creating & validating Swappers
/// @dev This contract uses token = address(0) to refer to ETH.
contract SwapperFactory {
    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateSwapper(
        Swapper indexed swapper,
        address owner,
        bool paused,
        address beneficiary,
        address tokenToBeneficiary,
        IOracle oracle
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// mapping of canonical swappers for flash callback validation
    mapping(Swapper => bool) public $isSwapper;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor() {}

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    function createSwapper(
        address owner_,
        bool paused_,
        address beneficiary_,
        address tokenToBeneficiary_,
        IOracle oracle_
    ) external returns (Swapper swapper) {
        swapper = new Swapper({
            owner_: owner_,
            paused_: paused_,
            beneficiary_: beneficiary_,
            tokenToBeneficiary_: tokenToBeneficiary_,
            oracle_: oracle_
        });

        $isSwapper[swapper] = true;

        emit CreateSwapper({
            swapper: swapper,
            owner: owner_,
            paused: paused_,
            beneficiary: beneficiary_,
            tokenToBeneficiary: tokenToBeneficiary_,
            oracle: oracle_
        });
    }

    function createOracleAndSwapper(
        address owner_,
        bool paused_,
        address beneficiary_,
        address tokenToBeneficiary_,
        IOracleFactory oracleFactory_,
        bytes calldata oracleInit_
    ) external returns (Swapper swapper) {
        IOracle oracle = oracleFactory_.createOracle(oracleInit_);

        swapper = new Swapper({
            owner_: owner_,
            paused_: paused_,
            beneficiary_: beneficiary_,
            tokenToBeneficiary_: tokenToBeneficiary_,
            oracle_: oracle
            });

        $isSwapper[swapper] = true;

        emit CreateSwapper({
            swapper: swapper,
            owner: owner_,
            paused: paused_,
            beneficiary: beneficiary_,
            tokenToBeneficiary: tokenToBeneficiary_,
            oracle: oracle
        });
    }
}
