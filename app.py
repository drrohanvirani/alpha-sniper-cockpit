import streamlit as st
import json
import os
from datetime import datetime

# Create memory storage file
LOG_FILE = "as2_memory_log.json"
if not os.path.exists(LOG_FILE):
    with open(LOG_FILE, "w") as f:
        json.dump([], f)

# Load past memory
with open(LOG_FILE, "r") as f:
    memory = json.load(f)

# UI Elements
st.title("Alpha Sniper 2: Memory-Enabled Prompt System")

uploaded_file = st.file_uploader("Upload Screenshot (optional)", type=["png", "jpg", "jpeg"])
prompt_text = st.text_area("Paste Your Macro/Sector/Stock Prompt")

if st.button("Submit Prompt"):
    if prompt_text.strip() == "":
        st.warning("Please enter a prompt.")
    else:
        # Fake AI response (replace later with actual logic or GPT call)
        ai_response = {
            "CMP": "145.20",
            "SL": "138.00",
            "Conviction": 8,
            "Explosion": "#ExplodeSoon_3to5D",
            "Sector Tag": "Energy Midcap",
            "Macro Bias": "🟢 Bull Confirmed",
            "Commentary": "Strong OBV base, sector in surge zone, safe to initiate small tranche."
        }

        # Store log
        log_entry = {
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "prompt": prompt_text,
            "response": ai_response,
            "image": uploaded_file.name if uploaded_file else None
        }
        memory.append(log_entry)
        with open(LOG_FILE, "w") as f:
            json.dump(memory, f, indent=2)

        st.success("Prompt submitted and saved!")
        st.json(ai_response)

# View past entries
with st.expander("📜 View Prompt History"):
    for entry in reversed(memory[-10:]):
        st.markdown(f"**{entry['timestamp']}**")
        st.markdown(f"*Prompt:* {entry['prompt']}")
        st.json(entry['response'])
        if entry['image']:
            st.markdown(f"Image: {entry['image']}")
        st.markdown("---")
