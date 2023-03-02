// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";

library TokenUtils {
    address internal constant ETH_ADDRESS = address(0);

    function getBalance(address addr, address token) internal view returns (uint256) {
        return isETH(token) ? addr.balance : ERC20(token).balanceOf(addr);
    }

    function isETH(address addr) internal pure returns (bool) {
        return (addr == ETH_ADDRESS);
    }
}
