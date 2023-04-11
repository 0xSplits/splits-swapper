// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {OracleImpl} from "splits-oracle/OracleImpl.sol";
import {PausableImpl} from "splits-utils/PausableImpl.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TokenUtils} from "splits-utils/TokenUtils.sol";
import {WalletImpl} from "splits-utils/WalletImpl.sol";

import {ISwapperFlashCallback} from "./interfaces/ISwapperFlashCallback.sol";

/// @title Swapper Implementation
/// @author 0xSplits
/// @notice A contract to trustlessly & automatically convert multi-token
/// onchain revenue into a single token
/// Please be aware, owner has _FULL CONTROL_ of the deployment.
/// @dev This contract uses a modular oracle. Be very careful to use a secure
/// oracle with sensible defaults & overrides for desired behavior. Otherwise
/// may result in catastrophic loss of funds.
/// This contract uses token = address(0) to refer to ETH.
contract SwapperImpl is WalletImpl, PausableImpl {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    error Invalid_AmountsToBeneficiary();
    error Invalid_QuoteToken();
    error InsufficientFunds_InContract();
    error InsufficientFunds_FromTrader();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct InitParams {
        address owner;
        bool paused;
        address beneficiary;
        address tokenToBeneficiary;
        OracleImpl oracle;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event SetBeneficiary(address beneficiary);
    event SetTokenToBeneficiary(address tokenToBeneficiary);
    event SetOracle(OracleImpl oracle);

    event ReceiveETH(uint256 amount);
    event Payback(address indexed payer, uint256 amount);
    event Flash(
        address indexed trader,
        OracleImpl.QuoteParams[] quoteParams,
        address tokenToBeneficiary,
        uint256[] amountsToBeneficiary,
        uint256 excessToBeneficiary
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    address public immutable swapperFactory;

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// slot 0 - 11 bytes free

    /// OwnableImpl storage
    /// address internal $owner;
    /// 20 bytes

    /// PausableImpl storage
    /// bool internal $paused;
    /// 1 byte

    /// slot 1 - 0 bytes free

    /// address to receive post-swap tokens
    address internal $beneficiary;
    /// 20 bytes

    /// used to track eth payback in flash
    uint96 internal $_payback;
    /// 12 bytes

    /// slot 2 - 12 bytes free

    /// token type to send beneficiary
    /// @dev 0x0 used for ETH
    address internal $tokenToBeneficiary;
    /// 20 bytes

    /// slot 3 - 12 bytes free

    /// price oracle for flash
    OracleImpl internal $oracle;
    /// 20 bytes

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor() {
        swapperFactory = msg.sender;
    }

    function initializer(InitParams calldata params_) external {
        // only swapperFactory may call `initializer`
        if (msg.sender != swapperFactory) revert Unauthorized();

        // don't need to init wallet separately
        __initPausable({owner_: params_.owner, paused_: params_.paused});

        $beneficiary = params_.beneficiary;
        $tokenToBeneficiary = params_.tokenToBeneficiary;
        $oracle = params_.oracle;
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external - onlyOwner
    /// -----------------------------------------------------------------------

    /// set beneficiary
    function setBeneficiary(address beneficiary_) external onlyOwner {
        $beneficiary = beneficiary_;
        emit SetBeneficiary(beneficiary_);
    }

    /// set tokenToBeneficiary
    function setTokenToBeneficiary(address tokenToBeneficiary_) external onlyOwner {
        $tokenToBeneficiary = tokenToBeneficiary_;
        emit SetTokenToBeneficiary(tokenToBeneficiary_);
    }

    /// set oracle
    function setOracle(OracleImpl oracle_) external onlyOwner {
        $oracle = oracle_;
        emit SetOracle(oracle_);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - view
    /// -----------------------------------------------------------------------

    function beneficiary() external view returns (address) {
        return $beneficiary;
    }

    function tokenToBeneficiary() external view returns (address) {
        return $tokenToBeneficiary;
    }

    function oracle() external view returns (OracleImpl) {
        return $oracle;
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - permissionless
    /// -----------------------------------------------------------------------

    /// emit event when receiving ETH
    /// @dev implemented w/i clone bytecode
    /* receive() external payable { */
    /*     emit ReceiveETH(msg.value); */
    /* } */

    /// allows flash to track eth payback to beneficiary
    /// @dev if used outside swapperFlashCallback, msg.sender may lose funds
    /// accumulates until next flash call
    function payback() external payable {
        $_payback += msg.value.toUint96();
        emit Payback(msg.sender, msg.value);
    }

    /// allow third parties to withdraw tokens in return for sending tokenToBeneficiary to beneficiary
    function flash(OracleImpl.QuoteParams[] calldata quoteParams_, bytes calldata callbackData_)
        external
        payable
        pausable
    {
        address _tokenToBeneficiary = $tokenToBeneficiary;
        (uint256 amountToBeneficiary, uint256[] memory amountsToBeneficiary) =
            _transferToTrader(_tokenToBeneficiary, quoteParams_);

        ISwapperFlashCallback(msg.sender).swapperFlashCallback({
            tokenToBeneficiary: _tokenToBeneficiary,
            amountToBeneficiary: amountToBeneficiary,
            data: callbackData_
        });

        uint256 excessToBeneficiary = _transferToBeneficiary(_tokenToBeneficiary, amountToBeneficiary);

        emit Flash(msg.sender, quoteParams_, _tokenToBeneficiary, amountsToBeneficiary, excessToBeneficiary);
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    function _transferToTrader(address tokenToBeneficiary_, OracleImpl.QuoteParams[] calldata quoteParams_)
        internal
        returns (uint256 amountToBeneficiary, uint256[] memory amountsToBeneficiary)
    {
        amountsToBeneficiary = $oracle.getQuoteAmounts(quoteParams_);
        uint256 length = quoteParams_.length;
        if (amountsToBeneficiary.length != length) revert Invalid_AmountsToBeneficiary();

        uint128 amountToTrader;
        address tokenToTrader;
        for (uint256 i; i < length;) {
            OracleImpl.QuoteParams calldata qp = quoteParams_[i];

            if (tokenToBeneficiary_ != qp.quotePair.quote) revert Invalid_QuoteToken();
            tokenToTrader = qp.quotePair.base;
            amountToTrader = qp.baseAmount;

            if (amountToTrader > tokenToTrader._balanceOf(address(this))) {
                revert InsufficientFunds_InContract();
            }

            amountToBeneficiary += amountsToBeneficiary[i];
            tokenToTrader._safeTransfer(msg.sender, amountToTrader);

            unchecked {
                ++i;
            }
        }
    }

    function _transferToBeneficiary(address tokenToBeneficiary_, uint256 amountToBeneficiary_)
        internal
        returns (uint256 excessToBeneficiary)
    {
        address _beneficiary = $beneficiary;
        if (tokenToBeneficiary_._isETH()) {
            if ($_payback < amountToBeneficiary_) {
                revert InsufficientFunds_FromTrader();
            }
            $_payback = 0;

            // send eth to beneficiary
            uint256 ethBalance = address(this).balance;
            excessToBeneficiary = ethBalance - amountToBeneficiary_;
            _beneficiary.safeTransferETH(ethBalance);
        } else {
            tokenToBeneficiary_.safeTransferFrom(msg.sender, _beneficiary, amountToBeneficiary_);

            // flush excess tokenToBeneficiary to beneficiary
            excessToBeneficiary = ERC20(tokenToBeneficiary_).balanceOf(address(this));
            if (excessToBeneficiary > 0) {
                tokenToBeneficiary_.safeTransfer(_beneficiary, excessToBeneficiary);
            }
        }
    }
}
