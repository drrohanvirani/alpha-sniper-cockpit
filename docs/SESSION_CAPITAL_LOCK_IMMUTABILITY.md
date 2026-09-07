# Same-day capital lock immutability — coordinated proposal only

Status: caller conflict confirmed by static analysis; coordinated repair proposed,
not implemented. No capital-lock migration or executable regression is included.
Production and cron have not been touched.

## Evidence

Source: current target/caller SQL, session-lock table shape and access-control
facts supplied by the owner from a read-only production inspection during this
task. Codex statically reviewed that supplied source; Codex did not query production.
The source was supplied in the task conversation, not imported as a runnable
production baseline or independently version/hash-verified.

Repository baseline: main at 3af434db42f5890b7e0c7e56efb192116d1d5048.
The superseded SQL on alpha-preopen-lock-v1 is not a production replay source.

Exact target:
```text
public.alpha_lock_session_capital(
  date,text,text,numeric,numeric,numeric,timestamptz,text
)
```

Owner-supplied facts:
- Target and caller alpha_sync_session_lock_from_brain() are SECURITY DEFINER
  and restricted to postgres/service_role.
- trade_date is the session table primary key.
- Statuses: DRAFT, LOCKED, TRIGGERED, EXECUTED, CANCELLED, EXPIRED, KEEP_CASH,
  DATA_BLOCKED.
- The session table has no non-internal triggers. RLS is enabled, no policies
  were found, and direct table privileges are limited to postgres/service_role.
- executed_route_id references alpha_campaign_routes(id).
- Existing constraints prevent negative counters and counters above the maximum.

## Confirmed old behavior and caller conflict

The low-level helper uses ON CONFLICT(trade_date) DO UPDATE. A repeat can replace
owner/campaign, set LOCKED, reset execution count, clear execution/invalidation
references and refresh timestamps. It emits SESSION_CAPITAL_LOCKED through
alpha_emit_brain_event after both first creation and repeat calls.

The supplied bridge is not just a caller. It has THREE independent session-table
upserts before its helper call:

| Bridge path | Existing-row mutation |
| --- | --- |
| Invalid/stale plan dates | Sets DATA_BLOCKED, clears owner, replaces invalidation reason and updated_at |
| CASH owner or empty items | Sets KEEP_CASH; replaces owner/campaign, resets execution count, clears execution references/reason, rewrites cash/NAV and timestamps |
| Invalid cash/NAV | Sets DATA_BLOCKED; replaces owner, cash/NAV, invalidation reason and updated_at |

The successful path also:
- Reads the latest broker cash and may recompute NAV from live_portfolio.
- Derives reserved cash from the current plan/item and live cash.
- Calls the helper with PERFORM, discarding the returned existing row.
- Continues into alpha_create_campaign_route, even on a logical retry.
- May upsert alpha_autonomy_queue when route geometry is missing.
- Returns a hard-coded LOCKED status rather than the helper's actual state.

Thus a helper-only fix leaves direct reset paths intact and can still permit
downstream route/queue side effects or misleading status on a preserved lock.
The bridge's weekday and before-09:15 checks restrict when it runs, but do not
prove same-day idempotency. There is no existing-row guard in the supplied source.

## Compatibility verdict

**CONFLICT/BYPASS CONFIRMED. Do not implement a helper-only repair.**

Changing only the helper to preserve and return an existing EXECUTED, KEEP_CASH
or other protected row would not make the bridge compatible: it ignores that
return value, reports LOCKED and continues downstream.

An identical canonical plan also does not guarantee identical helper arguments:
the bridge refreshes cash/NAV/reservation inputs. A strict geometry comparison
can reject retries that the old bridge accepted by overwriting. That is a
required fail-closed behavior for conflicting geometry, but the intended
definition of a logical retry must be explicit before final implementation.

The latest owner instruction is to propose a minimum coordinated repair.
Neither function is modified in this commit.

## Minimum coordinated repair proposal

Scope: these TWO existing functions only. No new tables, services, investment
rules or generic lock framework. No changes to alpha_create_campaign_route,
broker reconciliation, grants or cron.

1. Both functions acquire the same transaction-scoped lock for the trade date
   before reading/creating a session row. A date-keyed advisory transaction lock
   is a candidate because an absent row cannot be row-locked. Use one consistent,
   documented key and lock order in both functions. Existing-row reads also use
   row locking. This serializes the two known writers, including first creation.

2. The helper preserves current validation and first-create initialization.
   Its existing-row path performs no UPDATE and emits no new brain event.
   An identical logical request returns to_jsonb(existing_row). A conflicting
   request raises a clear SESSION_CAPITAL_LOCK_CONFLICT error, leaving the row
   and all execution/invalidation fields untouched. No status, including DRAFT,
   is silently promoted back to LOCKED on a repeat.

3. The bridge applies the same existing-row guard BEFORE any of its three direct
   upserts or helper/route/queue writes. Keep existing weekday/time/plan validation.
   Once a row exists, classify the request as an identical retry, conflicting
   request or unavailable/invalid evidence. Never clear an existing owner or
   execution state just to report a new validation failure. Reject conflicts or
   invalid evidence with a clear response while preserving the existing row.

4. Replace the bridge's three last-writer-wins paths with first-insert-only
   behavior under the shared lock. Preserve their first-call DATA_BLOCKED and
   KEEP_CASH meanings. Do not make the low-level LOCKED-only helper silently
   create other statuses. Subsequent calls cannot reopen those first rows.

5. Consume the helper's returned row instead of PERFORM/discard. On an existing
   row, return its real status and current preserved data using the bridge's
   established response contract; do not claim LOCKED when it is protected.
   An idempotent existing-row return must exit BEFORE route creation, queue
   upserts or repeat audit-event emission. Keep the route function itself unchanged.

6. Preserve first-create audit events and established initial route/queue behavior.
   Interpret "no side effects" as no NEW unintended writes on first creation and
   ZERO writes on identical/conflicting retries; removing first-create audit events
   would be a separate behavioral change. If the owner requires zero cross-table
   writes even on first creation, resolve that explicitly before implementation.

7. Leave existing ACLs/ownership and all unrelated definitions unchanged.
   Commit one coordinated forward migration only after this proposal is approved
   and the matching/response details below are resolved.

## Matching decisions and remaining evidence

Proposed helper identity includes trade_date, owner normalized exactly as today,
campaign, original total_cash_available, original cash_reserved, total_nav and
expires_at, using NULL-safe equality. Do not compare mutable execution state,
cash_remaining or timestamps generated by the first call. Do not add trimming,
new validation thresholds or allocation rules without authorization.

Confirm whether those stored financial fields can change legitimately after
creation through other writers. If they can, current-row equality cannot prove
identity of the original request; do not quietly add a new identity column or
infer original values. created_by is provenance; whether it is part of identity
also needs an explicit decision.

For the bridge, specify how a retried canonical plan and its original geometry
are identified when current broker cash/NAV changes. No plan-only identity check
may silently accept incompatible requested lock geometry.

Decide the response shape for an existing row under stale/invalid current input:
report rejection and actual preserved status separately. It must not report a
successful LOCKED session or mutate the row to DATA_BLOCKED merely to express
the rejection.

Before an executable proposal, review any other SQL/Edge/direct-table writers and
the relevant route/audit/queue definitions needed for representative fixtures.
Only one database-function caller was identified; that is not proof that there
are no other table writers. Shared advisory locks protect only cooperating
writers. If protection against every backend table UPDATE is required, that is
broader than these two functions and requires a separate scope decision.

## Regression matrix — design only, NOT RUN

| Case | Required isolated assertion |
| --- | --- |
| A FIRST LOCK | First valid helper call returns/persists the expected LOCKED row and retains existing validation |
| B IDENTICAL RETRY | Entire returned and stored row identical, including generated timestamps and IDs |
| C OWNER MUTATION | Different ticker raises conflict; full row unchanged |
| D CAMPAIGN MUTATION | Different campaign raises conflict; full row unchanged |
| E EXECUTED | Valid execution references/counters and EXECUTED status survive exact retry |
| F KEEP_CASH / DATA_BLOCKED | Separate tests preserve each state and invalidation reason |
| G TRIGGERED | Cannot be reset to LOCKED; all fields preserved |
| H EXPIRED / CANCELLED | Separate tests prove no reopening |
| I NO SIDE EFFECTS | Snapshot related tables and function definitions/ACLs; no retry/conflict writes; only established first-create effects allowed |
| J CALLER | Cover all three direct bridge paths and success path against each existing protected state; no helper bypass or downstream route/queue reset; truthful return status |
| K CONCURRENCY | Race identical/conflicting same-date requests through helper/helper, bridge/bridge and helper/bridge pairs |

Also test DRAFT, NULL/case normalization using current semantics, incompatible
cash/reservation/NAV/expiry, two different dates, unchanged role grants and
first-time missing/invalid evidence. For every rejection, check the full row and
absence of new audit/queue/route writes, not just the exception text.

## Concurrency regression design

Use TWO independent connections to an explicitly approved isolated PostgreSQL
database, with controlled barriers:
- Session A begins and establishes the first lock but does not commit.
- Session B issues an identical or conflicting same-date request and must wait.
- Commit A: B returns the preserved winner for an identical request or fails
  closed for a conflict, without overwriting.
- Repeat with A rolling back: B may become the first valid creator.
- Repeat across both function entry points and the bridge's CASH/DATA_BLOCKED paths.
- Repeat under the actual caller isolation level; serialization failures must
  surface for whole-transaction retry, not be converted into success.
- Capture the winner row, audit/route/queue deltas and both responses.

Primary-key uniqueness remains the backstop. Do not use ON CONFLICT DO UPDATE
to refresh state. If an existing row disappears or cannot be observed safely,
fail closed instead of resetting a session. Review lock ordering against other
writers to avoid deadlocks.

Local PGlite tooling supports single-connection SQL validation, not proof of
independent-session concurrency. No capital-lock regression or concurrency test
has been run in this task.

## Repository changes and stop boundary

Part A renames the existing ACL migration to production version 20260907143201,
preserving its SQL and updating test/document references. It is not another ACL
migration and is not deployed again.

Part B is this coordinated proposal only, following the instruction to stop
when static analysis establishes a caller conflict. No helper-only replacement,
coordinated executable migration, or passing capital-lock test claim is created.

Production touched: NO.
Cron, route code, broker reconciliation, capital policy and automation: unchanged.
Await review before preparing the coordinated implementation.
