# Alpha Sniper 2: Cockpit Deployment

This repo now includes:
- A **Streamlit cockpit** for manual prompting.
- A **TradingView webhook bridge** that sends alerts to ChatGPT and returns structured trade guidance.

## 🚀 Usage

### 1) Install dependencies
```bash
pip install -r requirements.txt
```

### 2) Set environment variables
```bash
export OPENAI_API_KEY="your_openai_key"
export TV_WEBHOOK_SECRET="your_shared_secret"
# Optional: forward GPT output to another webhook (Discord, bot, executor)
export DOWNSTREAM_WEBHOOK_URL="https://example.com/webhook"
```

### 3) Run Streamlit cockpit (manual analysis)
```bash
streamlit run app.py
```

### 4) Run TradingView bridge
```bash
uvicorn tradingview_bridge:app --host 0.0.0.0 --port 8000
```

If needed, expose your local bridge publicly:
```bash
ngrok http 8000
```

Use this URL in TradingView alerts:
```
https://YOUR_PUBLIC_URL/webhook/tradingview
```

## TradingView Alert JSON example

```json
{
  "secret": "YOUR_SHARED_SECRET",
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "price": "{{close}}",
  "signal": "BUY",
  "note": "Breakout with volume"
}
```

## Health check

```bash
curl http://localhost:8000/health
```

Response:
```json
{"status":"ok"}
```

Enjoy zero-prompt Alpha Sniper cockpit automation.
