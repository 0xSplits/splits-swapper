// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IWETH9} from "splits-utils/interfaces/external/IWETH9.sol";

import {SwapperFactory} from "../src/SwapperFactory.sol";
import {UniV3Swap} from "../src/integrations/UniV3Swap.sol";

contract UniV3SwapScript is Script {
    using stdJson for string;

    address swapperFactory;
    address swapRouter;
    address weth9;

    function run() public returns (UniV3Swap us) {
        // https://book.getfoundry.sh/cheatcodes/parse-json
        string memory json = readInput("inputs");

        swapperFactory = json.readAddress(".swapperFactory");
        swapRouter = json.readAddress(".swapRouter");
        weth9 = json.readAddress(".weth9");

        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        us = new UniV3Swap({
            swapperFactory_: SwapperFactory(swapperFactory),
            swapRouter_: ISwapRouter(swapRouter),
            weth9_: IWETH9(weth9)
        });

        vm.stopBroadcast();

        console2.log("UniV3Swap Deployed:", address(us));
    }

    function readInput(string memory input) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/input/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(input, ".json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }
}
