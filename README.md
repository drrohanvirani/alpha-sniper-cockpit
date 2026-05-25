# Alpha Sniper Cockpit

A Streamlit stock-scanner cockpit that helps you find breakout candidates **before** major expansion moves.

## What it does
- Scans your ticker universe (NSE or US)
- Scores each symbol on:
  - 20EMA > 50EMA trend alignment
  - 20-day breakout
  - Volume spike vs 20-day average
  - Inside-bar breakout
- Returns ranked names to research further
- Gives pre-trade checklist questions
- Optional GPT helper for follow-up analysis

## Run locally
```bash
pip install -r requirements.txt
streamlit run app.py
```

## Suggested workflow
1. Build your focused universe (30–150 stocks)
2. Run scanner daily after market close
3. Shortlist top 5–10 scores
4. Validate each with news, sector strength, and risk plan
5. Execute only setups with clear invalidation and position sizing

## Disclaimer
Educational tool only; not investment advice.
