// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IOracle} from "src/interfaces/IOracle.sol";

/// @title Oracle factory interface
interface IOracleFactory {
    function createOracle(bytes calldata init) external returns (IOracle oracle);
}
