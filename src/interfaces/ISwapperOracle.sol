// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Swapper} from "src/Swapper.sol";

/// @title Oracle interface for Swapper#flash
/// @notice An oracle interface for Swapper#flash
interface ISwapperOracle {
    error UnsupportedFile();

    /// @dev unwrap into enum in impl
    type IFileType is uint8;

    struct File {
        IFileType what;
        bytes data;
    }

    struct UnsortedTokenPair {
        address tokenA;
        address tokenB;
    }

    struct SortedTokenPair {
        address token0;
        address token1;
    }

    function file(File calldata incoming) external;

    function getFile(Swapper swapper, File calldata incoming) external view returns (bytes memory);

    function getAmountsToBeneficiary(
        Swapper swapper,
        address tokenToBeneficiary,
        Swapper.TradeParams[] calldata tradeParams,
        bytes calldata data
    ) external view returns (uint256[] memory);
}
