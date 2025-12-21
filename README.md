# osnap-lite

Optimistic Safe executor via UMA OOV3. Propose Safe tx, assert truth, settle, execute if undisputed and unvetoed.

## Why

Portfolio piece: oSnap-style DAO execution without oSnap dep (deprecated Dec 2025). Zero deps, Foundry only.

## Contracts

- `src/OptimisticExecutor.sol` — propose / settle / execute, OOV3 callbacks, pause, veto check.
- `src/VetoManager.sol` — owner + council veto flags.

Uses `assertTruth` with explicit `ASSERT_TRUTH2`. Never `assertTruthWithDefaults` (reverts since deprecation).

Safe sources for mastercopy deploy (gitignored): `forge install --no-git safe-global/safe-smart-account@v1.3.0`.

## Test + audit

```bash
forge build
forge test -vv   # 4/4 pass
slither .        # no highs; timestamp/immutable/naming notes only, accepted
```

## Demo (local fork-equivalent, no RPC needed)

```bash
sh script/demo.sh          # happy path: propose -> settle -> execute
sh script/demo.sh dispute  # dispute drill: disputed proposal cannot execute
```

Verified runs: happy path executes, dispute path `canExecute: false` + execute reverts.

## Deploy (Sepolia, manual v1)

```bash
forge create src/VetoManager.sol:VetoManager --rpc-url $RPC --private-key $PK
forge create src/OptimisticExecutor.sol:OptimisticExecutor \
  --rpc-url $RPC --private-key $PK \
  --constructor-args $SAFE $OOV3 $CURRENCY $LIVENESS $BOND $(cast --format-bytes32-string "ASSERT_TRUTH2") $VETO
# then enable executor as Safe module from Safe owners
```

Note: Sepolia has no UMA DVM per docs. Demo undisputed path only. Disputes need sandbox MockOracle or mainnet.

## Live — Base Sepolia (deployed)

OOV3 `0x0F7fC5E6482f096380db6158f978167b57388deE`, bond currency TestnetERC20
`0x7E6d9618Ba8a87421609352d6e711958A97e2512` (minBond 0, liveness 7200, identifier `ASSERT_TRUTH`).

| Contract | Address |
|---|---|
| Safe (1/1) | `0xcb71baacd18ec3d56b09c326977f25560f21113f` |
| GnosisSafe mastercopy | `0x2fD026d5fCb0d9753345b259c95f41365C03dD30` |
| ProxyFactory | `0x372b1E5cF96f656626FDD361bd065D743a08B4bB` |
| VetoManager | `0xB0f1f573E55AEf5A05D6C80b9Ec0F39Aa33De52B` |
| OptimisticExecutor | `0xb29B98104AF6a958E468DEbE9c1755451AEad23F` |

First proposal live: `0xdfe27748c89a32a1be23ebe320567d53ce56de56f7287e3fdc69d38ba78d0761`
(assertion `0x21523d9ff5332916fbd42fe59ba74b8c801dca645d8a52b1973744277fca6c26`,
tx `0x8b41a4ec0f75b32f2b7188cee0fb147b2a47b4949990c7f68f74c5f494e45872`).
Production-parameter cycle closed too (7200s liveness):

- settle tx `0x74c42460cde989504c34a5cb23dcd8f1964eeb4d97d75dde55a6241905b43df8` (truthful callback)
- execute tx `0x3e8987c350c92e1eaf67d2ab36dc7dc0aa5db148a8943236d33001e77546b0c3`
- Safe paid 0.0001 ETH to owner: balance 0.00025 → 0.00015 ETH.

Full replay: `sh script/base-deploy.sh` (needs Safe redeploy salt bump).

## Live demo — full cycle closed (5-min executor)

Executor `0x23760C09F6A77f62803583d646E65B99C2659D69` (liveness 300, same Safe/Veto/OOV3).
Proposal `0xb25f3938bc319daa98d2c591a9424c92c102d1be17036c9649f72610245e17fc`
pays 0.00005 ETH to owner:

- propose tx `0x9c27a5b563a879457b13eb0cd87b722aa18f5cf0236e199c0a96704232f21951`
- settle → `canExecute: true`
- execute tx `0x7ad207f44c1c8088c8ceb7dc214db47a4c6904493d29d9001e55632bb78b48a1` (ExecutionSuccess + Executed)
- Safe `0xcb71...113f` balance 0.0003 → 0.00025 ETH. Payout landed.

## Frontend

`app/index.html` — single static page, viem via CDN, no build. Connect, approve bond, propose, refresh/countdown, settle, execute, veto. Anvil + Sepolia + Base Sepolia switch, live addresses prefilled.
