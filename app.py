import os
import streamlit as st
from openai import OpenAI

st.set_page_config(page_title="Alpha Sniper 2: Memory Cockpit")

api_key = st.secrets.get("api_key") or os.getenv("OPENAI_API_KEY")
if not api_key:
    st.error("Missing OpenAI API key. Set st.secrets['api_key'] or OPENAI_API_KEY.")
    st.stop()

client = OpenAI(api_key=api_key)

st.title("🧠 Alpha Sniper 2: Memory-Enabled Prompt System")

manual_tab, tv_tab = st.tabs(["Manual Prompt", "TradingView Bridge"])

with manual_tab:
    st.subheader("Manual analysis")
    uploaded_file = st.file_uploader("Upload Screenshot (optional)", type=["png", "jpg", "jpeg"])
    prompt = st.text_area("Paste Your Macro/Sector/Stock Prompt", height=200)

    if st.button("Submit Prompt", type="primary") and prompt:
        with st.spinner("Running sniper logic..."):
            try:
                response = client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[
                        {"role": "system", "content": "You are a sniper-grade stock analysis assistant."},
                        {"role": "user", "content": prompt},
                    ],
                )
                reply = response.choices[0].message.content
                st.success("Prompt submitted!")
                st.markdown("### 🎯 Response")
                st.write(reply)
            except Exception as e:
                st.error(f"Error: {e}")

with tv_tab:
    st.subheader("Connect TradingView alerts to ChatGPT")
    st.markdown(
        """
1. Run the webhook bridge server:
   ```bash
   uvicorn tradingview_bridge:app --host 0.0.0.0 --port 8000
   ```
2. Expose it publicly (for example with ngrok):
   ```bash
   ngrok http 8000
   ```
3. In TradingView Alert **Webhook URL**, paste:
   ```
   https://YOUR_PUBLIC_URL/webhook/tradingview
   ```
4. Use this JSON in TradingView alert message:
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

The bridge verifies `secret`, sends alert context to ChatGPT, and returns a structured plan. Optionally, it can forward results to another webhook (Discord, bot, execution layer).
"""
    )
