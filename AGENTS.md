# Alpha OS Engineering Rules

## Purpose and current authorization

Maintain the existing Alpha OS Indian-equities system in STABILIZE_FIRST
mode. Make its engineering reliable, version-controlled, testable,
recoverable and simple.

Current authorization is READ-ONLY AUDIT ONLY:
- Inspect repository contents and available read-only evidence.
- Propose changes and draft complete file contents in the audit response.
- Do not write or modify files, install dependencies, run setup scripts,
  execute migrations, change infrastructure, merge PRs or deploy.
- Do not execute tests that write state or contact live services.
- Do not create additional agents or delegate work.
- Stop after the audit and proposals.
- A later explicit user instruction is required to authorize a specific
  implementation step. Audit approval is not deployment approval.

## Non-negotiable engineering rules

1. STABILIZE_FIRST: do not create new agents, frameworks or features
   unless explicitly approved.
2. Investment policy is controlled outside Codex by the Alpha Operating
   Manual. Never invent or weaken investment rules. If the applicable
   policy is unavailable or ambiguous, identify the gap and stop
   policy-dependent implementation.
3. Discovery signals have ZERO capital authority.
4. Missing mandatory evidence must fail closed / DATA BLOCKED.
   Never substitute guessed inputs.
5. Broker/Zerodha executed truth overrides chat, cached or model state.
   An internal claim or model response is not an executed trade.
6. Never autonomously place, modify or cancel real-money orders.
7. Never commit secrets, API keys, tokens, session strings or credentials.
   Never request that the user paste API keys, passwords, Telegram
   sessions, Zerodha credentials or Supabase service-role secrets into
   chat. Use approved secret-management mechanisms when later authorized.
8. Real-capital and paper/shadow decision lanes must remain strictly
   separated in storage, APIs, processing and user-visible outputs.
9. Historical tests must be timestamp-safe and contain no look-ahead or
   hindsight leakage. Preserve source publication time, first
   availability/ingestion time and the decision cutoff.
10. Production changes require tests and verification.
11. Prefer repairing an existing pipeline over adding another bot/service.
12. One change at a time: test -> review -> deploy -> verify.
    Deployment requires explicit authorization for the reviewed change.
13. Do not make production changes during market hours unless the user
    explicitly authorizes an emergency repair.
14. A source may be called LIVE only if end-to-end ingestion has been
    demonstrated through the required downstream state.
15. A cron returning SUCCESS is not proof that the business process worked.
16. Every repair should have a named regression test whenever possible.
17. Keep the user-facing workflow simple; complexity stays underneath.
18. No change to capital-allocation logic without explicit user
    authorization.

## Repository and recovery discipline

- Identify the branch and commit before auditing or proposing a repair.
- Distinguish implemented code, deployment-document claims and verified
  production behavior.
- Do not assume main is the deployed source of truth.
- Do not merge unrelated experiments or recreate components that already
  exist outside this repository.
- Reconcile deployed definitions and migration history before proposing
  replay of checked-in SQL.
- Version-control approved source, sanitized configuration, migrations,
  tests and recovery instructions. Keep secrets and private production
  datasets outside Git.
- Keep production read-only during audits. Do not invoke functions merely
  because they are callable through SELECT; they may mutate state.
- Run mutating regression tests only in an explicitly authorized isolated
  environment. Transaction rollback does not make production testing safe.
- Verify dependencies and setup scripts before running them.
- Report tests as planned, statically reviewed, executed or passed
  accurately. Never claim LIVE, saved, deployed or verified without proof.
- Propose the smallest structure required by the existing system.

## Mandatory regression cases

1. PAISALO
   Replay the Sep-3-2026 signal using only evidence available by the
   agreed timestamp. Verify prospective research promotion according to
   the Operating Manual, without capital authority or hindsight.
   Missing historical evidence means the case is blocked, not passed.

2. SMLMAH
   Verify early constructive evidence can reach the existing research/
   holding logic at its original timestamp, without requiring later
   expansion. Use approved policy and contemporaneous evidence.

3. REAL VS SHADOW
   Verify paper/shadow decisions never appear as real portfolio
   instructions or enter real-capital authorization paths.

4. STALE BROKER DATA
   Missing or stale Zerodha holdings, cash or NAV must produce
   DATA BLOCKED and no guessed allocation.

5. CAPITAL LOCK
   A new intraday scanner candidate cannot replace the pre-open capital
   owner. Test repeated locking, retries, concurrency and attempts to
   reopen an invalidated or executed session.

6. SOURCE HEALTH
   Telegram, Pro-Setups, NSE census and filings must not report LIVE
   unless identifiable raw input reaches the required downstream state.
   Scheduler success alone is insufficient.

7. DUPLICATES
   Repeated Telegram/Pro-Setups posts must not count as independent
   institutional/source confirmations. Test reposts and ingestion retries.

## Required audit output

A. Current repository inventory, with branch/commit and coverage limits.
B. Major gaps, with evidence and separation of fact from uncertainty.
C. Complete proposed root AGENTS.md contents, without writing the file.
D. Minimal staged implementation plan.
E. Risks, including deployment/recovery drift.
F. Access eventually required, using least privilege.

Stop after presenting the audit and proposals. Do not interpret this
document or an existing migration plan as authorization to implement.
