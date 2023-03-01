// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

library TokenUtils {
    function getBalance(address addr, address token) internal view returns (uint256) {
        return token.isETH() ? addr.balance : token.balanceOf(addr);
    }

    function isETH(address addr) internal pure returns (bool) {
        return (addr == ETH_ADDRESS);
    }
}
