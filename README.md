# Sentinel Contracts

The Move 2024.beta package for [Sentinel Protocol](https://github.com/Sentinel-AI-Protocol) — the
on-chain core that makes an AI agent's trading authority **bounded and self-enforced**. This is the
source of truth: budget caps, pool scope, expiry, and revocation are enforced *here*, not in the
backend.

> **Part of a polyrepo.** The [backend](https://github.com/Sentinel-AI-Protocol/backend) builds PTBs
> that call this package — point its `SENTINEL_PACKAGE_ID` at the `published-at` id in
> [`Published.toml`](Published.toml). The [frontend](https://github.com/Sentinel-AI-Protocol/frontend)
> renders the events these modules emit.

## Modules

| Module | Role |
| --- | --- |
| [`agent_policy.move`](sources/agent_policy.move) | The core `AgentPolicy` object — owner/agent/status/budget/expiry/nonce, `PoolRule`s, `Reservation`s. Budget-mutating `validate_and_consume` / `release_reservation` are `public(package)`, so **only the adapter can spend**. |
| [`deepbook_adapter.move`](sources/deepbook_adapter.move) | `place_limit_order_with_policy` / `cancel` / `modify`, generic over `<BaseAsset, QuoteAsset>`. The only path that mutates a policy's spent budget — keeps the core protocol-agnostic. |
| [`activity_log.move`](sources/activity_log.move) | Canonical event structs (`PolicyCreated`, `OrderPlaced`, `BudgetConsumed`, …). These are the indexer's contract — `OrderPlaced`/`BudgetConsumed` carry `risk_score: u64` + `reason_code`. |
| [`budget.move`](sources/budget.move), [`revocation.move`](sources/revocation.move) | Shared helpers — budget assertion; status enum (`active=0 / paused=1 / revoked=2 / expired=3`). |

## Enforced invariants (error codes)

`agent_policy::validate_and_consume` aborts with these codes — this is what a leaked agent key runs
into:

| Code | Error | Meaning |
| --- | --- | --- |
| 1 | `E_NOT_OWNER` | Owner-only action attempted by another address. |
| 2 | `E_NOT_AGENT` | Caller is not the policy's authorized agent. |
| 3 | `E_POLICY_NOT_ACTIVE` | Policy paused or revoked (the revocation guarantee). |
| 4 | `E_POLICY_EXPIRED` | Past the policy's expiry timestamp. |
| 5 | `E_POOL_NOT_ALLOWED` | Pool isn't in the policy's allowed set. |
| 6 | `E_ORDER_TOO_LARGE` | Exceeds the per-order cap. |
| 7 | `E_BUDGET_EXCEEDED` | Would exceed the remaining global budget. |
| 8 | `E_SLIPPAGE_EXCEEDED` | Order price outside the allowed band. |
| 9 | `E_BALANCE_MANAGER_MISMATCH` | Wrong DeepBook `BalanceManager`. |
| 10 | `E_REVOKED` | Policy revoked. |
| 11 | `E_POOL_CONFIG_LENGTH_MISMATCH` | Malformed pool config at creation. |
| 12 | `E_BALANCE_MANAGER_ALREADY_SET` | `BalanceManager` already bound. |
| 13 | `E_UNKNOWN_RESERVATION` | Releasing a reservation that doesn't exist. |

## Build & test

```bash
sui move build
sui move test                  # all Move tests
sui move test agent_policy     # filter by name substring
```

## Deployed (Sui testnet)

The package is published to **testnet** — ids are in [`Published.toml`](Published.toml):

- **published-at:** `0x88bcaa7dc74c1c0dbec2429a1a96e088cec566f6eb4dc8cfb7f027fe480ca035`
  ([Sui Explorer](https://suiscan.xyz/testnet/object/0x88bcaa7dc74c1c0dbec2429a1a96e088cec566f6eb4dc8cfb7f027fe480ca035))
- **upgrade-capability:** `0x9f97d8b6de3d6db7e14d2e5a6c9597de515867deab212223d7642f21f78fb648`

> **DeepBook version pin.** [`Move.toml`](Move.toml) pins DeepBook to `testnet-v17.0.0` (compiles
> `current_version = 5`). The live DEEP_SUI pool enables `allowed_versions = {1..5}`; linking against
> the newer (published-but-not-enabled) v6 package aborts with `EPackageVersionDisabled` (code 11) in
> `pool::load_inner`. Keep this pin until the pools enable v6.
