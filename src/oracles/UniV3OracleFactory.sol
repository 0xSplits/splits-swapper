// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {IOracleFactory} from "src/interfaces/IOracleFactory.sol";
import {UniV3OracleImpl} from "src/oracles/UniV3OracleImpl.sol";

/// @title UniV3 Oracle Factory
/// @author 0xSplits
/// @notice Factory for creating uniV3 oracles
contract UniV3OracleFactory is IOracleFactory {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using LibClone for address;

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event CreateOracle(
        UniV3OracleImpl indexed oracle,
        address owner,
        uint24 defaultFee,
        uint32 defaultPeriod,
        uint32 defaultScaledOfferFactor,
        UniV3OracleImpl.SetPairOverrideParams[] poParams
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    UniV3OracleImpl public immutable uniV3OracleImpl;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(IUniswapV3Factory uniswapV3Factory_, address weth9_) {
        uniV3OracleImpl = new UniV3OracleImpl({
            uniswapV3Factory_: uniswapV3Factory_,
            weth9_: weth9_
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
        uint24 defaultFee_,
        uint32 defaultPeriod_,
        uint32 defaultScaledOfferFactor_,
        UniV3OracleImpl.SetPairOverrideParams[] memory poParams_
    ) external returns (UniV3OracleImpl oracle) {
        oracle = UniV3OracleImpl(address(uniV3OracleImpl).clone());
        oracle.initializer({
            owner_: owner_,
            defaultFee_: defaultFee_,
            defaultPeriod_: defaultPeriod_,
            defaultScaledOfferFactor_: defaultScaledOfferFactor_,
            poParams_: poParams_
        });

        emit CreateOracle({
            oracle: oracle,
            owner: owner_,
            defaultFee: defaultFee_,
            defaultPeriod: defaultPeriod_,
            defaultScaledOfferFactor: defaultScaledOfferFactor_,
            poParams: poParams_
        });
    }

    function createOracle(bytes calldata init_) external returns (IOracle) {
        (
            address owner,
            uint24 defaultFee,
            uint32 defaultPeriod,
            uint32 defaultScaledOfferFactor,
            UniV3OracleImpl.SetPairOverrideParams[] memory poParams
        ) = abi.decode(init_, (address, uint24, uint32, uint32, UniV3OracleImpl.SetPairOverrideParams[]));

        UniV3OracleImpl oracle = UniV3OracleImpl(address(uniV3OracleImpl).clone());
        oracle.initializer({
            owner_: owner,
            defaultFee_: defaultFee,
            defaultPeriod_: defaultPeriod,
            defaultScaledOfferFactor_: defaultScaledOfferFactor,
            poParams_: poParams
        });

        emit CreateOracle({
            oracle: oracle,
            owner: owner,
            defaultFee: defaultFee,
            defaultPeriod: defaultPeriod,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            poParams: poParams
        });

        return IOracle(oracle);
    }
}
