// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract UniV3OracleDataScript is Script {
        address[3] tokens = [
                                    0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                                    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                                    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 // WETH
                             ];

        string[3] tokensStr = [
                                      "DAI", // DAI
                                      "USDC", // USDC
                                      "WETH" // WETH
                                    ];

        uint24[4] fees = [
                          uint24(1_00),
                          uint24(5_00),
                          uint24(30_00),
                          uint24(100_00)
                          ];

        string[4] feesStr = [
                                      "0.01%",
                                      "0.05%",
                                      "0.3%",
                                      "1.0%"
                                      ];

        uint32[5] periods = [
                                 uint32(1 minutes),
                                 uint32(5 minutes),
                                 uint32(10 minutes),
                                 uint32(30 minutes),
                                 uint32(1 hours)
                                 ];

        uint128 constant baseAmount = 1e18;

    function setUp() public {}

    function run() public {
        IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i; j < tokens.length; j++) {
                if (i == j) continue;

                for (uint256 k = 0; k < fees.length; k++) {
                    address pool = uniswapV3Factory.getPool(tokens[i], tokens[j], fees[k]);
                    if (pool == address(0)) {
                        console.log("no pool for (%s, %s, %s)", tokensStr[i], tokensStr[j], feesStr[k]);
                        continue;
                    }

                    console.log();
                    console.log("pool %s", pool);
                    console.log("(%s, %s, %s)", tokensStr[i], tokensStr[j], feesStr[k]);
                    (
                     uint160 sqrtRatioX96,
                     int24 tick,
                     ,
                     uint16 observationCardinality,
                     ,
                     ,
                     ) = IUniswapV3Pool(pool).slot0();

                    console.log("tick: ");
                    console.logInt(tick);
                    console.log("sqrtRatioX96: %s", sqrtRatioX96);

                    uint256 quoteAmount = OracleLibrary.getQuoteAtTick({
                                                                 tick: tick,
                                                                 baseAmount: baseAmount,
                                                                 baseToken: tokens[i],
                                                                 quoteToken: tokens[j]
                                                                 });
                    console.log("receive %s of %s for", quoteAmount, tokensStr[j]);
                    console.log(" %s of %s", baseAmount, tokensStr[i]);
                    console.log("num observations: ", observationCardinality);

                    console.log("twaps:");
                    for (uint256 a = 0; a < periods.length; a++) {
                        uint32 period = periods[a];

                        uint32[] memory secondsAgo = new uint32[](2);
                        secondsAgo[0] = period;
                        secondsAgo[1] = 0;

                        // consult reverts if not enough observations
                        try IUniswapV3Pool(pool).observe(secondsAgo) {
                            (int24 arithmeticMeanTick,) = OracleLibrary.consult({pool: pool, secondsAgo: period});
                            quoteAmount = OracleLibrary.getQuoteAtTick({
                                tick: arithmeticMeanTick,
                                baseAmount: baseAmount,
                                baseToken: tokens[i],
                                quoteToken: tokens[j]
                                });
                            console.log("%s second twap", period);
                            console.log("   tick:");
                            console.logInt(arithmeticMeanTick);
                            console.log("   receive %s of %s for", quoteAmount, tokensStr[j]);
                            console.log("    %s of %s", baseAmount, tokensStr[i]);
                        } catch {
                            console.log("- %s second twap: not enough observations", period);
                        }
                    }

                }
            }
        }
    }
}
