
# Alpha Sniper 2: Cockpit Deployment

## 🚀 Usage

### Option A: Run Locally
1. Install dependencies:
   ```
   pip install -r requirements.txt
   ```
2. Launch the app:
   ```
   streamlit run app.py
   ```

### Option B: Host on Streamlit Cloud
1. Upload this repo to GitHub
2. Go to [Streamlit Cloud](https://streamlit.io/cloud)
3. Deploy your repo and get a permanent URL

Enjoy zero-prompt Alpha Sniper cockpit automation.

## Alpha OS Engineering Status

- The `main` branch is **not currently a complete production recovery copy**.
- Production definitions and migration history must be reconciled before any migration is replayed.
- **STABILIZE_FIRST** is active.
- No autonomous real-money trading is permitted.
- Discovery signals have **zero capital authority**.
- Missing mandatory evidence fails closed / **DATA BLOCKED**.
- Deployment requires explicit user approval.
- Current experimental branches must not be merged automatically.

### Historical migration warning

> **DO NOT REPLAY — SUPERSEDED BY VERIFIED PRODUCTION HARDENING.**
>
> The older [20260905_alpha_preopen_lock_v1.sql](https://github.com/drrohanvirani/alpha-sniper-cockpit/blob/dea66682f7b1a4c3504e0042ec96e6186b5826dc/supabase/migrations/20260905_alpha_preopen_lock_v1.sql)
> on `alpha-preopen-lock-v1` is **SUPERSEDED / DO NOT REPLAY against production**.
> See [Production Reconciliation — 2026-09-07](docs/PRODUCTION_RECONCILIATION_20260907.md)
> for owner-verified production facts, GitHub facts and open risks.
