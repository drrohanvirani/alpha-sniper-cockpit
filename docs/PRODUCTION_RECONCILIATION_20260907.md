# Alpha OS Production Reconciliation — 2026-09-07

> **DO NOT REPLAY — SUPERSEDED BY VERIFIED PRODUCTION HARDENING.**
>
> The older checked-in [20260905_alpha_preopen_lock_v1.sql](https://github.com/drrohanvirani/alpha-sniper-cockpit/blob/dea66682f7b1a4c3504e0042ec96e6186b5826dc/supabase/migrations/20260905_alpha_preopen_lock_v1.sql)
> on `alpha-preopen-lock-v1` is **SUPERSEDED / DO NOT REPLAY against production**.
> It is historical repository source, not the current production recovery definition.

## Evidence provenance and scope

Production verification source: the repository owner independently checked live
Supabase production and supplied the findings recorded below on 2026-09-07.
**VERIFIED PRODUCTION FACT** means owner-verified production evidence reported
to Codex; it does not mean Codex independently queried or tested production.
This change records that verification report, not a captured source export.
Raw catalog output, complete deployed function definitions, exact overload
signatures, and a production capture timestamp were not supplied with the report.

**GITHUB FACT** means a fact established from repository source at an identified
commit. **OPEN RISK** means an unresolved issue requiring a future, separately
approved investigation or repair. A production observation can also support an
open risk; the labels distinguish evidence from remediation status.

Repository baseline: `main` at
`e3c32fa0555a6950572b67a9a99817a3d543073c`.
Historical migration source: `alpha-preopen-lock-v1` at
`dea66682f7b1a4c3504e0042ec96e6186b5826dc`.

This is a repository-only documentation change. No production operations,
SQL changes, migrations, deployment, investment-logic changes, or new features
are authorized by this document.

## VERIFIED PRODUCTION FACT — Migration history

The owner's production verification confirms these migrations are present:

- `alpha_preopen_route_lock_v1_production`
- `alpha_preopen_route_lock_integration_v1`
- `alpha_route_execution_safety_hardening_v1`

## VERIFIED PRODUCTION FACT — Direct execution claim disabled

Current production `alpha_claim_route_execution()` is disabled and raises:

```text
DIRECT_ROUTE_EXECUTION_DISABLED_USE_BROKER_RECONCILIATION
```

The older GitHub implementation must not be used to describe the current
production behavior of this function.

## VERIFIED PRODUCTION FACT — Route creation is preauthorization only

Current production `alpha_create_campaign_route()`:

- Calculates structural risk/reward (R:R).
- Blocks R:R below 3.
- Otherwise creates `PREAUTHORIZED` routes.

Route creation is not execution or independent capital authority.

## VERIFIED PRODUCTION FACT — Broker-fill reconciliation

Current production `alpha_reconcile_route_execution_from_broker()`:

- Uses normalized broker BUY fills.
- Is the path that marks approved routes `EXECUTED`.

An internal execution claim is not a substitute for broker-fill reconciliation.

## VERIFIED PRODUCTION FACT — RLS is enabled

The owner's verification reports that critical Alpha route tables currently
have row-level security (RLS) enabled.

This does not establish the exact policy inventory or prove that
`SECURITY DEFINER` RPC functions are protected. Function ownership, execution
grants and authorization checks must be assessed separately.

## GITHUB FACT — Historical SQL differs from production

The older checked-in migration contains behavior that differs from the
owner-verified production hardening:

- `alpha_claim_route_execution()` directly marks a route `EXECUTED`.
- `alpha_create_campaign_route()` normally assigns `CAPITAL_READY` and
  does not enforce the reported production R:R-below-3 block.
- The migration does not contain the complete production hardening,
  broker-fill reconciliation implementation, or current access-control setup.
- Its `CREATE OR REPLACE FUNCTION` statements could replace existing
  function behavior if replayed.

**DO NOT REPLAY — SUPERSEDED BY VERIFIED PRODUCTION HARDENING.**

This warning applies to
`supabase/migrations/20260905_alpha_preopen_lock_v1.sql` on the historical
branch identified above. No SQL file has been edited by this documentation
change. The older migration plan and deployment notes on that branch are
historical references, not current executable recovery instructions.

GitHub remains an incomplete production recovery copy. Recording production
facts does not supply the missing deployed definitions or establish full parity.

## OPEN RISK — A. Same-day capital lock can be reset

**VERIFIED PRODUCTION FACT (owner-reported):**
`alpha_lock_session_capital()` can overwrite/reset an existing same-day
session lock, including execution and invalidation state, when called again.
The owner reports that this low-level function is service-role restricted.

**OPEN RISK:** Backend access restriction does not prevent an authorized caller,
retry or repeated invocation from resetting protected session state. Same-day
ownership and terminal-state preservation require a separately approved repair.

## OPEN RISK — B. Route upsert can reset state

**VERIFIED PRODUCTION FACT (owner-reported):**
The `alpha_create_campaign_route()` upsert can reset route runtime/execution
fields when called again.

**OPEN RISK:** Initial R:R checks and PREAUTHORIZED creation do not resolve
repeated-call state preservation. A future repair must assess idempotency and
preserve protected execution/terminal state without changing investment policy.

## OPEN RISK — C. Privileged pre-open function has broad execute grants

**VERIFIED PRODUCTION FACT (owner-reported):**
`alpha_lock_capital_owner_preopen()` is `SECURITY DEFINER` and currently
has execute grants including `PUBLIC`, `anon` and `authenticated`.

**OPEN RISK:** Execution access should be reviewed and likely restricted to
the appropriate backend role. Determine the exact function overloads, owners,
effective privileges and legitimate callers before proposing grant changes.
Do not assume route-table RLS alone protects this privileged RPC function.

No grant changes are authorized or performed by this document.

## Future repair boundary

The next candidate engineering repair is capital-lock/access-control hardening,
with regression tests first and separate explicit approval.

Before that repair, obtain sanitized read-only definitions and permissions for
the affected functions, their callers and relevant triggers/policies. Plan
isolated regression cases for same-day relocking, repeated route creation,
execution/invalidation preservation, permitted backend callers and rejection
of unauthorized roles. Keep direct execution claims disabled and preserve
broker-confirmed execution semantics.

This document does not authorize implementing those tests or repairs, running
them against production, deploying anything, or merging branches.
