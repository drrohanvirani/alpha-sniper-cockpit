import os
from typing import Any, Dict

import httpx
from fastapi import FastAPI, Header, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
TV_WEBHOOK_SECRET = os.getenv("TV_WEBHOOK_SECRET", "")
DOWNSTREAM_WEBHOOK_URL = os.getenv("DOWNSTREAM_WEBHOOK_URL", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY is required")

client = OpenAI(api_key=OPENAI_API_KEY)
app = FastAPI(title="TradingView -> ChatGPT Bridge")


class TradingViewAlert(BaseModel):
    secret: str = Field(..., description="Shared secret configured in TradingView")
    symbol: str
    timeframe: str = ""
    price: str = ""
    signal: str = ""
    note: str = ""
    raw: Dict[str, Any] = Field(default_factory=dict)


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/webhook/tradingview")
async def tradingview_webhook(
    payload: TradingViewAlert,
    user_agent: str | None = Header(default=None),
) -> Dict[str, Any]:
    if TV_WEBHOOK_SECRET and payload.secret != TV_WEBHOOK_SECRET:
        raise HTTPException(status_code=401, detail="Invalid webhook secret")

    system_prompt = (
        "You are a disciplined trading copilot. Return JSON with keys: "
        "summary, risk, invalidation, entry, targets, confidence, and action. "
        "Keep it concise and operational."
    )

    user_prompt = (
        f"Signal from TradingView:\n"
        f"symbol={payload.symbol}\n"
        f"timeframe={payload.timeframe}\n"
        f"price={payload.price}\n"
        f"signal={payload.signal}\n"
        f"note={payload.note}\n"
        f"source_user_agent={user_agent}\n"
        f"raw={payload.raw}"
    )

    completion = client.chat.completions.create(
        model=OPENAI_MODEL,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    )

    gpt_response = completion.choices[0].message.content
    result: Dict[str, Any] = {
        "ok": True,
        "symbol": payload.symbol,
        "signal": payload.signal,
        "gpt": gpt_response,
    }

    if DOWNSTREAM_WEBHOOK_URL:
        async with httpx.AsyncClient(timeout=10) as http_client:
            forward_response = await http_client.post(
                DOWNSTREAM_WEBHOOK_URL,
                json={"source": "tradingview_bridge", "alert": payload.model_dump(), "analysis": result},
            )
            result["forward_status"] = forward_response.status_code

    return result
