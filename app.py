import streamlit as st
import os
from openai import OpenAI

st.set_page_config(page_title="Alpha Sniper 2: Memory Cockpit")

# Initialize client using API key from Streamlit secrets (exposed as env var)
client = OpenAI(api_key=st.secrets["api_key"])

st.title("🧠 Alpha Sniper 2: Memory-Enabled Prompt System (Memory Build Active)")

# File upload section
uploaded_file = st.file_uploader("Upload Screenshot (optional)", type=["png", "jpg", "jpeg"])

# Prompt input section
prompt = st.text_area("Paste Your Macro/Sector/Stock Prompt", height=200)

# On prompt submit
if st.button("Submit Prompt") and prompt:
    with st.spinner("Running sniper logic..."):
        try:
            response = client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are a sniper-grade stock analysis assistant."},
                    {"role": "user", "content": prompt}
                ]
            )
            reply = response.choices[0].message.content
            st.success("Prompt submitted and saved!")
            st.markdown("### 🎯 Response")
            st.write(reply)
        except Exception as e:
            st.error(f"Error: {e}")
