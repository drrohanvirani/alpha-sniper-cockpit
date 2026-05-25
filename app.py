import streamlit as st
import pandas as pd
import numpy as np
import yfinance as yf
from openai import OpenAI

st.set_page_config(page_title="Alpha Sniper Cockpit", layout="wide")

st.title("🧠 Alpha Sniper Cockpit")
st.caption("Find momentum breakout candidates to explore further (not financial advice).")

with st.sidebar:
    st.header("OpenAI Prompt Helper")
    use_openai = st.checkbox("Enable GPT helper", value=False)
    if use_openai:
        api_key = st.text_input("OpenAI API Key", type="password")

st.subheader("1) Scanner Setup")
col1, col2, col3 = st.columns(3)
with col1:
    exchange = st.selectbox("Market", ["NSE", "US"])
with col2:
    lookback = st.slider("Lookback candles", 60, 300, 120, 10)
with col3:
    min_price = st.number_input("Min price", min_value=0.0, value=20.0)

symbol_help = "Use comma-separated tickers. For NSE, type symbols without .NS (example: RELIANCE,TCS,SUNPHARMA)."
raw_symbols = st.text_area(
    "Tickers to scan",
    value="RELIANCE,TCS,INFY,HDFCBANK,ICICIBANK,SUNPHARMA,TATAMOTORS,SBIN,LT,BEL",
    help=symbol_help,
)

st.subheader("2) Rule Weights")
w1, w2, w3, w4 = st.columns(4)
with w1:
    wt_trend = st.slider("Trend (20EMA>50EMA)", 0.0, 5.0, 2.0, 0.5)
with w2:
    wt_breakout = st.slider("Breakout", 0.0, 5.0, 2.0, 0.5)
with w3:
    wt_volume = st.slider("Volume spike", 0.0, 5.0, 2.0, 0.5)
with w4:
    wt_inside = st.slider("Inside-bar break", 0.0, 5.0, 1.0, 0.5)


def normalize_symbols(text: str, market: str) -> list[str]:
    base = [s.strip().upper() for s in text.split(",") if s.strip()]
    if market == "NSE":
        return [s if s.endswith(".NS") else f"{s}.NS" for s in base]
    return base


def inside_bar_break(df: pd.DataFrame) -> bool:
    if len(df) < 4:
        return False
    prev = df.iloc[-2]
    before_prev = df.iloc[-3]
    latest = df.iloc[-1]
    inside = prev["High"] < before_prev["High"] and prev["Low"] > before_prev["Low"]
    broke_up = latest["Close"] > prev["High"]
    return bool(inside and broke_up)


def score_symbol(df: pd.DataFrame, min_px: float) -> dict | None:
    if df.empty or len(df) < 60:
        return None

    df = df.copy()
    df["EMA20"] = df["Close"].ewm(span=20, adjust=False).mean()
    df["EMA50"] = df["Close"].ewm(span=50, adjust=False).mean()
    df["VolMA20"] = df["Volume"].rolling(20).mean()

    latest = df.iloc[-1]
    if float(latest["Close"]) < min_px:
        return None

    trend = latest["EMA20"] > latest["EMA50"] and latest["Close"] > latest["EMA20"]
    breakout_lvl = df["High"].iloc[-21:-1].max()
    breakout = latest["Close"] > breakout_lvl
    vol_spike = latest["Volume"] > 1.8 * latest["VolMA20"] if not np.isnan(latest["VolMA20"]) else False
    inside_break = inside_bar_break(df)

    score = (
        wt_trend * float(trend)
        + wt_breakout * float(breakout)
        + wt_volume * float(vol_spike)
        + wt_inside * float(inside_break)
    )

    return {
        "Close": round(float(latest["Close"]), 2),
        "Pct_1D": round(float((latest["Close"] / df.iloc[-2]["Close"] - 1) * 100), 2),
        "Volume_x_MA20": round(float(latest["Volume"] / latest["VolMA20"]), 2) if latest["VolMA20"] else np.nan,
        "Trend": trend,
        "Breakout": breakout,
        "VolSpike": vol_spike,
        "InsideBreak": inside_break,
        "Score": round(score, 2),
    }


if st.button("Run Scanner", type="primary"):
    symbols = normalize_symbols(raw_symbols, exchange)
    rows = []
    progress = st.progress(0)

    for i, sym in enumerate(symbols, start=1):
        progress.progress(i / max(len(symbols), 1))
        try:
            data = yf.download(sym, period="1y", interval="1d", progress=False, auto_adjust=True)
            if isinstance(data.columns, pd.MultiIndex):
                data.columns = data.columns.get_level_values(0)
            metrics = score_symbol(data.tail(lookback), min_price)
            if metrics:
                rows.append({"Symbol": sym.replace(".NS", ""), **metrics})
        except Exception:
            continue

    if not rows:
        st.warning("No candidates matched with current universe/filters. Broaden symbols or lower filters.")
    else:
        out = pd.DataFrame(rows).sort_values("Score", ascending=False)
        st.success(f"Found {len(out)} candidates.")
        st.dataframe(out, use_container_width=True)

        top = out.head(5)["Symbol"].tolist()
        st.markdown("### Names to Explore Further")
        st.write(", ".join(top))

        st.markdown("### Questions to Ask Before Entry")
        st.markdown(
            """
1. Is today’s move **news-driven** (results/order/regulatory) or just technical?
2. Is this a **fresh breakout** from a multi-week base, or already extended?
3. Did volume expand at least ~2x 20-day average?
4. Where is invalidation (below breakout/20EMA)? Is risk ≤ 1R per trade?
5. What is the next overhead resistance where supply can appear?
            """
        )

        csv = out.to_csv(index=False).encode("utf-8")
        st.download_button("Download results (CSV)", csv, "scanner_results.csv", "text/csv")

if use_openai:
    st.subheader("3) Optional GPT Helper")
    prompt = st.text_area("Ask GPT to review scanner output / setup", height=140)
    if st.button("Ask GPT") and prompt:
        if not api_key:
            st.error("Please add OpenAI API key in sidebar.")
        else:
            try:
                client = OpenAI(api_key=api_key)
                response = client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[
                        {"role": "system", "content": "You are a disciplined swing-trading research assistant."},
                        {"role": "user", "content": prompt},
                    ],
                )
                st.markdown("### GPT Response")
                st.write(response.choices[0].message.content)
            except Exception as e:
                st.error(f"OpenAI error: {e}")

st.info("For education only. Backtest before risking capital.")
