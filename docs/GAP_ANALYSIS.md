# Alpha OS — Gap Analysis

## Blocking gaps

### 1. Research rank and capital authority are conflated
P1/P2/Ignore should be research priority metadata. A name can rank P1 and still be capital blocked. The current architecture does not persist that distinction as a dedicated pre-open record.

### 2. Multi-route execution is not first-class
Current trigger functions support basic `PRICE_ABOVE`, `PRICE_BELOW`, and `PRICE_RANGE`. They do not natively express:
- test then reclaim
- alternative breakout route
- mutually exclusive route groups
- route precedence
- session-wide kill conditions
- no same-day resurrection after kill

### 3. Session lock is JSON-only
`brain_state.current_truth.capital_plan` already stores a lock concept, but there is no normalized session lock table with atomic counters and constraints preventing double execution.

### 4. Runtime freshness thresholds drift
Current functions use different hard-coded thresholds (300s, 420s, 600s, 900s, 1200s). These should come from one policy table while retaining strict 300-second freshness for actual capital authorization.

### 5. Route transition audit is incomplete
The system needs append-only route-state transitions for deterministic replay and post-mortem analysis.

### 6. Subjective gates are not machine safe
Phrases such as “convincing volume”, “good hold”, and “strong acceptance” cannot be capital-authoritative unless converted into numeric, pre-approved criteria. Undefined subjective criteria should block automatic authorization and permit alerts only.

## Non-blocking gaps
- Terminal UI does not clearly separate research priority from capital authority.
- No first-class session kill display.
- No explicit database uniqueness rule for one executed route per mutex group.
- No single policy row defining one fresh campaign per session for this operating mode.

## Existing components to reuse
Do not replace broker arbitration, six-gate funding, tranche risk, control-room status, or winner protection. New route/session logic must feed into those gates rather than bypass them.