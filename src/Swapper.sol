// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IOracle} from "splits-oracle/interfaces/IOracleFactory.sol";

import {ISwapperFlashCallback} from "src/interfaces/ISwapperFlashCallback.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";

/// @title Swapper
/// @author 0xSplits
/// @notice A contract to trustlessly & automatically convert multi-token
/// revenue into a single token & push to a beneficiary.
/// Please be aware, owner has _FULL CONTROL_ of the deployment.
/// @dev This contract uses a modular oracle. Be very careful to use a secure
/// oracle with sensible defaults & overrides for desired behavior. Otherwise
/// may result in catastrophic loss of funds.
/// This contract uses token = address(0) to refer to ETH.
contract Swapper is Owned {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    error Paused();
    error Invalid_AmountsToBeneficiary();
    error Invalid_QuoteToken();
    error InsufficientFunds_InContract();
    error InsufficientFunds_FromTrader();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event SetBeneficiary(address beneficiary);
    event SetTokenToBeneficiary(address tokenToBeneficiaryd);
    event SetPaused(bool paused);
    event SetOracle(IOracle oracle);

    event ExecCalls(Call[] calls);

    event ReceiveETH(uint256 amount);
    event PayBack(address indexed payer, uint256 amount);
    event Flash(
        address indexed trader,
        IOracle.QuoteParams[] quoteParams,
        address tokenToBeneficiary,
        uint256[] amountsToBeneficiary,
        uint256 excessToBeneficiary
    );

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - mutables
    /// -----------------------------------------------------------------------

    /// slot 0 - 12 bytes free

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    /// slot 1 - 0 bytes free

    /// address to receive post-swap tokens
    address public $beneficiary;
    /// 20 bytes

    /// used to track eth payback in flash
    uint96 internal $_payback;
    /// 12 bytes

    /// slot 2 - 11 bytes free

    /// token type to send beneficiary
    /// @dev 0x0 used for ETH
    address public $tokenToBeneficiary;
    /// 20 bytes

    /// whether non-owner functions are paused
    bool public $paused;
    /// 1 byte

    /// slot 3 - 12 bytes free

    /// price oracle for flash
    IOracle public $oracle;
    /// 20 bytes

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(address owner_, bool paused_, address beneficiary_, address tokenToBeneficiary_, IOracle oracle_)
        Owned(owner_)
    {
        $beneficiary = beneficiary_;
        $tokenToBeneficiary = tokenToBeneficiary_;
        $paused = paused_;
        $oracle = oracle_;

        // event in factory
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

    /// set paused
    function setPaused(bool paused_) external onlyOwner {
        $paused = paused_;
        emit SetPaused(paused_);
    }

    /// set oracle
    function setOracle(IOracle oracle_) external onlyOwner {
        $oracle = oracle_;
        emit SetOracle(oracle_);
    }

    // TODO: can we approve, swap, & forward in a single call?
    // don't know the output amount of the swap.. may need delegatecall to handle properly
    // (or have to xfr funds first to integration contract? which is maybe fine..)

    /// allow owner to execute arbitrary calls from swapper
    function execCalls(Call[] calldata calls_)
        external
        payable
        onlyOwner
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;
        uint256 length = calls_.length;
        returnData = new bytes[](length);

        bool success;
        for (uint256 i; i < length;) {
            Call calldata calli = calls_[i];
            (success, returnData[i]) = calli.target.call{value: calli.value}(calli.callData);
            require(success, string(returnData[i]));

            unchecked {
                ++i;
            }
        }

        emit ExecCalls(calls_);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - permissionless
    /// -----------------------------------------------------------------------

    /// emit event when receiving ETH
    /// @dev implemented w/i clone bytecode
    receive() external payable {
        emit ReceiveETH(msg.value);
    }

    /// allows flash to track eth payback to beneficiary
    /// @dev if used outside swapperFlashCallback, msg.sender may lose funds
    /// accumulates until next flash call
    function payback() external payable {
        $_payback += msg.value.toUint96();

        emit PayBack(msg.sender, msg.value);
    }

    /// allow third parties to withdraw tokens in return for sending tokenToBeneficiary to beneficiary
    function flash(IOracle.QuoteParams[] calldata quoteParams_, bytes calldata callbackData_) external payable {
        if ($paused) revert Paused();

        address tokenToBeneficiary = $tokenToBeneficiary;
        (uint256 amountToBeneficiary, uint256[] memory amountsToBeneficiary) =
            _transferToTrader(tokenToBeneficiary, quoteParams_);

        ISwapperFlashCallback(msg.sender).swapperFlashCallback({
            tokenToBeneficiary: tokenToBeneficiary,
            amountToBeneficiary: amountToBeneficiary,
            data: callbackData_
        });

        uint256 excessToBeneficiary = _transferToBeneficiary(tokenToBeneficiary, amountToBeneficiary);

        emit Flash(msg.sender, quoteParams_, tokenToBeneficiary, amountsToBeneficiary, excessToBeneficiary);
    }

    function _transferToTrader(address tokenToBeneficiary_, IOracle.QuoteParams[] calldata quoteParams_)
        internal
        returns (uint256 amountToBeneficiary, uint256[] memory amountsToBeneficiary)
    {
        amountsToBeneficiary = $oracle.getQuoteAmounts(quoteParams_);
        uint256 length = quoteParams_.length;
        if (amountsToBeneficiary.length != length) revert Invalid_AmountsToBeneficiary();

        uint128 amountToTrader;
        address tokenToTrader;
        for (uint256 i; i < length;) {
            IOracle.QuoteParams calldata qp = quoteParams_[i];

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
        address beneficiary = $beneficiary;
        if (tokenToBeneficiary_._isETH()) {
            if ($_payback < amountToBeneficiary_) {
                revert InsufficientFunds_FromTrader();
            }
            $_payback = 0;

            // send eth to beneficiary
            uint256 ethBalance = address(this).balance;
            excessToBeneficiary = ethBalance - amountToBeneficiary_;
            beneficiary.safeTransferETH(ethBalance);
        } else {
            tokenToBeneficiary_.safeTransferFrom(msg.sender, beneficiary, amountToBeneficiary_);

            // flush excess tokenToBeneficiary to beneficiary
            excessToBeneficiary = ERC20(tokenToBeneficiary_).balanceOf(address(this));
            if (excessToBeneficiary > 0) {
                tokenToBeneficiary_.safeTransfer(beneficiary, excessToBeneficiary);
            }
        }
    }
}
