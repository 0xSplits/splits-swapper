# splits-swapper

[Docs](https://dev.docs.0xsplits.xyz/core/swapper)

## Why

Many onchain entities (e.g. creators, collectives, DAOs, businesses) generate onchain revenues in tokens that don't match the denominations of their expenses (e.g. salaries, taxes) resulting in [asset-liability currency mismatch](https://en.wikipedia.org/wiki/Asset%E2%80%93liability_mismatch#Currency_Mismatch).
More generally, many onchain value flows benefit technically and financially from the ability to curate the denomination.

## What

Swapper is a payments module that trustlessly & automatically transforms multi-token revenue into a particular output token.
![](https://docs.0xsplits.xyz/_next/image?url=%2F_next%2Fstatic%2Fmedia%2Fswapper_diagram.2f2890db.png&w=3840&q=75)

## How

[![](https://mermaid.ink/img/pako:eNp9UkFOwzAQ_IrlE4hGII4-VIICEgeEoL0RDltn01p17GCvQVHVv-PEKk1IwAdL9szs7Ni759IWyAX3-BHQSLxTsHFQsbhy0-4rBwW6bD6_WH5BXaN7NISRQtYJpoyiBw1-m7gjRk8mWDkitvCzA6lRsA3SS7CEN5UNhnziJTDSsp8q0MePdSJjors3Rg6ML9GxNXhkZHdozvw5ex91MaH26aqLtwCt1yB3f8U8-beu96-L6ysWj85-IrtkNTSt-Jft4JVO-UbBbtFgqaQC1wwidWlWtgePc2UTucgS6IHun7bS7wvGZ7xCV4Eq4qzsW0HOaYsV5jy2zAssIWjKeW4OkQqB7LIxkgtyAWc81AXQcbS4KEH7eIuFii5Paf66MTx8AxNR4rU?type=png)](https://mermaid.live/edit#pako:eNp9UkFOwzAQ_IrlE4hGII4-VIICEgeEoL0RDltn01p17GCvQVHVv-PEKk1IwAdL9szs7Ni759IWyAX3-BHQSLxTsHFQsbhy0-4rBwW6bD6_WH5BXaN7NISRQtYJpoyiBw1-m7gjRk8mWDkitvCzA6lRsA3SS7CEN5UNhnziJTDSsp8q0MePdSJjors3Rg6ML9GxNXhkZHdozvw5ex91MaH26aqLtwCt1yB3f8U8-beu96-L6ysWj85-IrtkNTSt-Jft4JVO-UbBbtFgqaQC1wwidWlWtgePc2UTucgS6IHun7bS7wvGZ7xCV4Eq4qzsW0HOaYsV5jy2zAssIWjKeW4OkQqB7LIxkgtyAWc81AXQcbS4KEH7eIuFii5Paf66MTx8AxNR4rU)

### How does it swap?

Directly with traders via integration contracts required to handle `#flash`'s callback `#swapperFlashCallback`.

### How does it price swaps?

Modularly, via each Swapper's designated [IOracle](https://github.com/0xSplits/splits-oracle/blob/main/src/interfaces/IOracle.sol).
Each Swapper may also apply it's own default & quote-specific scaling factors to said oracle's pricing.

### How is it governed?

A Swapper's owner, if set, has _FULL CONTROL_ of the deployment.
It may, at any time for any reason, change the `beneficiary`, `tokenToBeneficiary`, `oracle`, `defaultOfferScaledFactor`, `pairScaledOfferFactors`, as well as execute arbitrary calls on behalf of the Swapper.
In situations where flows ultimately belong to or benefit more than a single person & immutability is a nonstarter, we strongly recommend using multisigs or DAOs for governance.
To the extent your oracle has an owner as well, this same logic applies.

## Lint

`forge fmt`

## test

`forge test` - compile & test the contracts

`forge t -vvv` - produces a trace of any failing tests
