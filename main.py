import os
import json
import re
import streamlit as st
import pandas as pd

from dotenv import load_dotenv
load_dotenv()

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from openai import OpenAI

# Optional (recommended) for safety checks
try:
    import sqlglot
except ImportError:
    sqlglot = None

# Optional (only if you want to validate by connecting to DB)
try:
    from sqlalchemy import create_engine, text as sql_text
except ImportError:
    create_engine = None
    sql_text = None


# ----------------------------
# Strict-schema helper (fixes your 400)
# ----------------------------
def make_openai_strict(schema: dict) -> dict:
    """
    OpenAI Structured Outputs strict mode expects:
      - additionalProperties: false for every object
      - required includes ALL keys in properties for every object
    This function enforces that recursively.
    """
    if not isinstance(schema, dict):
        return schema

    schema = dict(schema)  # copy

    t = schema.get("type")
    if t == "object":
        props = schema.get("properties", {})
        if isinstance(props, dict):
            # required must include every property key
            schema["required"] = list(props.keys())
            schema["additionalProperties"] = False
            for k, v in props.items():
                props[k] = make_openai_strict(v)
            schema["properties"] = props

    if t == "array" and "items" in schema:
        schema["items"] = make_openai_strict(schema["items"])

    # anyOf recursion (if you later use nullable unions)
    if "anyOf" in schema and isinstance(schema["anyOf"], list):
        schema["anyOf"] = [make_openai_strict(x) for x in schema["anyOf"]]

    return schema


# ----------------------------
# SQL safety
# ----------------------------
DANGEROUS_SQL_RE = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|replace)\b",
    re.IGNORECASE,
)

def is_read_only_sql(sql: str) -> bool:
    if not sql or not sql.strip():
        return False
    if DANGEROUS_SQL_RE.search(sql):
        return False
    # If sqlglot is available, be stricter: only allow SELECT/CTE(SELECT)
    if sqlglot:
        try:
            parsed = sqlglot.parse_one(sql, read="mysql")
            # allow WITH ... SELECT
            return parsed.key.upper() in ("SELECT", "WITH")
        except Exception:
            return False
    # Fallback: allow if it starts with SELECT or WITH
    s = sql.strip().lower()
    return s.startswith("select") or s.startswith("with")


# ----------------------------
# Schema retrieval (table selection)
# ----------------------------
@st.cache_data(show_spinner=False)
def load_table_summary(csv_bytes: bytes) -> pd.DataFrame:
    df = pd.read_csv(pd.io.common.BytesIO(csv_bytes))
    required_cols = ["Table_name", "Table_description", "Table_columns(Data type)", "Primary_key"]
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"CSV missing columns: {missing}. Found: {list(df.columns)}")
    df = df.fillna("")
    return df

@st.cache_resource(show_spinner=False)
def build_retriever(df: pd.DataFrame):
    docs = (
        df["Table_name"].astype(str) + " | " +
        df["Table_description"].astype(str) + " | " +
        df["Table_columns(Data type)"].astype(str) + " | PK: " +
        df["Primary_key"].astype(str)
    ).tolist()

    vec = TfidfVectorizer(ngram_range=(1, 2), min_df=1)
    X = vec.fit_transform(docs)
    return vec, X, docs

def pick_relevant_tables(question: str, df: pd.DataFrame, vec, X, top_k: int = 8):
    qv = vec.transform([question])
    sims = cosine_similarity(qv, X).flatten()
    idxs = sims.argsort()[::-1][:top_k]
    picked = df.iloc[idxs][["Table_name", "Table_description", "Table_columns(Data type)", "Primary_key"]].copy()
    picked["score"] = sims[idxs]
    return picked

def build_schema_context(picked_df: pd.DataFrame) -> str:
    lines = []
    for _, r in picked_df.iterrows():
        lines.append(
            f"TABLE: {r['Table_name']}\n"
            f"DESCRIPTION: {r['Table_description']}\n"
            f"COLUMNS: {r['Table_columns(Data type)']}\n"
            f"PRIMARY KEY: {r['Primary_key']}\n"
        )
    return "\n---\n".join(lines)


# ----------------------------
# OpenAI call (Structured Outputs)
# ----------------------------
BASE_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "sql": {"type": "string"},
        "tables_used": {"type": "array", "items": {"type": "string"}},
        "columns_used": {"type": "array", "items": {"type": "string"}},
        "primary_keys_used": {"type": "array", "items": {"type": "string"}},
        "assumptions": {"type": "array", "items": {"type": "string"}},
        "warnings": {"type": "array", "items": {"type": "string"}},
        "needs_followup": {"type": "boolean"},
        "followup_questions": {"type": "array", "items": {"type": "string"}},
        "is_read_only": {"type": "boolean"},
        "confidence": {"type": "number"},
    },
}

STRICT_RESPONSE_SCHEMA = make_openai_strict(BASE_RESPONSE_SCHEMA)

def generate_sql_openai(client: OpenAI, model: str, question: str, schema_context: str) -> dict:
    instructions = (
        "You are a senior MySQL (MySQL 8.x) Text-to-SQL generator for the NEO database.\n"
        "Rules:\n"
        "1) Use ONLY the tables/columns provided in SCHEMA CONTEXT.\n"
        "2) Output MUST be a single JSON object matching the schema.\n"
        "3) Generate READ-ONLY SQL only (SELECT / WITH). Never write DML/DDL.\n"
        "4) If the question is ambiguous or missing filters, set needs_followup=true and ask up to 3 crisp followups.\n"
        "5) If returning many rows and user didn’t ask for full dump, add a sensible LIMIT (e.g., 200).\n"
        "6) Prefer explicit JOIN conditions using PK/FK-like columns (infer carefully from names).\n"
    )

    user_payload = (
        f"USER QUESTION:\n{question}\n\n"
        f"SCHEMA CONTEXT (only these tables are allowed):\n{schema_context}"
    )

    resp = client.responses.create(
        model=model,
        instructions=instructions,
        input=user_payload,
        text={
            "format": {
                "type": "json_schema",
                "name": "neo_sql_response",
                "strict": True,
                "schema": STRICT_RESPONSE_SCHEMA,
            }
        },
    )

    raw = getattr(resp, "output_text", "") or ""
    if not raw.strip():
        raise RuntimeError("Empty output_text from model response.")
    return json.loads(raw)


# ----------------------------
# Optional DB validation
# ----------------------------
def validate_sql_against_db(sql: str, mysql_url: str, mode: str = "EXPLAIN"):
    if not create_engine:
        raise RuntimeError("sqlalchemy not installed.")
    engine = create_engine(mysql_url, pool_pre_ping=True)
    with engine.connect() as conn:
        if mode == "EXPLAIN":
            rows = conn.execute(sql_text(f"EXPLAIN {sql}")).fetchall()
            return [dict(r._mapping) for r in rows]
        else:
            # Sample execution (SAFE ONLY FOR SELECT)
            df = pd.read_sql_query(sql, conn)
            return df


# ----------------------------
# Streamlit UI
# ----------------------------
st.set_page_config(page_title="NEO Text-to-SQL", layout="wide")
st.title("NEO Text-to-SQL (Schema-RAG + Structured Outputs)")

api_key = os.environ.get("OPENAI_API_KEY", "")
if not api_key:
    api_key = st.sidebar.text_input("OPENAI_API_KEY", type="password", help="Or set in .env file")
model = st.sidebar.text_input("Model", value="gpt-5.2")

st.sidebar.markdown("### Optional: DB validation (read-only)")
use_db = st.sidebar.checkbox("Enable MySQL validation", value=False)

mysql_url = None
if use_db:
    host = st.sidebar.text_input("Host", value="localhost")
    port = st.sidebar.text_input("Port", value="3306")
    user = st.sidebar.text_input("User", value="root")
    pwd = st.sidebar.text_input("Password", value="", type="password")
    db = st.sidebar.text_input("Database", value="neo")
    mysql_url = f"mysql+pymysql://{user}:{pwd}@{host}:{port}/{db}"

uploaded = st.file_uploader("Upload NEO table summary CSV", type=["csv"])
question = st.text_area("Ask a question (natural language)", height=120)

colA, colB = st.columns([1, 1])

if uploaded:
    try:
        df = load_table_summary(uploaded.getvalue())
        vec, X, _docs = build_retriever(df)

        with colA:
            st.subheader("Schema loaded")
            st.write(df.shape)
            st.dataframe(df.head(20), use_container_width=True)

        if question and st.button("Generate SQL"):
            if not api_key.strip():
                st.error("Set OPENAI_API_KEY (sidebar or environment).")
                st.stop()

            client = OpenAI(api_key=api_key)

            picked = pick_relevant_tables(question, df, vec, X, top_k=8)
            schema_context = build_schema_context(picked)

            with colB:
                st.subheader("Picked tables for this question")
                st.dataframe(picked[["Table_name", "score", "Primary_key"]], use_container_width=True)

            payload = generate_sql_openai(client, model, question, schema_context)

            st.subheader("Model output (structured)")
            st.json(payload)

            sql = payload.get("sql", "").strip()
            if sql:
                st.subheader("Generated SQL")
                st.code(sql, language="sql")

                safe = is_read_only_sql(sql)
                st.write(f"Safety check (read-only): **{safe}**")

                if use_db and mysql_url and safe and not payload.get("needs_followup", False):
                    st.subheader("DB validation")
                    mode = st.radio("Validation mode", ["EXPLAIN", "RUN (sample)"], horizontal=True)
                    try:
                        if mode == "EXPLAIN":
                            explain_rows = validate_sql_against_db(sql, mysql_url, mode="EXPLAIN")
                            st.json(explain_rows)
                        else:
                            # You can enforce a hard LIMIT here if you want extra safety
                            df_res = validate_sql_against_db(sql, mysql_url, mode="RUN")
                            st.dataframe(df_res, use_container_width=True)
                    except Exception as e:
                        st.error(f"DB validation failed: {e}")
            else:
                st.warning("No SQL generated (likely needs follow-up questions).")

    except Exception as e:
        st.error(f"Failed to load/parse CSV: {e}")
else:
    st.info("Upload your NEO table summary CSV to start.")
