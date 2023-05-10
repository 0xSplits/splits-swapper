// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/Base.t.sol";

import {IUniswapV3Factory, UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {IOracle} from "splits-oracle/interfaces/IOracle.sol";
import {OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {QuotePair, QuoteParams} from "splits-utils/LibQuotes.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";

import {ISwapperFlashCallback} from "../src/interfaces/ISwapperFlashCallback.sol";
import {SwapperFactory} from "../src/SwapperFactory.sol";
import {SwapperImpl} from "../src/SwapperImpl.sol";

// TODO: add test for scaling override ?
// TODO: add flash test for weth-weth
// TODO: add flash test for eth-weth
// TODO: add flash test for eth-eth

// TODO: separate file of tests for integration contract
// TODO: add fuzzing

contract SwapperImplTest is BaseTest {
    using TokenUtils for address;

    error Unauthorized();
    error Paused();
    error Invalid_AmountsToBeneficiary();
    error Invalid_QuoteToken();
    error InsufficientFunds_InContract();
    error InsufficientFunds_FromTrader();

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event SetBeneficiary(address beneficiary);
    event SetTokenToBeneficiary(address tokenToBeneficiaryd);
    event SetOracle(IOracle oracle);
    event SetDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor);
    event SetPairScaledOfferFactors(SwapperImpl.SetPairScaledOfferFactorParams[] params);

    event ReceiveETH(uint256 amount);
    event Payback(address indexed payer, uint256 amount);
    event Flash(
        address indexed trader,
        QuoteParams[] quoteParams,
        address tokenToBeneficiary,
        uint256[] amountsToBeneficiary,
        uint256 excessToBeneficiary
    );

    SwapperFactory swapperFactory;
    SwapperImplHarness swapperImplHarness;
    SwapperImpl swapperImpl;
    SwapperImpl swapper;

    UniV3OracleFactory oracleFactory;
    UniV3OracleImpl.InitParams initOracleParams;
    IOracle oracle;
    OracleParams oracleParams;

    QuoteParams[] ethQuoteParams;
    QuoteParams[] mockERC20QuoteParams;

    uint256[] mockQuoteAmounts;

    QuotePair wethETH;
    QuotePair usdcETH;

    address trader;

    address beneficiary;
    address owner;
    bool paused;
    address tokenToBeneficiary;
    uint32 defaultScaledOfferFactor;
    SwapperImpl.SetPairScaledOfferFactorParams[] setPairScaledOfferFactorParams;

    QuoteParams[] quoteParams;
    QuoteParams qp;
    address base;
    address quote;

    uint256 traderBasePreBalance;
    uint256 swapperBasePreBalance;
    uint256 beneficiaryBasePreBalance;

    uint256 traderQuotePreBalance;
    uint256 swapperQuotePreBalance;
    uint256 beneficiaryQuotePreBalance;

    function setUp() public virtual override {
        super.setUp();

        // set up oracle
        oracleFactory = new UniV3OracleFactory({
            uniswapV3Factory_: IUniswapV3Factory(UNISWAP_V3_FACTORY),
            weth9_: WETH9
        });
        // TODO: add other attributes?
        initOracleParams.owner = users.alice;
        oracle = oracleFactory.createUniV3Oracle(initOracleParams);
        oracleParams.oracle = oracle;

        // set up swapper
        swapperFactory = new SwapperFactory();
        swapperImpl = swapperFactory.swapperImpl();

        owner = users.alice;
        beneficiary = users.bob;
        paused = false;
        tokenToBeneficiary = ETH_ADDRESS;
        defaultScaledOfferFactor = 99_00_00;

        wethETH = QuotePair({base: WETH9, quote: ETH_ADDRESS});
        usdcETH = QuotePair({base: USDC, quote: ETH_ADDRESS});

        setPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({
                quotePair: wethETH,
                scaledOfferFactor: PERCENTAGE_SCALE // no discount
            })
        );

        swapper = swapperFactory.createSwapper(_createSwapperParams());
        _deal({account: address(swapper)});

        swapperImplHarness = new SwapperImplHarness();
        swapperImplHarness.initializer(_initSwapperParams());
        _deal({account: address(swapperImplHarness)});

        ethQuoteParams.push(
            QuoteParams({
                quotePair: QuotePair({base: address(mockERC20), quote: ETH_ADDRESS}),
                baseAmount: 1 ether,
                data: ""
            })
        );
        mockERC20QuoteParams.push(
            QuoteParams({
                quotePair: QuotePair({base: ETH_ADDRESS, quote: address(mockERC20)}),
                baseAmount: 1 ether,
                data: ""
            })
        );

        mockQuoteAmounts.push(1 ether);

        trader = address(new Trader());
        _deal({account: trader});

        quoteParams = ethQuoteParams;
        qp = quoteParams[0];
        base = qp.quotePair.base;
        quote = qp.quotePair.quote;

        traderBasePreBalance = base._balanceOf(trader);
        swapperBasePreBalance = base._balanceOf(address(swapper));
        beneficiaryBasePreBalance = base._balanceOf(beneficiary);

        traderQuotePreBalance = quote._balanceOf(trader);
        swapperQuotePreBalance = quote._balanceOf(address(swapper));
        beneficiaryQuotePreBalance = quote._balanceOf(beneficiary);

        vm.mockCall({
            callee: address(oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, (ethQuoteParams)),
            returnData: abi.encode(mockQuoteAmounts)
        });
        vm.mockCall({
            callee: address(oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, (mockERC20QuoteParams)),
            returnData: abi.encode(mockQuoteAmounts)
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
            pairScaledOfferFactors: setPairScaledOfferFactorParams
        });
    }

    function _createSwapperParams() internal view returns (SwapperFactory.CreateSwapperParams memory) {
        return SwapperFactory.CreateSwapperParams({
            owner: owner,
            paused: paused,
            beneficiary: beneficiary,
            tokenToBeneficiary: tokenToBeneficiary,
            oracleParams: oracleParams,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            pairScaledOfferFactors: setPairScaledOfferFactorParams
        });
    }

    /// -----------------------------------------------------------------------
    /// modifiers
    /// -----------------------------------------------------------------------

    modifier callerFactory() {
        _;
    }

    modifier callerOwner() {
        _;
    }

    modifier unpaused() {
        _;
    }

    /// -----------------------------------------------------------------------
    /// tests - basic
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// tests - basic - initializer
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotFactory_initializer() public {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.expectRevert(Unauthorized.selector);
        swapperImpl.initializer(initSwapperParams);

        vm.expectRevert(Unauthorized.selector);
        swapper.initializer(initSwapperParams);
    }

    function test_initializer_setsOwner() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);
        assertEq(swapper.owner(), initSwapperParams.owner);
    }

    function test_initializer_setsPaused() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);
        assertEq(swapper.paused(), initSwapperParams.paused);
    }

    function test_initializer_setsBeneficiary() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);
        assertEq(swapper.beneficiary(), initSwapperParams.beneficiary);
    }

    function test_initializer_setsTokenToBeneficiary() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);
        assertEq(swapper.tokenToBeneficiary(), initSwapperParams.tokenToBeneficiary);
    }

    function test_initializer_setsDefaultScaledOfferFactor() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);
        assertEq(swapper.defaultScaledOfferFactor(), initSwapperParams.defaultScaledOfferFactor);
    }

    function test_initializer_setsPairScaledOfferFactors() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);

        uint256 length = initSwapperParams.pairScaledOfferFactors.length;
        QuotePair[] memory initQuotePairs = new QuotePair[](length);
        uint32[] memory initScaledOfferFactors = new uint32[](length);
        for (uint256 i; i < length; i++) {
            initQuotePairs[i] = initSwapperParams.pairScaledOfferFactors[i].quotePair;
            initScaledOfferFactors[i] = initSwapperParams.pairScaledOfferFactors[i].scaledOfferFactor;
        }
        assertEq(swapper.getPairScaledOfferFactors(initQuotePairs), initScaledOfferFactors);
    }

    function test_initializer_emitsOwnershipTransferred() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(address(swapperFactory));
        _expectEmit();
        emit OwnershipTransferred(address(0), initSwapperParams.owner);
        swapper.initializer(initSwapperParams);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - setBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setBeneficiary() public {
        vm.expectRevert(Unauthorized.selector);
        swapper.setBeneficiary(users.eve);
    }

    function test_setBeneficiary_setsBeneficiary() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        swapper.setBeneficiary(users.eve);
        assertEq(swapper.beneficiary(), users.eve);
    }

    function test_setBeneficiary_emitsSetBeneficiary() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetBeneficiary(users.eve);
        swapper.setBeneficiary(users.eve);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - setTokenToBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setTokenToBeneficiary() public {
        vm.expectRevert(Unauthorized.selector);
        swapper.setTokenToBeneficiary(users.eve);
    }

    function test_setTokenToBeneficiary_setsTokenToBeneficiary() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        swapper.setTokenToBeneficiary(users.eve);
        assertEq(swapper.tokenToBeneficiary(), users.eve);
    }

    function test_setTokenToBeneficiary_emitsSetTokenToBeneficiary() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetTokenToBeneficiary(users.eve);
        swapper.setTokenToBeneficiary(users.eve);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - setOracle
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setOracle() public {
        vm.expectRevert(Unauthorized.selector);
        swapper.setOracle(IOracle(users.eve));
    }

    function test_setOracle_setsOracle() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        swapper.setOracle(IOracle(users.eve));
        assertEq(address(swapper.oracle()), users.eve);
    }

    function test_setOracle_emitsSetOracle() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetOracle(IOracle(users.eve));
        swapper.setOracle(IOracle(users.eve));
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - setDefaultScaledOfferFactor
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setDefaultScaledOfferFactor() public {
        uint32 newDefaultScaledOfferFactor = 98_00_00;
        vm.expectRevert(Unauthorized.selector);
        swapper.setDefaultScaledOfferFactor(newDefaultScaledOfferFactor);
    }

    function test_setDefaultScaledOfferFactor_setsDefaultScaledOfferFactor() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        uint32 newDefaultScaledOfferFactor = 98_00_00;

        vm.prank(initSwapperParams.owner);
        swapper.setDefaultScaledOfferFactor(newDefaultScaledOfferFactor);
        assertEq(swapper.defaultScaledOfferFactor(), newDefaultScaledOfferFactor);
    }

    function test_setDefaultScaledOfferFactor_emitsSetDefaultScaledOfferFactor() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        uint32 newDefaultScaledOfferFactor = 98_00_00;

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetDefaultScaledOfferFactor(newDefaultScaledOfferFactor);
        swapper.setDefaultScaledOfferFactor(newDefaultScaledOfferFactor);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - setPairScaledOfferFactors
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setPairScaledOfferFactors() public {
        vm.expectRevert(Unauthorized.selector);
        swapper.setPairScaledOfferFactors(setPairScaledOfferFactorParams);
    }

    function test_setPairScaledOfferFactors_setsPairScaledOfferFactors() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        delete setPairScaledOfferFactorParams;
        setPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({quotePair: wethETH, scaledOfferFactor: 0})
        );
        setPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({quotePair: usdcETH, scaledOfferFactor: 98_00_00})
        );
        uint256 length = setPairScaledOfferFactorParams.length;

        vm.prank(initSwapperParams.owner);
        swapper.setPairScaledOfferFactors(setPairScaledOfferFactorParams);

        QuotePair[] memory quotePairs = new QuotePair[](length);
        uint32[] memory newScaledOfferFactors = new uint32[](length);
        for (uint256 i; i < length; i++) {
            quotePairs[i] = setPairScaledOfferFactorParams[i].quotePair;
            newScaledOfferFactors[i] = setPairScaledOfferFactorParams[i].scaledOfferFactor;
        }
        assertEq(swapper.getPairScaledOfferFactors(quotePairs), newScaledOfferFactors);
    }

    function test_setPairScaledOfferFactors_emitsSetPairScaledOfferFactors() public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        // TODO: use setup?

        delete setPairScaledOfferFactorParams;
        setPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({quotePair: wethETH, scaledOfferFactor: 0})
        );
        setPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({quotePair: usdcETH, scaledOfferFactor: 98_00_00})
        );

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetPairScaledOfferFactors(setPairScaledOfferFactorParams);
        swapper.setPairScaledOfferFactors(setPairScaledOfferFactorParams);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - payback
    /// -----------------------------------------------------------------------

    function test_payback_incrementsPayback() public {
        swapperImplHarness.payback{value: 1 ether}();
        assertEq(swapperImplHarness.exposed_payback(), 1 ether);
    }

    function test_payback_emitsPayback() public {
        vm.expectEmit();
        emit Payback(address(this), uint96(1 ether));
        swapper.payback{value: 1 ether}();
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - flash
    /// -----------------------------------------------------------------------

    function test_revertWhen_paused_flash() public {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        swapper.setPaused(true);

        vm.expectRevert(Paused.selector);
        swapper.flash(ethQuoteParams, "");
    }

    function test_flash_mockERC20ToETH() public unpaused {
        vm.startPrank(trader);

        uint256 value = 1 ether * uint256(defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, value, "")),
            returnData: ""
        });

        swapper.payback{value: value}();
        swapper.flash(quoteParams, "");

        assertEq(base._balanceOf(trader), traderBasePreBalance + 1 ether);
        assertEq(base._balanceOf(address(swapper)), swapperBasePreBalance - 1 ether);
        assertEq(base._balanceOf(beneficiary), beneficiaryBasePreBalance);

        assertEq(quote._balanceOf(trader), traderQuotePreBalance - value);
        assertEq(quote._balanceOf(address(swapper)), 0);
        assertEq(quote._balanceOf(beneficiary), beneficiaryQuotePreBalance + swapperQuotePreBalance + value);
    }

    function test_flash_mockERC20ToETH_emitsFlash() public unpaused {
        vm.startPrank(trader);

        uint256 value = 1 ether * uint256(defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, value, "")),
            returnData: ""
        });

        swapper.payback{value: value}();
        mockQuoteAmounts[0] = value;

        _expectEmit();
        emit Flash({
            trader: trader,
            quoteParams: quoteParams,
            tokenToBeneficiary: quote,
            amountsToBeneficiary: mockQuoteAmounts,
            excessToBeneficiary: swapperQuotePreBalance
        });
        swapper.flash(quoteParams, "");
    }

    function test_flash_ethToMockERC20() public unpaused {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        uint256 value = 1 ether * uint256(defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        initSwapperParams.tokenToBeneficiary = mockERC20;
        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);

        vm.startPrank(trader);

        quoteParams = mockERC20QuoteParams;
        qp = quoteParams[0];
        base = qp.quotePair.base;
        quote = qp.quotePair.quote;

        traderBasePreBalance = base._balanceOf(trader);
        swapperBasePreBalance = base._balanceOf(address(swapper));
        beneficiaryBasePreBalance = base._balanceOf(beneficiary);

        traderQuotePreBalance = quote._balanceOf(trader);
        swapperQuotePreBalance = quote._balanceOf(address(swapper));
        beneficiaryQuotePreBalance = quote._balanceOf(beneficiary);

        MockERC20(mockERC20).approve(address(swapper), value);

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, value, "")),
            returnData: ""
        });

        swapper.flash(quoteParams, "");

        assertEq(base._balanceOf(trader), traderBasePreBalance + 1 ether);
        assertEq(base._balanceOf(address(swapper)), swapperBasePreBalance - 1 ether);
        assertEq(base._balanceOf(beneficiary), beneficiaryBasePreBalance);

        assertEq(quote._balanceOf(trader), traderQuotePreBalance - value);
        assertEq(quote._balanceOf(address(swapper)), 0);
        assertEq(quote._balanceOf(beneficiary), beneficiaryQuotePreBalance + swapperQuotePreBalance + value);
    }

    function test_flash_ethToMockERC20_emitsFlash() public unpaused {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        uint256 value = 1 ether * uint256(defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        initSwapperParams.tokenToBeneficiary = mockERC20;
        vm.prank(address(swapperFactory));
        swapper.initializer(initSwapperParams);

        vm.startPrank(trader);

        quoteParams = mockERC20QuoteParams;
        qp = quoteParams[0];
        base = qp.quotePair.base;
        quote = qp.quotePair.quote;

        swapperQuotePreBalance = quote._balanceOf(address(swapper));

        MockERC20(mockERC20).approve(address(swapper), value);

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, value, "")),
            returnData: ""
        });

        mockQuoteAmounts[0] = value;
        _expectEmit();
        emit Flash({
            trader: trader,
            quoteParams: quoteParams,
            tokenToBeneficiary: quote,
            amountsToBeneficiary: mockQuoteAmounts,
            excessToBeneficiary: swapperQuotePreBalance
        });
        swapper.flash(quoteParams, "");
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - _transferToTrader
    /// -----------------------------------------------------------------------

    function test_revertsWhen_quoteAndOracleArrayMismatch_transferToTrader() public unpaused {
        vm.startPrank(trader);

        mockQuoteAmounts.push(1 ether);
        vm.mockCall({
            callee: address(oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, (quoteParams)),
            returnData: abi.encode(mockQuoteAmounts)
        });

        vm.expectRevert(Invalid_AmountsToBeneficiary.selector);
        swapperImplHarness.exposed_transferToTrader(beneficiary, quoteParams);
    }

    function test_revertsWhen_traderRequestsTooMuch_transferToTrader() public unpaused {
        vm.startPrank(trader);

        quoteParams[0].baseAmount = type(uint128).max;
        vm.mockCall({
            callee: address(oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, (quoteParams)),
            returnData: abi.encode(mockQuoteAmounts)
        });

        vm.expectRevert(InsufficientFunds_InContract.selector);
        swapperImplHarness.exposed_transferToTrader(quote, quoteParams);
    }

    function test_transferToTrader_callsOracle() public {
        vm.expectCall({
            callee: address(oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, (quoteParams))
        });
        swapperImplHarness.exposed_transferToTrader(quote, quoteParams);
    }

    function test_transferToTrader_transfersToTrader_mockERC20() public {
        vm.startPrank(trader);

        swapperImplHarness.exposed_transferToTrader(quote, quoteParams);
        assertEq(base._balanceOf(trader), traderBasePreBalance + 1 ether);
        assertEq(base._balanceOf(address(swapperImplHarness)), swapperBasePreBalance - 1 ether);
    }

    function test_transferToTrader_transfersToTrader_eth() public {
        vm.startPrank(trader);

        swapperImplHarness.exposed_transferToTrader(base, mockERC20QuoteParams);
        assertEq(quote._balanceOf(trader), traderQuotePreBalance + 1 ether);
        assertEq(quote._balanceOf(address(swapperImplHarness)), swapperQuotePreBalance - 1 ether);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - _transferToBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertsWhen_traderHasntPaidEnoughETH_transfersToBeneficiary_eth() public {
        vm.expectRevert(InsufficientFunds_FromTrader.selector);
        swapperImplHarness.exposed_transferToBeneficiary(quote, 1 ether);
    }

    function test_transferToBeneficiary_transfersToBeneficiary_eth() public {
        swapperImplHarness.payback{value: 1 ether}();
        uint256 excessToBeneficiary = swapperImplHarness.exposed_transferToBeneficiary(quote, 1 ether);
        assertEq(quote._balanceOf(beneficiary), beneficiaryQuotePreBalance + swapperQuotePreBalance + 1 ether);
        assertEq(quote._balanceOf(address(swapperImplHarness)), 0);
        assertEq(excessToBeneficiary, swapperQuotePreBalance);
    }

    function test_transferToBeneficiary_transfersToBeneficiary_eth_resetsPayback() public {
        swapperImplHarness.payback{value: 1 ether}();
        swapperImplHarness.exposed_transferToBeneficiary(quote, 1 ether);
        assertEq(swapperImplHarness.exposed_payback(), 0);
    }

    function test_transferToBeneficiary_transfersToBeneficiary_mockERC20() public {
        vm.startPrank(trader);

        MockERC20(base).approve(address(swapperImplHarness), 1 ether);
        uint256 excessToBeneficiary = swapperImplHarness.exposed_transferToBeneficiary(base, 1 ether);
        assertEq(base._balanceOf(beneficiary), beneficiaryBasePreBalance + swapperBasePreBalance + 1 ether);
        assertEq(base._balanceOf(trader), traderBasePreBalance - 1 ether);
        assertEq(base._balanceOf(address(swapperImplHarness)), 0);
        assertEq(excessToBeneficiary, swapperBasePreBalance);
    }

    /// -----------------------------------------------------------------------
    /// tests - fuzz
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// tests - fuzz - setDefaultScaledOfferFactor
    /// -----------------------------------------------------------------------

    function testFuzz_revertWhen_callerNotOwner_setDefaultScaledOfferFactor(
        address notOwner_,
        uint32 newDefaultScaledOfferFactor_
    ) public {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.assume(notOwner_ != initSwapperParams.owner);
        vm.prank(notOwner_);
        vm.expectRevert(Unauthorized.selector);
        swapper.setDefaultScaledOfferFactor(newDefaultScaledOfferFactor_);
    }

    function testFuzz_setDefaultScaledOfferFactor_setsDefaultScaledOfferFactor(uint32 newDefaultScaledOfferFactor_)
        public
        callerOwner
    {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        swapper.setDefaultScaledOfferFactor(newDefaultScaledOfferFactor_);
        assertEq(swapper.defaultScaledOfferFactor(), newDefaultScaledOfferFactor_);
    }

    function testFuzz_setDefaultScaledOfferFactor_emitsSetDefaultScaledOfferFactor(uint32 newDefaultScaledOfferFactor_)
        public
        callerOwner
    {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetDefaultScaledOfferFactor(newDefaultScaledOfferFactor_);
        swapper.setDefaultScaledOfferFactor(newDefaultScaledOfferFactor_);
    }

    /// -----------------------------------------------------------------------
    /// tests - fuzz - setPairScaledOfferFactors
    /// -----------------------------------------------------------------------

    function testFuzz_revertWhen_callerNotOwner_setPairScaledOfferFactors(
        address notOwner_,
        SwapperImpl.SetPairScaledOfferFactorParams[] memory newSetPairScaledOfferFactors_
    ) public {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.assume(notOwner_ != initSwapperParams.owner);
        vm.prank(notOwner_);
        vm.expectRevert(Unauthorized.selector);
        swapper.setPairScaledOfferFactors(newSetPairScaledOfferFactors_);
    }

    // TODO: upgrade to test array; need to prune converted duplicates
    function testFuzz_setPairScaledOfferFactors_setsPairScaledOfferFactors(
        SwapperImpl.SetPairScaledOfferFactorParams memory newSetPairScaledOfferFactors_
    ) public callerOwner {
        uint256 length = 1;
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        SwapperImpl.SetPairScaledOfferFactorParams[] memory newSetPairScaledOfferFactors =
            new SwapperImpl.SetPairScaledOfferFactorParams[](1);
        newSetPairScaledOfferFactors[0] = newSetPairScaledOfferFactors_;

        vm.prank(initSwapperParams.owner);
        swapper.setPairScaledOfferFactors(newSetPairScaledOfferFactors);

        QuotePair[] memory quotePairs = new QuotePair[](length);
        uint32[] memory newScaledOfferFactors = new uint32[](length);
        for (uint256 i; i < length; i++) {
            quotePairs[i] = newSetPairScaledOfferFactors[i].quotePair;
            newScaledOfferFactors[i] = newSetPairScaledOfferFactors[i].scaledOfferFactor;
        }
        assertEq(swapper.getPairScaledOfferFactors(quotePairs), newScaledOfferFactors);
    }

    function testFuzz_setPairScaledOfferFactors_emitsSetPairScaledOfferFactors(
        SwapperImpl.SetPairScaledOfferFactorParams[] memory newSetPairScaledOfferFactors_
    ) public callerOwner {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        vm.prank(initSwapperParams.owner);
        vm.expectEmit();
        emit SetPairScaledOfferFactors(newSetPairScaledOfferFactors_);
        swapper.setPairScaledOfferFactors(newSetPairScaledOfferFactors_);
    }
}

contract SwapperImplHarness is SwapperImpl {
    function exposed_payback() external view returns (uint96) {
        return $_payback;
    }

    function exposed_transferToTrader(address tokenToBeneficiary_, QuoteParams[] calldata quoteParams_)
        external
        returns (uint256 amountToBeneficiary, uint256[] memory amountsToBeneficiary)
    {
        return _transferToTrader(tokenToBeneficiary_, quoteParams_);
    }

    function exposed_transferToBeneficiary(address tokenToBeneficiary_, uint256 amountToBeneficiary_)
        external
        returns (uint256 excessToBeneficiary)
    {
        return _transferToBeneficiary(tokenToBeneficiary_, amountToBeneficiary_);
    }
}

contract Trader {
    receive() external payable {}
}
