// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {FeedRegistryInterface} from "chainlink/interfaces/FeedRegistryInterface.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {IOracleFactory} from "src/interfaces/IOracleFactory.sol";
import {ChainlinkOracleImpl} from "src/oracles/ChainlinkOracleImpl.sol";

/// @title Chainlink Oracle Factory
/// @author 0xSplits
/// @notice Factory for creating chainlink oracles
contract ChainlinkOracleFactory is IOracleFactory {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using LibClone for address;

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateOracle(
        ChainlinkOracleImpl indexed oracle,
        address owner,
        uint32 defaultStaleAfter,
        uint32 defaultScaledOfferFactor,
        ChainlinkOracleImpl.SetTokenOverrideParams[] toParams,
        ChainlinkOracleImpl.SetPairOverrideParams[] poParams
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    ChainlinkOracleImpl public immutable chainlinkOracleImpl;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(FeedRegistryInterface clFeedRegistry_, address weth9_, address clETH_) {
        chainlinkOracleImpl = new ChainlinkOracleImpl({
            clFeedRegistry_: clFeedRegistry_,
            weth9_: weth9_,
            clETH_: clETH_
        });
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    function createOracle(
        address owner_,
        uint32 defaultStaleAfter_,
        uint32 defaultScaledOfferFactor_,
        ChainlinkOracleImpl.SetTokenOverrideParams[] memory toParams_,
        ChainlinkOracleImpl.SetPairOverrideParams[] memory poParams_
    ) external returns (ChainlinkOracleImpl oracle) {
        oracle = ChainlinkOracleImpl(address(chainlinkOracleImpl).clone());
        oracle.initializer({
            owner_: owner_,
            defaultStaleAfter_: defaultStaleAfter_,
            defaultScaledOfferFactor_: defaultScaledOfferFactor_,
            toParams_: toParams_,
            poParams_: poParams_
        });

        emit CreateOracle({
            oracle: oracle,
            owner: owner_,
            defaultStaleAfter: defaultStaleAfter_,
            defaultScaledOfferFactor: defaultScaledOfferFactor_,
            toParams: toParams_,
            poParams: poParams_
        });
    }

    function createOracle(bytes calldata init_) external returns (IOracle) {
        (
            address owner,
            uint32 defaultStaleAfter,
            uint32 defaultScaledOfferFactor,
            ChainlinkOracleImpl.SetTokenOverrideParams[] memory toParams,
            ChainlinkOracleImpl.SetPairOverrideParams[] memory poParams
        ) = abi.decode(
            init_,
            (
                address,
                uint32,
                uint32,
                ChainlinkOracleImpl.SetTokenOverrideParams[],
                ChainlinkOracleImpl.SetPairOverrideParams[]
            )
        );

        ChainlinkOracleImpl oracle = ChainlinkOracleImpl(address(chainlinkOracleImpl).clone());
        oracle.initializer({
            owner_: owner,
            defaultStaleAfter_: defaultStaleAfter,
            defaultScaledOfferFactor_: defaultScaledOfferFactor,
            toParams_: toParams,
            poParams_: poParams
        });

        emit CreateOracle({
            oracle: oracle,
            owner: owner,
            defaultStaleAfter: defaultStaleAfter,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            toParams: toParams,
            poParams: poParams
        });

        return IOracle(oracle);
    }
}
