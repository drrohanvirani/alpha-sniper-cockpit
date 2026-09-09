# Alpha daily employee report: deterministic evidence stage

This extends reporting around the existing Alpha database. It is not a second
trading engine, signal qualification model, service, or automated order system.
Standard-library Python only: no paid AI calls or added dependencies.

## What works

1. Run backend/daily_employee_input.sql through an existing authorized connection.
   It is a read-only transaction and invokes no mutating application functions.
2. Save the packet column as a private JSON file outside Git.
3. Run backend/daily_employee.py with --input, --output and one --source NAME=path
   per user-exported stock universe. Do not commit portfolio packets or reports.
4. The saved JSON is read back and compared before success is reported.

The compiler validates source syntax and provenance, deduplicates exchange-qualified
symbols, preserves all source memberships, and joins NSE symbols to the latest
completed census. BSE symbols are never matched to NSE merely by name. Rankings
are the existing census ranks, not invented conviction scores or BUY advice.
All holdings plus CASH appear; missing values are never silently zero-filled.
The latest worker attempt is used, including failure after a previous success.

Report status deliberately remains DATA_BLOCKED for capital decisions and audited
performance: this stage does not certify live-trade freshness, generate entry/GTT
geometry, reconcile external cash flows, calculate TWR/attribution, or validate
benchmark returns. It does not claim a saved local report is a production record
or a report successfully fetched by ChatGPT. Recent-listings membership does not
verify the IPO date or historical investability of that symbol.

## Test

python -m unittest discover -s backend -p "test_*.py" -v

Nine isolated tests cover duplicate memberships, exchange identity, future evidence,
wrong project/mixed census dates, deterministic output and state preservation,
missing cash, no fabricated performance/authority, latest-worker failure, and
Telegram evidence integrity. Telegram linked items, distinct intel events, and
primary-verified events are separate counts. Reposts do not become independent
confirmations; missing/future/inconsistent Telegram evidence fails validation.

## Verified on 2026-09-09

Read-only production snapshot: 07:27:31 UTC, project rclbninptekxitkdtmrs.
User exports: 900 List-1, 867 List-2, 415 recent listings; 1,794 union symbols,
1,777 census matches. Production market features: 3,509 rows. Nine holdings plus
CASH represented. Latest worker attempt failed; current-day tournament is WAIT
with zero qualified challengers. Three of six curiosity questions have answers;
zero overdue unanswered questions in this snapshot. These are snapshot facts,
not promises of continued runtime health or independently validated answers.

Production already contains migration 20260909045729 repairing the NULL-contract
scope and daily-learning vocabulary, deployed by another session. The earlier
local curiosity repair must not be replayed against that changed baseline.
Current worker failures include deadlocks in portfolio_campaign_targets.

## Remaining integration boundary

This commit does not deploy, schedule, change cron, publish to Telegram, or change
ChatGPT tools. The user confirmed ChatGPT Work Mode has stopped production changes and this
task owns implementation. Routine production deployment must occur outside market hours per
AGENTS.md. After that, integration must use the existing persistence/delivery
path and demonstrate a saved record ID, independent read-back, scheduler run ID
and mobile retrieval. A successful Python test alone does not satisfy those.

Chartink's URL is known but automated capture and current filter interpretation
are not established by these stock exports. Pro-Setups website login is lower
priority. No subscriptions or access permissions were changed.

