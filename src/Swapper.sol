// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {ISwapperFlashCallback} from "src/interfaces/ISwapperFlashCallback.sol";
import {ISwapperOracle} from "src/interfaces/ISwapperOracle.sol";
import {ISwapperReadOnly} from "src/interfaces/ISwapperReadOnly.sol";
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
    error UnsupportedFile();
    error UnsupportedOracleFile();
    error Invalid_AmountsToBeneficiary();
    error InsufficientFunds_InContract();
    error InsufficientFunds_FromTrader();

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    enum FileType {
        NotSupported,
        Beneficiary,
        TokenToBeneficiary,
        Oracle,
        OracleFile
    }

    struct File {
        FileType what;
        bytes data;
    }

    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }

    struct TradeParams {
        address token;
        uint128 amount;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event SetPaused(bool paused);
    event FilesUpdated(File[] files);

    event ExecCalls(Call[] calls);

    event ReceiveETH(uint256 amount);
    event PayBack(address indexed payer, uint256 amount);
    event Flash(
        address indexed trader,
        TradeParams[] tradeParams,
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

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 0
    /// -----------------------------------------------------------------------

    /// Owned storage
    /// address public owner;
    /// 20 bytes

    /// 12 bytes free

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 1
    /// -----------------------------------------------------------------------

    /// address to receive post-swap tokens
    address public beneficiary;
    /// 20 bytes

    /// used to track eth payback in flash
    uint96 internal _payback;
    /// 12 bytes

    /// 0 bytes free

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 2
    /// -----------------------------------------------------------------------

    /// token type to send beneficiary
    /// @dev 0x0 used for ETH
    address public tokenToBeneficiary;
    /// 20 bytes

    /// whether non-owner functions are paused
    bool public paused;
    /// 1 byte

    /// 11 bytes free

    /// -----------------------------------------------------------------------
    /// storage - mutables - slot 3
    /// -----------------------------------------------------------------------

    /// owner overrides for uniswap v3 oracle params
    ISwapperOracle public oracle;
    /// 20 bytes

    /// 12 bytes free

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(address owner_, bool paused_, File[] memory files) Owned(owner_) {
        paused = paused_;
        _file(files);
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

    /// set paused
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit SetPaused(paused_);
    }

    /// update storage
    function file(File[] calldata files) external onlyOwner {
        _file(files);
        emit FilesUpdated(files);
    }

    /// allow owner to execute arbitrary calls from swapper
    function execCalls(Call[] calldata calls)
        external
        payable
        onlyOwner
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;
        uint256 length = calls.length;
        returnData = new bytes[](length);

        bool success;
        uint256 i;
        for (; i < length;) {
            // TODO: calldata vs memory?
            Call calldata calli = calls[i];
            (success, returnData[i]) = calli.target.call{value: calli.value}(calli.callData);
            require(success, string(returnData[i]));

            unchecked {
                ++i;
            }
        }

        emit ExecCalls(calls);
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
        _payback += msg.value.toUint96();

        emit PayBack(msg.sender, msg.value);
    }

    /// incentivizes third parties to withdraw tokens in return for sending tokenToBeneficiary to beneficiary
    function flash(TradeParams[] calldata tradeParams, bytes calldata oracleData, bytes calldata callbackData)
        external
        payable
    {
        if (paused) revert Paused();

        address _tokenToBeneficiary = tokenToBeneficiary;
        uint256 amountToBeneficiary;
        uint256 length = tradeParams.length;
        // explicitly wrap in staticcall to prevent state mod from oracle delegatecall
        uint256[] memory amountsToBeneficiary =
            ISwapperReadOnly(address(this)).getAmountsToBeneficiary(_tokenToBeneficiary, tradeParams, oracleData);
        if (amountsToBeneficiary.length != length) revert Invalid_AmountsToBeneficiary();
        {
            uint128 amountToTrader;
            address tokenToTrader;
            uint256 i;
            for (; i < length;) {
                TradeParams calldata tp = tradeParams[i];
                tokenToTrader = tp.token;
                amountToTrader = tp.amount;

                if (amountToTrader > address(this).getBalance(tokenToTrader)) {
                    revert InsufficientFunds_InContract();
                }

                amountToBeneficiary += amountsToBeneficiary[i];

                if (tokenToTrader.isETH()) {
                    msg.sender.safeTransferETH(amountToTrader);
                } else {
                    tokenToTrader.safeTransfer(msg.sender, amountToTrader);
                }

                unchecked {
                    ++i;
                }
            }
        }

        ISwapperFlashCallback(msg.sender).swapperFlashCallback({
            tokenToBeneficiary: _tokenToBeneficiary,
            amountToBeneficiary: amountToBeneficiary,
            data: callbackData
        });

        address _beneficiary = beneficiary;
        uint256 excessToBeneficiary;
        if (_tokenToBeneficiary.isETH()) {
            if (_payback < amountToBeneficiary) {
                revert InsufficientFunds_FromTrader();
            }
            _payback = 0;

            // send eth to beneficiary
            uint256 ethBalance = address(this).balance;
            excessToBeneficiary = ethBalance - amountToBeneficiary;
            _beneficiary.safeTransferETH(ethBalance);
        } else {
            _tokenToBeneficiary.safeTransferFrom(msg.sender, _beneficiary, amountToBeneficiary);

            // flush excess tokenToBeneficiary to beneficiary
            excessToBeneficiary = ERC20(tokenToBeneficiary).balanceOf(address(this));
            if (excessToBeneficiary > 0) {
                tokenToBeneficiary.safeTransfer(_beneficiary, excessToBeneficiary);
            }
        }

        emit Flash(msg.sender, tradeParams, _tokenToBeneficiary, amountsToBeneficiary, excessToBeneficiary);
    }

    /// -----------------------------------------------------------------------
    /// functions - public & external - views
    /// -----------------------------------------------------------------------

    /// !!! ATTENTION !!!
    ///
    /// Due to the modular nature of ISwapperOracle & the resulting uses of delegatecall below,
    /// these functions cannot be marked as view in this file and _should not be called without
    /// first wrapping the Swapper inside ISwapperReadOnly_ to coerce solidity to use staticcall
    /// to prevent unexpected and unwanted state modification

    /// get storage
    function getFile(File calldata incoming) external returns (bytes memory b) {
        FileType what = incoming.what;
        bytes memory data = incoming.data;

        if (what == FileType.Beneficiary) {
            b = abi.encode(beneficiary);
        } else if (what == FileType.TokenToBeneficiary) {
            b = abi.encode(tokenToBeneficiary);
        } else if (what == FileType.Oracle) {
            b = abi.encode(oracle);
        } else if (what == FileType.OracleFile) {
            (bool success, bytes memory returnOrRevertData) = address(oracle).delegatecall(
                abi.encodeCall(ISwapperOracle.getFile, (abi.decode(data, (ISwapperOracle.File))))
            );
            if (!success) revert UnsupportedOracleFile();
            return returnOrRevertData;
        } else {
            revert UnsupportedFile();
        }
    }

    /// get amounts to beneficiary for a set of trades
    /// @dev call via ISwapperReadOnly to prevent state mod
    function getAmountsToBeneficiary(TradeParams[] calldata tradeParams, bytes calldata data)
        external
        returns (uint256[] memory)
    {
        return _getAmountsToBeneficiary(tokenToBeneficiary, tradeParams, data);
    }

    /// get amounts to beneficiary for a set of trades
    /// @dev call via ISwapperReadOnly to prevent state mod
    function getAmountsToBeneficiary(
        address _tokenToBeneficiary,
        TradeParams[] calldata tradeParams,
        bytes calldata data
    ) external returns (uint256[] memory) {
        return _getAmountsToBeneficiary(_tokenToBeneficiary, tradeParams, data);
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    /// update storage
    function _file(File[] memory files) internal {
        uint256 i;
        uint256 length = files.length;
        for (; i < length;) {
            File memory f = files[i];
            FileType what = f.what;
            bytes memory data = f.data;

            if (what == FileType.Beneficiary) {
                beneficiary = abi.decode(data, (address));
            } else if (what == FileType.TokenToBeneficiary) {
                tokenToBeneficiary = abi.decode(data, (address));
            } else if (what == FileType.Oracle) {
                oracle = abi.decode(data, (ISwapperOracle));
            } else if (what == FileType.OracleFile) {
                (bool success,) = address(oracle).delegatecall(
                    abi.encodeCall(ISwapperOracle.file, (abi.decode(data, (ISwapperOracle.File))))
                );
                if (!success) revert UnsupportedOracleFile();
            } else {
                revert UnsupportedFile();
            }
        }
    }

    /// get amounts to beneficiary for a set of trades
    function _getAmountsToBeneficiary(
        address _tokenToBeneficiary,
        TradeParams[] calldata tradeParams,
        bytes calldata data
    ) internal returns (uint256[] memory amountsToBeneficiary) {
        Swapper.TradeParams[] memory tps = tradeParams;
        (bool success, bytes memory returnOrRevertData) = address(oracle).delegatecall(
            abi.encodeCall(ISwapperOracle.getAmountsToBeneficiary, (_tokenToBeneficiary, tps, data))
        );
        if (!success) {
            assembly {
                revert(add(returnOrRevertData, 0x20), mload(returnOrRevertData))
            }
        }
        return abi.decode(returnOrRevertData, (uint256[]));
    }
}
