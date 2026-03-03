import csv
import io
import re
from difflib import SequenceMatcher
from typing import List, Tuple

import streamlit as st

st.set_page_config(page_title="Practice Guru Copilot (Free)", page_icon="🦷", layout="wide")

DEFAULT_KNOWLEDGE = """
Practice Guru Pro - Module 2 Platinum Core Topics
- Case Mix Engineering
- Consultation Evolution
- Pricing Authority System
- EMI Conversion Strategy
- Internal Revenue Multipliers
- Database Reactivation System
- Revenue Ceiling Architecture
- Owner Strategic Shift
- 4 Revenue Categories: Traffic, Stabilizer, Accelerator, Authority

Gold: foundation (4 months). Platinum: strategic refinement with GPT support (8 months). Diamond: ownership and scale (12 months).

Response style principles:
- Diagnose first, then execute.
- Keep advice strategic, structured, and practical.
- Avoid clinical diagnosis and dosage guidance.
""".strip()

OUT_OF_SCOPE = (
    "This assistant only covers strategic dental practice management topics "
    "(operations, consultations, pricing, team systems, and growth). "
    "Please consult a qualified dental professional for clinical questions."
)


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def split_chunks(text: str, chunk_size: int = 350) -> List[str]:
    text = normalize(text)
    if not text:
        return []

    parts = re.split(r"(?<=[.!?])\s+|\n+", text)
    chunks: List[str] = []
    buff = ""

    for part in parts:
        if not part:
            continue
        if len(buff) + len(part) + 1 <= chunk_size:
            buff = f"{buff} {part}".strip()
        else:
            if buff:
                chunks.append(buff)
            buff = part

    if buff:
        chunks.append(buff)

    return chunks


def read_text_upload(file) -> str:
    name = file.name.lower()
    raw = file.read()

    if name.endswith((".txt", ".md")):
        return raw.decode("utf-8", errors="ignore")

    if name.endswith(".csv"):
        text_rows = []
        decoded = raw.decode("utf-8", errors="ignore")
        for row in csv.reader(io.StringIO(decoded)):
            text_rows.append(" | ".join(row))
        return "\n".join(text_rows)

    return ""


def rank_chunks(question: str, chunks: List[str], top_k: int = 3) -> List[Tuple[float, str]]:
    q = question.lower().strip()
    scored: List[Tuple[float, str]] = []

    for chunk in chunks:
        c = chunk.lower()
        ratio = SequenceMatcher(None, q, c).ratio()
        overlap = sum(1 for tok in q.split() if tok in c)
        score = ratio + 0.03 * overlap
        scored.append((score, chunk))

    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[:top_k]


def looks_clinical(question: str) -> bool:
    clinical_terms = [
        "dose",
        "dosage",
        "mg",
        "medicine",
        "drug",
        "antibiotic",
        "diagnosis",
        "xray finding",
        "prescription",
        "anesthesia",
    ]
    q = question.lower()
    return any(term in q for term in clinical_terms)


def build_answer(question: str, evidence: List[Tuple[float, str]]) -> str:
    if not evidence or evidence[0][0] < 0.12:
        return (
            "That question appears outside the loaded curriculum. "
            "Please ask a related practice-management question or upload additional content."
        )

    top = evidence[0][1]
    insight = (
        "Your priority is to diagnose the root business bottleneck first, "
        "then run one focused intervention for 7-14 days before changing strategy."
    )

    return f"""
### 1) Quick Diagnosis
{insight}

### 2) What To Do Next
1. Define the bottleneck in one line (consultation, pricing confidence, team execution, or reactivation).
2. Pick one KPI for 2 weeks (case acceptance %, average case value, or dormant patient reactivation count).
3. Deploy one script/SOP and review daily for consistency.

### 3) Module-Based Example
{top}

### 4) Micro Tracker
- **Today (5 mins):** assign owner + KPI.
- **This Week:** run the script for every eligible case.
- **This Month:** compare baseline vs current numbers and keep only what improved outcomes.
""".strip()


st.title("🦷 Practice Guru Copilot — Free Standalone Starter")
st.caption("No API key required. Runs locally in Streamlit using your uploaded knowledge.")

if "knowledge_text" not in st.session_state:
    st.session_state.knowledge_text = DEFAULT_KNOWLEDGE

with st.sidebar:
    st.header("Knowledge Base")
    st.write("Load your Module/Guideline data. Supported: .txt, .md, .csv")

    uploads = st.file_uploader(
        "Upload files",
        type=["txt", "md", "csv"],
        accept_multiple_files=True,
    )

    append_text = st.text_area("Or paste additional guidelines", height=180)

    if st.button("Update knowledge"):
        texts = [st.session_state.knowledge_text]

        if append_text.strip():
            texts.append(append_text.strip())

        if uploads:
            for f in uploads:
                content = read_text_upload(f)
                if content:
                    texts.append(content)

        st.session_state.knowledge_text = "\n\n".join(texts)
        st.success("Knowledge updated.")

    if st.button("Reset to starter content"):
        st.session_state.knowledge_text = DEFAULT_KNOWLEDGE
        st.info("Knowledge reset complete.")

col1, col2 = st.columns([2, 1])

with col1:
    question = st.text_area("Ask a practice-management question", height=130)
    ask = st.button("Get strategic answer")

with col2:
    st.subheader("Guardrails")
    st.markdown(
        "- Practice management scope only\n"
        "- No clinical/medical advice\n"
        "- Structured answers: Diagnose → Execute"
    )

if ask and question.strip():
    if looks_clinical(question):
        st.warning(OUT_OF_SCOPE)
    else:
        chunks = split_chunks(st.session_state.knowledge_text)
        evidence = rank_chunks(question, chunks)
        st.markdown(build_answer(question, evidence))

        with st.expander("Top matched knowledge"):
            for idx, (score, chunk) in enumerate(evidence, start=1):
                st.markdown(f"**{idx}. score={score:.2f}**")
                st.write(chunk)

st.divider()
st.markdown(
    "**Tip:** Start free with this local app. Later, you can add authentication, analytics, and a hosted model/API when scaling to many users."
)
