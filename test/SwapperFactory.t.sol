// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/Base.t.sol";
import {LibCloneBase} from "splits-tests/LibClone.t.sol";

import {CreateOracleParams, IOracleFactory, IOracle, OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {IUniswapV3Factory, UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {QuotePair} from "splits-utils/QuotePair.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";

import {SwapperFactory} from "../src/SwapperFactory.sol";
import {SwapperImpl} from "../src/SwapperImpl.sol";

// TODO: add fuzz tests

contract SwapperFactoryTest is BaseTest, LibCloneBase {
    event CreateSwapper(SwapperImpl indexed swapper, SwapperImpl.InitParams initSwapperParams);

    SwapperFactory swapperFactory;
    SwapperImpl swapperImpl;

    address beneficiary;
    address owner;
    bool paused;
    address tokenToBeneficiary;
    uint32 defaultScaledOfferFactor;
    SwapperImpl.SetPairOverrideParams[] pairOverrides;

    UniV3OracleFactory oracleFactory;

    uint24 defaultFee;
    uint32 defaultPeriod;
    UniV3OracleImpl.SetPairOverrideParams[] oraclePairOverrides;
    CreateOracleParams createOracleParams;
    OracleParams oracleParams;
    IOracle oracle;

    function setUp() public virtual override(BaseTest, LibCloneBase) {
        BaseTest.setUp();

        owner = users.alice;
        beneficiary = users.bob;
        paused = false;
        tokenToBeneficiary = ETH_ADDRESS;
        defaultScaledOfferFactor = 99_00_00;

        pairOverrides.push(
            SwapperImpl.SetPairOverrideParams({
                quotePair: QuotePair({base: WETH9, quote: ETH_ADDRESS}),
                pairOverride: SwapperImpl.PairOverride({
                    scaledOfferFactor: PERCENTAGE_SCALE // no discount
                })
            })
        );

        // set oracle up
        oracleFactory = new UniV3OracleFactory({
            uniswapV3Factory_: IUniswapV3Factory(UNISWAP_V3_FACTORY),
            weth9_: WETH9
        });

        // TODO: add pair override?

        defaultFee = 30_00; // = 0.3%
        defaultPeriod = 30 minutes;

        UniV3OracleImpl.InitParams memory initOracleParams = _initOracleParams();

        createOracleParams =
            CreateOracleParams({factory: IOracleFactory(address(oracleFactory)), data: abi.encode(initOracleParams)});
        oracleParams.createOracleParams = createOracleParams;

        oracle = oracleFactory.createUniV3Oracle(initOracleParams);
        oracleParams.oracle = oracle;

        // set swapper up
        swapperFactory = new SwapperFactory(IWETH9(WETH9));
        swapperImpl = swapperFactory.swapperImpl();

        // setup LibCloneBase
        impl = address(swapperImpl);
        clone = address(swapperFactory.createSwapper(_createSwapperParams()));
        amount = 1 ether;
        data = "Hello, World!";
    }

    function _createSwapperParams() internal view returns (SwapperFactory.CreateSwapperParams memory) {
        return SwapperFactory.CreateSwapperParams({
            owner: owner,
            paused: paused,
            beneficiary: beneficiary,
            tokenToBeneficiary: tokenToBeneficiary,
            oracleParams: oracleParams,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            pairOverrides: pairOverrides
        });
    }

    function _initSwapperParams() internal view returns (SwapperImpl.InitParams memory) {
        return SwapperImpl.InitParams({
            owner: owner,
            paused: paused,
            beneficiary: beneficiary,
            tokenToBeneficiary: tokenToBeneficiary,
            oracle: oracle,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            pairOverrides: pairOverrides
        });
    }

    function _initOracleParams() internal view returns (UniV3OracleImpl.InitParams memory) {
        return UniV3OracleImpl.InitParams({
            owner: owner,
            paused: paused,
            defaultFee: defaultFee,
            defaultPeriod: defaultPeriod,
            pairOverrides: oraclePairOverrides
        });
    }

    /// -----------------------------------------------------------------------
    /// createSwapper
    /// -----------------------------------------------------------------------

    function test_createSwapper_callsInitializer() public {
        vm.expectCall({
            callee: address(swapperImpl),
            msgValue: 0 ether,
            data: abi.encodeCall(SwapperImpl.initializer, (_initSwapperParams()))
        });
        swapperFactory.createSwapper(_createSwapperParams());
    }

    function test_createSwapper_emitsCreateSwapper() public {
        SwapperImpl expectedSwapper = SwapperImpl(_predictNextAddressFrom(address(swapperFactory)));
        _expectEmit();
        emit CreateSwapper(expectedSwapper, _initSwapperParams());
        swapperFactory.createSwapper(_createSwapperParams());
    }

    function test_createSwapper_createsOracleIfNotProvidedOne() public {
        SwapperFactory.CreateSwapperParams memory createSwapperParams = _createSwapperParams();

        createSwapperParams.oracleParams.oracle = IOracle(ADDRESS_ZERO);
        vm.expectCall({
            callee: address(oracleFactory),
            msgValue: 0 ether,
            data: abi.encodeCall(IOracleFactory.createOracle, abi.encode(_initOracleParams()))
        });
        swapperFactory.createSwapper(createSwapperParams);
    }

    function testFuzz_createSwapper_createsClone_code(
        SwapperFactory.CreateSwapperParams calldata createSwapperParams_,
        address newOracle_
    ) public {
        vm.mockCall({
            callee: address(createSwapperParams_.oracleParams.createOracleParams.factory),
            msgValue: 0,
            data: abi.encodeCall(IOracleFactory.createOracle, (createSwapperParams_.oracleParams.createOracleParams.data)),
            returnData: abi.encode(newOracle_)
        });
        clone = address(swapperFactory.createSwapper(createSwapperParams_));

        test_clone_code();
    }

    function testFuzz_createSwapper_createsClone_canReceiveETH(
        SwapperFactory.CreateSwapperParams calldata createSwapperParams_,
        address newOracle_,
        uint96 amount_
    ) public {
        vm.mockCall({
            callee: address(createSwapperParams_.oracleParams.createOracleParams.factory),
            msgValue: 0,
            data: abi.encodeCall(IOracleFactory.createOracle, (createSwapperParams_.oracleParams.createOracleParams.data)),
            returnData: abi.encode(newOracle_)
        });
        clone = address(swapperFactory.createSwapper(createSwapperParams_));
        amount = amount_;

        test_clone_canReceiveETH();
    }

    function testFuzz_createSwapper_createsClone_emitsReceiveETH(
        SwapperFactory.CreateSwapperParams calldata createSwapperParams_,
        address newOracle_,
        uint96 amount_
    ) public {
        vm.mockCall({
            callee: address(createSwapperParams_.oracleParams.createOracleParams.factory),
            msgValue: 0,
            data: abi.encodeCall(IOracleFactory.createOracle, (createSwapperParams_.oracleParams.createOracleParams.data)),
            returnData: abi.encode(newOracle_)
        });
        clone = address(swapperFactory.createSwapper(createSwapperParams_));
        amount = amount_;

        test_clone_emitsReceiveETH();
    }

    function testFuzz_createSwapper_createsClone_canDelegateCall(
        SwapperFactory.CreateSwapperParams calldata createSwapperParams_,
        address newOracle_,
        bytes calldata data_
    ) public {
        vm.assume(data_.length > 0);

        vm.mockCall({
            callee: address(createSwapperParams_.oracleParams.createOracleParams.factory),
            msgValue: 0,
            data: abi.encodeCall(IOracleFactory.createOracle, (createSwapperParams_.oracleParams.createOracleParams.data)),
            returnData: abi.encode(newOracle_)
        });
        clone = address(swapperFactory.createSwapper(createSwapperParams_));
        data = data_;

        test_clone_canDelegateCall();
    }

    /// -----------------------------------------------------------------------
    /// isSwapper
    /// -----------------------------------------------------------------------

    function test_isSwapper() public {
        SwapperImpl expectedSwapper = SwapperImpl(_predictNextAddressFrom(address(swapperFactory)));
        assertFalse(swapperFactory.isSwapper(expectedSwapper));
        swapperFactory.createSwapper(_createSwapperParams());
        assertTrue(swapperFactory.isSwapper(expectedSwapper));
    }
}
