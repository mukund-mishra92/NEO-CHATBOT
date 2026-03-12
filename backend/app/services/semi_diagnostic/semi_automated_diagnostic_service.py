"""
Semi-Automated Diagnostic Support Service
Interactive problem diagnosis with SQL audit and multi-case verification
With session-based memory for conversational follow-ups
"""

import pandas as pd
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import re
import pymysql
import uuid
from datetime import datetime
from app.core.config import settings
from app.services.llm_service import LLMService

logger = logging.getLogger(__name__)


class SessionManager:
    """
    Manages conversation sessions with memory for follow-up questions
    """
    def __init__(self):
        self.sessions: Dict[str, Dict[str, Any]] = {}
    
    def create_session(self, user_problem: str) -> str:
        """Create a new session with conversation history"""
        session_id = str(uuid.uuid4())[:8]
        self.sessions[session_id] = {
            'session_id': session_id,
            'created_at': datetime.now().isoformat(),
            'user_problem': user_problem,
            'conversation_history': [{
                'role': 'user',
                'message': user_problem,
                'timestamp': datetime.now().isoformat()
            }],
            'context': {
                'matched_cases': [],
                'current_case_index': 0,
                'current_case': None,
                'sql_results': None,
                'user_feedback': []
            },
            'resolved': False
        }
        return session_id
    
    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data"""
        return self.sessions.get(session_id)
    
    def update_session(self, session_id: str, updates: Dict[str, Any]):
        """Update session context"""
        if session_id in self.sessions:
            if 'context' in updates:
                self.sessions[session_id]['context'].update(updates['context'])
            if 'resolved' in updates:
                self.sessions[session_id]['resolved'] = updates['resolved']
    
    def add_message(self, session_id: str, role: str, message: str, metadata: Dict[str, Any] = None):
        """Add a message to conversation history"""
        if session_id in self.sessions:
            self.sessions[session_id]['conversation_history'].append({
                'role': role,
                'message': message,
                'timestamp': datetime.now().isoformat(),
                'metadata': metadata or {}
            })
    
    def get_conversation_history(self, session_id: str) -> List[Dict[str, Any]]:
        """Get full conversation history"""
        session = self.get_session(session_id)
        return session['conversation_history'] if session else []
    
    def get_context_summary(self, session_id: str) -> str:
        """Generate context summary for follow-up questions"""
        session = self.get_session(session_id)
        if not session:
            return ""
        
        context = session['context']
        summary = f"Original Problem: {session['user_problem']}\n"
        
        if context['current_case']:
            case = context['current_case']
            summary += f"\nCurrent Case: {case.get('case_number', 'N/A')}\n"
            summary += f"Problem Type: {case.get('type', 'N/A')}\n"
            summary += f"Solution: {case.get('solution', 'N/A')}\n"
        
        if context['sql_results']:
            summary += f"\nSQL Audit Results: {context['sql_results'].get('row_count', 0)} rows found\n"
        
        return summary
    
    def clear_old_sessions(self, max_age_hours: int = 24):
        """Clear sessions older than specified hours"""
        from datetime import timedelta
        now = datetime.now()
        to_remove = []
        
        for session_id, session in self.sessions.items():
            created = datetime.fromisoformat(session['created_at'])
            if (now - created) > timedelta(hours=max_age_hours):
                to_remove.append(session_id)
        
        for session_id in to_remove:
            del self.sessions[session_id]
        
        if to_remove:
            logger.info(f"🧹 Cleared {len(to_remove)} old sessions")


class SemiAutomatedDiagnosticService:
    """
    Semi-automated diagnostic support with:
    - Similarity search for problem matching
    - Impact-based solution prioritization
    - SQL query execution for problem audit
    - Multi-case verification with user feedback
    - Session-based memory for conversational follow-ups
    - Next-best suggestions when user says "not correct"
    """
    
    def __init__(self):
        self.bot_level_issues: List[Dict[str, Any]] = []
        self.station_level_issues: List[Dict[str, Any]] = []
        self.session_manager = SessionManager()
        self.llm_service = LLMService()
        
        # Use absolute path from settings
        self.support_logs_path = settings.SUPPORT_DIR / "support_logs"
        
        logger.info(f"📁 Support logs path: {self.support_logs_path}")
        logger.info(f"📁 Path exists: {self.support_logs_path.exists()}")
        
        # Database config
        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME,
            'charset': 'utf8mb4'
        }
        
        self._load_support_logs()
        
        logger.info(f"✅ Semi-Automated Diagnostic Service initialized")
        logger.info(f"   Bot-level: {len(self.bot_level_issues)} | Station-level: {len(self.station_level_issues)}")
    
    def _clean_text(self, text: str) -> str:
        """Clean and normalize text (for descriptions, solutions, etc.)"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        # Remove problematic invisible characters but keep normal punctuation
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', text)
        # Replace smart quotes with regular quotes
        text = text.replace('\x91', "'").replace('\x92', "'")  # Smart single quotes
        text = text.replace('\x93', '"').replace('\x94', '"')  # Smart double quotes
        text = text.replace('\u2018', "'").replace('\u2019', "'")  # Unicode smart quotes
        text = text.replace('\u201c', '"').replace('\u201d', '"')  # Unicode smart quotes
        # Normalize whitespace
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
        text = text.replace('�', "'")  # Common encoding issue character
        # Remove only null/control characters that would break SQL
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
        # Normalize line breaks
        text = text.replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ')
        # Normalize multiple spaces to single space
        text = re.sub(r'\s+', ' ', text)
        # Convert sentence separators before SELECT into semicolons
        text = re.sub(r'\.\s*(select\b)', r'; \1', text, flags=re.IGNORECASE)
        # If multiple SELECTs exist without semicolons, separate them
        text = re.sub(r'(?i)(?<!^)(?<!;)\s+select\b', '; select', text)
        # Fix common CSV issue: missing '*' in SELECT
        text = re.sub(r'\bselect\s+from\b', 'select * from', text, flags=re.IGNORECASE)
        # Clean up spaces around semicolons
        text = re.sub(r'\s*;\s*', '; ', text)
        # Remove trailing semicolons or periods at the end
        text = text.rstrip(';. ')
        return text.strip()

    def _rephrase_with_llm(self, user_question: str, base_answer: str, context: str) -> str:
        """Rephrase the base answer using LLM (OpenAI/Groq/Anthropic) if available"""
        try:
            if not self.llm_service or self.llm_service.provider == "mock":
                return base_answer

            system_prompt = (
                "You are a helpful assistant for a diagnostic support tool. "
                "Rephrase the provided answer to be clear, concise, and aligned with the user's question. "
                "Do NOT add new facts. Preserve IDs, table names, and SQL exactly if present. "
                "Return plain text only."
            )

            messages = [
                {"role": "user", "content": f"User question: {user_question}"},
                {"role": "assistant", "content": f"Base answer: {base_answer}"},
                {"role": "assistant", "content": f"Context: {context}"}
            ]

            rewritten = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=350,
                temperature=0.2
            )

            return rewritten.strip() if rewritten else base_answer
        except Exception:
            return base_answer
    
    def _load_support_logs(self):
        """Load support logs from CSV files"""
        try:
            if not self.support_logs_path.exists():
                logger.error(f"❌ Support logs path does not exist: {self.support_logs_path}")
                return
            
            # Bot Level
            bot_csv = self.support_logs_path / "NEO Support Logs(Bot Level).csv"
            logger.info(f"📄 Loading bot-level CSV: {bot_csv}")
            logger.info(f"📄 File exists: {bot_csv.exists()}")
            
            if bot_csv.exists():
                for encoding in ['latin1', 'utf-8', 'cp1252', 'iso-8859-1']:
                    try:
                        logger.info(f"  Trying encoding: {encoding}")
                        df = pd.read_csv(bot_csv, skiprows=1, encoding=encoding)
                        logger.info(f"✅ Successfully loaded with {encoding}: {len(df)} rows")
                        break
                    except UnicodeDecodeError as e:
                        logger.warning(f"  Failed with {encoding}: {e}")
                        continue
                    except Exception as e:
                        logger.error(f"  Error with {encoding}: {e}")
                        continue
                
                loaded_count = 0
                for _, row in df.iterrows():
                    if pd.notna(row.iloc[0]):
                        issue = {
                            'id': int(row.iloc[0]),
                            'problem': self._clean_text(str(row.iloc[1])),
                            'impact': self._clean_text(str(row.iloc[2])),  # Severity/Impact
                            'solution': self._clean_text(str(row.iloc[3])),
                            'sql_query': self._clean_sql_query(str(row.iloc[4])),  # Use SQL-specific cleaning
                            'outcome': self._clean_text(str(row.iloc[5])),
                            'dev_escalation': self._clean_text(str(row.iloc[6])),
                            'type': 'BOT_LEVEL'
                        }
                        # Only add if problem is not empty
                        if issue['problem']:
                            self.bot_level_issues.append(issue)
                            loaded_count += 1
                
                logger.info(f"✅ Loaded {loaded_count} bot-level issues")
            else:
                logger.warning(f"⚠️ Bot-level CSV not found: {bot_csv}")
            
            # Station Level
            station_csv = self.support_logs_path / "NEO Support Logs(Station Level ).csv"
            logger.info(f"📄 Loading station-level CSV: {station_csv}")
            logger.info(f"📄 File exists: {station_csv.exists()}")
            
            if station_csv.exists():
                for encoding in ['latin1', 'utf-8', 'cp1252', 'iso-8859-1']:
                    try:
                        logger.info(f"  Trying encoding: {encoding}")
                        df = pd.read_csv(station_csv, skiprows=1, encoding=encoding)
                        logger.info(f"✅ Successfully loaded with {encoding}: {len(df)} rows")
                        break
                    except UnicodeDecodeError as e:
                        logger.warning(f"  Failed with {encoding}: {e}")
                        continue
                    except Exception as e:
                        logger.error(f"  Error with {encoding}: {e}")
                        continue
                
                loaded_count = 0
                for _, row in df.iterrows():
                    if pd.notna(row.iloc[0]):
                        issue = {
                            'id': int(row.iloc[0]),
                            'problem': self._clean_text(str(row.iloc[1])),
                            'impact': self._clean_text(str(row.iloc[2])),
                            'scenario': self._clean_text(str(row.iloc[3])),
                            'solution': self._clean_text(str(row.iloc[4])),
                            'sql_query': self._clean_sql_query(str(row.iloc[5])),  # Use SQL-specific cleaning
                            'outcome': self._clean_text(str(row.iloc[6])),
                            'dev_escalation': self._clean_text(str(row.iloc[7])),
                            'type': 'STATION_LEVEL'
                        }
                        # Only add if problem is not empty
                        if issue['problem']:
                            self.station_level_issues.append(issue)
                            loaded_count += 1
                
                logger.info(f"✅ Loaded {loaded_count} station-level issues")
            else:
                logger.warning(f"⚠️ Station-level CSV not found: {station_csv}")
        
        except Exception as e:
            logger.error(f"❌ Error loading support logs: {e}")
    
    def start_diagnosis(self, user_problem: str, issue_type: Optional[str] = None) -> Dict[str, Any]:
        """
        Start diagnosis by finding similar problems
        Creates a new session with conversation memory
        
        Returns:
            {
                'session_id': str,
                'matched_cases': List[case],
                'current_case': case with index,
                'requires_sql_audit': bool
            }
        """
        # Create session
        session_id = self.session_manager.create_session(user_problem)
        
        # Find similar problems using keyword matching
        matched_cases = self._find_similar_problems(user_problem, issue_type=issue_type)
        
        if not matched_cases:
            self.session_manager.add_message(
                session_id, 
                'assistant', 
                'No similar cases found. Please provide more details.'
            )
            return {
                'session_id': session_id,
                'matched_cases': [],
                'message': 'No similar cases found. Please provide more details.'
            }
        
        # Sort by impact (High > Medium > Low)
        matched_cases.sort(key=lambda x: self._impact_priority(x['impact']), reverse=True)
        
        current_case = matched_cases[0]
        formatted_case = self._format_case_concise(current_case, 0, len(matched_cases))
        formatted_case['assistant_summary'] = self._generate_case_summary(user_problem, formatted_case)
        
        # Update session context
        self.session_manager.update_session(session_id, {
            'context': {
                'matched_cases': matched_cases,
                'current_case_index': 0,
                'current_case': formatted_case
            }
        })
        
        # Add assistant response to history
        self.session_manager.add_message(
            session_id,
            'assistant',
            f"Found {len(matched_cases)} potential solutions. Here's the most likely one.",
            {'case': formatted_case}
        )
        
        return {
            'session_id': session_id,
            'total_matches': len(matched_cases),
            'matched_cases': matched_cases,
            'current_case_index': 0,
            'current_case': formatted_case,
            'requires_sql_audit': bool(current_case.get('sql_query')),
            'issue_type': issue_type
        }

    def _generate_case_summary(self, user_problem: str, case: Dict[str, Any]) -> str:
        """Generate a rephrased summary for the case using LLM"""
        try:
            if not self.llm_service or self.llm_service.provider == "mock":
                return f"Based on your issue, the likely cause is: {case.get('problem', 'N/A')}. Recommended action: {case.get('solution', 'N/A')}"

            system_prompt = (
                "You are a diagnostic assistant. Rephrase the case response based on the user's problem. "
                "Keep it concise (1-3 sentences). Do not add new facts. Preserve IDs and technical terms."
            )

            messages = [
                {"role": "user", "content": f"User problem: {user_problem}"},
                {"role": "assistant", "content": f"Case problem: {case.get('problem', '')}"},
                {"role": "assistant", "content": f"Case solution: {case.get('solution', '')}"}
            ]

            summary = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=180,
                temperature=0.3
            )

            return summary.strip() if summary else f"Based on your issue, the likely cause is: {case.get('problem', 'N/A')}. Recommended action: {case.get('solution', 'N/A')}"
        except Exception:
            return f"Based on your issue, the likely cause is: {case.get('problem', 'N/A')}. Recommended action: {case.get('solution', 'N/A')}"
    
    def _find_similar_problems(self, query: str, issue_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """Find problems matching query keywords"""
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
            
            # Scoring
            score = 0
            if query_lower in problem_lower:
                score += 50
            
            problem_terms = set(problem_lower.split())
            matching_terms = query_terms & problem_terms
            score += len(matching_terms) * 5
            
            if score > 0:
                matches.append({**issue, 'similarity_score': score})
        
        matches.sort(key=lambda x: x['similarity_score'], reverse=True)
        return matches[:5]  # Top 5

    def classify_issue_type(self, user_problem: str) -> Dict[str, Any]:
        """Classify issue type as BOT_LEVEL or STATION_LEVEL using LLM"""
        try:
            # Fallback heuristic if LLM unavailable
            if not self.llm_service or self.llm_service.provider == "mock":
                heuristic = 'BOT_LEVEL' if 'bot' in user_problem.lower() else 'STATION_LEVEL'
                return {
                    'predicted_type': heuristic,
                    'confidence': 0.55,
                    'source': 'heuristic'
                }

            system_prompt = (
                "You are classifying diagnostic issues into one of two categories: BOT_LEVEL or STATION_LEVEL. "
                "Return ONLY one token: BOT_LEVEL or STATION_LEVEL. Do not add any extra text."
            )

            messages = [
                {"role": "user", "content": f"Issue: {user_problem}"}
            ]

            result = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=5,
                temperature=0.0
            ).strip().upper()

            predicted = 'BOT_LEVEL' if 'BOT' in result else 'STATION_LEVEL'
            return {
                'predicted_type': predicted,
                'confidence': 0.75,
                'source': 'llm'
            }
        except Exception:
            heuristic = 'BOT_LEVEL' if 'bot' in user_problem.lower() else 'STATION_LEVEL'
            return {
                'predicted_type': heuristic,
                'confidence': 0.5,
                'source': 'heuristic'
            }
    
    def _impact_priority(self, impact: str) -> int:
        """Convert impact to priority score"""
        impact_lower = impact.lower()
        if 'high' in impact_lower:
            return 3
        elif 'medium' in impact_lower:
            return 2
        return 1
    
    def _format_case_concise(self, case: Dict[str, Any], index: int, total: int) -> Dict[str, Any]:
        """Format case in concise, point-to-point format"""
        formatted = {
            'case_number': f"{index + 1}/{total}",
            'type': case['type'],
            'problem': case['problem'],
            'impact': case['impact'],
            'solution': case['solution']
        }
        
        if case.get('scenario'):
            formatted['scenario'] = case['scenario']
        
        if case.get('sql_query'):
            formatted['sql_query'] = case['sql_query']
            formatted['expected_outcome'] = case.get('outcome', '')
        
        return formatted
    
    def execute_sql_audit(self, sql_query: str) -> Dict[str, Any]:
        """
        Execute SQL query to audit the problem
        Handles multiple queries by executing them sequentially
        
        Returns:
            {
                'success': bool,
                'data': List[dict] or error message,
                'row_count': int
            }
        """
        try:
            # Split multiple queries if separated by semicolons
            queries = [q.strip() for q in sql_query.split(';') if q.strip()]
            
            if not queries:
                return {
                    'success': False,
                    'error': 'No valid SQL query provided',
                    'data': None
                }
            
            # For now, execute only the first query to avoid complexity
            # In production, you might want to execute all and combine results
            query_to_execute = queries[0]
            
            logger.info(f"Executing SQL audit: {query_to_execute}")
            
            conn = pymysql.connect(**self.db_config)
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            cursor.execute(query_to_execute)
            results = cursor.fetchall()
            
            cursor.close()
            conn.close()
            
            return {
                'success': True,
                'data': results,
                'row_count': len(results),
                'columns': list(results[0].keys()) if results else [],
                'query_executed': query_to_execute,
                'total_queries': len(queries),
                'note': f'Executed first query of {len(queries)}' if len(queries) > 1 else None
            }
        
        except Exception as e:
            logger.error(f"❌ SQL audit failed: {e}")
            return {
                'success': False,
                'error': str(e),
                'data': None
            }
    
    def handle_user_feedback(
        self,
        session_id: str,
        is_correct: bool,
        user_comment: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Handle user feedback and suggest next case if not correct
        
        Args:
            session_id: Session ID for conversation context
            is_correct: True if solution worked, False if not
            user_comment: Optional user feedback
        
        Returns:
            Next case or success message
        """
        session = self.session_manager.get_session(session_id)
        if not session:
            return {'error': 'Session not found or expired'}
        
        context = session['context']
        
        # Add user feedback to history
        self.session_manager.add_message(
            session_id,
            'user',
            'This solution worked!' if is_correct else 'This solution did not work.',
            {'feedback': user_comment}
        )
        
        if is_correct:
            self.session_manager.update_session(session_id, {'resolved': True})
            self.session_manager.add_message(
                session_id,
                'assistant',
                'Problem resolved successfully! ✅'
            )
            
            return {
                'status': 'resolved',
                'message': 'Problem resolved successfully! ✅',
                'solved_with': context['current_case']
            }
        
        # Move to next case
        matched_cases = context['matched_cases']
        current_index = context['current_case_index']
        next_index = current_index + 1
        
        if next_index >= len(matched_cases):
            self.session_manager.add_message(
                session_id,
                'assistant',
                'All known solutions tried. Escalating to development team.'
            )
            
            return {
                'status': 'exhausted',
                'message': 'All known solutions tried. Escalating to development team.',
                'recommendation': 'Manual investigation required'
            }
        
        next_case = matched_cases[next_index]
        formatted_case = self._format_case_concise(next_case, next_index, len(matched_cases))
        
        # Update session
        self.session_manager.update_session(session_id, {
            'context': {
                'current_case_index': next_index,
                'current_case': formatted_case
            }
        })
        
        self.session_manager.add_message(
            session_id,
            'assistant',
            'Trying next possible cause...',
            {'case': formatted_case}
        )
        
        return {
            'status': 'next_suggestion',
            'message': 'Trying next possible cause...',
            'current_case_index': next_index,
            'current_case': formatted_case,
            'requires_sql_audit': bool(next_case.get('sql_query'))
        }
    
    def handle_followup_question(
        self,
        session_id: str,
        question: str
    ) -> Dict[str, Any]:
        """
        Handle follow-up questions within the session context
        
        Args:
            session_id: Session ID for conversation context
            question: User's follow-up question
        
        Returns:
            Contextual answer based on conversation history
        """
        session = self.session_manager.get_session(session_id)
        if not session:
            return {
                'error': 'Session not found or expired',
                'message': 'Please start a new diagnosis session.'
            }
        
        # Add user question to history
        self.session_manager.add_message(session_id, 'user', question)
        
        context = session['context']
        current_case = context.get('current_case')
        history = session.get('conversation_history', [])
        
        question_lower = question.lower()
        
        # Context-aware responses based on common follow-up patterns
        response = ""
        
        # Questions about the current solution
        if any(keyword in question_lower for keyword in ['how', 'why', 'what if', 'can you explain']):
            if current_case:
                if 'sql' in question_lower or 'query' in question_lower:
                    if current_case.get('sql_query'):
                        response = f"The SQL query helps verify the problem by checking: {current_case.get('expected_outcome', 'the system state')}. "
                        response += f"The query is:\n```sql\n{current_case['sql_query']}\n```"
                    else:
                        response = "This case doesn't require SQL verification. The solution can be applied directly."
                
                elif 'solution' in question_lower or 'fix' in question_lower:
                    response = f"The recommended solution is: {current_case.get('solution', 'N/A')}"
                    if current_case.get('scenario'):
                        response += f"\n\nScenario: {current_case['scenario']}"
                
                elif 'impact' in question_lower or 'severity' in question_lower:
                    response = f"This issue has {current_case.get('impact', 'unknown')} impact. "
                    if 'high' in current_case.get('impact', '').lower():
                        response += "It requires immediate attention."
                    
                else:
                    response = f"Based on the current case:\n\n"
                    response += f"**Problem:** {current_case.get('problem', 'N/A')}\n\n"
                    response += f"**Solution:** {current_case.get('solution', 'N/A')}\n\n"
                    response += "Is there something specific you'd like to know?"
            else:
                response = "No case is currently being analyzed. Please start a diagnosis first."
        
        # Questions about alternatives
        elif any(keyword in question_lower for keyword in ['other', 'alternative', 'different', 'else']):
            matched_cases = context.get('matched_cases', [])
            current_index = context.get('current_case_index', 0)
            
            if current_index + 1 < len(matched_cases):
                response = f"Yes, I have {len(matched_cases) - current_index - 1} more alternative solution(s). "
                response += "You can mark the current solution as 'Not Correct' to see the next one."
            else:
                response = "This is the last known solution for your problem. If it doesn't work, we may need to escalate to the development team."
        
        # Questions about next steps
        elif any(keyword in question_lower for keyword in ['next', 'then', 'after', 'step']):
            if current_case and current_case.get('sql_query'):
                response = "Next steps:\n1. Run the SQL audit to verify the problem\n2. Review the results\n3. Apply the solution if the audit confirms the issue\n4. Verify the problem is resolved"
            else:
                response = "Next steps:\n1. Apply the recommended solution\n2. Test to verify the problem is resolved\n3. Let me know if it worked or if you need to try another solution"
        
        # Questions about SQL results
        elif 'result' in question_lower and context.get('sql_results'):
            sql_results = context['sql_results']
            response = f"The SQL audit found {sql_results.get('row_count', 0)} record(s). "
            if sql_results.get('analysis'):
                response += f"\n\n**Analysis:** {sql_results['analysis']}"

        # Questions about last message
        elif any(keyword in question_lower for keyword in ['last message', 'what i asked', 'what did i ask', 'previous message']):
            last_user_message = None
            for msg in reversed(history):
                if msg.get('role') == 'user' and msg.get('message') != question:
                    last_user_message = msg.get('message')
                    break
            if last_user_message:
                response = f"Your previous message was: {last_user_message}"
            else:
                response = "I couldn't find a previous message in this session."
        
        # General help or unclear questions
        else:
            response = "I can help you with:\n"
            response += "- Explaining the current solution in detail\n"
            response += "- Providing alternative solutions\n"
            response += "- Clarifying SQL audit queries\n"
            response += "- Suggesting next steps\n\n"
            response += "What would you like to know more about?"
        
        # Add assistant response to history
        context_summary = self.session_manager.get_context_summary(session_id)
        final_response = self._rephrase_with_llm(question, response, context_summary)

        self.session_manager.add_message(
            session_id,
            'assistant',
            final_response
        )
        
        return {
            'session_id': session_id,
            'question': question,
            'answer': final_response,
            'context': context_summary
        }
    
    def get_session_history(self, session_id: str) -> Dict[str, Any]:
        """
        Get complete session history for review
        
        Args:
            session_id: Session ID
        
        Returns:
            Session data with conversation history
        """
        session = self.session_manager.get_session(session_id)
        if not session:
            return {'error': 'Session not found'}
        
        return {
            'session_id': session_id,
            'created_at': session['created_at'],
            'user_problem': session['user_problem'],
            'conversation_history': session['conversation_history'],
            'resolved': session['resolved'],
            'current_context': session['context']
        }
    
    def update_sql_results(self, session_id: str, sql_results: Dict[str, Any]):
        """
        Store SQL results in session for follow-up context
        
        Args:
            session_id: Session ID
            sql_results: Results from SQL audit
        """
        session = self.session_manager.get_session(session_id)
        if session:
            self.session_manager.update_session(session_id, {
                'context': {'sql_results': sql_results}
            })
            
            self.session_manager.add_message(
                session_id,
                'system',
                f"SQL audit completed: {sql_results.get('row_count', 0)} rows found",
                {'sql_results': sql_results}
            )
    
    def analyze_sql_results(
        self,
        case: Dict[str, Any],
        sql_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Analyze SQL audit results against expected outcome
        
        Returns:
            Analysis with recommendations
        """
        if not sql_results['success']:
            return {
                'analysis': 'SQL audit failed to execute',
                'recommendation': 'Check SQL query or database connectivity'
            }
        
        row_count = sql_results['row_count']
        expected_outcome = case.get('outcome', '').lower()
        
        # Parse expected outcome for validation
        analysis = {
            'rows_found': row_count,
            'expected': expected_outcome,
            'data_preview': sql_results['data'][:3] if sql_results['data'] else []
        }
        
        # Simple heuristics
        if row_count == 0:
            analysis['interpretation'] = 'No data found - issue may not exist or already resolved'
        elif 'empty' in expected_outcome or 'zero' in expected_outcome or 'no' in expected_outcome:
            if row_count > 0:
                analysis['interpretation'] = 'Problem confirmed - data exists when it should be empty'
                analysis['status'] = 'problem_confirmed'
        else:
            analysis['interpretation'] = f'{row_count} record(s) found'
            analysis['status'] = 'data_found'
        
        return analysis
    
    def get_session_summary(self, session_id: str) -> str:
        """Generate concise session summary"""
        session = self.session_manager.get_session(session_id)
        if not session:
            return "Session not found"
        
        context = session['context']
        current_case = context.get('current_case')
        
        if not current_case:
            return f"**Session:** {session_id}\n**Problem:** {session['user_problem']}\n**Status:** No case analyzed yet"
        
        summary = f"""
**Session:** {session_id}
**Original Problem:** {session['user_problem']}

**Current Case {current_case['case_number']}** | {current_case['type']} | Impact: {current_case['impact']}

**Problem:** {current_case['problem']}

**Solution:** {current_case['solution']}
"""
        
        if current_case.get('sql_query'):
            summary += f"""
**Audit SQL:**
```sql
{current_case['sql_query']}
```
**Expected:** {current_case.get('expected_outcome', 'N/A')}
"""
        
        summary += f"\n**Conversation Messages:** {len(session['conversation_history'])}"
        summary += f"\n**Resolved:** {'Yes ✅' if session['resolved'] else 'No'}"
        
        return summary.strip()

