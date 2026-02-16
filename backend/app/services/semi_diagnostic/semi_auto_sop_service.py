"""
Semi-Auto SOP Diagnostic Service
Based on semi-auto-diag.py - Step-by-step SOP workflow execution
with TF-IDF matching and interactive SQL execution
"""

import re
import time
import uuid
import logging
import numpy as np
import pandas as pd
import pymysql
from typing import Dict, List, Optional, Any, Tuple
from pathlib import Path
from datetime import datetime, timedelta

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from app.core.config import settings
from app.utils.session_manager import get_session_manager

logger = logging.getLogger(__name__)
session_manager = get_session_manager()  # Unified session management


# -------------------------
# CONFIG
# -------------------------
DEFAULT_SOP_PATH = settings.SUPPORT_DIR / "NEO_SUPPORT_SOP.xlsx"
MAX_RESULT_ROWS = 200
MATCH_THRESHOLD = 0.20


# -------------------------
# TEXT + ENTITY HELPERS
# -------------------------
BOT_NUM_RE = re.compile(r"\bbot\s*[-#:]*\s*(\d+)\b", re.IGNORECASE)
BOT_ID_RE = re.compile(r"\bBOT-\d{4}\b", re.IGNORECASE)


def extract_entities(user_text: str) -> dict:
    """Extract BOT IDs and numbers from user text"""
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
    """Normalize text for TF-IDF matching"""
    if s is None:
        return ""
    s = str(s).lower()

    s = re.sub(r"\bbot\s*[-#:]*\s*\d+\b", "bot", s)
    s = re.sub(r"\bbot-\d{4}\b", "bot", s)

    s = re.sub(r"[^a-z0-9\s]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def personalize_text(text: str, entities: dict) -> str:
    """Replace BOT placeholders with actual BOT ID"""
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
    """Substitute BOT IDs into SQL queries"""
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
    """Check if SQL is a safe read-only query"""
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


class SOPWorkflowSession:
    """Represents an active SOP diagnostic workflow session"""
    
    def __init__(self, session_id: str, user_query: str, entities: dict):
        self.session_id = session_id
        self.created_at = datetime.now()
        self.user_query = user_query
        self.entities = entities
        self.status = "initialized"  # initialized, needs_selection, running, awaiting_step_input, awaiting_resolution, completed, resolved
        self.messages: List[Dict[str, Any]] = []
        
        # Workflow state
        self.ranked_problems: List[Dict] = []
        self.selected_s_no: Optional[float] = None
        self.selected_problem: Optional[str] = None
        self.selected_impact: Optional[str] = None
        self.steps: List[Dict] = []
        self.step_idx: int = 0
        self.captured_steps: List[Dict] = []
        
        # Pending states
        self.pending_resolution: Optional[Dict] = None
        self.awaiting_step_input: bool = False
        
    def add_message(self, role: str, content: str, extra: Optional[Dict] = None):
        """Add a message to session history"""
        self.messages.append({
            "id": str(uuid.uuid4()),
            "role": role,
            "content": content,
            "extra": extra,
            "timestamp": datetime.now().isoformat()
        })
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert session to dictionary for API response"""
        return {
            "session_id": self.session_id,
            "created_at": self.created_at.isoformat(),
            "user_query": self.user_query,
            "entities": self.entities,
            "status": self.status,
            "messages": self.messages,
            "selected_problem": self.selected_problem,
            "selected_impact": self.selected_impact,
            "current_step": self.step_idx,
            "total_steps": len(self.steps),
            "pending_resolution": self.pending_resolution,
            "awaiting_step_input": self.awaiting_step_input
        }


class SemiAutoSOPService:
    """
    Semi-Automated SOP Diagnostic Service
    
    Features:
    - Load SOP from Excel file
    - TF-IDF based problem matching
    - Priority-based step-by-step execution
    - SQL query execution and result display
    - Interactive resolution workflow
    """
    
    def __init__(self, sop_path: Optional[Path] = None):
        self.sop_path = sop_path or DEFAULT_SOP_PATH
        self.df: Optional[pd.DataFrame] = None
        self.problems_df: Optional[pd.DataFrame] = None
        self.vectorizer: Optional[TfidfVectorizer] = None
        self.tfidf_matrix = None
        
        # Session storage
        self.sessions: Dict[str, SOPWorkflowSession] = {}
        
        # Database config
        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME,
            'charset': 'utf8mb4',
            'connect_timeout': 5,
            'read_timeout': 10,
            'write_timeout': 10,
            'cursorclass': pymysql.cursors.DictCursor,
            'autocommit': True
        }
        
        self._load_sop()
        self._build_index()
        
        logger.info(f"✅ Semi-Auto SOP Service initialized")
        logger.info(f"   SOP Path: {self.sop_path}")
        logger.info(f"   Problems loaded: {len(self.problems_df) if self.problems_df is not None else 0}")
    
    def _load_sop(self):
        """Load SOP from Excel file"""
        try:
            if not self.sop_path.exists():
                logger.error(f"❌ SOP file not found: {self.sop_path}")
                return
            
            df = pd.read_excel(self.sop_path)
            
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
            self.df = df
            
            logger.info(f"✅ Loaded SOP with {len(df)} rows")
            
        except Exception as e:
            logger.error(f"❌ Error loading SOP: {e}")
    
    def _build_index(self):
        """Build TF-IDF index for problem matching"""
        if self.df is None:
            return
        
        try:
            self.problems_df = (
                self.df[["S.No.", "Problem Statement", "Impact"]]
                .drop_duplicates()
                .reset_index(drop=True)
                .copy()
            )
            self.problems_df["norm"] = self.problems_df["Problem Statement"].apply(normalize_for_match)
            
            self.vectorizer = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), min_df=1)
            self.tfidf_matrix = self.vectorizer.fit_transform(self.problems_df["norm"].tolist())
            
            logger.info(f"✅ Built TF-IDF index for {len(self.problems_df)} problem statements")
            
        except Exception as e:
            logger.error(f"❌ Error building index: {e}")
    
    def _select_best_problem(self, user_query: str) -> Tuple[Dict, pd.DataFrame]:
        """Find best matching problem using TF-IDF similarity"""
        qn = normalize_for_match(user_query)
        qv = self.vectorizer.transform([qn])
        sims = cosine_similarity(self.tfidf_matrix, qv).ravel()
        
        best_idx = int(np.argmax(sims))
        best_score = float(sims[best_idx])
        
        ranked = (
            self.problems_df.assign(score=sims)
            .sort_values("score", ascending=False)
            .head(5)
            .reset_index(drop=True)
        )
        
        best_row = self.problems_df.iloc[best_idx].to_dict()
        best_row["score"] = best_score
        return best_row, ranked
    
    def _get_steps_for_problem(self, s_no: float) -> List[Dict]:
        """Get priority-ordered steps for a problem"""
        steps = self.df[self.df["S.No."] == s_no].copy()
        steps = steps.sort_values(["Priority"], ascending=True)
        return steps.to_dict("records")
    
    def _connect_db(self, attempts: int = 5):
        """Connect to database with retry logic"""
        last_error = None
        for i in range(attempts):
            try:
                return pymysql.connect(**self.db_config)
            except Exception as e:
                last_error = e
                time.sleep(0.4 * (i + 1))
        raise last_error
    
    def _run_sql(self, sql: str) -> Tuple[Optional[List[Dict]], Optional[str]]:
        """Execute SQL query and return results"""
        try:
            conn = self._connect_db()
            with conn.cursor() as cur:
                cur.execute(sql)
                rows = cur.fetchall()
            conn.close()
            return rows, None
        except Exception as e:
            return None, str(e)
    
    # =========================================
    # PUBLIC API METHODS
    # =========================================
    
    def start_workflow(self, user_query: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Start a new SOP diagnostic workflow
        
        Args:
            user_query: User's problem description
            session_id: Optional existing session ID to reuse (for cross-service continuity)
            
        Returns:
            Session data with matched problems or first step
        """
        if self.df is None or self.problems_df is None:
            return {
                "success": False,
                "error": "SOP data not loaded. Please upload or configure SOP file."
            }
        
        # Create or reuse session
        if not session_id:
            session_id = str(uuid.uuid4())[:8]
        entities = extract_entities(user_query)
        session = SOPWorkflowSession(session_id, user_query, entities)
        session.add_message("user", user_query)
        
        # 🔥 ADD: Sync with unified session manager for cross-service history
        session_manager.add_message(
            session_id,
            'user',
            user_query,
            metadata={'chatbot_type': 'semi_auto_diagnostic', 'service': 'sop'}
        )
        
        # Find best matching problem
        best, ranked = self._select_best_problem(user_query)
        
        # Convert ranked to list of dicts
        ranked_list = ranked[["S.No.", "Problem Statement", "Impact", "score"]].to_dict("records")
        session.ranked_problems = ranked_list
        
        if best["score"] < MATCH_THRESHOLD:
            # Low confidence - need user selection
            session.status = "needs_selection"
            selection_message = f"Match confidence is low (score={best['score']:.2f}). Please select the correct Problem Statement from the options below."
            session.add_message(
                "assistant",
                selection_message,
                extra={"type": "top_matches", "candidates": ranked_list}
            )
            self.sessions[session_id] = session
            
            # 🔥 ADD: Sync with unified session manager
            session_manager.add_message(
                session_id,
                'assistant',
                selection_message,
                metadata={'chatbot_type': 'semi_auto_diagnostic', 'status': 'needs_selection', 'candidates_count': len(ranked_list)}
            )
            
            return {
                "success": True,
                "session_id": session_id,
                "status": "needs_selection",
                "message": selection_message,
                "candidates": ranked_list,
                "messages": session.messages
            }
        
        # High confidence match - start workflow
        s_no = best["S.No."]
        session.selected_s_no = s_no
        session.selected_problem = best["Problem Statement"]
        session.selected_impact = best.get("Impact", "")
        session.steps = self._get_steps_for_problem(s_no)
        session.status = "running"
        
        workflow_start_message = f"Matched SOP: **{personalize_text(best['Problem Statement'], entities)}**\n\nImpact: **{best.get('Impact', 'N/A')}**\n\nStarting priority-wise checks."
        session.add_message(
            "assistant",
            workflow_start_message
        )
        
        self.sessions[session_id] = session
        
        # 🔥 ADD: Sync with unified session manager
        session_manager.add_message(
            session_id,
            'assistant',
            workflow_start_message,
            metadata={'chatbot_type': 'semi_auto_diagnostic', 'status': 'running', 'problem': best["Problem Statement"]}
        )
        
        # Execute first step
        step_result = self._execute_next_step(session)
        
        return {
            "success": True,
            "session_id": session_id,
            "status": session.status,
            "matched_problem": best["Problem Statement"],
            "impact": best.get("Impact", ""),
            "score": best["score"],
            "total_steps": len(session.steps),
            "current_step": session.step_idx,
            "messages": session.messages,
            "pending_resolution": session.pending_resolution,
            "awaiting_step_input": session.awaiting_step_input,
            **step_result
        }
    
    def select_problem(self, session_id: str, s_no: float) -> Dict[str, Any]:
        """
        User selects a problem from candidates
        
        Args:
            session_id: Session ID
            s_no: S.No. of selected problem
            
        Returns:
            Updated session with first step
        """
        session = self.sessions.get(session_id)
        if not session:
            return {"success": False, "error": "Session not found"}
        
        if session.status != "needs_selection":
            return {"success": False, "error": "Session is not awaiting selection"}
        
        # Get selected problem details
        selected_row = self.problems_df[self.problems_df["S.No."] == s_no]
        if selected_row.empty:
            return {"success": False, "error": f"Problem S.No. {s_no} not found"}
        
        selected_row = selected_row.iloc[0]
        
        session.selected_s_no = s_no
        session.selected_problem = selected_row["Problem Statement"]
        session.selected_impact = selected_row.get("Impact", "")
        session.steps = self._get_steps_for_problem(s_no)
        session.step_idx = 0
        session.status = "running"
        
        selection_message = f"Selected SOP: **{personalize_text(selected_row['Problem Statement'], session.entities)}**\n\nImpact: **{selected_row.get('Impact', 'N/A')}**\n\nStarting priority-wise checks."
        session.add_message(
            "assistant",
            selection_message
        )
        
        # 🔥 ADD: Sync with unified session manager
        session_manager.add_message(
            session_id,
            'assistant',
            selection_message,
            metadata={'chatbot_type': 'semi_auto_diagnostic', 'status': 'running', 'selected_problem': selected_row["Problem Statement"]}
        )
        
        # Execute first step
        step_result = self._execute_next_step(session)
        
        return {
            "success": True,
            "session_id": session_id,
            "status": session.status,
            "selected_problem": session.selected_problem,
            "impact": session.selected_impact,
            "total_steps": len(session.steps),
            "current_step": session.step_idx,
            "messages": session.messages,
            "pending_resolution": session.pending_resolution,
            "awaiting_step_input": session.awaiting_step_input,
            **step_result
        }
    
    def submit_step_input(self, session_id: str, user_input: str) -> Dict[str, Any]:
        """
        User submits observation/output for a manual step
        
        Args:
            session_id: Session ID
            user_input: User's observation or output
            
        Returns:
            Updated session state
        """
        session = self.sessions.get(session_id)
        if not session:
            return {"success": False, "error": "Session not found"}
        
        if not session.awaiting_step_input:
            return {"success": False, "error": "Session is not awaiting step input"}
        
        session.add_message("user", user_input)
        
        # 🔥 ADD: Sync with unified session manager
        session_manager.add_message(
            session_id,
            'user',
            user_input,
            metadata={'chatbot_type': 'semi_auto_diagnostic', 'type': 'step_observation'}
        )
        
        # Capture the step observation
        i = session.step_idx
        step = session.steps[i]
        priority = step.get("Priority")
        subp = step.get("Sub Problem Statement", "")
        
        session.captured_steps.append({
            "priority": int(priority) if priority is not None else None,
            "sub_problem": subp,
            "user_observation": user_input
        })
        
        session.add_message("assistant", "Observation recorded.")
        
        # 🔥 ADD: Sync with unified session manager
        session_manager.add_message(
            session_id,
            'assistant',
            "Observation recorded.",
            metadata={'chatbot_type': 'semi_auto_diagnostic', 'type': 'acknowledgment'}
        )
        
        # Advance and ask resolution question
        session.step_idx = i + 1
        session.awaiting_step_input = False
        session.pending_resolution = {
            "priority": int(priority) if priority is not None else None,
            "sub_problem": personalize_text(subp, session.entities)
        }
        session.status = "awaiting_resolution"
        
        return {
            "success": True,
            "session_id": session_id,
            "status": session.status,
            "messages": session.messages,
            "pending_resolution": session.pending_resolution,
            "awaiting_step_input": session.awaiting_step_input,
            "current_step": session.step_idx,
            "total_steps": len(session.steps)
        }
    
    def mark_resolved(self, session_id: str) -> Dict[str, Any]:
        """
        User marks the issue as resolved
        
        Args:
            session_id: Session ID
            
        Returns:
            Final session state
        """
        session = self.sessions.get(session_id)
        if not session:
            return {"success": False, "error": "Session not found"}
        
        session.status = "resolved"
        session.pending_resolution = None
        session.awaiting_step_input = False
        
        session.add_message("user", "Resolved")
        session.add_message("assistant", "Workflow stopped. Issue marked as resolved. 🎉")
        
        return {
            "success": True,
            "session_id": session_id,
            "status": session.status,
            "messages": session.messages,
            "message": "Issue marked as resolved."
        }
    
    def mark_not_resolved(self, session_id: str) -> Dict[str, Any]:
        """
        User marks the step as not resolved, continue to next step
        
        Args:
            session_id: Session ID
            
        Returns:
            Updated session with next step
        """
        session = self.sessions.get(session_id)
        if not session:
            return {"success": False, "error": "Session not found"}
        
        session.add_message("user", "Not yet")
        session.pending_resolution = None
        session.status = "running"
        
        # Execute next step
        step_result = self._execute_next_step(session)
        
        return {
            "success": True,
            "session_id": session_id,
            "status": session.status,
            "messages": session.messages,
            "pending_resolution": session.pending_resolution,
            "awaiting_step_input": session.awaiting_step_input,
            "current_step": session.step_idx,
            "total_steps": len(session.steps),
            **step_result
        }
    
    def _execute_next_step(self, session: SOPWorkflowSession) -> Dict[str, Any]:
        """
        Execute exactly ONE actionable step
        
        Returns:
            Step execution result
        """
        if session.status != "running":
            return {}
        
        if session.awaiting_step_input or session.pending_resolution:
            return {}
        
        entities = session.entities
        steps = session.steps
        i = session.step_idx
        
        # Process steps
        while i < len(steps):
            step = steps[i]
            priority = step.get("Priority")
            subp = step.get("Sub Problem Statement", "")
            typ = str(step.get("SQL/Step", "")).strip().upper()
            sol = step.get("Solution", "")
            
            session.add_message(
                "assistant",
                f"**Priority {priority}:** {personalize_text(subp, entities)}"
            )
            
            if typ == "SQL":
                sql = substitute_sql(sol, entities)
                
                if not sql:
                    session.add_message(
                        "assistant",
                        "No SQL found in SOP for this priority. Moving to the next step."
                    )
                    i += 1
                    session.step_idx = i
                    continue
                
                session.add_message("assistant", f"```sql\n{sql}\n```")
                
                # If SQL is not safe, treat as manual step
                if not is_safe_select_query(sql):
                    session.add_message(
                        "assistant",
                        "This SQL is not a single read-only query. Please execute it manually and paste the output here to proceed.",
                        extra={"type": "step_capture"}
                    )
                    session.awaiting_step_input = True
                    session.step_idx = i
                    return {"requires_manual_input": True, "sql": sql}
                
                # Execute SQL
                rows, err = self._run_sql(sql)
                if err:
                    session.add_message(
                        "assistant",
                        "SQL execution failed.",
                        extra={"type": "sql_result", "error": err, "rows": []}
                    )
                else:
                    trimmed = (rows or [])[:MAX_RESULT_ROWS]
                    session.add_message(
                        "assistant",
                        f"SQL result: {len(rows or [])} rows returned (showing up to {MAX_RESULT_ROWS})",
                        extra={"type": "sql_result", "error": None, "rows": trimmed}
                    )
                
                # Advance step, pause for resolution
                session.step_idx = i + 1
                session.pending_resolution = {
                    "priority": int(priority) if priority is not None else None,
                    "sub_problem": personalize_text(subp, entities)
                }
                session.status = "awaiting_resolution"
                
                return {
                    "step_executed": True,
                    "step_type": "SQL",
                    "sql": sql,
                    "sql_result": {"rows": trimmed if not err else [], "error": err}
                }
            
            elif typ == "STEP":
                instruction = personalize_text(sol, entities)
                session.add_message(
                    "assistant",
                    f"Manual step required:\n\n**Action:** {instruction}\n\nPlease perform this step and describe the result below.",
                    extra={"type": "manual_step", "instruction": instruction}
                )
                session.awaiting_step_input = True
                session.step_idx = i
                session.pending_resolution = None  # No resolution yet, waiting for input
                return {
                    "requires_manual_input": True, 
                    "instruction": instruction,
                    "step_type": "STEP",
                    "awaiting_step_input": True
                }
            
            else:
                session.add_message(
                    "assistant",
                    f"Unrecognized step type '{typ}'. Moving to the next step."
                )
                i += 1
                session.step_idx = i
                continue
        
        # All steps completed
        session.status = "completed"
        session.add_message(
            "assistant",
            "All priorities are completed for this SOP. If the issue persists, please escalate or try a different approach."
        )
        
        return {"workflow_completed": True}
    
    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session details"""
        session = self.sessions.get(session_id)
        if not session:
            return None
        return session.to_dict()
    
    def reset_session(self, session_id: str) -> Dict[str, Any]:
        """Reset a session"""
        if session_id in self.sessions:
            del self.sessions[session_id]
        return {"success": True, "message": "Session reset"}
    
    def get_all_problems(self) -> List[Dict[str, Any]]:
        """Get all problem statements for selection"""
        if self.problems_df is None:
            return []
        return self.problems_df[["S.No.", "Problem Statement", "Impact"]].to_dict("records")
    
    def cleanup_old_sessions(self, max_age_hours: int = 24):
        """Remove sessions older than specified hours"""
        now = datetime.now()
        to_remove = []
        
        for session_id, session in self.sessions.items():
            if (now - session.created_at) > timedelta(hours=max_age_hours):
                to_remove.append(session_id)
        
        for session_id in to_remove:
            del self.sessions[session_id]
        
        if to_remove:
            logger.info(f"🧹 Cleaned up {len(to_remove)} old sessions")


# Singleton instance
_sop_service: Optional[SemiAutoSOPService] = None


def get_sop_service() -> SemiAutoSOPService:
    """Get or create the SOP service singleton"""
    global _sop_service
    if _sop_service is None:
        _sop_service = SemiAutoSOPService()
    return _sop_service
