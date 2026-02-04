# app.py
import re
import time
import uuid
import numpy as np
import pandas as pd
import streamlit as st
import pymysql

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity


# -------------------------
# DB CONNECT (as provided)
# -------------------------
def connect_neo(attempts=5):
    last = None
    for i in range(attempts):
        try:
            return pymysql.connect(
                host="192.168.1.149",
                port=3307,
                user="CBSUSER",
                password="Falcon@2022",
                database="neo",
                charset="utf8mb4",
                connect_timeout=5,
                read_timeout=10,
                write_timeout=10,
                cursorclass=pymysql.cursors.DictCursor,
                autocommit=True,
            )
        except Exception as e:
            last = e
            time.sleep(0.4 * (i + 1))
    raise last


# -------------------------
# CONFIG
# -------------------------
DEFAULT_SOP_PATH = "NEO_SUPPORT_SOP.xlsx"
MAX_RESULT_ROWS = 200
MATCH_THRESHOLD = 0.20

# Streaming speed: tweak if needed (smaller is faster)
STREAM_WORD_DELAY_SEC = 0.01


# -------------------------
# TEXT + ENTITY HELPERS
# -------------------------
BOT_NUM_RE = re.compile(r"\bbot\s*[-#:]*\s*(\d+)\b", re.IGNORECASE)
BOT_ID_RE = re.compile(r"\bBOT-\d{4}\b", re.IGNORECASE)

def extract_entities(user_text: str) -> dict:
    if not user_text:
        return {"BOT_NUM": None, "BOT_ID": None}

    m2 = BOT_ID_RE.search(user_text)
    if m2:
        bot_id = m2.group(0).upper()
        return {"BOT_NUM": int(bot_id.split("-")[1]), "BOT_ID": bot_id}

    m = BOT_NUM_RE.search(user_text)
    if m:
        n = int(m.group(1))
        return {"BOT_NUM": n, "BOT_ID": f"BOT-{n:04d}"}

    return {"BOT_NUM": None, "BOT_ID": None}


def normalize_for_match(s: str) -> str:
    if s is None:
        return ""
    s = str(s).lower()

    s = re.sub(r"\bbot\s*[-#:]*\s*\d+\b", "bot", s)
    s = re.sub(r"\bbot-\d{4}\b", "bot", s)

    s = re.sub(r"[^a-z0-9\s]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def personalize_text(text: str, entities: dict) -> str:
    if text is None:
        return ""
    t = str(text)
    bot_id = entities.get("BOT_ID")
    bot_num = entities.get("BOT_NUM")

    if bot_id:
        t = re.sub(r"\bBOT-\d{4}\b", bot_id, t, flags=re.IGNORECASE)

    if bot_num is not None:
        t = re.sub(r"\b(bot)\s+\d+\b", f"Bot {bot_num}", t, flags=re.IGNORECASE)

    return t


def substitute_sql(sql: str, entities: dict) -> str:
    if sql is None:
        return ""
    q = str(sql).strip()
    if q.lower() in ("nan", "none", ""):
        return ""

    bot_id = entities.get("BOT_ID")
    if bot_id:
        q = re.sub(r"\bBOT-\d{4}\b", bot_id, q, flags=re.IGNORECASE)

    return q


def is_safe_select_query(sql: str) -> bool:
    if not sql:
        return False
    s = sql.strip().lstrip("(").strip()
    first = re.split(r"\s+", s, maxsplit=1)[0].upper()
    allowed = {"SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN"}
    if first not in allowed:
        return False

    # Disallow multi-statement
    if ";" in s[:-1]:
        return False

    return True


# -------------------------
# SOP LOADING + INDEXING
# -------------------------
@st.cache_data(show_spinner=False)
def load_sop_dataframe_from_path(path_or_file) -> pd.DataFrame:
    df = pd.read_excel(path_or_file)

    # Clean columns
    df.columns = [str(c).strip() for c in df.columns]
    df = df.loc[:, ~df.columns.str.startswith("Unnamed")]

    # Normalize "Problem Statement" name
    col_map = {}
    for c in df.columns:
        if c.strip().lower() == "problem statement":
            col_map[c] = "Problem Statement"
    df = df.rename(columns=col_map)

    # Forward fill group columns
    for c in ["S.No.", "Problem Statement", "Impact"]:
        if c in df.columns:
            df[c] = df[c].ffill()

    # Normalize types
    df["Priority"] = pd.to_numeric(df.get("Priority"), errors="coerce").astype("Int64")
    df["SQL/Step"] = df.get("SQL/Step").astype(str).str.strip()
    df["Sub Problem Statement"] = df.get("Sub Problem Statement").astype(str).str.strip()
    df["Solution"] = df.get("Solution").astype(str)

    # Keep rows with valid priority
    df = df[df["Priority"].notna()].copy()
    return df


@st.cache_resource(show_spinner=False)
def build_problem_index(problem_rows_df: pd.DataFrame):
    problems_df = (
        problem_rows_df[["S.No.", "Problem Statement", "Impact"]]
        .drop_duplicates()
        .reset_index(drop=True)
        .copy()
    )
    problems_df["norm"] = problems_df["Problem Statement"].apply(normalize_for_match)

    vec = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), min_df=1)
    X = vec.fit_transform(problems_df["norm"].tolist())
    return problems_df, vec, X


def select_best_problem(problems_df: pd.DataFrame, vec, X, user_query: str):
    qn = normalize_for_match(user_query)
    qv = vec.transform([qn])
    sims = cosine_similarity(X, qv).ravel()

    best_idx = int(np.argmax(sims))
    best_score = float(sims[best_idx])

    ranked = (
        problems_df.assign(score=sims)
        .sort_values("score", ascending=False)
        .head(5)
        .reset_index(drop=True)
    )

    best_row = problems_df.iloc[best_idx].to_dict()
    best_row["score"] = best_score
    return best_row, ranked


def get_steps_for_problem(df: pd.DataFrame, s_no):
    steps = df[df["S.No."] == s_no].copy()
    steps = steps.sort_values(["Priority"], ascending=True)
    return steps.reset_index(drop=True)


# -------------------------
# SQL EXECUTION
# -------------------------
def run_sql(sql: str):
    conn = connect_neo()
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            rows = cur.fetchall()
        return rows, None
    except Exception as e:
        return None, str(e)
    finally:
        try:
            conn.close()
        except Exception:
            pass


# -------------------------
# CHAT STATE + HELPERS
# -------------------------
def init_state():
    if "messages" not in st.session_state:
        st.session_state["messages"] = []
    if "workflow" not in st.session_state:
        st.session_state["workflow"] = None
    if "awaiting_step_input" not in st.session_state:
        st.session_state["awaiting_step_input"] = False
    if "pending_resolution" not in st.session_state:
        st.session_state["pending_resolution"] = None  # dict or None
    if "streamed_ids" not in st.session_state:
        st.session_state["streamed_ids"] = set()


def add_msg(role: str, content: str, extra=None, stream=False):
    msg = {
        "id": str(uuid.uuid4()),
        "role": role,
        "content": content,
        "extra": extra,
        "stream": bool(stream),
    }
    st.session_state["messages"].append(msg)
    return msg["id"]


def stream_markdown(text: str):
    placeholder = st.empty()
    out = ""
    for w in text.split():
        out += w + " "
        placeholder.markdown(out)
        time.sleep(STREAM_WORD_DELAY_SEC)
    placeholder.markdown(text)


def render_messages():
    for m in st.session_state["messages"]:
        with st.chat_message(m["role"]):
            if m.get("stream") and m["id"] not in st.session_state["streamed_ids"]:
                stream_markdown(m["content"])
                st.session_state["streamed_ids"].add(m["id"])
            else:
                st.markdown(m["content"])

            if m.get("extra"):
                ex = m["extra"]
                if ex.get("type") == "sql_result":
                    rows = ex.get("rows", [])
                    err = ex.get("error")
                    if err:
                        st.error(err)
                    else:
                        if rows:
                            st.caption(f"Rows returned: {len(rows)} (showing up to {MAX_RESULT_ROWS})")
                            st.dataframe(pd.DataFrame(rows))
                        else:
                            st.info("0 rows returned.")
                elif ex.get("type") == "top_matches":
                    st.caption("Top matches:")
                    st.dataframe(pd.DataFrame(ex["rows"]))
                elif ex.get("type") == "step_capture":
                    st.info("Waiting for your observation/output for this step.")


# -------------------------
# WORKFLOW ENGINE (ONE STEP AT A TIME)
# -------------------------
def start_new_workflow(df: pd.DataFrame, problems_df: pd.DataFrame, vec, X, user_query: str):
    entities = extract_entities(user_query)

    best, ranked = select_best_problem(problems_df, vec, X, user_query)

    if best["score"] < MATCH_THRESHOLD:
        add_msg(
            "assistant",
            f"Match confidence is low (score={best['score']:.2f}). Please select the correct Problem Statement.",
            extra={"type": "top_matches", "rows": ranked[["S.No.", "Problem Statement", "Impact", "score"]].to_dict("records")},
            stream=True
        )
        return {
            "status": "needs_selection",
            "entities": entities,
            "ranked": ranked.to_dict("records"),
            "selected_s_no": None,
            "steps": None,
            "step_idx": 0,
            "captured_steps": [],
        }

    s_no = best["S.No."]
    steps = get_steps_for_problem(df, s_no).to_dict("records")

    add_msg(
        "assistant",
        f"Matched SOP: **{personalize_text(best['Problem Statement'], entities)}**\n\nImpact: **{best['Impact']}**\n\nStarting priority-wise checks.",
        stream=True
    )

    return {
        "status": "running",
        "entities": entities,
        "selected_s_no": s_no,
        "steps": steps,
        "step_idx": 0,
        "captured_steps": [],
    }


def execute_next_step_once(df: pd.DataFrame):
    """
    Executes exactly ONE actionable step, then pauses for:
      - resolution confirmation (pending_resolution), OR
      - manual input (awaiting_step_input), OR
      - completion
    """
    wf = st.session_state["workflow"]
    if not wf or wf.get("status") != "running":
        return

    # Do not proceed if we are waiting for something
    if st.session_state["awaiting_step_input"]:
        return
    if st.session_state["pending_resolution"] is not None:
        return

    entities = wf["entities"]
    steps = wf["steps"]
    i = wf["step_idx"]

    # Skip non-actionable rows, but still only execute ONE actionable step per call.
    while i < len(steps):
        step = steps[i]
        priority = step.get("Priority")
        subp = step.get("Sub Problem Statement", "")
        typ = str(step.get("SQL/Step", "")).strip().upper()
        sol = step.get("Solution", "")

        add_msg("assistant", f"**Priority {priority}:** {personalize_text(subp, entities)}", stream=True)

        if typ == "SQL":
            sql = substitute_sql(sol, entities)

            if not sql:
                add_msg("assistant", "No SQL found in SOP for this priority. Moving to the next step.", stream=True)
                i += 1
                wf["step_idx"] = i
                st.session_state["workflow"] = wf
                continue

            add_msg("assistant", f"```sql\n{sql}\n```")

            # If SQL is not safe/read-only, treat it as manual step
            if not is_safe_select_query(sql):
                add_msg(
                    "assistant",
                    "This SQL is not a single read-only query. Please execute it manually and paste the output here to proceed.",
                    extra={"type": "step_capture"},
                    stream=True
                )
                st.session_state["awaiting_step_input"] = True
                # Do NOT advance step_idx yet; we will advance after user provides output
                wf["step_idx"] = i
                st.session_state["workflow"] = wf
                return

            rows, err = run_sql(sql)
            if err:
                add_msg("assistant", "SQL execution failed.", extra={"type": "sql_result", "error": err, "rows": []})
            else:
                trimmed = (rows or [])[:MAX_RESULT_ROWS]
                add_msg("assistant", "SQL result:", extra={"type": "sql_result", "error": None, "rows": trimmed})

            # Advance step index immediately; pause for resolution confirmation
            wf["step_idx"] = i + 1
            st.session_state["workflow"] = wf
            st.session_state["pending_resolution"] = {
                "priority": int(priority) if priority is not None else None,
                "sub_problem": personalize_text(subp, entities),
            }
            return

        elif typ == "STEP":
            instruction = personalize_text(sol, entities)
            add_msg(
                "assistant",
                f"Step to perform:\n\n> {instruction}\n\nPaste your observation/output here to continue.",
                extra={"type": "step_capture"},
                stream=True
            )
            st.session_state["awaiting_step_input"] = True
            wf["step_idx"] = i  # stay on same step until user provides output
            st.session_state["workflow"] = wf
            return

        else:
            add_msg("assistant", f"Unrecognized step type '{typ}'. Moving to the next step.", stream=True)
            i += 1
            wf["step_idx"] = i
            st.session_state["workflow"] = wf
            continue

    # If we reached here, no more steps
    wf["status"] = "completed"
    st.session_state["workflow"] = wf
    add_msg("assistant", "All priorities are completed for this SOP.", stream=True)


def mark_resolved():
    wf = st.session_state["workflow"]
    if not wf:
        return
    wf["status"] = "resolved"
    st.session_state["workflow"] = wf
    st.session_state["pending_resolution"] = None
    st.session_state["awaiting_step_input"] = False
    add_msg("assistant", "Workflow stopped. Marked as resolved.", stream=True)


def mark_not_resolved_and_continue(df: pd.DataFrame):
    st.session_state["pending_resolution"] = None
    # Execute exactly one more step on this rerun
    execute_next_step_once(df)


# -------------------------
# UI
# -------------------------
st.set_page_config(page_title="NEO SOP Diagnostic Chatbot", layout="wide")
st.title("NEO SOP Diagnostic Chatbot")

init_state()

with st.sidebar:
    st.subheader("SOP Source")
    uploaded = st.file_uploader("Upload SOP XLSX (optional)", type=["xlsx"])
    use_default = st.checkbox("Use default SOP path", value=True)

    sop_source = None
    if uploaded is not None:
        sop_source = uploaded
        st.caption("Using uploaded file.")
    elif use_default:
        sop_source = DEFAULT_SOP_PATH
        st.caption(f"Using default: {DEFAULT_SOP_PATH}")
    else:
        st.warning("Upload an XLSX or enable default path.")

    st.divider()
    if st.button("Reset", use_container_width=True):
        st.session_state.clear()
        st.rerun()


if sop_source is None:
    st.info("Upload SOP XLSX or enable default path in the sidebar.")
    st.stop()

# Load SOP + index
try:
    df = load_sop_dataframe_from_path(sop_source)
except Exception as e:
    st.error(f"Failed to load SOP XLSX: {e}")
    st.stop()

problem_rows_df = df[["S.No.", "Problem Statement", "Impact"]].copy()
problems_df, vec, X = build_problem_index(problem_rows_df)

# Render chat history
render_messages()

# If workflow needs selection, show selector
wf = st.session_state.get("workflow")
if wf and wf.get("status") == "needs_selection":
    st.divider()
    st.subheader("Select SOP match")
    ranked = wf["ranked"]
    options = [
        f"S.No. {r['S.No.']} | {r['Problem Statement']} (score={r.get('score', 0):.2f})"
        for r in ranked
    ]
    sel = st.selectbox("Candidates", options=options)
    if st.button("Use selected SOP", type="primary"):
        sel_s_no = float(sel.split("|")[0].replace("S.No.", "").strip())
        wf["selected_s_no"] = sel_s_no
        wf["steps"] = get_steps_for_problem(df, sel_s_no).to_dict("records")
        wf["status"] = "running"
        wf["step_idx"] = 0
        st.session_state["workflow"] = wf

        selected_row = problems_df[problems_df["S.No."] == sel_s_no].iloc[0]
        add_msg(
            "assistant",
            f"Selected SOP: **{personalize_text(selected_row['Problem Statement'], wf['entities'])}**\n\nImpact: **{selected_row['Impact']}**\n\nStarting priority-wise checks.",
            stream=True
        )

        # Immediately run the first step
        execute_next_step_once(df)
        st.rerun()

# Resolution prompt (interactive) - shown after each executed step result
pending = st.session_state.get("pending_resolution")
if pending is not None:
    st.divider()
    st.write("Did this resolve the issue?")

    c1, c2 = st.columns(2)
    with c1:
        if st.button("✓ Resolved", use_container_width=True, key="btn_resolved"):
            add_msg("user", "Resolved")
            mark_resolved()
            st.rerun()

    with c2:
        if st.button("✕ Not yet", use_container_width=True, key="btn_not_yet"):
            add_msg("user", "Not yet")
            mark_not_resolved_and_continue(df)
            st.rerun()


# Chat input
user_text = st.chat_input("Describe the issue, or paste observation output when asked")

if user_text:
    cmd = user_text.strip().lower()
    if cmd in ("/reset", "reset", "/restart"):
        st.session_state.clear()
        st.rerun()

    add_msg("user", user_text)

    wf = st.session_state.get("workflow")

    # If we're waiting for resolution buttons, guide user to use buttons
    if st.session_state.get("pending_resolution") is not None:
        add_msg(
            "assistant",
            "Please use the buttons below to confirm whether the last step resolved the issue.",
            stream=True
        )
        st.rerun()

    # Manual step input capture
    if st.session_state.get("awaiting_step_input") and wf and wf.get("status") == "running":
        i = wf["step_idx"]
        step = wf["steps"][i]
        priority = step.get("Priority")
        subp = step.get("Sub Problem Statement", "")

        wf["captured_steps"].append({
            "priority": int(priority) if priority is not None else None,
            "sub_problem": subp,
            "user_observation": user_text
        })

        add_msg("assistant", "Observation recorded.", stream=True)

        # Advance and ask resolution question
        wf["step_idx"] = i + 1
        st.session_state["workflow"] = wf
        st.session_state["awaiting_step_input"] = False
        st.session_state["pending_resolution"] = {
            "priority": int(priority) if priority is not None else None,
            "sub_problem": personalize_text(subp, wf["entities"]),
        }
        st.rerun()

    # If workflow is resolved/completed or absent, start fresh
    if wf is None or wf.get("status") in ("resolved", "completed"):
        st.session_state["workflow"] = start_new_workflow(df, problems_df, vec, X, user_text)
        # If started running, execute one step immediately
        if st.session_state["workflow"].get("status") == "running":
            execute_next_step_once(df)
        st.rerun()

    # If workflow is running and user typed a new symptom (not manual input), start a new workflow
    if wf and wf.get("status") == "running" and not st.session_state.get("awaiting_step_input"):
        # Start new SOP match as a new issue
        add_msg("assistant", "Starting a new SOP match based on the latest message.", stream=True)
        st.session_state["workflow"] = start_new_workflow(df, problems_df, vec, X, user_text)
        if st.session_state["workflow"].get("status") == "running":
            execute_next_step_once(df)
        st.rerun()


# Auto-run the first step if workflow is running and nothing is pending
wf = st.session_state.get("workflow")
if wf and wf.get("status") == "running":
    if (not st.session_state.get("awaiting_step_input")) and (st.session_state.get("pending_resolution") is None):
        # This ensures that after page refresh/rerun, it continues step-by-step properly
        execute_next_step_once(df)
