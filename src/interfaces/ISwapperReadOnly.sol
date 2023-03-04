// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Swapper} from "src/Swapper.sol";

/// @title Staticcall Swapper Wrapper
/// @notice Use to wrap Swapper contract before executing one of the included view fns
/// to coerce solidity to use staticcall & prevent any unwanted or unexpected state modification
interface ISwapperReadOnly {
    function getFile(Swapper.File calldata incoming) external view returns (bytes memory);

    function getAmountsToBeneficiary(Swapper.TradeParams[] calldata tradeParams, bytes calldata data)
        external
        view
        returns (uint256[] memory);

    function getAmountsToBeneficiary(
        address _tokenToBeneficiary,
        Swapper.TradeParams[] calldata tradeParams,
        bytes calldata data
    ) external view returns (uint256[] memory);
}
