# Portfolio maintenance serialization — prepared, not deployed

Four existing scheduled entry points overlap: autonomous worker (15 minutes), liveness (5 minutes during market hours), master SOP (5 minutes), and heartbeat. Production cron run 11556 at 2026-09-09 07:45 UTC failed with a deadlock while updating portfolio_campaign_targets from alpha_winner_protection_tick. The worker has already updated queue rows before reaching winner protection; other entry points can acquire the same resources in a different order.

## Change
A SECURITY INVOKER wrapper acquires one transaction-scoped advisory lock before calling an allowlisted existing entry point. Four cron commands call the wrapper. Schedules, active flags, owners, and all existing function definitions remain unchanged. Existing return values and exceptions propagate unchanged. PUBLIC/anon/authenticated cannot execute the wrapper; postgres/service_role can.

The migration checks the exact captured function hashes and cron commands before making any change. It aborts on drift and must run atomically. Do not replay earlier repository migrations.

## Native regression evidence
Executed on local PostgreSQL 17.11 (production is 17.6; patch versions differ), using independent psql connections and a third observer.
- 16 ordered pairs of the four entry points: PASS. pg_locks shows an ungranted advisory lock and pg_blocking_pids identifies the holder before transaction A is released.
- Commit: each original entry point executes exactly once; both fixture counters become 2 and exactly two fixture side-effect rows exist.
- Rollback: A leaves no side effects and B completes as the only committed call.
- Negative control: deliberately inverted row-lock acquisition without the wrapper reproduces a native deadlock.
- Existing function definitions: hashes identical before/after migration.
- ACL, invalid/null selector rejection, error propagation, repeat migration rejection, schedule/owner/active preservation: PASS.
- Seven unittest methods passed, including the 16-pair matrix. Raw evidence is in supabase/tests/native-results.json.

Important scope: actual captured function definitions are loaded for migration/hash checks, then replaced with isolated counter-writing test doubles for the concurrency matrix. cron.alter_job is also a test double because this Windows PostgreSQL distribution does not contain pg_cron. This is NOT a full Alpha integration or production scheduling rehearsal. No native PostgreSQL proof is claimed for capital-lock repair #2.

## Remaining checks before live claim
This serializes only the four scheduled callers. Direct RPC calls and other writers do not automatically acquire this advisory lock. It does not remove duplicate work already performed inside an entry point, certify downstream business results, or repair investment logic. Queued jobs may wait; inspect duration and skipped/backlogged schedules after deployment. Recheck production definitions, cron configuration, and grants immediately before applying.

Production was read only throughout preparation. No orders, cron mutations, or production migrations were executed.

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

Rollback restores the former concurrency exposure; it does not fix the deadlock.

References: [PostgreSQL advisory locks](https://www.postgresql.org/docs/17/explicit-locking.html), [Supabase Cron](https://supabase.com/docs/guides/cron/quickstart).

