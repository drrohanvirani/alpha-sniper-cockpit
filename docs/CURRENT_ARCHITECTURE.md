# Alpha OS — Current Architecture

## Objective
Independent capital-compounding operating system for Indian equities. Real-money execution remains human-approved.

## Canonical truth hierarchy
1. Zerodha executions / broker snapshot
2. NSE/BSE + company primary filings
3. Fresh market data
4. Compiled research / underwriting
5. Discovery inputs such as Telegram
6. Conversational narrative

Lower tiers must never overwrite higher tiers.

## Existing deterministic core
- Broker truth: `zerodha_raw_snapshot_internal`, `zerodha_executions_internal`, `zerodha_sync_log_internal`, `live_portfolio`, `portfolio_snapshots`
- Research: `alpha_research_coverage`, `ticker_state`, `portfolio_campaign_targets`, `alpha_underwriting_decisions`
- Market data: `alpha_watch_quotes`, `alpha_intraday_candles`, `alpha_market_census`, `alpha_market_features`
- Capital: `alpha_trade_reality_packets`, `alpha_six_gate_runs`, `alpha_tranche_audit_runs`, `decisions`
- Memory/outcomes: `brain_state`, `brain_events`, `outcomes`, `decision_outcome_schedule`, `alpha_forward_predictions`
- Intelligence: `alpha_intel_events`, `alpha_official_filing_inbox`, `alpha_signal_triage`, `alpha_knowledge_nodes`, `alpha_knowledge_edges`
- Autonomy: `alpha_autonomy_queue`, `alpha_missions`, `alpha_mission_steps`
- Audit: `alpha_audit_runs`, `alpha_audit_gate_results`, `alpha_grey_area_register`, `rules`

## Existing critical functions
- `compile_alpha_context(...)`
- `alpha_control_room_status(...)`
- `alpha_ground_truth_arbitrate(...)`
- `build_trade_reality_packet(...)`
- `run_six_gate_funding_gate(...)`
- `run_tranche_risk_gate(...)`
- `alpha_preopen_add_readiness_tick()`
- `alpha_lock_capital_owner_preopen()`
- `alpha_locked_capital_plan_tick()`
- `alpha_intraday_trigger_state(...)`
- `alpha_winner_protection_tick()`

## Existing Edge Functions
- `alpha-context`
- `alpha-decision`
- `zerodha-auth`
- `zerodha-sync`
- `alpha-watch-quote-sync`
- `funding-gate`
- `alpha-audit-harness`
- `alpha-outcome-collector`
- `alpha-eod-census`
- `alpha-official-filings-sync`
- `alpha-semantic-memory`
- `alpha-telegram-cloud-reader`
- `alpha-telegram-public-scout`
- `alpha-telegram-user-ingest`
- `alpha-terminal`
- `alpha-terminal-data`
- regime sync functions

## Existing enforcement already present
- Fresh broker and price checks before capital actions
- Portfolio truth reconciliation
- Six-gate funding validation
- Tranche / cumulative risk checks
- Pre-open capital owner concept
- Intraday new-destination blocking concept
- Winner-protection path separated from fresh buys
- Telegram ingestion flagged as non-capital-authoritative

## Current structural weakness
The live system still stores execution geometry mainly as JSON on `portfolio_campaign_targets.execution_plan`, and its trigger logic is mostly single-condition price logic. It does not yet model mutually exclusive multi-route state machines, session-wide kill conditions, pre-open research rank vs capital authorization as separate first-class entities, or atomic one-campaign-per-session execution claims.