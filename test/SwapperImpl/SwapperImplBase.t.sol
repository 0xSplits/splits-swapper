// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "splits-tests/Base.t.sol";

import {
    Initialized_PausableImplBase,
    PausableImplHarness,
    Uninitialized_PausableImplBase
} from "splits-tests/PausableImpl/PausableImplBase.t.sol";
import {
    Initialized_WalletImplBase,
    WalletImpl,
    WalletImplHarness,
    Uninitialized_WalletImplBase
} from "splits-tests/WalletImpl/WalletImplBase.t.sol";
import {OwnableImplHarness, Uninitialized_OwnableImplBase} from "splits-tests/OwnableImpl/OwnableImplBase.t.sol";
import {IOracle} from "splits-oracle/interfaces/IOracle.sol";
import {UniV3OracleFactory} from "splits-oracle/UniV3OracleFactory.sol";
import {OracleParams} from "splits-oracle/peripherals/OracleParams.sol";
import {QuotePair, QuoteParams} from "splits-utils/LibQuotes.sol";
import {UniV3OracleImpl} from "splits-oracle/UniV3OracleImpl.sol";

import {ISwapperFlashCallback} from "../../src/interfaces/ISwapperFlashCallback.sol";
import {SwapperImpl} from "../../src/SwapperImpl.sol";
import {SwapperFactory} from "../../src/SwapperFactory.sol";

// State tree
//  Uninitialized
//  Initialized
//   Paused
//   Unpaused

abstract contract Uninitialized_SwapperImplBase is Uninitialized_PausableImplBase, Uninitialized_WalletImplBase {
    using TokenUtils for address;

    error Invalid_AmountsToBeneficiary();
    error Invalid_QuoteToken();
    error InsufficientFunds_InContract();
    error InsufficientFunds_FromTrader();

    event SetBeneficiary(address $beneficiary);
    event SetTokenToBeneficiary(address $tokenToBeneficiaryd);
    event SetOracle(IOracle oracle);
    event SetDefaultScaledOfferFactor(uint32 $defaultScaledOfferFactor);
    event SetPairScaledOfferFactors(SwapperImpl.SetPairScaledOfferFactorParams[] params);

    event Payback(address indexed payer, uint256 amount);
    event Flash(
        address indexed beneficiary,
        address indexed trader,
        QuoteParams[] quoteParams,
        address tokenToBeneficiary,
        uint256[] amountsToBeneficiary,
        uint256 excessToBeneficiary
    );

    SwapperFactory $swapperFactory;
    address $notFactory;
    SwapperImplHarness $swapperImplHarness;
    SwapperImpl $swapper;

    UniV3OracleFactory $oracleFactory;
    UniV3OracleImpl.InitParams $initOracleParams;
    IOracle $oracle;
    OracleParams $oracleParams;

    QuoteParams[] $ethQuoteParams;
    QuoteParams[] $mockERC20QuoteParams;

    uint256[] $mockQuoteAmounts;

    QuotePair $wethETH;
    QuotePair $usdcETH;
    QuotePair $mockERC20ETH;
    QuotePair $ethMockERC20;

    address $trader;

    address $beneficiary;
    address $tokenToBeneficiary;
    uint32 $defaultScaledOfferFactor;
    SwapperImpl.SetPairScaledOfferFactorParams[] $setPairScaledOfferFactorParams;

    address $nextBeneficiary;
    address $nextTokenToBeneficiary;
    uint32 $nextDefaultScaledOfferFactor;
    IOracle $nextOracle;
    SwapperImpl.SetPairScaledOfferFactorParams[] $nextSetPairScaledOfferFactorParams;

    QuoteParams[] $quoteParams;
    QuoteParams $qp;
    address $base;
    address $quote;

    uint128 $baseAmount;
    uint256 $quoteAmount;

    uint256 $traderBasePreBalance;
    uint256 $swapperBasePreBalance;
    uint256 $beneficiaryBasePreBalance;

    uint256 $traderQuotePreBalance;
    uint256 $swapperQuotePreBalance;
    uint256 $beneficiaryQuotePreBalance;

    function setUp() public virtual override(Uninitialized_PausableImplBase, Uninitialized_WalletImplBase) {
        Uninitialized_OwnableImplBase.setUp();

        $oracleFactory = new UniV3OracleFactory({
            weth9_: WETH9
        });
        $swapperFactory = new SwapperFactory();

        $owner = users.alice;
        $beneficiary = users.bob;
        $paused = false;
        $tokenToBeneficiary = ETH_ADDRESS;
        $defaultScaledOfferFactor = 99_00_00;

        $initOracleParams.owner = $owner;
        $oracle = $oracleFactory.createUniV3Oracle($initOracleParams);
        $oracleParams.oracle = $oracle;

        $nextBeneficiary = users.eve;
        $nextTokenToBeneficiary = USDC;
        $nextDefaultScaledOfferFactor = 98_00_00;
        $nextOracle = IOracle(users.eve);

        $wethETH = QuotePair({base: WETH9, quote: ETH_ADDRESS});
        $usdcETH = QuotePair({base: USDC, quote: ETH_ADDRESS});
        $mockERC20ETH = QuotePair({base: mockERC20, quote: ETH_ADDRESS});
        $ethMockERC20 = QuotePair({base: ETH_ADDRESS, quote: mockERC20});

        $setPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({
                quotePair: $wethETH,
                scaledOfferFactor: PERCENTAGE_SCALE // no discount
            })
        );

        $nextSetPairScaledOfferFactorParams.push(
            SwapperImpl.SetPairScaledOfferFactorParams({quotePair: $usdcETH, scaledOfferFactor: 98_00_00})
        );

        $swapper = $swapperFactory.createSwapper(_createSwapperParams());
        _deal({account: address($swapper)});

        $swapperImplHarness = new SwapperImplHarness();
        $swapperImplHarness.initializer(_initSwapperParams());
        _deal({account: address($swapperImplHarness)});

        $baseAmount = 1 ether;
        $quoteAmount = 1 ether;

        $ethQuoteParams.push(QuoteParams({quotePair: $mockERC20ETH, baseAmount: $baseAmount, data: ""}));
        $mockERC20QuoteParams.push(QuoteParams({quotePair: $ethMockERC20, baseAmount: $baseAmount, data: ""}));

        $mockQuoteAmounts.push($quoteAmount);

        $trader = address(new Trader());
        _deal({account: $trader});

        $quoteParams = $ethQuoteParams;
        $qp = $quoteParams[0];
        $base = $qp.quotePair.base;
        $quote = $qp.quotePair.quote;

        $traderBasePreBalance = $base._balanceOf($trader);
        $swapperBasePreBalance = $base._balanceOf(address($swapper));
        $beneficiaryBasePreBalance = $base._balanceOf($beneficiary);

        $traderQuotePreBalance = $quote._balanceOf($trader);
        $swapperQuotePreBalance = $quote._balanceOf(address($swapper));
        $beneficiaryQuotePreBalance = $quote._balanceOf($beneficiary);

        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($ethQuoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });
        vm.mockCall({
            callee: address($oracle),
            msgValue: 0,
            data: abi.encodeCall(IOracle.getQuoteAmounts, ($mockERC20QuoteParams)),
            returnData: abi.encode($mockQuoteAmounts)
        });

        $calls.push(WalletImpl.Call({to: users.alice, value: 1 ether, data: "0x123456789"}));

        $erc1155Ids.push(0);
        $erc1155Ids.push(1);
        $erc1155Amounts.push(1);
        $erc1155Amounts.push(2);

        _setUpPausableImplState({pausable_: address($swapper), paused_: $paused});
        _setUpWalletImplState({
            wallet_: address($swapper),
            calls_: $calls,
            erc721Amount_: 1,
            erc1155Id_: 0,
            erc1155Amount_: 2,
            erc1155Data_: "data",
            erc1155Ids_: $erc1155Ids,
            erc1155Amounts_: $erc1155Amounts
        });
    }

    function _setUpSwapperState(SwapperImpl.InitParams memory params_) internal virtual {
        $owner = params_.owner;
        $paused = params_.paused;
        $beneficiary = params_.beneficiary;
        $tokenToBeneficiary = params_.tokenToBeneficiary;
        $oracle = params_.oracle;
        $oracleParams.oracle = params_.oracle;
        $defaultScaledOfferFactor = params_.defaultScaledOfferFactor;

        delete $setPairScaledOfferFactorParams;
        for (uint256 i = 0; i < params_.pairScaledOfferFactors.length; i++) {
            $setPairScaledOfferFactorParams.push(params_.pairScaledOfferFactors[i]);
        }
    }

    function _initSwapperParams() internal view returns (SwapperImpl.InitParams memory) {
        return SwapperImpl.InitParams({
            owner: $owner,
            paused: $paused,
            beneficiary: $beneficiary,
            tokenToBeneficiary: $tokenToBeneficiary,
            oracle: $oracle,
            defaultScaledOfferFactor: $defaultScaledOfferFactor,
            pairScaledOfferFactors: $setPairScaledOfferFactorParams
        });
    }

    function _createSwapperParams() internal view returns (SwapperFactory.CreateSwapperParams memory) {
        return SwapperFactory.CreateSwapperParams({
            owner: $owner,
            paused: $paused,
            beneficiary: $beneficiary,
            tokenToBeneficiary: $tokenToBeneficiary,
            oracleParams: $oracleParams,
            defaultScaledOfferFactor: $defaultScaledOfferFactor,
            pairScaledOfferFactors: $setPairScaledOfferFactorParams
        });
    }

    function _initialize() internal virtual override(Uninitialized_PausableImplBase, Uninitialized_WalletImplBase) {
        $swapper = $swapperFactory.createSwapper(_createSwapperParams());
        $ownable = OwnableImplHarness(address($swapper));
        $pausable = PausableImplHarness(address($swapper));
        $wallet = WalletImplHarness(address($swapper));
    }

    /// -----------------------------------------------------------------------
    /// modifiers
    /// -----------------------------------------------------------------------

    modifier callerNotFactory(address notFactory_) {
        vm.assume(notFactory_ != address($swapperFactory));
        $notFactory = notFactory_;
        changePrank(notFactory_);
        _;
    }

    modifier callerFactory() {
        changePrank(address($swapperFactory));
        _;
    }

    /// -----------------------------------------------------------------------
    /// modifiers
    /// -----------------------------------------------------------------------

    function assertEq(IOracle a, IOracle b) internal {
        assertEq(address(a), address(b));
    }
}

abstract contract Initialized_SwapperImplBase is
    Uninitialized_SwapperImplBase,
    Initialized_PausableImplBase,
    Initialized_WalletImplBase
{
    function setUp()
        public
        virtual
        override(Uninitialized_SwapperImplBase, Initialized_PausableImplBase, Initialized_WalletImplBase)
    {
        Uninitialized_SwapperImplBase.setUp();
        _initialize();
    }

    function _initialize()
        internal
        virtual
        override(Uninitialized_SwapperImplBase, Initialized_PausableImplBase, Initialized_WalletImplBase)
    {
        Uninitialized_SwapperImplBase._initialize();
        _deal({account: address($swapper)});
    }
}

abstract contract Paused_Initialized_SwapperImplBase is Initialized_SwapperImplBase {
    function setUp() public virtual override {
        Uninitialized_SwapperImplBase.setUp();
        $paused = true;
        _initialize();
    }
}

abstract contract Unpaused_Initialized_SwapperImplBase is Initialized_SwapperImplBase {}

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

    function exposed_transferToBeneficiary(
        address beneficiary_,
        address tokenToBeneficiary_,
        uint256 amountToBeneficiary_
    ) external returns (uint256 excessToBeneficiary) {
        return _transferToBeneficiary(beneficiary_, tokenToBeneficiary_, amountToBeneficiary_);
    }
}

contract Trader {
    receive() external payable {}
}
