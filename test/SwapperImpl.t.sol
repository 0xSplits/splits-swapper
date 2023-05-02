// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/Base.t.sol";

import {IUniswapV3Factory, UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {IOracle, QuotePair} from "splits-oracle/interfaces/IOracle.sol";
import {OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";

import {ISwapperFlashCallback} from "../src/interfaces/ISwapperFlashCallback.sol";
import {SwapperFactory} from "../src/SwapperFactory.sol";
import {SwapperImpl} from "../src/SwapperImpl.sol";

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

    event ReceiveETH(uint256 amount);
    event Payback(address indexed payer, uint256 amount);
    event Flash(
        address indexed trader,
        IOracle.QuoteParams[] quoteParams,
        address tokenToBeneficiary,
        uint256[] amountsToBeneficiary,
        uint256 excessToBeneficiary
    );

    SwapperFactory swapperFactory;
    SwapperImplHarness swapperImplHarness;
    SwapperImpl swapperImpl;
    SwapperImpl swapper;

    SwapperFactory.CreateSwapperParams createSwapperParams;
    SwapperImpl.InitParams initParams;

    UniV3OracleFactory oracleFactory;
    UniV3OracleImpl.InitParams initOracleParams;
    IOracle oracle;
    OracleParams oracleParams;

    IOracle.QuoteParams[] ethQuoteParams;
    IOracle.QuoteParams[] mockERC20QuoteParams;

    uint256[] mockQuoteAmounts;

    address trader;
    address beneficiary;

    IOracle.QuoteParams[] quoteParams;
    IOracle.QuoteParams qp;
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

        beneficiary = users.bob;

        createSwapperParams = SwapperFactory.CreateSwapperParams({
            owner: users.alice,
            paused: false,
            beneficiary: beneficiary,
            tokenToBeneficiary: ETH_ADDRESS,
            oracleParams: oracleParams
        });
        initParams = SwapperImpl.InitParams({
            owner: users.alice,
            paused: false,
            beneficiary: beneficiary,
            tokenToBeneficiary: ETH_ADDRESS,
            oracle: oracle
        });
        swapper = swapperFactory.createSwapper(createSwapperParams);
        _deal({account: address(swapper)});

        swapperImplHarness = new SwapperImplHarness();
        swapperImplHarness.initializer(initParams);
        _deal({account: address(swapperImplHarness)});

        ethQuoteParams.push(
            IOracle.QuoteParams({
                quotePair: QuotePair({base: address(mockERC20), quote: ETH_ADDRESS}),
                baseAmount: 1 ether,
                data: ""
            })
        );
        mockERC20QuoteParams.push(
            IOracle.QuoteParams({
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
        vm.expectRevert(Unauthorized.selector);
        swapperImpl.initializer(initParams);

        vm.expectRevert(Unauthorized.selector);
        swapper.initializer(initParams);
    }

    function test_initializer_setsOwner() public callerFactory {
        vm.prank(address(swapperFactory));
        swapper.initializer(initParams);
        assertEq(swapper.owner(), initParams.owner);
    }

    function test_initializer_setsPaused() public callerFactory {
        vm.prank(address(swapperFactory));
        swapper.initializer(initParams);
        assertEq(swapper.paused(), initParams.paused);
    }

    function test_initializer_setsBeneficiary() public callerFactory {
        vm.prank(address(swapperFactory));
        swapper.initializer(initParams);
        assertEq(swapper.beneficiary(), initParams.beneficiary);
    }

    function test_initializer_setsTokenToBeneficiary() public callerFactory {
        vm.prank(address(swapperFactory));
        swapper.initializer(initParams);
        assertEq(swapper.tokenToBeneficiary(), initParams.tokenToBeneficiary);
    }

    function test_initializer_emitsOwnershipTransferred() public callerFactory {
        vm.prank(address(swapperFactory));
        _expectEmit();
        emit OwnershipTransferred(address(0), initParams.owner);
        swapper.initializer(initParams);
    }

    /// -----------------------------------------------------------------------
    /// tests - basic - setBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setBeneficiary() public {
        vm.expectRevert(Unauthorized.selector);
        swapper.setBeneficiary(users.eve);
    }

    function test_setBeneficiary_setsBeneficiary() public callerOwner {
        vm.prank(initParams.owner);
        swapper.setBeneficiary(users.eve);
        assertEq(swapper.beneficiary(), users.eve);
    }

    function test_setBeneficiary_emitsSetBeneficiary() public callerOwner {
        vm.prank(initParams.owner);
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
        vm.prank(initParams.owner);
        swapper.setTokenToBeneficiary(users.eve);
        assertEq(swapper.tokenToBeneficiary(), users.eve);
    }

    function test_setTokenToBeneficiary_emitsSetTokenToBeneficiary() public callerOwner {
        vm.prank(initParams.owner);
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
        vm.prank(initParams.owner);
        swapper.setOracle(IOracle(users.eve));
        assertEq(address(swapper.oracle()), users.eve);
    }

    function test_setOracle_emitsSetOracle() public callerOwner {
        vm.prank(initParams.owner);
        vm.expectEmit();
        emit SetOracle(IOracle(users.eve));
        swapper.setOracle(IOracle(users.eve));
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
        vm.prank(initParams.owner);
        swapper.setPaused(true);

        vm.expectRevert(Paused.selector);
        swapper.flash(ethQuoteParams, "");
    }

    function test_flash_mockERC20ToETH() public unpaused {
        vm.startPrank(trader);

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, 1 ether, "")),
            returnData: ""
        });

        swapper.payback{value: 1 ether}();
        swapper.flash(quoteParams, "");

        assertEq(base._balanceOf(trader), traderBasePreBalance + 1 ether);
        assertEq(base._balanceOf(address(swapper)), swapperBasePreBalance - 1 ether);
        assertEq(base._balanceOf(beneficiary), beneficiaryBasePreBalance);

        assertEq(quote._balanceOf(trader), traderQuotePreBalance - 1 ether);
        assertEq(quote._balanceOf(address(swapper)), 0);
        assertEq(quote._balanceOf(beneficiary), beneficiaryQuotePreBalance + swapperQuotePreBalance + 1 ether);
    }

    function test_flash_mockERC20ToETH_emitsFlash() public unpaused {
        vm.startPrank(trader);

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, 1 ether, "")),
            returnData: ""
        });

        swapper.payback{value: 1 ether}();

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
        initParams.tokenToBeneficiary = mockERC20;
        vm.prank(address(swapperFactory));
        swapper.initializer(initParams);

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

        MockERC20(mockERC20).approve(address(swapper), 1 ether);

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, 1 ether, "")),
            returnData: ""
        });

        swapper.flash(quoteParams, "");

        assertEq(base._balanceOf(trader), traderBasePreBalance + 1 ether);
        assertEq(base._balanceOf(address(swapper)), swapperBasePreBalance - 1 ether);
        assertEq(base._balanceOf(beneficiary), beneficiaryBasePreBalance);

        assertEq(quote._balanceOf(trader), traderQuotePreBalance - 1 ether);
        assertEq(quote._balanceOf(address(swapper)), 0);
        assertEq(quote._balanceOf(beneficiary), beneficiaryQuotePreBalance + swapperQuotePreBalance + 1 ether);
    }

    function test_flash_ethToMockERC20_emitsFlash() public unpaused {
        initParams.tokenToBeneficiary = mockERC20;
        vm.prank(address(swapperFactory));
        swapper.initializer(initParams);

        vm.startPrank(trader);

        quoteParams = mockERC20QuoteParams;
        qp = quoteParams[0];
        base = qp.quotePair.base;
        quote = qp.quotePair.quote;

        swapperQuotePreBalance = quote._balanceOf(address(swapper));

        MockERC20(mockERC20).approve(address(swapper), 1 ether);

        vm.mockCall({
            callee: trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, (quote, 1 ether, "")),
            returnData: ""
        });

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
}

contract SwapperImplHarness is SwapperImpl {
    function exposed_payback() external view returns (uint96) {
        return $_payback;
    }

    function exposed_transferToTrader(address tokenToBeneficiary_, IOracle.QuoteParams[] calldata quoteParams_)
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
