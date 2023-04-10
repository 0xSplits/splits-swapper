// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/base.t.sol";

import {CreateOracleParams, IOracleFactory, OracleImpl, OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {IUniswapV3Factory, UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";

import {SwapperFactory} from "../src/SwapperFactory.sol";
import {SwapperImpl} from "../src/SwapperImpl.sol";

// TODO: add fuzz tests

contract SwapperFactoryTest is BaseTest {
    event CreateSwapper(SwapperImpl indexed swapper, SwapperImpl.InitParams params);

    SwapperFactory swapperFactory;
    SwapperImpl swapperImpl;

    SwapperFactory.CreateSwapperParams params;
    SwapperImpl.InitParams swapperInitParams;

    UniV3OracleFactory oracleFactory;

    UniV3OracleImpl.SetPairOverrideParams[] pairOverrides;
    CreateOracleParams createOracleParams;
    OracleParams oracleParams;
    OracleImpl oracle;

    function setUp() public virtual override {
        super.setUp();

        // set oracle up
        oracleFactory = new UniV3OracleFactory({
            uniswapV3Factory_: IUniswapV3Factory(UNISWAP_V3_FACTORY),
            weth9_: WETH9
        });

        // TODO: add pair override?

        UniV3OracleImpl.InitParams memory initOracleParams = _initOracleParams();

        createOracleParams =
            CreateOracleParams({factory: IOracleFactory(address(oracleFactory)), data: abi.encode(initOracleParams)});
        oracleParams.createOracleParams = createOracleParams;

        oracle = oracleFactory.createUniV3Oracle(initOracleParams);
        oracleParams.oracle = oracle;

        // set swapper up
        swapperFactory = new SwapperFactory();
        swapperImpl = swapperFactory.swapperImpl();

        params = SwapperFactory.CreateSwapperParams({
            owner: users.alice,
            paused: false,
            beneficiary: users.bob,
            tokenToBeneficiary: ETH_ADDRESS,
            oracleParams: oracleParams
        });

        swapperInitParams = SwapperImpl.InitParams({
            owner: users.alice,
            paused: false,
            beneficiary: users.bob,
            tokenToBeneficiary: ETH_ADDRESS,
            oracle: oracle
        });
    }

    /// -----------------------------------------------------------------------
    /// tests - basic
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// tests - basic - createSwapper
    /// -----------------------------------------------------------------------

    function test_createSwapper_callsInitializer() public {
        vm.expectCall({
            callee: address(swapperImpl),
            msgValue: 0 ether,
            data: abi.encodeCall(
                SwapperImpl.initializer,
                (
                    SwapperImpl.InitParams({
                        owner: users.alice,
                        paused: false,
                        beneficiary: users.bob,
                        tokenToBeneficiary: ETH_ADDRESS,
                        oracle: oracle
                    })
                )
                )
        });
        swapperFactory.createSwapper(params);
    }

    function test_createSwapper_emitsCreateSwapper() public {
        SwapperImpl expectedSwapper = SwapperImpl(_predictNextAddressFrom(address(swapperFactory)));
        _expectEmit();
        emit CreateSwapper(expectedSwapper, swapperInitParams);
        swapperFactory.createSwapper(params);
    }

    function test_createSwapper_createsOracleIfNotProvidedOne() public {
        params.oracleParams.oracle = OracleImpl(ADDRESS_ZERO);
        vm.expectCall({
            callee: address(oracleFactory),
            msgValue: 0 ether,
            data: abi.encodeCall(IOracleFactory.createOracle, abi.encode(_initOracleParams()))
        });
        swapperFactory.createSwapper(params);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - isSwapper
    /// -----------------------------------------------------------------------

    function test_isSwapper() public {
        SwapperImpl expectedSwapper = SwapperImpl(_predictNextAddressFrom(address(swapperFactory)));
        assertFalse(swapperFactory.isSwapper(expectedSwapper));
        swapperFactory.createSwapper(params);
        assertTrue(swapperFactory.isSwapper(expectedSwapper));
    }

    /// -----------------------------------------------------------------------
    /// internal
    /// -----------------------------------------------------------------------

    /// @dev can't be init'd in setUp & saved to storage bc of nested dynamic array solc error
    /// UnimplementedFeatureError: Copying of type struct UniV3OracleImpl.SetPairOverrideParams memory[] memory to storage not yet supported.
    function _initOracleParams() internal view returns (UniV3OracleImpl.InitParams memory) {
        return UniV3OracleImpl.InitParams({
            owner: users.alice,
            defaultFee: 30_00, // = 0.3%
            defaultPeriod: 30 minutes,
            defaultScaledOfferFactor: PERCENTAGE_SCALE,
            pairOverrides: pairOverrides
        });
    }
}
