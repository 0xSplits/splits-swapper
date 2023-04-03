// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISplitMain {
    error InvalidSplit__TooFewAccounts(uint256 accountsLength);

    function createSplit(
        address[] calldata accounts,
        uint32[] calldata percentAllocations,
        uint32 distributorFee,
        address controller
    ) external returns (address);

    function transferControl(address split, address newController) external;

    function acceptControl(address split) external;

    function distributeETH(
        address split,
        address[] calldata accounts,
        uint32[] calldata percentAllocations,
        uint32 distributorFee,
        address distributorAddress
    ) external;

    function distributeERC20(
        address split,
        address token,
        address[] calldata accounts,
        uint32[] calldata percentAllocations,
        uint32 distributorFee,
        address distributorAddress
    ) external;
}
