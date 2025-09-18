// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {SwapperFactory} from "../src/SwapperFactory.sol";
import {UniversalSwap} from "../src/integrations/UniversalSwap.sol";

contract UniversalSwapScript is Script {
    using stdJson for string;

    function run() public returns (UniversalSwap us) {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        us = new UniversalSwap{salt: keccak256("splits.universalSwap.v1")}();

        vm.stopBroadcast();

        console2.log("UniversalSwap Deployed:", address(us));
    }
}
