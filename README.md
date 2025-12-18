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
sh script/demo.sh
# deploys mocks + veto + executor on anvil (unlocked accounts),
# propose -> settle -> canExecute true -> execute -> Safe records call
```

Verified run: proposal settled, `canExecute: true`, Safe call to target recorded.

## Deploy (Sepolia, manual v1)

```bash
forge create src/VetoManager.sol:VetoManager --rpc-url $RPC --private-key $PK
forge create src/OptimisticExecutor.sol:OptimisticExecutor \
  --rpc-url $RPC --private-key $PK \
  --constructor-args $SAFE $OOV3 $CURRENCY $LIVENESS $BOND $(cast --format-bytes32-string "ASSERT_TRUTH2") $VETO
# then enable executor as Safe module from Safe owners
```

Note: Sepolia has no UMA DVM per docs. Demo undisputed path only. Disputes need sandbox MockOracle or mainnet.

## Frontend

Deferred v1. Next: single Next.js page (propose / countdown / settle / execute) via wagmi+viem.
