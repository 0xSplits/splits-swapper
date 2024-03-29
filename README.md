# splits-swapper

[Docs](https://docs.0xsplits.xyz/core/swapper)

## What

Swapper is a payments module that trustlessly & automatically transforms multi-token revenue into a single output token
![](https://docs.0xsplits.xyz/_next/image?url=%2F_next%2Fstatic%2Fmedia%2Fswapper_diagram.2f2890db.png&w=3840&q=75)

## Why

Many onchain entities (e.g. creators, collectives, DAOs, businesses) generate onchain revenues in tokens that don't match the denominations of their expenses (e.g. salaries, taxes) resulting in [asset-liability currency mismatch](https://en.wikipedia.org/wiki/Asset%E2%80%93liability_mismatch#Currency_Mismatch).
More generally, many onchain value flows benefit technically and financially from the ability to curate the denomination.

## How

[![Sequence diagram of successful example call to Swapper#flash](https://mermaid.ink/svg/pako:eNqNlE2P0zAQhv-KZVQFRCuqbbetclipCY3EASHYFRfCYZpMd6117GBPFqpV_zt2rG6bJqy45MPzzDvz-uuZF7pEHvPR6DlXjAklKGbtJ2MRPWCFUcyiLViMxuej38EI2Eq00QveBndaUQaVkHuf5yF5TAzJ-IdSLbXx4TeLZHm1mnaA2ogKzP7EZLNsni2GmESbEs2rahYLrcqO3mKzWSbLYepScTpfrq67LBQknoCEVv8BExoSnerr62SepYPQpd58Nlul6yiQB_9yj8NolKtcWfzVoCrwo4B7A5UnAndnwIlMbm7e3_6GukbzSRE6hLSJ29XNJNiHwPaIs7SY7XqgD38xUEiM2T3S10YTrivdKLKBC0GHTV5U4Dx-1HHEQHc_GBlQdoeG-f3GSD-iemvfsZ-9LgaybRhq7aUg5RaKx3_ZPNX3VTff0qspc79GPyH7wGrY--SLsp1ZOvnrGUtQ4U4UfkE7llo3d_os3Pc1GfBFmkB28l5pK6x-zPiYV2gqEKU72u3xzHl7bHPuWuZ-enPuNpPjoCF9u1cFj8k0OOZNXQId99VxEEvhKnwOV0V7Yxz-An7IWig)](https://mermaid.live/edit#pako:eNqNlMtu2zAQRX-FYGGoRW3UiB3b0CKApVpAFkGQJuim6mIsjRIiFKmSo7RG4H8vKcGxZalBN3pwztyZy9crz3SOPOSj0WuqGBNKUMiaT8YCesISg5AFW7AYjE9Hv4MRsJVogze8CRZaUQKlkDuf5yF5SGyT8Q_FWmrjwx8W0fJiNe0AlRElmN2RSWbJPFkMMZE2OZp31SxmWuUdvcVms4yWw9S54nS-XF12WchIvAAJrf4DJjQkOtXXl9E8iQehc735bLaK10FL7v3LPfajUapSZfFXjSrDrwIeDZSeaLkHA05kcnX1-f43VBWaa0XoENImbFY3kWCfWrZHnKSFrOiBPnxrIJMYskeku1oTrktdK7It1wYdNnlTgdP4QccRA939YGRA2QIN8_uNkX5G9dF-Yj97XQxk23aosReDlFvInv9l81jfV918iy-mzP0a_YLsC6tg55PPynZm6eivZyxChYXI_IJ2LDVuHvRJuO9rMuCLNIHs5L3TVrv6IeNjXqIpQeTuaDfHM-XNsU25a5n76U2520yOg5r0_U5lPCRT45jXVQ502Fc8LEBaN4q5cCVu2ruiuTL2fwHX4Vpz)

### How does it swap?

Directly with traders via integration contracts required to handle `#flash`'s callback `#swapperFlashCallback`.

### How does it price swaps?

Modularly, via each Swapper's designated [IOracle](https://github.com/0xSplits/splits-oracle).
Each Swapper may also apply it's own default & quote-specific scaling factors to said oracle's pricing.

### How is it governed?

A Swapper's owner, if set, has _FULL CONTROL_ of the deployment.
It may, at any time for any reason, change the `beneficiary`, `tokenToBeneficiary`, `oracle`, `defaultOfferScaledFactor`, `pairScaledOfferFactors`, as well as execute arbitrary calls on behalf of the Swapper.
In situations where flows ultimately belong to or benefit more than a single person & immutability is a nonstarter, we strongly recommend using a multisig or DAO for governance.
To the extent your Oracle has an owner as well, this same logic applies.

## Lint

`forge fmt`

## Setup & test

`forge i` - install dependencies

`forge b` - compile the contracts

`forge t` - compile & test the contracts

`forge t -vvv` - produces a trace of any failing tests

## Natspec

`forge doc --serve --port 4000` - serves natspec docs at http://localhost:4000/
