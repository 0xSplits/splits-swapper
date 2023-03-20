// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Swapper} from "src/Swapper.sol";

// TODO: we should be releasing engineering / technical ~launch blog posts for every ~contract etc?
// swapper: direct swap; integration contracts; oracle interface. maximum composability. clones vs full deploys.
// oracle interface; oracle options - how they worked, what we picked, tradeoffs considered
// usage of types - parse, dont validate
// file pattern
// oracle: clones vs single contract

// TODO: rename IOracle? rename getAmounts to { getQuoteAmount }
// TODO: the oracle _~interface_ is actually.. very important?
// TODO: should each swapper be deploying it's own oracle clone instead of having all the oracles share storage?
// TODO: theoretically that would .. enhance security (lack of commingled storage?) but also allow people to opt into sharing oracles?
// would be the equivalent of like having an operator or something for yours
// actually ig you can already do this

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
        Swapper.TradeParams[] calldata tradeParams
    ) external view returns (uint256[] memory);
}
