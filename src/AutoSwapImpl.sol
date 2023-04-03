// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IOracle} from "splits-oracle/interfaces/IOracleFactory.sol";
import {ISplitMain} from "./interfaces/external/ISplitMain.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {PausableImpl} from "src/utils/PausableImpl.sol";
import {TokenUtils} from "src/utils/TokenUtils.sol";
import {WalletImpl} from "src/utils/WalletImpl.sol";

/// @title AutoSwap Implementation
/// @author 0xSplits
/// @notice A contract to trustlessly & automatically convert multi-token
/// revenue into a single token & push to a beneficiary.
/// Please be aware, owner has _FULL CONTROL_ of the deployment.
/// @dev This contract uses a modular oracle. Be very careful to use a secure
/// oracle with sensible defaults & overrides for desired behavior. Otherwise
/// may result in catastrophic loss of funds.
/// This contract uses token = address(0) to refer to ETH.
contract AutoSwapImpl is Clone, WalletImpl, PausableImpl {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using SafeTransferLib for address;
    using TokenUtils for address;

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct InitParams {
        address owner;
        bool paused;
    }

    struct SplitParams {
        address[] accounts;
        uint32[] percentAllocations;
        uint32 distributorFee;
    }

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    event ReceiveETH(uint256 amount);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    address public immutable autoSwapFactory;
    ISplitMain public immutable splitMain;

    // 0; first item
    uint256 internal constant UNDERLYING_SPLIT_OFFSET = 0;

    /// @dev equivalent to address public immutable underlyingSplit;
    function underlyingSplit() public pure returns (address) {
        return _getArgAddress(UNDERLYING_SPLIT_OFFSET);
    }

    /// -----------------------------------------------------------------------
    /// constructor & initializer
    /// -----------------------------------------------------------------------

    constructor(ISplitMain splitMain_) {
        splitMain = splitMain_;
        autoSwapFactory = msg.sender;
    }

    function initializer(InitParams calldata params_) external {
        // only autoSwapFactory may call `initializer`
        if (msg.sender != autoSwapFactory) revert Unauthorized();

        // TODO: check if compiler handles packing properly
        // don't need to init wallet separately
        __initPausable({owner_: params_.owner, paused_: params_.paused});

        splitMain.acceptControl(underlyingSplit());
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// emit event when receiving ETH
    /// @dev implemented w/i clone bytecode
    /* receive() external payable { */
    /*     emit ReceiveETH(msg.value); */
    /* } */

    /// send tokens to underlyingSplit
    function sendFundsToUnderlying(address[] calldata tokens_) external pausable {
        uint256 length = tokens_.length;
        for (uint256 i; i < length;) {
            address token = tokens_[i];
            token.safeTransfer(underlyingSplit(), token._balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }
}
