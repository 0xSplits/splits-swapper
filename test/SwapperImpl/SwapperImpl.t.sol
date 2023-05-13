// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/Base.t.sol";

import {
    Initialized_PausableImplBase,
    Initialized_PausableImplTest,
    Uninitialized_PausableImplBase,
    Uninitialized_PausableImplTest
} from "splits-tests/PausableImpl/PausableImpl.t.sol";
import {
    Initialized_WalletImplBase,
    Initialized_WalletImplTest,
    Uninitialized_WalletImplBase,
    Uninitialized_WalletImplTest
} from "splits-tests/WalletImpl/WalletImpl.t.sol";
import {IOracle} from "splits-oracle/interfaces/IOracle.sol";
import {OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";
import {UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {QuotePair, QuoteParams} from "splits-utils/LibQuotes.sol";

import {
    Initialized_SwapperImplBase,
    Paused_Initialized_SwapperImplBase,
    Uninitialized_SwapperImplBase,
    Unpaused_Initialized_SwapperImplBase
} from "./SwapperImplBase.t.sol";
import {ISwapperFlashCallback} from "../../src/interfaces/ISwapperFlashCallback.sol";
import {SwapperImpl} from "../../src/SwapperImpl.sol";
import {SwapperFactory} from "../../src/SwapperFactory.sol";

contract Uninitialized_SwapperImplTest is
    Uninitialized_PausableImplTest,
    Uninitialized_WalletImplTest,
    Uninitialized_SwapperImplBase
{
    using TokenUtils for address;

    function setUp()
        public
        virtual
        override(Uninitialized_PausableImplTest, Uninitialized_WalletImplTest, Uninitialized_SwapperImplBase)
    {
        Uninitialized_SwapperImplBase.setUp();
    }

    function _initialize()
        internal
        virtual
        override(Uninitialized_PausableImplTest, Uninitialized_WalletImplTest, Uninitialized_SwapperImplBase)
    {
        Uninitialized_SwapperImplBase._initialize();
    }

    /// -----------------------------------------------------------------------
    /// initializer
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotFactory_initializer() public callerNotFactory($notFactory) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.initializer(_initSwapperParams());
    }

    function testFuzz_revertWhen_callerNotFactory_initializer(address caller_, SwapperImpl.InitParams calldata params_)
        public
        callerNotFactory(caller_)
    {
        _setUpSwapperState(params_);
        test_revertWhen_callerNotFactory_initializer();
    }

    function test_initializer_setsBeneficiary() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        $swapper.initializer(initSwapperParams);
        assertEq($swapper.beneficiary(), initSwapperParams.beneficiary);
    }

    function testFuzz_initializer_setsBeneficiary(SwapperImpl.InitParams calldata params_) public callerFactory {
        _setUpSwapperState(params_);
        test_initializer_setsBeneficiary();
    }

    function test_initializer_setsTokenToBeneficiary() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        $swapper.initializer(initSwapperParams);
        assertEq($swapper.tokenToBeneficiary(), initSwapperParams.tokenToBeneficiary);
    }

    function testFuzz_initializer_setsTokenToBeneficiary(SwapperImpl.InitParams calldata params_)
        public
        callerFactory
    {
        _setUpSwapperState(params_);
        test_initializer_setsTokenToBeneficiary();
    }

    function test_initializer_setsDefaultScaledOfferFactor() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        $swapper.initializer(initSwapperParams);
        assertEq($swapper.defaultScaledOfferFactor(), initSwapperParams.defaultScaledOfferFactor);
    }

    function testFuzz_initializer_setsDefaultScaledOfferFactor(SwapperImpl.InitParams calldata params_)
        public
        callerFactory
    {
        _setUpSwapperState(params_);
        test_initializer_setsDefaultScaledOfferFactor();
    }

    function test_initializer_setsPairScaledOfferFactors() public callerFactory {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        $swapper.initializer(initSwapperParams);

        uint256 length = initSwapperParams.pairScaledOfferFactors.length;
        QuotePair[] memory initQuotePairs = new QuotePair[](length);
        uint32[] memory initScaledOfferFactors = new uint32[](length);
        for (uint256 i; i < length; i++) {
            initQuotePairs[i] = initSwapperParams.pairScaledOfferFactors[i].quotePair;
            initScaledOfferFactors[i] = initSwapperParams.pairScaledOfferFactors[i].scaledOfferFactor;
        }
        assertEq($swapper.getPairScaledOfferFactors(initQuotePairs), initScaledOfferFactors);
    }

    function testFuzz_initializer_setsPairScaledOfferFactors(
        SwapperImpl.InitParams memory params_,
        SwapperImpl.SetPairScaledOfferFactorParams calldata setPairScaledOfferFactorParams_
    ) public callerFactory {
        _setUpSwapperState(params_);
        delete $setPairScaledOfferFactorParams;
        $setPairScaledOfferFactorParams.push(setPairScaledOfferFactorParams_);
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();
        $swapper.initializer(initSwapperParams);

        uint256 length = initSwapperParams.pairScaledOfferFactors.length;
        QuotePair[] memory initQuotePairs = new QuotePair[](length);
        uint32[] memory initScaledOfferFactors = new uint32[](length);
        for (uint256 i; i < length; i++) {
            initQuotePairs[i] = initSwapperParams.pairScaledOfferFactors[i].quotePair;
            initScaledOfferFactors[i] = initSwapperParams.pairScaledOfferFactors[i].scaledOfferFactor;
        }
        assertEq($swapper.getPairScaledOfferFactors(initQuotePairs), initScaledOfferFactors);
    }
}

contract Initialized_SwapperImplTest is
    Initialized_PausableImplTest,
    Initialized_WalletImplTest,
    Initialized_SwapperImplBase
{
    function setUp()
        public
        virtual
        override(Initialized_PausableImplTest, Initialized_WalletImplTest, Initialized_SwapperImplBase)
    {
        Initialized_SwapperImplBase.setUp();
    }

    function _initialize()
        internal
        virtual
        override(Initialized_PausableImplTest, Initialized_WalletImplTest, Initialized_SwapperImplBase)
    {
        Initialized_SwapperImplBase._initialize();
    }

    /// -----------------------------------------------------------------------
    /// setBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setBeneficiary() public callerNotOwner($notOwner) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setBeneficiary($nextBeneficiary);
    }

    function testFuzz_revertWhen_callerNotOwner_setBeneficiary(address notOwner_, address nextBeneficiary_)
        public
        callerNotOwner(notOwner_)
    {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setBeneficiary(nextBeneficiary_);
    }

    function test_setBeneficiary_setsBeneficiary() public callerOwner {
        $swapper.setBeneficiary($nextBeneficiary);
        assertEq($swapper.beneficiary(), $nextBeneficiary);
    }

    function testFuzz_setBeneficiary_setsBeneficiary(address nextBeneficiary_) public callerOwner {
        $swapper.setBeneficiary(nextBeneficiary_);
        assertEq($swapper.beneficiary(), nextBeneficiary_);
    }

    function test_setBeneficiary_emitsSetBeneficiary() public callerOwner {
        vm.expectEmit();
        emit SetBeneficiary($nextBeneficiary);
        $swapper.setBeneficiary($nextBeneficiary);
    }

    function testFuzz_setBeneficiary_emitsSetBeneficiary(address nextBeneficiary_) public callerOwner {
        vm.expectEmit();
        emit SetBeneficiary(nextBeneficiary_);
        $swapper.setBeneficiary(nextBeneficiary_);
    }

    /// -----------------------------------------------------------------------
    /// setTokenToBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setTokenToBeneficiary() public callerNotOwner($notOwner) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setTokenToBeneficiary($nextTokenToBeneficiary);
    }

    function test_revertWhen_callerNotOwner_setTokenToBeneficiary(address notOwner_, address nextTokenToBeneficiary_)
        public
        callerNotOwner(notOwner_)
    {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setTokenToBeneficiary(nextTokenToBeneficiary_);
    }

    function test_setTokenToBeneficiary_setsTokenToBeneficiary() public callerOwner {
        $swapper.setTokenToBeneficiary($nextTokenToBeneficiary);
        assertEq($swapper.tokenToBeneficiary(), $nextTokenToBeneficiary);
    }

    function testFuzz_setTokenToBeneficiary_setsTokenToBeneficiary(address nextTokenToBeneficiary_)
        public
        callerOwner
    {
        $swapper.setTokenToBeneficiary(nextTokenToBeneficiary_);
        assertEq($swapper.tokenToBeneficiary(), nextTokenToBeneficiary_);
    }

    function test_setTokenToBeneficiary_emitsSetTokenToBeneficiary() public callerOwner {
        vm.expectEmit();
        emit SetTokenToBeneficiary($nextTokenToBeneficiary);
        $swapper.setTokenToBeneficiary($nextTokenToBeneficiary);
    }

    function testFuzz_setTokenToBeneficiary_emitsSetTokenToBeneficiary(address nextTokenToBeneficiary_)
        public
        callerOwner
    {
        vm.expectEmit();
        emit SetTokenToBeneficiary(nextTokenToBeneficiary_);
        $swapper.setTokenToBeneficiary(nextTokenToBeneficiary_);
    }

    /// -----------------------------------------------------------------------
    /// setOracle
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setOracle() public callerNotOwner($notOwner) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setOracle($nextOracle);
    }

    function testFuzz_revertWhen_callerNotOwner_setOracle(address notOwner_, IOracle nextOracle_)
        public
        callerNotOwner(notOwner_)
    {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setOracle(nextOracle_);
    }

    function test_setOracle_setsOracle() public callerOwner {
        $swapper.setOracle($nextOracle);
        assertEq($swapper.oracle(), $nextOracle);
    }

    function testFuzz_setOracle_setsOracle(IOracle nextOracle_) public callerOwner {
        $swapper.setOracle(nextOracle_);
        assertEq($swapper.oracle(), nextOracle_);
    }

    function test_setOracle_emitsSetOracle() public callerOwner {
        vm.expectEmit();
        emit SetOracle($nextOracle);
        $swapper.setOracle($nextOracle);
    }

    function testFuzz_setOracle_emitsSetOracle(IOracle nextOracle_) public callerOwner {
        vm.expectEmit();
        emit SetOracle(nextOracle_);
        $swapper.setOracle(nextOracle_);
    }

    /// -----------------------------------------------------------------------
    /// setDefaultScaledOfferFactor
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setDefaultScaledOfferFactor() public callerNotOwner($notOwner) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setDefaultScaledOfferFactor($nextDefaultScaledOfferFactor);
    }

    function testFuzz_revertWhen_callerNotOwner_setDefaultScaledOfferFactor(
        address notOwner_,
        uint32 nextDefaultScaledOfferFactor_
    ) public callerNotOwner(notOwner_) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setDefaultScaledOfferFactor(nextDefaultScaledOfferFactor_);
    }

    function test_setDefaultScaledOfferFactor_setsDefaultScaledOfferFactor() public callerOwner {
        $swapper.setDefaultScaledOfferFactor($nextDefaultScaledOfferFactor);
        assertEq($swapper.defaultScaledOfferFactor(), $nextDefaultScaledOfferFactor);
    }

    function test_setDefaultScaledOfferFactor_emitsSetDefaultScaledOfferFactor() public callerOwner {
        vm.expectEmit();
        emit SetDefaultScaledOfferFactor($nextDefaultScaledOfferFactor);
        $swapper.setDefaultScaledOfferFactor($nextDefaultScaledOfferFactor);
    }

    function testFuzz_setDefaultScaledOfferFactor_setsDefaultScaledOfferFactor(uint32 nextDefaultScaledOfferFactor_)
        public
        callerOwner
    {
        $swapper.setDefaultScaledOfferFactor(nextDefaultScaledOfferFactor_);
        assertEq($swapper.defaultScaledOfferFactor(), nextDefaultScaledOfferFactor_);
    }

    function testFuzz_setDefaultScaledOfferFactor_emitsSetDefaultScaledOfferFactor(uint32 nextDefaultScaledOfferFactor_)
        public
        callerOwner
    {
        vm.expectEmit();
        emit SetDefaultScaledOfferFactor(nextDefaultScaledOfferFactor_);
        $swapper.setDefaultScaledOfferFactor(nextDefaultScaledOfferFactor_);
    }

    /// -----------------------------------------------------------------------
    /// setPairScaledOfferFactors
    /// -----------------------------------------------------------------------

    function test_revertWhen_callerNotOwner_setPairScaledOfferFactors() public callerNotOwner($notOwner) {
        vm.expectRevert(Unauthorized.selector);
        $swapper.setPairScaledOfferFactors($nextSetPairScaledOfferFactorParams);
    }

    function testFuzz_revertWhen_callerNotOwner_setPairScaledOfferFactors(
        address notOwner_,
        SwapperImpl.SetPairScaledOfferFactorParams calldata nextSetPairScaledOfferFactorParams_
    ) public callerNotOwner(notOwner_) {
        delete $nextSetPairScaledOfferFactorParams;
        $nextSetPairScaledOfferFactorParams.push(nextSetPairScaledOfferFactorParams_);

        vm.expectRevert(Unauthorized.selector);
        $swapper.setPairScaledOfferFactors($nextSetPairScaledOfferFactorParams);
    }

    function test_setPairScaledOfferFactors_setsPairScaledOfferFactors() public callerOwner {
        $swapper.setPairScaledOfferFactors($nextSetPairScaledOfferFactorParams);

        uint256 length = $nextSetPairScaledOfferFactorParams.length;
        QuotePair[] memory quotePairs = new QuotePair[](length);
        uint32[] memory newScaledOfferFactors = new uint32[](length);
        for (uint256 i; i < length; i++) {
            quotePairs[i] = $nextSetPairScaledOfferFactorParams[i].quotePair;
            newScaledOfferFactors[i] = $nextSetPairScaledOfferFactorParams[i].scaledOfferFactor;
        }
        assertEq($swapper.getPairScaledOfferFactors(quotePairs), newScaledOfferFactors);
    }

    function testFuzz_setPairScaledOfferFactors_setsPairScaledOfferFactors(
        SwapperImpl.SetPairScaledOfferFactorParams calldata nextSetPairScaledOfferFactorParams_
    ) public callerOwner {
        delete $nextSetPairScaledOfferFactorParams;
        $nextSetPairScaledOfferFactorParams.push(nextSetPairScaledOfferFactorParams_);

        test_setPairScaledOfferFactors_setsPairScaledOfferFactors();
    }

    function test_setPairScaledOfferFactors_emitsSetPairScaledOfferFactors() public callerOwner {
        vm.expectEmit();
        emit SetPairScaledOfferFactors($nextSetPairScaledOfferFactorParams);
        $swapper.setPairScaledOfferFactors($nextSetPairScaledOfferFactorParams);
    }

    function testFuzz_setPairScaledOfferFactors_emitsSetPairScaledOfferFactors(
        SwapperImpl.SetPairScaledOfferFactorParams calldata nextSetPairScaledOfferFactorParams_
    ) public callerOwner {
        delete $nextSetPairScaledOfferFactorParams;
        $nextSetPairScaledOfferFactorParams.push(nextSetPairScaledOfferFactorParams_);

        test_setPairScaledOfferFactors_emitsSetPairScaledOfferFactors;
    }

    /// -----------------------------------------------------------------------
    /// payback
    /// -----------------------------------------------------------------------

    function test_payback_incrementsPayback() public {
        $swapperImplHarness.payback{value: $quoteAmount}();
        assertEq($swapperImplHarness.exposed_payback(), $quoteAmount);
    }

    function testFuzz_payback_incrementsPayback(uint96 quoteAmount_) public {
        $swapperImplHarness.payback{value: quoteAmount_}();
        assertEq($swapperImplHarness.exposed_payback(), quoteAmount_);
    }

    function test_payback_emitsPayback() public {
        vm.expectEmit();
        emit Payback(address(this), uint96($quoteAmount));
        $swapper.payback{value: $quoteAmount}();
    }

    function testFuzz_payback_emitsPayback(uint96 quoteAmount_) public {
        vm.expectEmit();
        emit Payback(address(this), quoteAmount_);
        $swapper.payback{value: quoteAmount_}();
    }
}

contract Paused_Initialized_SwapperImplTest is Initialized_SwapperImplTest, Paused_Initialized_SwapperImplBase {
    function setUp() public virtual override(Paused_Initialized_SwapperImplBase, Initialized_SwapperImplTest) {
        Paused_Initialized_SwapperImplBase.setUp();
    }

    function _initialize() internal virtual override(Initialized_SwapperImplBase, Initialized_SwapperImplTest) {
        Initialized_SwapperImplBase._initialize();
    }

    /// -----------------------------------------------------------------------
    /// flash
    /// -----------------------------------------------------------------------

    function test_revertWhen_paused_flash() public paused {
        vm.expectRevert(Paused.selector);
        $swapper.flash($quoteParams, "");
    }

    function testFuzz_revertWhen_paused_flash(address caller_, QuoteParams[] calldata quoteParams_) public paused {
        changePrank(caller_);
        vm.expectRevert(Paused.selector);
        $swapper.flash(quoteParams_, "");
    }
}

contract Unpaused_Initialized_SwapperImplTest is Initialized_SwapperImplTest, Unpaused_Initialized_SwapperImplBase {
    using TokenUtils for address;

    function setUp() public virtual override(Initialized_SwapperImplBase, Initialized_SwapperImplTest) {
        Initialized_SwapperImplBase.setUp();
    }

    function _initialize() internal virtual override(Initialized_SwapperImplBase, Initialized_SwapperImplTest) {
        Initialized_SwapperImplBase._initialize();
    }

    /// -----------------------------------------------------------------------
    /// flash
    /// -----------------------------------------------------------------------

    function test_flash_mockERC20ToETH() public unpaused {
        vm.startPrank($trader);

        uint256 value = $quoteAmount * uint256($defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        vm.mockCall({
            callee: $trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, ($quote, value, "")),
            returnData: ""
        });

        $swapper.payback{value: value}();
        uint256 totalToBeneficiary = $swapper.flash($quoteParams, "");

        assertEq($base._balanceOf($trader), $traderBasePreBalance + $baseAmount);
        assertEq($base._balanceOf(address($swapper)), $swapperBasePreBalance - $baseAmount);
        assertEq($base._balanceOf($beneficiary), $beneficiaryBasePreBalance);

        assertEq(totalToBeneficiary, value + $swapperQuotePreBalance);
        assertEq($quote._balanceOf($trader), $traderQuotePreBalance - value);
        assertEq($quote._balanceOf(address($swapper)), 0);
        assertEq($quote._balanceOf($beneficiary), $beneficiaryQuotePreBalance + $swapperQuotePreBalance + value);
    }

    function testFuzz_flash_mockERC20ToETH(uint96 ethAmount_, uint128 mockERC20Amount_) public unpaused {
        _deal({account: address($trader), token: ETH_ADDRESS, amount: ethAmount_});
        $traderQuotePreBalance = $quote._balanceOf($trader);
        _deal({account: address($swapper), token: mockERC20, amount: mockERC20Amount_});
        $swapperBasePreBalance = $base._balanceOf(address($swapper));

        $baseAmount = mockERC20Amount_;
        $quoteAmount = ethAmount_;

        delete $quoteParams;
        $quoteParams.push(QuoteParams({quotePair: $mockERC20ETH, baseAmount: $baseAmount, data: ""}));

        delete $mockQuoteAmounts;
        $mockQuoteAmounts.push($quoteAmount);

        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        test_flash_mockERC20ToETH();
    }

    function test_flash_mockERC20ToETH_emitsFlash() public unpaused {
        vm.startPrank($trader);

        uint256 value = $quoteAmount * uint256($defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        vm.mockCall({
            callee: $trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, ($quote, value, "")),
            returnData: ""
        });

        $mockQuoteAmounts[0] = value;
        $swapper.payback{value: value}();

        _expectEmit();
        emit Flash({
            beneficiary: $beneficiary,
            trader: $trader,
            quoteParams: $quoteParams,
            tokenToBeneficiary: $quote,
            amountsToBeneficiary: $mockQuoteAmounts,
            excessToBeneficiary: $swapperQuotePreBalance
        });
        $swapper.flash($quoteParams, "");
    }

    function testFuzz_flash_mockERC20ToETH_emitsFlash(uint96 ethAmount_, uint128 mockERC20Amount_) public unpaused {
        _deal({account: address($trader), token: ETH_ADDRESS, amount: ethAmount_});
        $traderQuotePreBalance = $quote._balanceOf($trader);
        _deal({account: address($swapper), token: mockERC20, amount: mockERC20Amount_});
        $swapperBasePreBalance = $base._balanceOf(address($swapper));

        $baseAmount = mockERC20Amount_;
        $quoteAmount = ethAmount_;

        delete $quoteParams;
        $quoteParams.push(QuoteParams({quotePair: $mockERC20ETH, baseAmount: $baseAmount, data: ""}));

        delete $mockQuoteAmounts;
        $mockQuoteAmounts.push($quoteAmount);

        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        test_flash_mockERC20ToETH_emitsFlash();
    }

    function test_flash_ethToMockERC20() public unpaused {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        uint256 value = $quoteAmount * uint256($defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        initSwapperParams.tokenToBeneficiary = mockERC20;
        vm.prank(address($swapperFactory));
        $swapper.initializer(initSwapperParams);

        vm.startPrank($trader);

        $quoteParams = $mockERC20QuoteParams;
        $qp = $quoteParams[0];
        $base = $qp.quotePair.base;
        $quote = $qp.quotePair.quote;

        $traderBasePreBalance = $base._balanceOf($trader);
        $swapperBasePreBalance = $base._balanceOf(address($swapper));
        $beneficiaryBasePreBalance = $base._balanceOf($beneficiary);

        $traderQuotePreBalance = $quote._balanceOf($trader);
        $swapperQuotePreBalance = $quote._balanceOf(address($swapper));
        $beneficiaryQuotePreBalance = $quote._balanceOf($beneficiary);

        MockERC20(mockERC20).approve(address($swapper), value);

        vm.mockCall({
            callee: $trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, ($quote, value, "")),
            returnData: ""
        });

        uint256 totalToBeneficiary = $swapper.flash($quoteParams, "");

        assertEq($base._balanceOf($trader), $traderBasePreBalance + $baseAmount);
        assertEq($base._balanceOf(address($swapper)), $swapperBasePreBalance - $baseAmount);
        assertEq($base._balanceOf($beneficiary), $beneficiaryBasePreBalance);

        assertEq(totalToBeneficiary, value + $swapperQuotePreBalance);
        assertEq($quote._balanceOf($trader), $traderQuotePreBalance - value);
        assertEq($quote._balanceOf(address($swapper)), 0);
        assertEq($quote._balanceOf($beneficiary), $beneficiaryQuotePreBalance + $swapperQuotePreBalance + value);
    }

    function testFuzz_flash_ethToMockERC20(uint96 ethAmount_, uint128 mockERC20Amount_) public unpaused {
        _deal({account: address($trader), token: mockERC20, amount: mockERC20Amount_});
        $traderBasePreBalance = $base._balanceOf($trader);
        _deal({account: address($swapper), token: ETH_ADDRESS, amount: ethAmount_});
        $swapperQuotePreBalance = $quote._balanceOf(address($swapper));

        $baseAmount = ethAmount_;
        $quoteAmount = mockERC20Amount_;

        delete $mockERC20QuoteParams;
        $mockERC20QuoteParams.push(QuoteParams({quotePair: $ethMockERC20, baseAmount: $baseAmount, data: ""}));

        delete $mockQuoteAmounts;
        $mockQuoteAmounts.push($quoteAmount);

        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($mockERC20QuoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        test_flash_ethToMockERC20();
    }

    function test_flash_ethToMockERC20_emitsFlash() public unpaused {
        SwapperImpl.InitParams memory initSwapperParams = _initSwapperParams();

        uint256 value = $quoteAmount * uint256($defaultScaledOfferFactor) / PERCENTAGE_SCALE;

        initSwapperParams.tokenToBeneficiary = mockERC20;
        vm.prank(address($swapperFactory));
        $swapper.initializer(initSwapperParams);

        vm.startPrank($trader);

        $quoteParams = $mockERC20QuoteParams;
        $qp = $quoteParams[0];
        $base = $qp.quotePair.base;
        $quote = $qp.quotePair.quote;

        $swapperQuotePreBalance = $quote._balanceOf(address($swapper));

        MockERC20(mockERC20).approve(address($swapper), value);

        vm.mockCall({
            callee: $trader,
            msgValue: 0,
            data: abi.encodeCall(ISwapperFlashCallback.swapperFlashCallback, ($quote, value, "")),
            returnData: ""
        });

        $mockQuoteAmounts[0] = value;
        _expectEmit();
        emit Flash({
            beneficiary: $beneficiary,
            trader: $trader,
            quoteParams: $quoteParams,
            tokenToBeneficiary: $quote,
            amountsToBeneficiary: $mockQuoteAmounts,
            excessToBeneficiary: $swapperQuotePreBalance
        });
        $swapper.flash($quoteParams, "");
    }

    function testFuzz_flash_ethToMockERC20_emitsFlash(uint96 ethAmount_, uint128 mockERC20Amount_) public unpaused {
        _deal({account: address($trader), token: mockERC20, amount: mockERC20Amount_});
        $traderBasePreBalance = $base._balanceOf($trader);
        _deal({account: address($swapper), token: ETH_ADDRESS, amount: ethAmount_});
        $swapperQuotePreBalance = $quote._balanceOf(address($swapper));

        $baseAmount = ethAmount_;
        $quoteAmount = mockERC20Amount_;

        delete $mockERC20QuoteParams;
        $mockERC20QuoteParams.push(QuoteParams({quotePair: $ethMockERC20, baseAmount: $baseAmount, data: ""}));

        delete $mockQuoteAmounts;
        $mockQuoteAmounts.push($quoteAmount);

        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($mockERC20QuoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        test_flash_ethToMockERC20_emitsFlash();
    }

    /// -----------------------------------------------------------------------
    /// _transferToTrader
    /// -----------------------------------------------------------------------

    function test_revertsWhen_quoteAndOracleArrayMismatch_transferToTrader() public unpaused {
        vm.startPrank($trader);

        $mockQuoteAmounts.push($quoteAmount);
        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        vm.expectRevert(Invalid_AmountsToBeneficiary.selector);
        $swapperImplHarness.exposed_transferToTrader($beneficiary, $quoteParams);
    }

    function testFuzz_revertsWhen_quoteAndOracleArrayMismatch_transferToTrader(uint256[] calldata mockQuoteAmounts_)
        public
        unpaused
    {
        vm.assume(mockQuoteAmounts_.length != $quoteParams.length);
        vm.startPrank($trader);

        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode(mockQuoteAmounts_)
        });

        vm.expectRevert(Invalid_AmountsToBeneficiary.selector);
        $swapperImplHarness.exposed_transferToTrader($beneficiary, $quoteParams);
    }

    function test_revertsWhen_traderRequestsTooMuch_transferToTrader() public unpaused {
        vm.startPrank($trader);

        $quoteParams[0].baseAmount = type(uint128).max;
        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        vm.expectRevert(InsufficientFunds_InContract.selector);
        $swapperImplHarness.exposed_transferToTrader($quote, $quoteParams);
    }

    function testFuzz_revertsWhen_traderRequestsTooMuch_transferToTrader(uint128 baseAmount_) public unpaused {
        vm.assume(baseAmount_ > $swapperBasePreBalance);
        vm.startPrank($trader);

        $quoteParams[0].baseAmount = baseAmount_;
        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        vm.expectRevert(InsufficientFunds_InContract.selector);
        $swapperImplHarness.exposed_transferToTrader($quote, $quoteParams);
    }

    function test_transferToTrader_callsOracle() public unpaused {
        vm.expectCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams))
        });
        $swapperImplHarness.exposed_transferToTrader($quote, $quoteParams);
    }

    function test_transferToTrader_transfersToTrader_mockERC20() public unpaused {
        vm.startPrank($trader);

        $swapperImplHarness.exposed_transferToTrader($quote, $quoteParams);
        assertEq($base._balanceOf($trader), $traderBasePreBalance + $baseAmount);
        assertEq($base._balanceOf(address($swapperImplHarness)), $swapperBasePreBalance - $baseAmount);
    }

    function testFuzz_transferToTrader_transfersToTrader_mockERC20(uint128 mockERC20Amount_) public unpaused {
        _deal({account: address($swapperImplHarness), token: mockERC20, amount: mockERC20Amount_});
        vm.startPrank($trader);

        $quoteParams[0].baseAmount = mockERC20Amount_;
        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($quoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });
        $swapperImplHarness.exposed_transferToTrader($quote, $quoteParams);
        assertEq($base._balanceOf($trader), $traderBasePreBalance + mockERC20Amount_);
        assertEq($base._balanceOf(address($swapperImplHarness)), 0);
    }

    function test_transferToTrader_transfersToTrader_eth() public unpaused {
        vm.startPrank($trader);

        $swapperImplHarness.exposed_transferToTrader($base, $mockERC20QuoteParams);
        assertEq($quote._balanceOf($trader), $traderQuotePreBalance + $baseAmount);
        assertEq($quote._balanceOf(address($swapperImplHarness)), $swapperQuotePreBalance - $baseAmount);
    }

    function testFuzz_transferToTrader_transfersToTrader_eth(uint96 ethAmount_) public unpaused {
        _deal({account: address($swapperImplHarness), token: ETH_ADDRESS, amount: ethAmount_});
        vm.startPrank($trader);

        $mockERC20QuoteParams[0].baseAmount = ethAmount_;
        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($mockERC20QuoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });
        $swapperImplHarness.exposed_transferToTrader($base, $mockERC20QuoteParams);
        assertEq($quote._balanceOf($trader), $traderQuotePreBalance + ethAmount_);
        assertEq($quote._balanceOf(address($swapperImplHarness)), 0);
    }

    /// -----------------------------------------------------------------------
    /// _transferToBeneficiary
    /// -----------------------------------------------------------------------

    function test_revertsWhen_traderHasntPaidEnoughETH_transferToBeneficiary_eth() public unpaused {
        vm.expectRevert(InsufficientFunds_FromTrader.selector);
        $swapperImplHarness.exposed_transferToBeneficiary($beneficiary, $quote, $quoteAmount);
    }

    function testFuzz_revertsWhen_traderHasntPaidEnoughETH_transferToBeneficiary_eth(uint96 ethAmount_)
        public
        unpaused
    {
        vm.assume(ethAmount_ > 0);
        vm.expectRevert(InsufficientFunds_FromTrader.selector);
        $swapperImplHarness.exposed_transferToBeneficiary($beneficiary, ETH_ADDRESS, ethAmount_);
    }

    function test_transferToBeneficiary_transfersToBeneficiary_eth() public unpaused {
        vm.startPrank($trader);
        $swapperImplHarness.payback{value: $quoteAmount}();
        uint256 excessToBeneficiary =
            $swapperImplHarness.exposed_transferToBeneficiary($beneficiary, $quote, $quoteAmount);
        assertEq(
            $quote._balanceOf($beneficiary), $beneficiaryQuotePreBalance + $swapperQuotePreBalance + $quoteAmount, "1"
        );
        assertEq($quote._balanceOf($trader), $traderQuotePreBalance - $quoteAmount, "2");
        assertEq($quote._balanceOf(address($swapperImplHarness)), 0, "3");
        assertEq(excessToBeneficiary, $swapperQuotePreBalance, "4");
    }

    function testFuzz_transferToBeneficiary_transfersToBeneficiary_eth(uint96 ethAmount_) public unpaused {
        _deal({account: address($trader), token: ETH_ADDRESS, amount: ethAmount_});
        $traderQuotePreBalance = $quote._balanceOf($trader);
        $quoteAmount = ethAmount_;
        test_transferToBeneficiary_transfersToBeneficiary_eth();
    }

    function test_transferToBeneficiary_transfersToBeneficiary_eth_resetsPayback() public unpaused {
        $swapperImplHarness.payback{value: $quoteAmount}();
        $swapperImplHarness.exposed_transferToBeneficiary($beneficiary, $quote, $quoteAmount);
        assertEq($swapperImplHarness.exposed_payback(), 0);
    }

    function testFuzz_transferToBeneficiary_transfersToBeneficiary_eth_resetsPayback(uint96 ethAmount_)
        public
        unpaused
    {
        _deal({account: address($trader), token: ETH_ADDRESS, amount: ethAmount_});
        $quoteAmount = ethAmount_;
        test_transferToBeneficiary_transfersToBeneficiary_eth_resetsPayback();
    }

    function test_transferToBeneficiary_transfersToBeneficiary_mockERC20() public unpaused {
        vm.startPrank($trader);
        MockERC20($base).approve(address($swapperImplHarness), $baseAmount);
        uint256 excessToBeneficiary =
            $swapperImplHarness.exposed_transferToBeneficiary($beneficiary, $base, $baseAmount);
        assertEq($base._balanceOf($beneficiary), $beneficiaryBasePreBalance + $swapperBasePreBalance + $baseAmount, "1");
        assertEq($base._balanceOf($trader), $traderBasePreBalance - $baseAmount, "2");
        assertEq($base._balanceOf(address($swapperImplHarness)), 0, "3");
        assertEq(excessToBeneficiary, $swapperBasePreBalance, "4");
    }

    function testFuzz_transferToBeneficiary_transfersToBeneficiary_mockERC20(uint128 mockERC20Amount_)
        public
        unpaused
    {
        _deal({account: address($trader), token: mockERC20, amount: mockERC20Amount_});
        $traderBasePreBalance = $base._balanceOf($trader);
        $baseAmount = mockERC20Amount_;
        test_transferToBeneficiary_transfersToBeneficiary_mockERC20();
    }
}
