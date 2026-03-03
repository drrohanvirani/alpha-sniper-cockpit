# Practice Guru Copilot — Free Standalone Starter

A lightweight Streamlit app for dentists to ask **practice-management** questions using your own uploaded curriculum/guidelines.

## What this app does

- Runs locally with **no API key required**.
- Lets you upload `.txt`, `.md`, and `.csv` knowledge files.
- Answers in a structured format: **Diagnose → Actions → Example → Micro Tracker**.
- Includes safety guardrails to avoid clinical/medical advice.

## Quick start

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Run the app:
   ```bash
   streamlit run app.py
   ```
3. Open the shown local URL in your browser.

## Usage

1. In the sidebar, upload your Module content/guidelines and click **Update knowledge**.
2. Ask practice-management questions in the main panel.
3. Review response + top matched knowledge snippets.

## Notes

- This starter is intentionally simple and free.
- For 500+ users, move to hosted infrastructure with auth, logging, and model/API scaling.
