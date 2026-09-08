# Same-day capital lock immutability — prepared repair

Implemented and tested in isolated in-memory PostgreSQL only. NOT MERGED;
NOT DEPLOYED. Production, main, cron and automation untouched.

This implements the approved proposal from
`2f83e3ceb5d85f88427b3de728c1bbf5a45bb489` on the same branch,
`fix/session-capital-lock-immutability`. Its earlier ACL migration-ID alignment
is unchanged: production `20260907143201` maps to the verified ACL repair from
`3af434db`. No second ACL migration is introduced.

## Evidence and scope

The owner supplied current production helper/bridge definitions, session-table
shape, trigger inventory and backend-only access facts from a read-only pull.
Codex reviewed that source; it did not query production or independently verify
current live hashes. The isolated baseline file is a formatting-condensed copy
of supplied behavior, not a verified production recovery artifact.

Migration `supabase/migrations/20260908125005_session_capital_lock_immutability.sql`
was generated with Supabase CLI 2.116.0. It contains only two replacements:

```text
public.alpha_lock_session_capital(date,text,text,numeric,numeric,numeric,timestamptz,text)
public.alpha_sync_session_lock_from_brain()
```

No grants, table/schema changes, new functions/triggers, policy thresholds,
route logic, broker reconciliation, cron or automation changes. Signatures,
SECURITY DEFINER, search_path, owners and existing ACLs remain unchanged.
Both functions must already exist with the verified postgres/service_role ACLs.
Apply both replacements in ONE transaction only after separate approval and
baseline verification. This is not a recovery migration for an empty database.

## Function diff summary

| Path | Old behavior | Prepared behavior |
| --- | --- | --- |
| Helper first valid call | Creates LOCKED and first financial snapshot/event | Unchanged |
| Helper same owner/campaign retry | Rewrites state, balances, counters, timestamps and execution/invalidation references; repeats event | Returns entire stored row; no UPDATE or event |
| Helper different owner/campaign | Overwrites same-date row | Raises P0001 / SESSION_CAPITAL_LOCK_CONFLICT; unchanged row |
| Bridge existing same usable identity | Repeats helper/direct upsert and route/queue writes; reports LOCKED | Actual status and stored row, idempotent_retry=true; exits before downstream effects |
| Bridge usable different identity | Can replace session | ok=false, SESSION_CAPITAL_LOCK_CONFLICT, existing_status, preserved owner/campaign and session |
| Bridge invalid/stale input with existing row | Can overwrite state or set DATA_BLOCKED | ok=false, SESSION_LOCK_PRESERVED_CURRENT_INPUT_INVALID, reason, existing_status and preserved session; no write |
| Bridge first call without row | First DATA_BLOCKED / KEEP_CASH / LOCKED plus initial routes/queue | Original first-create interpretation; three reset upserts replaced by INSERTs under shared lock |

Identity is trade_date, upper(ticker) and NULL-safe campaign equality. Uppercase
normalization follows the existing implementation; no new trimming rule.
Cash/NAV/reservation/remaining cash/expiry/created_by are NOT retry identity.
Valid financial refreshes preserve the first snapshot. Helper validation still
runs before handling retries. All statuses, including DRAFT, are preserved.
A first DATA_BLOCKED row without owner/campaign stays authoritative; a later
usable different identity conflicts rather than reopening it.

The bridge keeps weekday and 09:15 checks. Under the shared lock it selects the
existing row FOR UPDATE before any write. An existing-row-only resolution block
classifies current evidence without writes; malformed numeric/date/items input
returns preservation with a reason. Unexpected database errors are not swallowed
as successful retries. With no existing row, the original first-create code
continues apart from its three INSERT-only replacements. The complete initial
route/queue tail is byte-identical to the supplied test baseline.

## Locking and concurrency

Both functions acquire `pg_catalog.pg_advisory_xact_lock(1095520332, date_key)`.
Namespace `1095520332` is `0x414C504C` (ALPL); date_key is the signed integer
number of days since `2000-01-01`. Helper uses p_trade_date; bridge uses v_day.
Lock order: transaction advisory lock, then SELECT session FOR UPDATE. The
bridge's helper call reacquires its own transaction lock. No new framework/table.

Under READ COMMITTED the intended result is that the second creator waits,
then observes the committed winner and returns a retry/conflict. Primary-key
uniqueness remains a backstop; there is no overwrite fallback. Stronger isolation
can require whole-transaction retry after serialization/uniqueness failure.
Failures must not be converted into successful allocations. Only cooperating
writers use the advisory lock. Legitimate forward updates may temporarily wait
on row locks; no trigger or permanent restriction blocks them.

**P concurrency = NOT PROVEN.** No native psql, postgres server or Docker was
available on PATH. PGlite is single-session; serial calls are not race evidence.

Required native isolated design before deployment:

1. Use a disposable PostgreSQL matching production's major version and TWO
   independent connections A/B with sanitized verified definitions. Run bridge
   cases in a controlled weekday pre-open fixture window; never alter production
   clocks or patch the submitted target-function source for these tests.
2. A begins, invokes the first creator and stays uncommitted. Capture its full
   row and events/routes/queue. Issue B's same-date call asynchronously; observe
   its advisory-lock wait using pg_locks/wait_event before releasing A.
3. Commit A. B must return exactly the winner for identical identity, or the
   helper exception/bridge conflict for different identity. Assert one session,
   one set of first-create effects, and zero loser writes.
4. Cover helper/helper identical and conflicting, bridge/bridge identical and
   conflicting, helper/bridge in BOTH orderings, refreshed financials,
   KEEP_CASH/DATA_BLOCKED first paths and an already EXECUTED winner with IDs.
5. Repeat with A rolled back so B becomes sole creator; test different dates
   do not contend; run actual caller isolation levels and retain both responses,
   wait evidence and snapshots. Exercise actual forward writers concurrently
   to check lock ordering and transaction-retry behavior.

## Executed isolated tests

PostgreSQL 18.3 via PGlite 0.5.8, Node 24.19; fresh in-memory databases only.
The candidate migration is executed byte-for-byte. The fixture replaces
pg_catalog.now() ONLY in its disposable database to make pre-open deterministic.
The runner accepts no database URL or production credentials.

| Case | Result |
| --- | --- |
| A first LOCKED row, financials, counters, flags, first event | PASS |
| B identical retry; full row/UUID/timestamps unchanged; no second event | PASS |
| C refreshed cash/NAV/reserved/expiry/provenance; normalized owner | PASS |
| D different owner conflict; row/effects unchanged | PASS |
| E different campaign conflict; row/effects unchanged | PASS |
| F TRIGGERED preservation | PASS |
| G EXECUTED counters and valid execution IDs preserved | PASS |
| H KEEP_CASH preservation | PASS |
| I DATA_BLOCKED and invalidation reason preserved | PASS |
| J CANCELLED preservation | PASS |
| K EXPIRED preservation | PASS |
| L bridge all-status retries; no route/queue/event changes; truthful status | PASS |
| M bridge owner/campaign/CASH conflict | PASS |
| N stale/malformed/missing/invalid input preserves existing row | PASS |
| O non-target definition/ACL snapshots and forward table updates | PASS — isolated metadata/table contract only |
| P independent-session concurrency | NOT PROVEN |
| Extra DRAFT, NULL campaign, validation, first-create branches, cutoff/weekend, bridge financial refresh | PASS |

Negative control: the same cases B-N reject the original functions in a separate
disposable instance. The runner fails if the candidate fails or the original
defect controls unexpectedly pass. First-create controls pass on both versions.

Before/after migration snapshots cover non-target public definitions, owners,
ACLs and attributes; target owners/ACLs/attributes; table columns, constraints,
triggers, RLS/grants; and data. Retry tests compare all session fields and full
route/queue/event records. No deployment-time data migration occurs.

**O limitation:** the complete live bodies/signatures of evaluator, reconciliation,
expiry and monitor were not supplied. The fixture labels these four functions
as metadata sentinels, not live implementation copies. Snapshot comparisons prove
the migration leaves these non-target definitions/ACLs unchanged. Direct table
updates prove it adds no prohibition on forward statuses. This does NOT prove
their actual production integration. Snapshot all real overloads before/after
any separately approved native rehearsal/deployment; no production snapshot was
taken in this task.

Reproduce with pinned @electric-sql/pglite 0.5.8 in an isolated tools directory,
outside application dependencies. Set PGLITE_MODULE to its absolute dist/index.js
(or provide that package through Node module resolution), then run:

```text
node supabase/tests/session_capital_lock/regression.mjs
```

fixture.sql and baseline.sql contain test doubles and intentionally unsafe old
behavior. NEVER run them against Supabase or use them as recovery migrations.

## Writer inventory

Inspected main `3af434db42f5890b7e0c7e56efb192116d1d5048` and repair parent
`2f83e3ceb5d85f88427b3de728c1bbf5a45bb489`. Main has no capital-lock implementation.
Executable files in the scout and three experimental application branches have
no session-table/helper references. Historical SQL on alpha-preopen-lock-v1 at
`dea66682f7b1a4c3504e0042ec96e6186b5826dc` contains:

| Writer/reference | Finding |
| --- | --- |
| alpha_lock_session_capital | Known reset path; current supplied behavior repaired |
| alpha_sync_session_lock_from_brain | Supplied production-only bridge; three reset paths repaired |
| alpha_evaluate_campaign_route | Historical KEEP_CASH and LOCKED-to-TRIGGERED writes; untouched |
| alpha_expire_session_routes | Historical expiry writer preserving EXECUTED; untouched |
| alpha_claim_route_execution | Historical EXECUTED writer, not a reset path; owner verified production disabled it; DO NOT REPLAY |
| alpha_reconcile_route_execution_from_broker | Owner-identified live forward writer; full body not supplied; untouched |
| alpha_route_monitor_tick | Owner-identified caller; full body not supplied; untouched |

No additional repository reset/reopen path was found. This is not an inventory
of unexported live Edge Functions or privileged external clients. Old migration
remains SUPERSEDED / DO NOT REPLAY.

## Remaining risks and stop boundary

- Native concurrency and actual forward-function integration remain unproven.
- Supplied production source may drift. Reverify definitions and backend-only
  ACLs before deployment; do not apply to missing functions or a stale schema.
- Direct privileged UPDATE/DELETE and separate route-creation retries remain
  outside scope. This is not universal database immutability.
- First-create validation/policy interpretation is intentionally retained;
  this repair does not claim to fix unrelated evidence/finance-policy defects.
- Restoring the baseline reintroduces the reset bug. No automatic rollback is
  included; any rollback requires separate review of captured definitions.

References: [PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html),
[function replacement](https://www.postgresql.org/docs/current/sql-createfunction.html),
[Supabase functions](https://supabase.com/docs/guides/database/functions).

Production touched = NO. Main touched = NO. Stop after the implementation commit
for code review. No merge or deployment authorization is implied.
