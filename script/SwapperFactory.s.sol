// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {SwapperFactory} from "../src/SwapperFactory.sol";

contract SwapperFactoryScript is Script {
    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        new SwapperFactory{salt: keccak256("0xSplits.swapper.v1")}();

        vm.stopBroadcast();
    }
}
