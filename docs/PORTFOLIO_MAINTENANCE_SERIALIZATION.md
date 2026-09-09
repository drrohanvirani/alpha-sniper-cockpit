# Portfolio maintenance deadlock repair — Stage 2 prepared, not deployed

Four scheduled entry points overlap: autonomous worker, liveness, master SOP, and heartbeat. Nine of the latest fifteen worker attempts observed during investigation failed with the same deadlock while alpha_winner_protection_tick updated portfolio_campaign_targets.

Stage 1 is already live: only alpha-autonomous-worker-15m moved from */15 to 3,18,33,48 * * * *. Its command, active state, database, and owner were preserved. This is temporary collision reduction, not the real fix.

## Change
A SECURITY INVOKER wrapper acquires one transaction-scoped advisory lock before calling an allowlisted existing entry point. Four cron commands call the wrapper while schedules, active flags, owners, and databases remain unchanged. Direct alpha_winner_protection_tick calls acquire the same lock, and holdings are processed in normalized ticker order.

Deadlocks are retried at most three times with a PostgreSQL warning on each retry. Inside the autonomous worker, winner protection has its own bounded retry; if all three attempts fail, the worker records FAILED_DEADLOCK_RETRIES_EXHAUSTED in its result and continues the unrelated delivery and evolution stages. No investment rule or capital logic changes.

PUBLIC/anon/authenticated cannot execute the scheduled wrapper; postgres/service_role can.

The migration checks the exact captured function hashes and cron commands before making any change. It aborts on drift and must run atomically. Do not replay earlier repository migrations.

## Prior native regression evidence
The parent commit 5db4444 was executed on local PostgreSQL 17.11 (production is 17.6; patch versions differ), using independent psql connections and a third observer.
- 16 ordered pairs of the four entry points: PASS. pg_locks shows an ungranted advisory lock and pg_blocking_pids identifies the holder before transaction A is released.
- Commit: each original entry point executes exactly once; both fixture counters become 2 and exactly two fixture side-effect rows exist.
- Rollback: A leaves no side effects and B completes as the only committed call.
- Negative control: deliberately inverted row-lock acquisition without the wrapper reproduces a native deadlock.
- ACL, invalid/null selector rejection, error propagation, repeat migration rejection, schedule/owner/active preservation: PASS.
- Seven unittest methods passed for that parent commit, including the 16-pair matrix. Raw evidence is in supabase/tests/native-results.json.

## Current extended-branch verification
- Python compilation, migration-content assertions, and git diff checks: PASS.
- Heartbeat, liveness, and master-SOP definitions are required to remain byte-identical. Only winner protection and worker v7 may change.
- The harness now includes deterministic winner ordering/direct gate assertions, forced SQLSTATE 40P01 retry, and three-attempt worker fail-soft continuation checks.
- Native PostgreSQL rerun of the extended migration: NOT RUN in the current environment because PostgreSQL 17, psql, Docker, and Podman are unavailable.
- Therefore the extended branch is not merge-ready and no merge approval is requested.

Important scope: actual captured function definitions are loaded for migration/hash checks, then isolated failure/counter fixtures exercise retry and concurrency. cron.alter_job is a test double because that PostgreSQL distribution does not contain pg_cron. This is NOT a full Alpha integration or production scheduling rehearsal.

## Remaining checks before live claim
This serializes the four scheduled callers and direct winner-protection calls. It does not certify downstream business results or repair investment logic. Queued jobs may wait; inspect duration and skipped/backlogged schedules after deployment. Recheck production definitions, cron configuration, and grants immediately before applying.

No Stage 2 migration, command-wrapper change, function replacement, order mutation, or capital change was deployed.

## Local reproduction
Use disposable localhost PostgreSQL 17 on port 55439 with administrative test role alpha_test. Set ALPHA_TEST_PSQL to its psql executable and run:
python supabase/tests/native_serialization.py

The test recreates ONLY the local database alpha_serialization_test. It cannot accept a production host/port. The local fixtures contain no portfolio records or credentials.

## Rollback (separately controlled production operation)
Run atomically after confirming the four job commands still reference this wrapper. Restore only these commands through cron.alter_job, keeping schedules and flags unchanged:

```sql
BEGIN;
SELECT cron.alter_job(jobid,command:='select public.alpha_autonomy_heartbeat();') FROM cron.job WHERE jobname='alpha-autonomy-heartbeat-30m';
SELECT cron.alter_job(jobid,command:='select public.alpha_autonomous_worker_tick_v7();') FROM cron.job WHERE jobname='alpha-autonomous-worker-15m';
SELECT cron.alter_job(jobid,command:='select public.alpha_liveness_guard_tick();') FROM cron.job WHERE jobname='alpha-ground-truth-liveness-5m';
SELECT cron.alter_job(jobid,command:='select public.alpha_master_daily_sop_tick();') FROM cron.job WHERE jobname='alpha-master-daily-sop';
DROP FUNCTION public.alpha_run_portfolio_maintenance_serialized(text);
COMMIT;
```

The rollback also requires restoring the captured pre-migration definitions of alpha_winner_protection_tick() and alpha_autonomous_worker_tick_v7(). It preserves the Stage 1 3,18,33,48 * * * * schedule. Execute rollback only from a reviewed, complete rollback migration.

References: [PostgreSQL advisory locks](https://www.postgresql.org/docs/17/explicit-locking.html), [Supabase Cron](https://supabase.com/docs/guides/cron/quickstart).

