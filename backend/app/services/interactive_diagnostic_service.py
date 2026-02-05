"""
Interactive Diagnostic Service - ChatGPT-like Conversational Troubleshooting
Provides step-by-step guided diagnosis with clarification questions and feedback loops
"""

import pandas as pd
import logging
import re
import uuid
import json
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, field

from app.core.config import settings
from app.services.llm_service import LLMService

logger = logging.getLogger(__name__)


class DiagnosticState(Enum):
    """State machine for interactive diagnosis"""
    INITIAL = "initial"                           # Just started, need to understand problem
    AWAITING_CLARIFICATION = "awaiting_clarification"  # Asked user for more details
    PROBLEM_IDENTIFIED = "problem_identified"     # Matched to specific issue
    PRESENTING_STEP = "presenting_step"           # Showing a solution step
    AWAITING_STEP_FEEDBACK = "awaiting_step_feedback"  # Waiting for step result
    TRYING_ALTERNATIVE = "trying_alternative"     # Previous steps didn't work
    RESOLVED = "resolved"                         # Problem solved
    ESCALATED = "escalated"                       # Need developer help


@dataclass
class DiagnosticSession:
    """Session data for interactive diagnosis"""
    session_id: str
    created_at: str
    original_problem: str
    current_state: DiagnosticState = DiagnosticState.INITIAL
    issue_type: Optional[str] = None  # BOT_LEVEL or STATION_LEVEL
    
    # Matched cases from CSV
    matched_cases: List[Dict[str, Any]] = field(default_factory=list)
    current_case_index: int = 0
    
    # Current case solution steps
    solution_steps: List[str] = field(default_factory=list)
    current_step_index: int = 0
    
    # Clarification tracking
    clarification_questions: List[str] = field(default_factory=list)
    clarification_answers: List[str] = field(default_factory=list)
    
    # Conversation history
    conversation_history: List[Dict[str, Any]] = field(default_factory=list)
    
    # Feedback tracking
    step_feedback: List[Dict[str, Any]] = field(default_factory=list)
    
    # Resolution
    resolved: bool = False
    resolution_summary: str = ""


class InteractiveDiagnosticService:
    """
    Super intelligent interactive diagnostic service
    Features:
    - Clarification questions when problem is ambiguous
    - Step-by-step solution walkthrough
    - Feedback after each step
    - Memory of what was tried
    - Smart progression based on user responses
    """
    
    def __init__(self):
        self.sessions: Dict[str, DiagnosticSession] = {}
        self.llm_service = LLMService()
        
        # Load support data
        self.bot_level_issues: List[Dict[str, Any]] = []
        self.station_level_issues: List[Dict[str, Any]] = []
        self.support_logs_path = settings.SUPPORT_DIR / "support_logs"
        
        self._load_support_logs()
        
        logger.info(f"✅ Interactive Diagnostic Service initialized")
        logger.info(f"   Bot-level: {len(self.bot_level_issues)} | Station-level: {len(self.station_level_issues)}")
    
    def _clean_text(self, text: str) -> str:
        """Clean and normalize text"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', text)
        text = text.replace('\u2018', "'").replace('\u2019', "'")
        text = text.replace('\u201c', '"').replace('\u201d', '"')
        text = re.sub(r'\s+', ' ', text)
        return text.strip()
    
    def _clean_sql_query(self, text: str) -> str:
        """Clean SQL query while preserving SQL syntax"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        # Replace smart quotes with regular SQL quotes
        text = text.replace('\x91', "'").replace('\x92', "'")  # Smart single quotes
        text = text.replace('\x93', "'").replace('\x94', "'")  # Smart double quotes
        text = text.replace('\u2018', "'").replace('\u2019', "'")  # Unicode smart quotes
        text = text.replace('\u201c', "'").replace('\u201d', "'")  # Unicode smart quotes
        text = text.replace('…', "'")  # Common encoding issue character
        # Remove only null/control characters that would break SQL
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
        # Normalize line breaks
        text = text.replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ')
        # Normalize multiple spaces to single space
        text = re.sub(r'\s+', ' ', text)
        # Fix missing '*' in SELECT statements - CRITICAL!
        # This MUST happen after whitespace normalization
        text = re.sub(r'\bselect\s+from\b', 'select * from', text, flags=re.IGNORECASE)
        # If multiple SELECTs exist without semicolons, separate them
        text = re.sub(r'(?i)(?<!^)(?<!;)\s+select\b', '; select', text)
        # Fix common CSV issue: missing '*' in SELECT (catch "Select*" with no space)
        text = re.sub(r'\bselect\*\b', 'select *', text, flags=re.IGNORECASE)
        # Clean up spaces around semicolons
        text = re.sub(r'\s*;\s*', '; ', text)
        # Remove trailing semicolons or periods at the end
        text = text.rstrip(';. ')
        return text.strip()
    
    def _clean_sql_query(self, text: str) -> str:
        """Clean SQL query while preserving SQL syntax including * and special characters"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        
        # Replace smart quotes with regular SQL quotes
        text = text.replace('\x91', "'").replace('\x92', "'")  # Smart single quotes
        text = text.replace('\x93', "'").replace('\x94', "'")  # Smart double quotes
        text = text.replace('\u2018', "'").replace('\u2019', "'")  # Unicode smart quotes
        text = text.replace('\u201c', "'").replace('\u201d', "'")  # Unicode smart quotes
        text = text.replace('�', "'")  # Common encoding issue character
        
        # Remove only null/control characters that would break SQL (BUT NOT *)
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
        
        # Normalize line breaks
        text = text.replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ')
        
        # Normalize multiple spaces to single space
        text = re.sub(r'\s+', ' ', text)
        
        # Convert sentence separators before SELECT into semicolons
        text = re.sub(r'\.\s*(select\b)', r'; \1', text, flags=re.IGNORECASE)
        
        # If multiple SELECTs exist without semicolons, separate them
        text = re.sub(r'(?i)(?<!^)(?<!;)\s+select\b', '; select', text)
        
        # Fix common CSV issue: if SELECT is followed directly by FROM (missing *), add *
        text = re.sub(r'\bselect\s+from\b', 'SELECT * FROM', text, flags=re.IGNORECASE)
        
        # Clean up spaces around semicolons
        text = re.sub(r'\s*;\s*', '; ', text)
        
        # Remove trailing semicolons or periods at the end
        text = text.rstrip(';. ')
        
        return text.strip()
    
    def _parse_solution_steps(self, solution_text: str) -> List[str]:
        """
        Parse multi-step solutions from CSV into individual actionable steps
        Handles bullet points (·, -, •, *) and numbered lists
        """
        if not solution_text:
            return []
        
        # Split by bullet points or line breaks
        # Common patterns: ·, -, •, *, numbered (1., 2., etc.)
        steps = []
        
        # First, try to split by bullet patterns
        bullet_pattern = r'[·•\-\*]|\d+\.'
        parts = re.split(bullet_pattern, solution_text)
        
        for part in parts:
            step = part.strip()
            # Clean up the step
            step = re.sub(r'^[\s,;]+', '', step)  # Remove leading punctuation
            step = re.sub(r'[\s,;]+$', '', step)  # Remove trailing punctuation
            
            if step and len(step) > 10:  # Only meaningful steps
                steps.append(step)
        
        # If no steps found, treat the whole thing as one step
        if not steps and solution_text:
            steps = [solution_text]
        
        return steps
    
    def _load_support_logs(self):
        """Load support logs from CSV files with enhanced parsing"""
        try:
            if not self.support_logs_path.exists():
                logger.error(f"❌ Support logs path does not exist: {self.support_logs_path}")
                return
            
            # Bot Level
            bot_csv = self.support_logs_path / "NEO Support Logs(Bot Level).csv"
            if bot_csv.exists():
                self._load_csv_with_multiline_solutions(bot_csv, 'BOT_LEVEL', self.bot_level_issues)
            
            # Station Level
            station_csv = self.support_logs_path / "NEO Support Logs(Station Level ).csv"
            if station_csv.exists():
                self._load_csv_with_multiline_solutions(station_csv, 'STATION_LEVEL', self.station_level_issues)
                
        except Exception as e:
            logger.error(f"❌ Error loading support logs: {e}")
    
    def _load_csv_with_multiline_solutions(self, csv_path: Path, issue_type: str, issues_list: List):
        """Load CSV handling multi-line solutions properly"""
        try:
            for encoding in ['latin1', 'utf-8', 'cp1252', 'iso-8859-1']:
                try:
                    # Read with pandas, handling multi-line cells
                    df = pd.read_csv(csv_path, skiprows=1, encoding=encoding)
                    
                    current_issue = None
                    
                    for _, row in df.iterrows():
                        # Check if this is a new issue (has ID) or continuation
                        first_col = row.iloc[0]
                        
                        if pd.notna(first_col) and str(first_col).strip().isdigit():
                            # New issue
                            if current_issue and current_issue['problem']:
                                issues_list.append(current_issue)
                            
                            current_issue = {
                                'id': int(first_col),
                                'problem': self._clean_text(str(row.iloc[1])) if pd.notna(row.iloc[1]) else '',
                                'impact': self._clean_text(str(row.iloc[2])) if pd.notna(row.iloc[2]) else '',
                                'solution': self._clean_text(str(row.iloc[3])) if pd.notna(row.iloc[3]) else '',
                                'sql_query': self._clean_sql_query(str(row.iloc[4])) if pd.notna(row.iloc[4]) else '',
                                'outcome': self._clean_text(str(row.iloc[5])) if pd.notna(row.iloc[5]) else '',
                                'dev_escalation': self._clean_text(str(row.iloc[6])) if pd.notna(row.iloc[6]) else '',
                                'type': issue_type
                            }
                        elif current_issue:
                            # Continuation - append to solution
                            additional_solution = self._clean_text(str(row.iloc[3])) if pd.notna(row.iloc[3]) else ''
                            if additional_solution:
                                current_issue['solution'] += ' · ' + additional_solution
                    
                    # Don't forget the last issue
                    if current_issue and current_issue['problem']:
                        issues_list.append(current_issue)
                    
                    # Parse solution steps for each issue
                    for issue in issues_list:
                        issue['solution_steps'] = self._parse_solution_steps(issue['solution'])
                    
                    logger.info(f"✅ Loaded {len(issues_list)} {issue_type} issues")
                    break
                    
                except UnicodeDecodeError:
                    continue
                    
        except Exception as e:
            logger.error(f"❌ Error loading {issue_type} CSV: {e}")
    
    # ========================================
    # MAIN CHAT INTERFACE
    # ========================================
    
    def chat(self, message: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Main chat interface - handles all user messages intelligently
        
        Args:
            message: User's message
            session_id: Optional existing session ID
            
        Returns:
            Response with message, state, and suggested actions
        """
        try:
            # Get or create session
            session = None
            if session_id:
                session = self.sessions.get(session_id)
            
            if not session:
                # New conversation - start diagnosis
                return self._start_new_diagnosis(message)
            
            # Add user message to history
            self._add_to_history(session, 'user', message)
            
            # Handle based on current state
            if session.current_state == DiagnosticState.AWAITING_CLARIFICATION:
                return self._handle_clarification_response(session, message)
            
            elif session.current_state == DiagnosticState.AWAITING_STEP_FEEDBACK:
                return self._handle_step_feedback(session, message)
            
            elif session.current_state == DiagnosticState.PRESENTING_STEP:
                return self._handle_during_step(session, message)
            
            elif session.current_state in [DiagnosticState.RESOLVED, DiagnosticState.ESCALATED]:
                return self._handle_after_resolution(session, message)
            
            else:
                # General follow-up or new problem
                return self._handle_general_message(session, message)
                
        except Exception as e:
            logger.error(f"❌ Error in chat: {e}", exc_info=True)
            return {
                'response': f"I encountered an error: {str(e)}. Let's try again.",
                'state': 'error',
                'session_id': session_id
            }
    
    def _start_new_diagnosis(self, problem: str) -> Dict[str, Any]:
        """Start a new diagnostic session"""
        # Create session
        session_id = str(uuid.uuid4())[:12]
        session = DiagnosticSession(
            session_id=session_id,
            created_at=datetime.now().isoformat(),
            original_problem=problem
        )
        self.sessions[session_id] = session
        
        # Add initial message
        self._add_to_history(session, 'user', problem)
        
        # Classify issue type
        issue_type = self._classify_issue_type(problem)
        session.issue_type = issue_type
        
        # Find matching cases
        matched_cases = self._find_matching_cases(problem, issue_type)
        session.matched_cases = matched_cases
        
        if not matched_cases:
            # No matches - ask for more details
            response = self._generate_no_match_response(problem)
            session.current_state = DiagnosticState.AWAITING_CLARIFICATION
            self._add_to_history(session, 'assistant', response)
            
            return {
                'response': response,
                'state': 'awaiting_clarification',
                'session_id': session_id,
                'issue_type': issue_type
            }
        
        # Check if problem is ambiguous (multiple similar matches)
        if self._is_problem_ambiguous(problem, matched_cases):
            return self._ask_clarification(session, matched_cases)
        
        # Clear match - start solution walkthrough
        return self._start_solution_walkthrough(session, matched_cases[0])
    
    def _is_problem_ambiguous(self, problem: str, matched_cases: List[Dict]) -> bool:
        """Check if problem description is too vague and needs clarification"""
        if len(matched_cases) < 2:
            return False
        
        problem_lower = problem.lower()
        
        # Short problem descriptions are often ambiguous
        if len(problem_lower.split()) < 5:
            return True
        
        # Check if top matches are very similar in score
        if len(matched_cases) >= 2:
            top_score = matched_cases[0].get('similarity_score', 0)
            second_score = matched_cases[1].get('similarity_score', 0)
            
            # If scores are close, it's ambiguous
            if top_score > 0 and (second_score / top_score) > 0.7:
                return True
        
        # Check for generic keywords that need clarification
        vague_keywords = [
            'stopped', 'not working', 'issue', 'problem', 'error',
            'stuck', 'failed', 'broken', 'help'
        ]
        
        vague_count = sum(1 for kw in vague_keywords if kw in problem_lower)
        specific_count = len(problem_lower.split()) - vague_count
        
        if vague_count >= 2 and specific_count < 3:
            return True
        
        return False
    
    def _ask_clarification(self, session: DiagnosticSession, matched_cases: List[Dict]) -> Dict[str, Any]:
        """Generate clarification questions based on possible matches"""
        session.current_state = DiagnosticState.AWAITING_CLARIFICATION
        
        # Extract unique problem types from matches
        problem_options = []
        for i, case in enumerate(matched_cases[:4], 1):  # Top 4 options
            problem_options.append(f"{i}. {case['problem']}")
        
        # Generate smart clarification question using LLM
        clarification = self._generate_clarification_question(
            session.original_problem,
            matched_cases
        )
        
        session.clarification_questions.append(clarification)
        self._add_to_history(session, 'assistant', clarification)
        
        return {
            'response': clarification,
            'state': 'awaiting_clarification',
            'session_id': session.session_id,
            'options': problem_options,
            'issue_type': session.issue_type
        }
    
    def _generate_clarification_question(self, problem: str, matched_cases: List[Dict]) -> str:
        """Generate a smart clarification question using LLM"""
        try:
            # Build options summary
            options = []
            for i, case in enumerate(matched_cases[:4], 1):
                options.append(f"{i}. {case['problem']}")
            
            if self.llm_service and self.llm_service.provider != "mock":
                prompt = f"""You are a helpful diagnostic assistant. The user reported an issue but it's not specific enough.

User's Problem: "{problem}"

Possible issues from our knowledge base:
{chr(10).join(options)}

Generate a friendly, conversational clarification question to help narrow down the exact issue.
Be specific about WHAT information you need (location, status, error type, etc.)
Keep it concise (2-3 sentences max).
Include the numbered options if helpful."""

                messages = [{"role": "user", "content": prompt}]
                response = self.llm_service.generate_response(
                    messages=messages,
                    system_prompt="You are a friendly diagnostic support assistant. Be conversational and helpful.",
                    max_tokens=200,
                    temperature=0.7
                )
                return response.strip()
            
            # Fallback without LLM
            return f"""I understand you're having an issue. To help you better, I need a bit more information.

Could you please clarify which of these best describes your situation?

{chr(10).join(options)}

Or describe in more detail: Where exactly is the problem occurring?"""
            
        except Exception as e:
            logger.error(f"Error generating clarification: {e}")
            return f"""I need more details to diagnose your issue correctly.

Which of these matches your problem?
{chr(10).join([f"{i+1}. {c['problem']}" for i, c in enumerate(matched_cases[:4])])}"""
    
    def _handle_clarification_response(self, session: DiagnosticSession, response: str) -> Dict[str, Any]:
        """Handle user's response to clarification question"""
        session.clarification_answers.append(response)
        response_lower = response.lower().strip()
        
        # Check if user selected a number
        if response_lower.isdigit():
            option_num = int(response_lower) - 1
            if 0 <= option_num < len(session.matched_cases):
                selected_case = session.matched_cases[option_num]
                return self._start_solution_walkthrough(session, selected_case)
        
        # Check for number at start ("1", "1.", "option 1", etc.)
        number_match = re.match(r'^(?:option\s*)?(\d+)', response_lower)
        if number_match:
            option_num = int(number_match.group(1)) - 1
            if 0 <= option_num < len(session.matched_cases):
                selected_case = session.matched_cases[option_num]
                return self._start_solution_walkthrough(session, selected_case)
        
        # User provided more context - re-search with combined query
        combined_query = f"{session.original_problem} {response}"
        new_matches = self._find_matching_cases(combined_query, session.issue_type)
        
        if new_matches:
            session.matched_cases = new_matches
            
            if self._is_problem_ambiguous(combined_query, new_matches):
                return self._ask_clarification(session, new_matches)
            
            return self._start_solution_walkthrough(session, new_matches[0])
        
        # Still no good match - ask again
        msg = "I still need more details. Could you describe:\n"
        msg += "- Where exactly is the issue (which bot/station)?\n"
        msg += "- What were you doing when it happened?\n"
        msg += "- Any error messages or indicator lights?"
        
        self._add_to_history(session, 'assistant', msg)
        return {
            'response': msg,
            'state': 'awaiting_clarification',
            'session_id': session.session_id
        }
    
    def _start_solution_walkthrough(self, session: DiagnosticSession, case: Dict[str, Any]) -> Dict[str, Any]:
        """Start step-by-step solution walkthrough"""
        session.current_case_index = session.matched_cases.index(case) if case in session.matched_cases else 0
        session.solution_steps = case.get('solution_steps', [])
        session.current_step_index = 0
        session.current_state = DiagnosticState.PRESENTING_STEP
        
        if not session.solution_steps:
            # No steps parsed - use the full solution
            session.solution_steps = [case.get('solution', 'Please check the system.')]
        
        # Generate introduction message
        intro = self._generate_solution_intro(case, session.solution_steps)
        self._add_to_history(session, 'assistant', intro)
        
        return {
            'response': intro,
            'state': 'presenting_step',
            'session_id': session.session_id,
            'current_case': case['problem'],
            'total_steps': len(session.solution_steps),
            'current_step': 1,
            'issue_type': session.issue_type
        }
    
    def _generate_solution_intro(self, case: Dict[str, Any], steps: List[str]) -> str:
        """Generate introduction to solution walkthrough"""
        try:
            problem = case['problem']
            impact = case.get('impact', 'Unknown')
            first_step = steps[0] if steps else "Check the system"
            total_steps = len(steps)
            
            if self.llm_service and self.llm_service.provider != "mock":
                prompt = f"""You are a friendly diagnostic assistant. Generate a response that:
1. Acknowledges understanding the user's problem: "{problem}"
2. Mentions this is a {impact} impact issue
3. Says we'll solve it step by step ({total_steps} steps total)
4. Presents the FIRST step clearly: "{first_step}"
5. Asks the user to try this step and report the result

Keep it conversational and supportive. Use emoji sparingly. Max 4 sentences before the step."""

                messages = [{"role": "user", "content": prompt}]
                response = self.llm_service.generate_response(
                    messages=messages,
                    system_prompt="You are a friendly diagnostic support assistant.",
                    max_tokens=250,
                    temperature=0.7
                )
                return response.strip()
            
            # Fallback
            return f"""I understand the issue: **{problem}**

This is a **{impact}** priority issue. Let's solve it step by step ({total_steps} steps total).

---

**📋 Step 1 of {total_steps}:**
{first_step}

---

Please try this step and let me know the result. Did this solve the issue, or should we continue to the next step?"""
            
        except Exception as e:
            logger.error(f"Error generating intro: {e}")
            return f"""I found a matching issue: **{case['problem']}**

**Step 1:** {steps[0] if steps else 'Check the system'}

Please try this and let me know the result."""
    
    def _handle_step_feedback(self, session: DiagnosticSession, feedback: str) -> Dict[str, Any]:
        """Handle user feedback after a solution step"""
        feedback_lower = feedback.lower().strip()
        
        # Record feedback
        session.step_feedback.append({
            'step_index': session.current_step_index,
            'step': session.solution_steps[session.current_step_index] if session.current_step_index < len(session.solution_steps) else '',
            'feedback': feedback,
            'timestamp': datetime.now().isoformat()
        })
        
        # Check if resolved
        resolved_keywords = ['solved', 'fixed', 'working', 'resolved', 'works', 'done', 'yes', 'that worked', 'thank']
        if any(kw in feedback_lower for kw in resolved_keywords):
            return self._mark_resolved(session, feedback)
        
        # Check if need next step
        continue_keywords = ['no', 'not', 'next', 'continue', 'still', 'didn\'t work', 'not working', 'same issue', 'try next']
        if any(kw in feedback_lower for kw in continue_keywords):
            return self._present_next_step(session)
        
        # User asked a question or gave unclear feedback
        return self._handle_during_step(session, feedback)
    
    def _handle_during_step(self, session: DiagnosticSession, message: str) -> Dict[str, Any]:
        """Handle questions or messages while presenting a step"""
        message_lower = message.lower()
        
        # Check for common questions
        if any(q in message_lower for q in ['how', 'what', 'where', 'why', 'explain']):
            return self._answer_step_question(session, message)
        
        # Check for navigation
        if 'next' in message_lower or 'continue' in message_lower:
            return self._present_next_step(session)
        
        if 'previous' in message_lower or 'back' in message_lower:
            return self._present_previous_step(session)
        
        if 'skip' in message_lower:
            return self._present_next_step(session)
        
        # Assume it's feedback
        session.current_state = DiagnosticState.AWAITING_STEP_FEEDBACK
        return self._handle_step_feedback(session, message)
    
    def _answer_step_question(self, session: DiagnosticSession, question: str) -> Dict[str, Any]:
        """Answer a question about the current step"""
        current_step = session.solution_steps[session.current_step_index] if session.current_step_index < len(session.solution_steps) else ""
        current_case = session.matched_cases[session.current_case_index] if session.matched_cases else {}
        
        try:
            if self.llm_service and self.llm_service.provider != "mock":
                prompt = f"""The user is working on a diagnostic step and has a question.

Current Problem: {current_case.get('problem', session.original_problem)}
Current Step ({session.current_step_index + 1}): {current_step}
User's Question: {question}

Provide a helpful, concise answer. If it's about HOW to do the step, explain clearly.
After answering, remind them to let you know the result after trying the step."""

                messages = [{"role": "user", "content": prompt}]
                response = self.llm_service.generate_response(
                    messages=messages,
                    system_prompt="You are a helpful diagnostic assistant. Be clear and concise.",
                    max_tokens=300,
                    temperature=0.5
                )
                answer = response.strip()
            else:
                answer = f"For this step: {current_step}\n\nPlease follow the instructions carefully. If you need help navigating the dashboard, look for the mentioned sections in the main menu.\n\nLet me know the result after you try it!"
            
            self._add_to_history(session, 'assistant', answer)
            return {
                'response': answer,
                'state': 'presenting_step',
                'session_id': session.session_id,
                'current_step': session.current_step_index + 1,
                'total_steps': len(session.solution_steps)
            }
            
        except Exception as e:
            logger.error(f"Error answering question: {e}")
            return {
                'response': f"About step {session.current_step_index + 1}: {current_step}\n\nTry following the instructions and let me know the result!",
                'state': 'presenting_step',
                'session_id': session.session_id
            }
    
    def _present_next_step(self, session: DiagnosticSession) -> Dict[str, Any]:
        """Present the next solution step"""
        session.current_step_index += 1
        
        if session.current_step_index >= len(session.solution_steps):
            # All steps exhausted for this case - try next case
            return self._try_next_case(session)
        
        current_step = session.solution_steps[session.current_step_index]
        total_steps = len(session.solution_steps)
        step_num = session.current_step_index + 1
        
        session.current_state = DiagnosticState.AWAITING_STEP_FEEDBACK
        
        msg = f"""Okay, let's try the next step.

---

**📋 Step {step_num} of {total_steps}:**
{current_step}

---

Please try this and let me know: Does this solve the issue, or should we continue?"""
        
        self._add_to_history(session, 'assistant', msg)
        
        return {
            'response': msg,
            'state': 'awaiting_step_feedback',
            'session_id': session.session_id,
            'current_step': step_num,
            'total_steps': total_steps
        }
    
    def _present_previous_step(self, session: DiagnosticSession) -> Dict[str, Any]:
        """Go back to previous step"""
        if session.current_step_index > 0:
            session.current_step_index -= 1
        
        current_step = session.solution_steps[session.current_step_index]
        step_num = session.current_step_index + 1
        
        msg = f"""Going back to the previous step.

**📋 Step {step_num}:**
{current_step}

Let me know the result when you've tried this."""
        
        self._add_to_history(session, 'assistant', msg)
        return {
            'response': msg,
            'state': 'presenting_step',
            'session_id': session.session_id,
            'current_step': step_num
        }
    
    def _try_next_case(self, session: DiagnosticSession) -> Dict[str, Any]:
        """Try the next matching case when current case didn't work"""
        session.current_case_index += 1
        
        if session.current_case_index >= len(session.matched_cases):
            return self._escalate(session)
        
        next_case = session.matched_cases[session.current_case_index]
        session.solution_steps = next_case.get('solution_steps', [next_case.get('solution', '')])
        session.current_step_index = 0
        session.current_state = DiagnosticState.TRYING_ALTERNATIVE
        
        msg = f"""The previous solution didn't fully resolve the issue. Let me try a different approach.

---

**🔄 Alternative Solution ({session.current_case_index + 1} of {len(session.matched_cases)}):**
**Issue:** {next_case['problem']}

**📋 Step 1 of {len(session.solution_steps)}:**
{session.solution_steps[0] if session.solution_steps else 'Check the system'}

---

Please try this step and let me know the result."""
        
        self._add_to_history(session, 'assistant', msg)
        
        return {
            'response': msg,
            'state': 'trying_alternative',
            'session_id': session.session_id,
            'case_number': session.current_case_index + 1,
            'total_cases': len(session.matched_cases),
            'current_step': 1,
            'total_steps': len(session.solution_steps)
        }
    
    def _mark_resolved(self, session: DiagnosticSession, feedback: str) -> Dict[str, Any]:
        """Mark the issue as resolved"""
        session.resolved = True
        session.current_state = DiagnosticState.RESOLVED
        
        current_case = session.matched_cases[session.current_case_index] if session.matched_cases else {}
        
        resolution_msg = f"""🎉 **Great news! The issue has been resolved.**

**Problem:** {session.original_problem}
**Solution Applied:** {current_case.get('problem', 'N/A')}
**Steps Completed:** {session.current_step_index + 1}

Is there anything else I can help you with today?"""
        
        session.resolution_summary = resolution_msg
        self._add_to_history(session, 'assistant', resolution_msg)
        
        return {
            'response': resolution_msg,
            'state': 'resolved',
            'session_id': session.session_id,
            'resolved': True,
            'steps_taken': session.current_step_index + 1,
            'case_used': session.current_case_index + 1
        }
    
    def _escalate(self, session: DiagnosticSession) -> Dict[str, Any]:
        """Escalate to development team when all solutions exhausted"""
        session.current_state = DiagnosticState.ESCALATED
        
        # Build escalation summary
        steps_tried = []
        for fb in session.step_feedback:
            steps_tried.append(f"- {fb.get('step', 'N/A')[:100]}...")
        
        escalation_msg = f"""⚠️ **Escalation Required**

I've tried all known solutions for your issue, but the problem persists.

**Original Problem:** {session.original_problem}
**Issue Type:** {session.issue_type}
**Cases Tried:** {session.current_case_index + 1}
**Steps Attempted:** {len(session.step_feedback)}

**Recommendation:**
1. Please raise a ticket with the development team
2. Include this session ID: **{session.session_id}**
3. Attach any error logs or screenshots

A developer will investigate this issue further. Is there anything else I can help with in the meantime?"""
        
        self._add_to_history(session, 'assistant', escalation_msg)
        
        return {
            'response': escalation_msg,
            'state': 'escalated',
            'session_id': session.session_id,
            'escalation_required': True,
            'summary': {
                'problem': session.original_problem,
                'cases_tried': session.current_case_index + 1,
                'steps_attempted': len(session.step_feedback)
            }
        }
    
    def _handle_after_resolution(self, session: DiagnosticSession, message: str) -> Dict[str, Any]:
        """Handle messages after resolution or escalation"""
        message_lower = message.lower()
        
        # Check if user has a new problem
        new_problem_keywords = ['another', 'new', 'different', 'also', 'now', 'having']
        if any(kw in message_lower for kw in new_problem_keywords):
            # Start fresh diagnosis
            return self._start_new_diagnosis(message)
        
        # General thank you or closing
        closing_keywords = ['thank', 'bye', 'done', 'ok', 'great', 'no']
        if any(kw in message_lower for kw in closing_keywords):
            msg = "You're welcome! Feel free to start a new conversation anytime you need help. Have a great day! 👋"
            self._add_to_history(session, 'assistant', msg)
            return {
                'response': msg,
                'state': session.current_state.value,
                'session_id': session.session_id
            }
        
        # Unclear - ask what they need
        msg = "Is there another issue I can help you with, or would you like to start a new diagnostic session?"
        self._add_to_history(session, 'assistant', msg)
        return {
            'response': msg,
            'state': session.current_state.value,
            'session_id': session.session_id
        }
    
    def _handle_general_message(self, session: DiagnosticSession, message: str) -> Dict[str, Any]:
        """Handle general messages that don't fit other patterns"""
        # Treat as a new problem or continue
        if session.matched_cases and session.current_state != DiagnosticState.RESOLVED:
            # Resume from where we left off
            current_step = session.solution_steps[session.current_step_index] if session.current_step_index < len(session.solution_steps) else ""
            
            msg = f"Let's continue with the diagnostic. We were at step {session.current_step_index + 1}:\n\n{current_step}\n\nHave you tried this step? What was the result?"
            self._add_to_history(session, 'assistant', msg)
            session.current_state = DiagnosticState.AWAITING_STEP_FEEDBACK
            
            return {
                'response': msg,
                'state': 'awaiting_step_feedback',
                'session_id': session.session_id
            }
        
        # Start fresh
        return self._start_new_diagnosis(message)
    
    def _generate_no_match_response(self, problem: str) -> str:
        """Generate response when no matching cases found"""
        return f"""I couldn't find an exact match for your issue in our knowledge base.

Could you provide more details about:
1. **Where** is the problem occurring? (which bot ID, station, location)
2. **What** exactly is happening? (error messages, indicator lights, behaviors)
3. **When** did it start? (after an update, randomly, specific trigger)

The more details you provide, the better I can help diagnose the issue."""
    
    # ========================================
    # HELPER METHODS
    # ========================================
    
    def _classify_issue_type(self, problem: str) -> str:
        """Classify issue as BOT_LEVEL or STATION_LEVEL"""
        problem_lower = problem.lower()
        
        bot_keywords = ['bot', 'robot', 'moving', 'stuck', 'charging', 'lidar', 'xy', 'z axis', 'parking']
        station_keywords = ['station', 'induct', 'pick', 'scanner', 'conveyor', 'bin', 'tote']
        
        bot_score = sum(1 for kw in bot_keywords if kw in problem_lower)
        station_score = sum(1 for kw in station_keywords if kw in problem_lower)
        
        if bot_score > station_score:
            return 'BOT_LEVEL'
        elif station_score > bot_score:
            return 'STATION_LEVEL'
        
        # Default to bot level
        return 'BOT_LEVEL'
    
    def _find_matching_cases(self, query: str, issue_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """Find matching cases from knowledge base"""
        query_lower = query.lower()
        query_terms = set(query_lower.split())
        
        if issue_type == 'BOT_LEVEL':
            all_issues = self.bot_level_issues
        elif issue_type == 'STATION_LEVEL':
            all_issues = self.station_level_issues
        else:
            all_issues = self.bot_level_issues + self.station_level_issues
        
        matches = []
        
        for issue in all_issues:
            problem_lower = issue['problem'].lower()
            score = 0
            
            # Exact phrase match
            if query_lower in problem_lower:
                score += 50
            
            # Individual word matches
            problem_terms = set(problem_lower.split())
            matching_terms = query_terms & problem_terms
            score += len(matching_terms) * 5
            
            # Keyword relevance
            for term in query_terms:
                if term in problem_lower:
                    score += 3
            
            if score > 0:
                matches.append({**issue, 'similarity_score': score})
        
        matches.sort(key=lambda x: (-x['similarity_score'], -self._impact_priority(x.get('impact', ''))))
        return matches[:5]
    
    def _impact_priority(self, impact: str) -> int:
        """Convert impact to priority score"""
        impact_lower = (impact or '').lower()
        if 'high' in impact_lower:
            return 3
        elif 'medium' in impact_lower:
            return 2
        return 1
    
    def _add_to_history(self, session: DiagnosticSession, role: str, message: str, metadata: Dict = None):
        """Add message to conversation history"""
        session.conversation_history.append({
            'role': role,
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'metadata': metadata or {}
        })
    
    def get_session(self, session_id: str) -> Optional[DiagnosticSession]:
        """Get session by ID"""
        return self.sessions.get(session_id)
    
    def get_session_summary(self, session_id: str) -> Dict[str, Any]:
        """Get session summary"""
        session = self.sessions.get(session_id)
        if not session:
            return {'error': 'Session not found'}
        
        return {
            'session_id': session.session_id,
            'created_at': session.created_at,
            'original_problem': session.original_problem,
            'current_state': session.current_state.value,
            'issue_type': session.issue_type,
            'cases_tried': session.current_case_index + 1,
            'current_step': session.current_step_index + 1,
            'total_steps': len(session.solution_steps),
            'resolved': session.resolved,
            'message_count': len(session.conversation_history)
        }


# Singleton instance
_interactive_diagnostic_service = None

def get_interactive_diagnostic_service() -> InteractiveDiagnosticService:
    """Get singleton instance of InteractiveDiagnosticService"""
    global _interactive_diagnostic_service
    if _interactive_diagnostic_service is None:
        _interactive_diagnostic_service = InteractiveDiagnosticService()
    return _interactive_diagnostic_service
