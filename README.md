# splits-swapper

[Docs](https://docs.0xsplits.xyz/core/swapper)

## What

Swapper is a payments module that trustlessly & automatically transforms multi-token revenue into a particular output token.
![](https://docs.0xsplits.xyz/_next/image?url=%2F_next%2Fstatic%2Fmedia%2Fswapper_diagram.2f2890db.png&w=3840&q=75)

## Why

Many onchain entities (e.g. creators, collectives, DAOs, businesses) generate onchain revenues in tokens that don't match the denominations of their expenses (e.g. salaries, taxes) resulting in [asset-liability currency mismatch](https://en.wikipedia.org/wiki/Asset%E2%80%93liability_mismatch#Currency_Mismatch).
More generally, many onchain value flows benefit technically and financially from the ability to curate the denomination.

## How

[![Sequence diagram of successful example call to Swapper#flash](https://mermaid.ink/img/pako:eNp9k21r2zAQx7-K0AjeaELLaFfQi0LiJrAXo6wte1PvxcU-t6Ky5J7OHaHku1eSSRPP2Wzww93vHv6S7k2WrkKp5GTyVlghtNWsRPoUIuMnbDBTIluDx2x6aP0FpGFt0GcfeHLWzvIKGm02MS5CZheY_C3pBmiTO-MoEp9W83gfYxaOKqQ9madrQHosna0G-b4tl5eLywHFSKwH0Pxicb7Ks57Zxld4bCeTwhbW40uHtsRrDY8ETSR67p4g9DO7ujq5-wNti_TdMgaEHam0cCsD_qlnR8RBmBL1CIzuG4LSoBKPyD87xzhvXGfZ91zvDNjsIwsc-nd5AnGkuwfBBNbXSCJupWD3jPaz_yJ-j7o4Eu17U5KXgzFrKJ__JXNfP1Zd3uZfz0T4JfeK4lS0sInBf5UdrNJe30jYAi3WuoxbOZCU1Ny7A_dY1-yILnYMZhD3n7b63VdCTmWD1ICuwtSkk1_INBGFDC3LuLyFDIcpcNCxu9vYUiqmDqeyayvg3bmSqgbjgxUrHUr86McwTeP2HWoHLUA?type=png)](https://mermaid.live/edit#pako:eNp9k21r2zAQx7-K0AjeaELLaFfQi0LiJrAXo6wte1PvxcU-t6Ky5J7OHaHku1eSSRPP2Wzww93vHv6S7k2WrkKp5GTyVlghtNWsRPoUIuMnbDBTIluDx2x6aP0FpGFt0GcfeHLWzvIKGm02MS5CZheY_C3pBmiTO-MoEp9W83gfYxaOKqQ9madrQHosna0G-b4tl5eLywHFSKwH0Pxicb7Ks57Zxld4bCeTwhbW40uHtsRrDY8ETSR67p4g9DO7ujq5-wNti_TdMgaEHam0cCsD_qlnR8RBmBL1CIzuG4LSoBKPyD87xzhvXGfZ91zvDNjsIwsc-nd5AnGkuwfBBNbXSCJupWD3jPaz_yJ-j7o4Eu17U5KXgzFrKJ__JXNfP1Zd3uZfz0T4JfeK4lS0sInBf5UdrNJe30jYAi3WuoxbOZCU1Ny7A_dY1-yILnYMZhD3n7b63VdCTmWD1ICuwtSkk1_INBGFDC3LuLyFDIcpcNCxu9vYUiqmDqeyayvg3bmSqgbjgxUrHUr86McwTeP2HWoHLUA)

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

## Setup & test

`forge i` - install dependencies

`forge b` - compile the contracts

`forge t` - compile & test the contracts

`forge t -vvv` - produces a trace of any failing tests

## Natspec

`forge doc --serve --port 4000` - serves natspec docs at http://localhost:4000/
