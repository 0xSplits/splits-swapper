// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";

library TokenUtils {
    address internal constant ETH_ADDRESS = address(0);

    function _isETH(address addr) internal pure returns (bool) {
        return (addr == ETH_ADDRESS);
    }

    function _getBalance(address addr, address token) internal view returns (uint256) {
        return _isETH(token) ? addr.balance : ERC20(token).balanceOf(addr);
    }

    function _getDecimals(address token) internal view returns (uint8) {
        return _isETH(token) ? 18 : ERC20(token).decimals();
    }
}
