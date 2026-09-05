# Alpha OS — Migration Plan

## Phase 1 — Schema only
Add:
- `alpha_runtime_policy`
- `alpha_preopen_rankings`
- `alpha_campaign_routes`
- `alpha_session_capital_lock`
- `alpha_route_evaluations`

No existing tables are removed.

## Phase 2 — Deterministic functions
Add:
- `alpha_runtime_policy_number(...)`
- `alpha_lock_session_capital(...)`
- `alpha_create_campaign_route(...)`
- `alpha_evaluate_campaign_route(...)`
- `alpha_claim_route_execution(...)`
- `alpha_expire_session_routes(...)`

Refactor existing freshness checks only after regression tests prove parity.

## Phase 3 — Integrate with existing capital gates
A route reaching `TRIGGER_READY` must still pass:
1. `alpha_ground_truth_arbitrate`
2. research coverage
3. underwriting
4. `build_trade_reality_packet`
5. `run_six_gate_funding_gate`
6. `run_tranche_risk_gate`
7. `alpha_control_room_status`
8. human approval
9. decision freeze

No new function may bypass these.

## Phase 4 — Terminal/read model
Expose:
- pre-open ranking
- capital authorization state
- session owner
- route states
- kill state
- broker/price freshness
- explicit block reasons

## Phase 5 — Scheduler
Before open:
- refresh broker truth
- finish research coverage
- write pre-open ranking
- lock capital owner
- create routes

Market hours:
- broker sync
- quote sync
- route evaluation
- existing risk exits/winner protection
- no broad capital reranking

Post-close:
- expire session routes
- reconcile fills
- rerank for next session
- outcome/audit updates

## Deployment safety
1. Apply to isolated Supabase development branch.
2. Seed Astra regression fixture.
3. Run regression SQL.
4. Run existing audit harness and battlefield tests.
5. Confirm broker/six-gate/tranche/Telegram/official filing paths are unchanged.
6. Merge only after all blocking tests pass.

## Production rule
Do not claim the architecture is live until the production migration is applied and the Astra fixture passes on the deployed database.