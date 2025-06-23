import streamlit as st
import json
import os
from datetime import datetime
import openai

# Set OpenAI API Key (replace with your actual key)
openai.api_key = "sk-proj-xxxxxxxxxx"  # replace with your actual key

# Create memory storage file
LOG_FILE = "as2_memory_log.json"
if not os.path.exists(LOG_FILE):
    with open(LOG_FILE, "w") as f:
        json.dump([], f)

# Load past memory
with open(LOG_FILE, "r") as f:
    memory = json.load(f)

# UI Elements
st.title("🟢 Alpha Sniper 2: Memory-Enabled Prompt System (Memory Build Active)")

uploaded_file = st.file_uploader("Upload Screenshot (optional)", type=["png", "jpg", "jpeg"])
prompt_text = st.text_area("Paste Your Macro/Sector/Stock Prompt")

if st.button("Submit Prompt"):
    if prompt_text.strip() == "":
        st.warning("Please enter a prompt.")
    else:
        # Real GPT-4 powered response
        try:
            response = openai.ChatCompletion.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are a sniper-grade stock analysis assistant. Respond with JSON containing CMP, SL, Conviction (1-10), Explosion timing tag, Sector Tag, Macro Bias, and a Commentary."},
                    {"role": "user", "content": prompt_text}
                ]
            )
            ai_response = json.loads(response['choices'][0]['message']['content'])
        except Exception as e:
            st.error(f"GPT error: {e}")
            ai_response = {}

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
