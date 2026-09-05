# Alpha OS Preopen Lock — Production Deployment Status

Date: 2026-09-05
Project: `alpha-os-brain`

## Production migrations applied

1. `alpha_preopen_route_lock_v1_production`
   - `alpha_runtime_policy`
   - `alpha_preopen_rankings`
   - `alpha_campaign_routes`
   - `alpha_session_capital_lock`
   - `alpha_route_evaluations`
   - deterministic route/session functions

2. `alpha_preopen_route_lock_integration_v1`
   - preopen bridge from canonical `brain_state.current_truth.capital_plan`
   - automatic locked-route monitor
   - cron wiring

3. `alpha_route_execution_safety_hardening_v1`
   - routes are PREAUTHORIZED, not capital-authoritative on creation
   - <3R geometry is BLOCKED
   - direct route execution claim disabled
   - route authorization requires an OFFICIAL compiled decision + PASS six-gate + PASS tranche gate + ACTIONABLE control room
   - EXECUTED state is reconciled from broker fills, not chat/internal claims

## Active schedules

- `alpha-session-lock-bridge-preopen`: `10,40 3 * * 1-5`
- `alpha-route-monitor-5m`: `*/5 3-10 * * 1-5`
- `alpha-route-broker-reconcile-5m`: `2-59/5 3-10 * * 1-5`
- `alpha-route-expire-postclose`: `10 10 * * 1-5`

All market-time functions are internally guarded by IST market windows.

## Regression tests passed

- support test -> reclaim -> trigger-ready
- session kill -> KEEP CASH
- session kill cannot later resurrect breakout
- R:R below 3 -> BLOCKED
- subjective/non-numeric volume acceptance -> AWAITING_APPROVAL, not capital authority
- direct route execution claim -> disabled

Tests were run inside a transaction and rolled back, leaving no synthetic production state.

## Current hard-gate status

The existing Alpha system audit still blocks fresh capital because of pre-existing research/capital-allocation completeness gates. This deployment does not bypass those gates. When no fully underwritten campaign clears them, the daily session outcome remains KEEP CASH.

## Governing invariant

Preopen selection -> one capital owner -> frozen route(s) -> trigger or invalidate -> human-approved deterministic gates -> broker execution -> broker reconciliation.

No intraday destination substitution.
