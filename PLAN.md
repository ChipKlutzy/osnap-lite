# oSnap-lite — Optimistic Safe Executor (PLAN)

> Status: DONE + PUSHED. Both live cycles closed (5-min + 2h production params) on Base Sepolia. Dispute drill green. Portfolio card live. Public repo: github.com/ChipKlutzy/osnap-lite.
> Staging dir: `new-chapter/projects/osnap-lite` — name locked.

## 1. Goal

Ship smallest oSnap-style executor that proves senior UMA + Safe skill:

Offchain vote → assert tx bundle truth via UMA OOV3 → pass liveness undisputed → Safe executes.

Portfolio fit: extends Omnichain Escrow (escrow/release) + ONCHAINID (verification) + pSTAKE Safe ops into DAO governance infra.

## 2. Non-goals (ponytail cuts)

- No Snapshot integration. Votes are signed JSON pasted into UI, hashed onchain. Add Snapshot API later.
- No multi-tx bundles v1. Single `to/value/data/operation` per proposal. Bundle later.
- No custom token / DAO token. Bond + reward in one whitelisted ERC20 (WETH or USDC Sepolia).
- No OOV2. OOV3 only. No Polymarket CTF adapter.
- No indexer/subgraph v1. Frontend reads chain via viem + localStorage cache.

## 3. Architecture

```
Proposer (EOA) -> OptimisticExecutor.propose() -> OOV3.assertTruthWithDefaults()
                                             -> Dispute window (liveness)
                                             -> OOV3.settleAssertion()
                                             -> OptimisticExecutor.execute() -> Safe.execTransactionFromModule()
Discord/bot (optional) -> watches AssertionDisputed / Executed events
Next.js dapp -> propose / assert status / countdown / execute
```

Callback path: Executor is `callbackRecipient` in OOV3 assertion. `assertionResolvedCallback(assertionId, assertedTruthfully)` marks proposal settled truthfully or slashed. `execute()` only passes if `settled && assertedTruthfully`.

## 4. Contracts (v1 scope)

Mirrors `omnichain-escrow/src/` layout: `src/`, `test/`, `script/`, `foundry.toml`.

### 4.1 `src/OptimisticExecutor.sol`

State:
- `Safe` + `OOV3` + `bondCurrency` immutables
- `liveness`, `bond` (clamped to `oo.getMinimumBond()`)
- `mapping(bytes32 proposalId => Proposal)` where Proposal = { to, value, data, operation, proposer, assertionId, settled, assertedTruthfully, executed }
- `VetoManager` address (Escalation Manager lite)

Functions:
- `propose(to,value,data,operation, explanation)` → builds claim string, pulls bond, calls `oo.assertTruthWithDefaults`, stores proposalId = keccak(txHash + explanationHash + nonce). Emits `Proposed`.
- `assertionResolvedCallback(assertionId, assertedTruthfully)` — only OOV3. Marks settled.
- `assertionDisputedCallback(assertionId)` — marks disputed, blocks execute.
- `execute(proposalId)` — requires settled + truthful + not executed, calls `Safe.execTransactionFromModule`. Emits `Executed`.
- `emergencyPause/unpause` — owner/guardian only. Blocks propose + execute.
- View: `getAssertion(proposalId)`, `canExecute(proposalId)`.

Claim format (ancillary data via OOV3 defaults):
`Propose Safe tx to {to} value {value} data {dataHash} on chain {chainId} per offchain vote {voteHash}. Explanation: {ipfsOrText}`

### 4.2 `src/VetoManager.sol` (Escalation Manager lite)

- `isVetoed(proposalId)` hook called before execute.
- v1: `owner` + `council` mapping can flag veto within liveness. No token vote.
- Later upgrade: token threshold / UMA EscalationManager interface.

### 4.3 Interfaces / deps (no new deps)

- Reuse UMA `OptimisticOracleV3Interface` via forge remapping or copy from `dev-quickstart-oov3` (MIT).
- Reuse Safe `ISafe` minimal interface (`execTransactionFromModule` only). No safe-contracts npm dep v1; add as git submodule later if needed for Module setup scripts.
- OpenZeppelin `Ownable` only if already in lib; else hand-rolled `owner` (prefer OZ if present).

## 5. Frontend (Next.js + wagmi + viem, mirrors onchainid/app)

Routes (single page v1, 3 panels):
- `/` Propose: inputs to/value/data + explanation, shows bond + liveness, `propose` write.
- Proposal list: proposalId, status (Pending / Disputed / Settled-true / Executed), countdown to `assertionExpiration`, buttons: Settle (calls OOV3), Execute, link to Sepolia Etherscan + UMA CTF UI.
- Guardian: veto flag, pause.

Reads: `viem publicClient` + `useReadContract` for Proposal + `oo.getAssertion`. Writes: `wagmi useWriteContract`.

No backend v1. Vote hash = keccak256 of pasted JSON. Store explanation text onchain only as hash + short string to save gas.

## 6. Testing

- `test/OptimisticExecutor.t.sol`: propose → settle → execute happy path; disputed path blocks execute; only-OO callback reverts; pause blocks; replay (double execute reverts).
- Fork test Sepolia: use real OOV3 + WETH, real Safe (1/1 test Safe).
- Sandbox dispute test: deploy `OracleSandbox.s.sol` flow from quickstart, pushPrice 1e18 / 0, verify callback.
- Gas snapshot + Slither run. Target: same bar as onchainid (42 tests) but v1 needs ~12 focused tests.

## 7. Deploy + demo script

- Network: Sepolia only v1.
- Script `script/Deploy.s.sol`: deploy VetoManager → Executor (args: safe, OOV3 Sepolia, WETH, liveness 7200, bond min), enable Executor as Safe module via `Safe.enableModule`.
- `script/ProposeDemo.s.sol`: propose → assert → fast-forward → settle → execute on fork.
- Frontend env: `NEXT_PUBLIC_EXECUTOR`, `NEXT_PUBLIC_OOV3`, `NEXT_PUBLIC_CHAIN_ID=11155111`.
- Demo video flow: propose 0.001 ETH send → wait liveness → settle → execute → Safe balance change.

## 8. End-to-end build order (no commits until you say)

1. Scaffold: foundry.toml, remappings, src interfaces, failing test (you approve).
2. Executor + VetoManager minimal pass.
3. Tests green + Slither clean.
4. Deploy script + Sepolia fork run.
5. Next.js dapp (3 panels) wired to Sepolia.
6. README + demo + live Sepolia addresses.
7. You review → you say commit → commit + push.

Each step stops for your go-ahead. No `git commit`, no `git push`, no `bd close` until explicit.

## 9. Open decisions (need your pick)

- Repo name (options in chat, staging dir `osnap-lite` renames in one mv).
- Bond currency: WETH (easiest faucet) vs USDC Sepolia.
- Liveness: 2h (UMA default, demo-slow) vs 30min (demo-fast, less secure).
- Safe: reuse existing test Safe vs deploy fresh 1/1 Safe in script.
