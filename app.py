
import streamlit as st
import pandas as pd
import numpy as np
import pytesseract
from PIL import Image
import json
import os
from datetime import datetime
from io import BytesIO

st.set_page_config(layout="wide")
st.title("📊 Alpha Sniper 2 Cockpit")

# === Sidebar Memory Loader ===
st.sidebar.header("📁 Session Manager")
memory_files = [f for f in os.listdir() if f.startswith("analysis_memory_") and f.endswith(".json")]
selected_memory = st.sidebar.selectbox("Load Past Memory", [""] + sorted(memory_files, reverse=True))

analysis_memory = {}
if selected_memory:
    with open(selected_memory, "r") as f:
        analysis_memory = json.load(f)
        st.sidebar.success(f"Loaded: {selected_memory}")

# === OCR Upload ===
st.subheader("🖼️ Upload Screenshot (OCR)")
image_file = st.file_uploader("Upload Image", type=["png", "jpg", "jpeg"])
if image_file:
    image = Image.open(image_file)
    st.image(image, caption="Uploaded Screenshot", use_column_width=True)
    text = pytesseract.image_to_string(image)
    st.text_area("🔍 Extracted Text", text, height=200)

    # Save OCR result to memory
    analysis_memory['ocr'] = {
        'text': text,
        'filename': image_file.name,
        'timestamp': str(datetime.now())
    }

# === Excel Upload ===
st.subheader("📈 Upload Excel (ProSetups)")
excel_file = st.file_uploader("Upload Excel", type=["xlsx"])
if excel_file:
    df = pd.read_excel(excel_file, sheet_name=0)
    st.dataframe(df)
    analysis_memory['excel'] = {
        'filename': excel_file.name,
        'timestamp': str(datetime.now()),
        'columns': df.columns.tolist()
    }

# === Leaderboard (Conviction Stub) ===
st.subheader("🏆 Sniper Leaderboard (Prototype)")
placeholder_data = [
    {"symbol": "NSE:BAJAJINDEF", "score": 9, "tags": ["#HVY", "#OBVThrust"]},
    {"symbol": "NSE:SUNFLAG", "score": 8.5, "tags": ["#ExplodeLikely_1to2D"]},
]
for row in placeholder_data:
    st.markdown(f"- **{row['symbol']}** | Score: `{row['score']}` | Tags: {' '.join(row['tags'])}")

# === Save to Memory Button ===
if st.button("💾 Save Memory Snapshot"):
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    fn = f"analysis_memory_{ts}.json"
    with open(fn, "w") as f:
        json.dump(analysis_memory, f, indent=2)
    st.success(f"Saved to {fn}")
