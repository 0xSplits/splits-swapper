// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Swapper} from "src/Swapper.sol";

/// @title Oracle interface for Swapper#flash
/// @notice An oracle interface for Swapper#flash
/// @dev To be used exclusively via delegateCall from Swapper. MUST use explicit
/// storage bucket to avoid storage overlap with Swapper & other past or future
/// oracles (if owner chooses to update).
interface ISwapperOracle {
    error UnsupportedOracleFile();

    /// @dev unwrap into enum in impl
    type IFileType is uint8;

    struct File {
        IFileType what;
        bytes data;
    }

    function file(File calldata incoming) external;

    function getFile(File calldata incoming) external view returns (bytes memory);

    function getAmountsToBeneficiary(
        address tokenToBeneficiary,
        Swapper.TradeParams[] calldata tradeParams,
        bytes calldata data
    ) external view returns (uint256[] memory);
}
