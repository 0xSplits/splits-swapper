// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IOracle, IOracleFactory} from "splits-oracle/interfaces/IOracleFactory.sol";
import {ISplitMain} from "./interfaces/ISplitMain.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {AutoSwapImpl} from "src/AutoSwapImpl.sol";
import {SwapperFactory, SwapperImpl} from "src/SwapperFactory.sol";

/// @title Auto Swap Factory
/// @author 0xSplits
/// @notice Factory for creating Autoswaps
/// @dev This contract uses token = address(0) to refer to ETH.
contract AutoSwapFactory {
    /// -----------------------------------------------------------------------
    /// libraries
    /// -----------------------------------------------------------------------

    using LibClone for address;

    /// -----------------------------------------------------------------------
    /// events
    /// -----------------------------------------------------------------------

    // TODO: capture split / swapper addresses separately?
    event CreateAutoSwap(AutoSwapImpl indexed autoSwap, CreateAutoSwapParams params);

    /// -----------------------------------------------------------------------
    /// structs
    /// -----------------------------------------------------------------------

    struct CreateOracleAndAutoSwapParams {
        CreateOracleParams createOracle;
        CreateAutoSwapParams createAutoSwap;
    }

    struct CreateOracleParams {
        IOracleFactory factory;
        bytes data;
    }

    struct CreateAutoSwapParams {
        AutoSwapImpl.InitParams initAutoSwap;
        Recipient[] recipients;
        uint32[] initPercentAllocations;
    }

    struct Recipient {
        address account;
        SwapperImpl.InitParams createSwapper;
    }

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// storage - constants & immutables
    /// -----------------------------------------------------------------------

    ISplitMain public immutable splitMain;
    SwapperFactory public immutable swapperFactory;
    AutoSwapImpl public immutable autoSwapImpl;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(ISplitMain splitMain_, SwapperFactory swapperFactory_) {
        splitMain = splitMain_;
        swapperFactory = swapperFactory_;
        autoSwapImpl = new AutoSwapImpl(splitMain_);
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    function createAutoSwap(CreateAutoSwapParams calldata params_) external returns (AutoSwapImpl) {
        return _createAutoSwap(params_);
    }

    /// @dev params_.createAutoSwap.recipients[i].createSwapper.oracle are overridden by newly created oracle
    function createOracleAndAutoSwap(CreateOracleAndAutoSwapParams calldata params_) external returns (AutoSwapImpl) {
        IOracle oracle = params_.createOracle.factory.createOracle(params_.createOracle.data);

        CreateAutoSwapParams memory createAutoSwapParams = params_.createAutoSwap;
        uint256 length = createAutoSwapParams.recipients.length;
        for (uint256 i; i < length;) {
            createAutoSwapParams.recipients[i].createSwapper.oracle = oracle;

            unchecked {
                ++i;
            }
        }
        return _createAutoSwap(createAutoSwapParams);
    }

    /// -----------------------------------------------------------------------
    /// functions - private & internal
    /// -----------------------------------------------------------------------

    // TODO: should this complexity be inside AutoSwapImpl.initializer? would mean underlyingSplit can't be immutable

    function _createAutoSwap(CreateAutoSwapParams memory params_) internal returns (AutoSwapImpl autoSwap) {
        // create swappers
        uint256 length = params_.recipients.length;
        address[] memory recipients = new address[](length);
        for (uint256 i; i < length;) {
            Recipient memory recipient = params_.recipients[i];
            recipients[i] = _isSwapper(recipient)
                ? address(swapperFactory.createSwapper(recipient.createSwapper))
                : recipient.account;

            unchecked {
                ++i;
            }
        }

        // create split
        address underlyingSplit = payable(
            splitMain.createSplit({
                accounts: recipients,
                percentAllocations: params_.initPercentAllocations,
                distributorFee: 0,
                controller: address(this)
            })
        );

        // create auto swap
        autoSwap = AutoSwapImpl(payable(address(autoSwapImpl).clone(abi.encodePacked(underlyingSplit))));
        splitMain.transferControl(underlyingSplit, address(autoSwap));
        autoSwap.initializer(params_.initAutoSwap);
        // TODO: event ordering?
        emit CreateAutoSwap({autoSwap: autoSwap, params: params_});
    }

    function _isSwapper(Recipient memory recipient_) internal pure returns (bool) {
        return recipient_.account == address(0);
    }
}
