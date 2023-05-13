// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/Base.t.sol";
import {LibCloneBase} from "splits-tests/LibClone.t.sol";

import {CreateOracleParams, IOracleFactory, IOracle, OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {QuotePair} from "splits-utils/LibQuotes.sol";
import {UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";

import {SwapperFactory} from "../src/SwapperFactory.sol";
import {SwapperImpl} from "../src/SwapperImpl.sol";

contract SwapperFactoryTest is BaseTest, LibCloneBase {
    event CreateSwapper(SwapperImpl indexed swapper, SwapperImpl.InitParams initSwapperParams);

    UniV3OracleFactory $oracleFactory;

    SwapperFactory $swapperFactory;
    SwapperImpl $swapperImpl;

    address $owner;
    bool $paused;
    uint32 $defaultPeriod;

    QuotePair $wethETH;
    QuotePair $usdcETH;

    UniV3OracleImpl.SetPairDetailParams[] $oraclePairDetails;
    OracleParams $oracleParams;
    IOracle $oracle;

    address $beneficiary;
    address $tokenToBeneficiary;
    uint32 $defaultScaledOfferFactor;
    SwapperImpl.SetPairScaledOfferFactorParams[] $pairScaledOfferFactors;

    function setUp() public virtual override(BaseTest, LibCloneBase) {
        BaseTest.setUp();

        $oracleFactory = new UniV3OracleFactory({
            weth9_: WETH9
            });
        $swapperFactory = new SwapperFactory();
        $swapperImpl = $swapperFactory.swapperImpl();

        $owner = users.alice;
        $paused = false;
        $defaultPeriod = 30 minutes;

        $wethETH = QuotePair({base: WETH9, quote: ETH_ADDRESS});
        $usdcETH = QuotePair({base: USDC, quote: ETH_ADDRESS});

        $oraclePairDetails.push(
            UniV3OracleImpl.SetPairDetailParams({
                quotePair: $usdcETH,
                pairDetail: UniV3OracleImpl.PairDetail({
                    pool: users.eve, // fake pool fine here
                    period: 0 // no override
                })
            })
        );

        $beneficiary = users.bob;
        $tokenToBeneficiary = ETH_ADDRESS;
        $defaultScaledOfferFactor = 99_00_00;

        $pairScaledOfferFactors.push(
            SwapperImpl.SetPairScaledOfferFactorParams({
                quotePair: $wethETH,
                scaledOfferFactor: PERCENTAGE_SCALE // no discount
            })
        );

        UniV3OracleImpl.InitParams memory initOracleParams = _initOracleParams();
        $oracleParams.createOracleParams =
            CreateOracleParams({factory: IOracleFactory(address($oracleFactory)), data: abi.encode(initOracleParams)});

        $oracle = $oracleFactory.createUniV3Oracle(initOracleParams);
        $oracleParams.oracle = $oracle;

        // setup LibCloneBase
        impl = address($swapperImpl);
        clone = address($swapperFactory.createSwapper(_createSwapperParams()));
        amount = 1 ether;
        data = "Hello, World!";
    }

    function _setUpSwapperState(SwapperImpl.InitParams memory params_) internal virtual {
        $owner = params_.owner;
        $paused = params_.paused;
        $beneficiary = params_.beneficiary;
        $tokenToBeneficiary = params_.tokenToBeneficiary;
        $oracle = params_.oracle;
        $oracleParams.oracle = params_.oracle;
        $defaultScaledOfferFactor = params_.defaultScaledOfferFactor;

        delete $pairScaledOfferFactors;
        for (uint256 i = 0; i < params_.pairScaledOfferFactors.length; i++) {
            $pairScaledOfferFactors.push(params_.pairScaledOfferFactors[i]);
        }
    }

    function _createSwapperParams() internal view returns (SwapperFactory.CreateSwapperParams memory) {
        return SwapperFactory.CreateSwapperParams({
            owner: $owner,
            paused: $paused,
            beneficiary: $beneficiary,
            tokenToBeneficiary: $tokenToBeneficiary,
            oracleParams: $oracleParams,
            defaultScaledOfferFactor: $defaultScaledOfferFactor,
            pairScaledOfferFactors: $pairScaledOfferFactors
        });
    }

    function _initSwapperParams() internal view returns (SwapperImpl.InitParams memory) {
        return SwapperImpl.InitParams({
            owner: $owner,
            paused: $paused,
            beneficiary: $beneficiary,
            tokenToBeneficiary: $tokenToBeneficiary,
            oracle: $oracle,
            defaultScaledOfferFactor: $defaultScaledOfferFactor,
            pairScaledOfferFactors: $pairScaledOfferFactors
        });
    }

    function _initOracleParams() internal view returns (UniV3OracleImpl.InitParams memory) {
        return UniV3OracleImpl.InitParams({
            owner: $owner,
            paused: $paused,
            defaultPeriod: $defaultPeriod,
            pairDetails: $oraclePairDetails
        });
    }

    /// -----------------------------------------------------------------------
    /// createSwapper
    /// -----------------------------------------------------------------------

    function test_createSwapper_callsInitializer() public {
        vm.expectCall({
            callee: address($swapperImpl),
            msgValue: 0 ether,
            data: abi.encodeCall(SwapperImpl.initializer, (_initSwapperParams()))
        });
        $swapperFactory.createSwapper(_createSwapperParams());
    }

    function testFuzz_createSwapper_callsInitializer(SwapperImpl.InitParams calldata initSwapperParams_) public {
        _setUpSwapperState(initSwapperParams_);
        test_createSwapper_callsInitializer();
    }

    function test_createSwapper_emitsCreateSwapper() public {
        SwapperImpl expectedSwapper = SwapperImpl(_predictNextAddressFrom(address($swapperFactory)));
        _expectEmit();
        emit CreateSwapper(expectedSwapper, _initSwapperParams());
        $swapperFactory.createSwapper(_createSwapperParams());
    }

    function testFuzz_createSwapper_emitsCreateSwapper(SwapperImpl.InitParams calldata initSwapperParams_) public {
        _setUpSwapperState(initSwapperParams_);
        test_createSwapper_emitsCreateSwapper();
    }

    function test_createSwapper_createsOracleIfNotProvidedOne() public {
        SwapperFactory.CreateSwapperParams memory createSwapperParams = _createSwapperParams();
        createSwapperParams.oracleParams.oracle = IOracle(ADDRESS_ZERO);

        vm.expectCall({
            callee: address($oracleFactory),
            msgValue: 0 ether,
            data: abi.encodeCall(IOracleFactory.createOracle, abi.encode(_initOracleParams()))
        });
        $swapperFactory.createSwapper(createSwapperParams);
    }

    function testFuzz_createSwapper_createsOracleIfNotProvidedOne() public {
        SwapperFactory.CreateSwapperParams memory createSwapperParams = _createSwapperParams();
        createSwapperParams.oracleParams.oracle = IOracle(ADDRESS_ZERO);

        vm.expectCall({
            callee: address($oracleFactory),
            msgValue: 0 ether,
            data: abi.encodeCall(IOracleFactory.createOracle, abi.encode(_initOracleParams()))
        });
        $swapperFactory.createSwapper(createSwapperParams);
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
        clone = address($swapperFactory.createSwapper(createSwapperParams_));

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
        clone = address($swapperFactory.createSwapper(createSwapperParams_));
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
        clone = address($swapperFactory.createSwapper(createSwapperParams_));
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
        clone = address($swapperFactory.createSwapper(createSwapperParams_));
        data = data_;

        test_clone_canDelegateCall();
    }
}
