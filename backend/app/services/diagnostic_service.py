"""
Diagnostic Service - Automated troubleshooting and issue resolution
Helps users diagnose and solve NEO system issues
"""

import logging
import json
import csv
import uuid
from typing import List, Dict, Any, Optional
from pathlib import Path

from .llm_service import LLMService
from .rlhf_service import RLHFService
from .diagnostic_support_service import DiagnosticSupportService
from .sql_assistant_integrated import SQLAssistantService
from ..models.schemas import ChatRequest, ChatResponse, ChatbotType, DiagnosticIssue, SystemHealthStatus
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class DiagnosticService:
    """
    Service for system diagnostics and troubleshooting
    Loads issue knowledge base and provides guided support
    """
    
    def __init__(self):
        """Initialize diagnostic service"""
        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()
        self.support_service = DiagnosticSupportService()  # Use new CSV-based service
        self.sql_service = SQLAssistantService()  # SQL query execution service
        self.session_manager = get_session_manager()
        self.issues_db = self._load_issues_database()
        
        self.system_prompt = """You are a troubleshooting expert for the NEO Warehouse Management System.

When helping users with issues:
1. Listen to their problem description carefully
2. Match symptoms to known issues
3. Guide them through diagnostic steps one at a time
4. Provide clear, step-by-step solutions
5. Explain what each step does
6. Offer prevention tips

Be patient, clear, and supportive. Break down complex solutions into simple steps."""

        logger.info(f"✅ Diagnostic Service initialized with {len(self.issues_db)} known issues")
    
    def _load_issues_database(self) -> List[Dict[str, Any]]:
        """Load support issues from JSON or CSV file"""
        try:
            base_path = Path(__file__).parent.parent / "data" / "support"
            
            # Try JSON first
            json_path = base_path / "issues.json"
            if json_path.exists():
                with open(json_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    issues = data.get("issues", [])
                    logger.info(f"📂 Loaded {len(issues)} issues from {json_path}")
                    return issues
            
            # Try CSV
            csv_path = base_path / "issues.csv"
            if csv_path.exists():
                issues = []
                with open(csv_path, 'r', encoding='utf-8') as f:
                    reader = csv.DictReader(f)
                    for row in reader:
                        # Parse pipe-separated fields
                        issue = {
                            "issue_id": row.get("issue_id", ""),
                            "issue_name": row.get("issue_name", ""),
                            "category": row.get("category", ""),
                            "severity": row.get("severity", "medium"),
                            "symptoms": row.get("symptoms", "").split("|"),
                            "root_causes": row.get("root_causes", "").split("|"),
                            "diagnostic_steps": row.get("diagnostic_steps", "").split("|"),
                            "solution_1_title": row.get("solution_1_title", ""),
                            "solution_1_steps": row.get("solution_1_steps", ""),
                            "solution_1_type": row.get("solution_1_type", ""),
                            "solution_2_title": row.get("solution_2_title", ""),
                            "solution_2_steps": row.get("solution_2_steps", ""),
                            "solution_2_type": row.get("solution_2_type", ""),
                            "prevention": row.get("prevention", "").split("|")
                        }
                        issues.append(issue)
                logger.info(f"📂 Loaded {len(issues)} issues from {csv_path}")
                return issues
            
            logger.warning("⚠️ No issues.json or issues.csv found in data/support/")
            return []
            
        except Exception as e:
            logger.error(f"❌ Error loading issues database: {e}")
            return []
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process diagnostic query with intelligent AI-powered analysis
        Uses unified session management for conversation memory
        
        Args:
            chat_request: User's chat request
            
        Returns:
            Chat response with intelligent diagnostic guidance
        """
        try:
            logger.info(f"🔍 Processing intelligent diagnostic query: {chat_request.message[:50]}...")
            
            # Step 1: Get session for context (managed by endpoint)
            session_id = chat_request.session_id
            if session_id:
                conversation_history = self.session_manager.get_conversation_history(session_id)
            else:
                conversation_history = []
            
            # Step 3: Use LLM service for diagnosis with context
            response = self._diagnose_with_llm(chat_request, conversation_history)
            
            # Note: Session management is handled by the endpoint
            
            # Update session ID in response
            response.session_id = session_id
            
            # Record for RLHF learning
            try:
                self.rlhf_service.record_feedback(
                    chatbot_type="diagnostic_support",
                    query=chat_request.message,
                    response=response.response,
                    feedback_type="neutral",
                    rating=None,
                    comment="Intelligent diagnostic analysis",
                    metadata={
                        "confidence": response.confidence_score,
                        "analysis_type": "intelligent",
                        "session_id": session_id,
                        "conversation_messages": len(conversation_history)
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to record RLHF feedback: {e}")
            
            return response
            
        except Exception as e:
            logger.error(f"❌ Error processing diagnostic query: {e}", exc_info=True)
            return ChatResponse(
                response="I apologize, but I encountered an error while analyzing your issue. Please describe your issue in more detail, or try asking: 'Check bot status and tasks' or 'Diagnose station communication issues'.",
                chatbot_type=ChatbotType.DIAGNOSTIC,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                confidence_score=0.0
            )
    
    def _diagnose_with_llm(self, chat_request: ChatRequest, conversation_history: List[Dict]) -> ChatResponse:
        """Use LLM service to diagnose the problem with context"""
        try:
            # Build context from conversation history
            context = "\n".join([
                f"{msg['role']}: {msg['content']}" 
                for msg in conversation_history[-5:]  # Last 5 messages
            ])
            
            # Create enhanced prompt with diagnostic context
            prompt = f"""{self.system_prompt}

Previous conversation:
{context}

Current issue: {chat_request.message}

Analyze the issue and provide:
1. Problem diagnosis
2. Likely causes
3. Step-by-step solution
4. Prevention recommendations"""
            
            # Get LLM response
            llm_response = self.llm_service.generate_response(prompt)
            
            return ChatResponse(
                response=llm_response,
                chatbot_type=ChatbotType.DIAGNOSTIC,
                session_id=chat_request.session_id,
                confidence_score=0.8
            )
        except Exception as e:
            logger.error(f"Error in LLM diagnosis: {e}")
            return ChatResponse(
                response="I can help you troubleshoot this issue. Please describe the problem in more detail.",
                chatbot_type=ChatbotType.DIAGNOSTIC,
                session_id=chat_request.session_id,
                confidence_score=0.5
            )
    
    def _handle_no_issues_db(self, chat_request: ChatRequest) -> ChatResponse:
        """Handle case when no issues database is available"""
        return ChatResponse(
            response="""⚠️ No support issues are currently loaded in the diagnostic database.

However, I can still help you with general troubleshooting advice. Please describe your issue in detail, and I'll do my best to assist you.

Common troubleshooting areas:
- Bot operational issues
- Station communication problems
- Task assignment errors
- System configuration issues

What problem are you experiencing?""",
            chatbot_type=ChatbotType.DIAGNOSTIC,
            session_id=chat_request.session_id or str(uuid.uuid4()),
            confidence_score=0.0,
            suggested_actions=["Describe your issue", "Check system status", "View documentation"]
        )
    
    def _handle_no_matches(self, chat_request: ChatRequest) -> ChatResponse:
        """Handle case when query doesn't match any known issues"""
        return ChatResponse(
            response="""🔍 I couldn't find an exact match for your issue in our support database.

However, you can try:
1. **Rephrasing your question** - Use keywords like "bot stuck", "station error", "communication failed"
2. **Asking about specific symptoms** - What exactly is happening?
3. **Browsing all issues** - Use the Diagnostic Support dashboard

Common issues I can help with:
- Bot not responding or stuck
- Station pick/place failures
- Communication errors
- Task assignment problems

Could you describe your issue in more detail?""",
            chatbot_type=ChatbotType.DIAGNOSTIC,
            session_id=chat_request.session_id or str(uuid.uuid4()),
            confidence_score=0.3,
            suggested_actions=["Rephrase question", "View all issues", "Contact support"]
        )
    
    def _format_diagnostic_response(self, matches: List[Dict], query: str) -> str:
        """Format diagnostic response from matches with SQL execution"""
        response_parts = []
        
        response_parts.append(f"🔧 **Diagnostic Analysis Complete**\n")
        response_parts.append(f"Found {len(matches)} potential solution(s). Running diagnostics...\n")
        
        for i, match in enumerate(matches, 1):
            response_parts.append(f"\n{'=' * 60}")
            response_parts.append(f"\n### Issue {i}: {match['problem']}")
            response_parts.append(f"\n**Type:** {match['type'].replace('_', ' ').title()}")
            response_parts.append(f"\n**Severity:** {match['severity']}")
            response_parts.append(f"\n**Relevance:** {match['relevance_score']}%")
            
            # Execute SQL query if available
            sql_query = match.get('sql_query', '').strip()
            if sql_query and sql_query.lower() not in ['nan', 'none', 'n/a', '']:
                response_parts.append(f"\n\n**🔍 Running Diagnostic Query...**")
                
                try:
                    # Check if it's a SELECT query (safe to execute)
                    is_select = sql_query.strip().upper().startswith('SELECT')
                    
                    if is_select:
                        # Execute SELECT queries
                        results, error = self.sql_service._execute_query_safe(sql_query)
                        
                        if error:
                            response_parts.append(f"\n⚠️ **Query failed:** {error}")
                            response_parts.append(f"\n\n**Query attempted:**\n```sql\n{sql_query}\n```")
                        else:
                            row_count = len(results)
                            
                            response_parts.append(f"\n✅ **Query executed successfully**")
                            response_parts.append(f"\n📊 **Found {row_count} record(s)**")
                            
                            if row_count > 0:
                                # Show first few results
                                response_parts.append(f"\n\n**Current Status:**")
                                
                                # Analyze results based on query type
                                analysis = self._analyze_sql_results(sql_query, results, match)
                                response_parts.append(f"\n{analysis}")
                                
                                # Show sample data (first 3 rows)
                                if row_count <= 3:
                                    response_parts.append(f"\n\n**Data:**")
                                    for idx, row in enumerate(results, 1):
                                        # Format row nicely
                                        row_str = ", ".join([f"{k}={v}" for k, v in list(row.items())[:5]])
                                        response_parts.append(f"\n  {idx}. {row_str}")
                                else:
                                    response_parts.append(f"\n\n**Sample Data (first 3):**")
                                    for idx, row in enumerate(results[:3], 1):
                                        row_str = ", ".join([f"{k}={v}" for k, v in list(row.items())[:5]])
                                        response_parts.append(f"\n  {idx}. {row_str}")
                                    response_parts.append(f"\n  ... and {row_count - 3} more")
                            else:
                                response_parts.append(f"\n\n✅ **No issues found** - This suggests the problem might be resolved or in a different area.")
                    
                    else:
                        # For INSERT/UPDATE/DELETE queries, just show the query as reference
                        response_parts.append(f"\n📝 **Suggested Fix Query** (requires manual execution):")
                        response_parts.append(f"\n```sql\n{sql_query}\n```")
                        response_parts.append(f"\n⚠️ **Note:** This query modifies data and must be executed manually by an administrator.")
                
                except Exception as e:
                    logger.error(f"Error executing diagnostic SQL: {e}")
                    response_parts.append(f"\n⚠️ **Could not execute query:** {str(e)}")
                    response_parts.append(f"\n\n**Query:**\n```sql\n{sql_query}\n```")
            
            # Add solution steps
            response_parts.append(f"\n\n**📋 Solution Steps:**")
            solution_lines = match['solution'].split('.')
            for step in solution_lines:
                step = step.strip()
                if step and len(step) > 3:
                    response_parts.append(f"\n• {step}")
            
            # Add outcome
            if match.get('outcome') and match['outcome'].strip() and match['outcome'].lower() not in ['nan', 'none']:
                response_parts.append(f"\n\n**Expected Outcome:** {match['outcome']}")
            
            # Developer escalation flag
            if match.get('reported_to_dev', '').upper() == 'Y':
                response_parts.append(f"\n\n⚠️ **Note:** This issue may require developer attention if not resolved.")
        
        # Add general tips
        response_parts.append(f"\n\n{'=' * 60}")
        response_parts.append(f"\n### � **Next Steps:**")
        response_parts.append(f"\n1. Review the diagnostic results above")
        response_parts.append(f"\n2. Follow the solution steps for the most relevant issue")
        response_parts.append(f"\n3. Check bot status and task assignments")
        response_parts.append(f"\n4. Try RECOVERY mode before NON-RECOVERY")
        response_parts.append(f"\n5. Contact support if issue persists")
        
        return "".join(response_parts)
    
    def _find_matching_issues(self, query: str) -> List[Dict[str, Any]]:
        """Find issues matching the user's query"""
        query_lower = query.lower()
        matches = []
        
        for issue in self.issues_db:
            score = 0
            
            # Check issue name
            if issue.get("issue_name", "").lower() in query_lower:
                score += 10
            
            # Check category
            if issue.get("category", "").lower() in query_lower:
                score += 5
            
            # Check symptoms
            symptoms = issue.get("symptoms", [])
            if isinstance(symptoms, str):
                symptoms = symptoms.split("|")
            
            for symptom in symptoms:
                if symptom.strip().lower() in query_lower:
                    score += 3
            
            # Check keywords
            keywords = ["error", "fail", "not working", "issue", "problem", "broken"]
            for keyword in keywords:
                if keyword in query_lower and keyword in issue.get("issue_name", "").lower():
                    score += 2
            
            if score > 0:
                matches.append({"issue": issue, "score": score})
        
        # Sort by score
        matches.sort(key=lambda x: x["score"], reverse=True)
        return [m["issue"] for m in matches[:3]]  # Return top 3 matches
    
    def _generate_diagnostic_response(self, issue: Dict[str, Any], user_query: str) -> str:
        """Generate diagnostic response for a specific issue"""
        response_parts = []
        
        # Issue identification
        response_parts.append(f"🔍 **Issue Identified: {issue.get('issue_name', 'Unknown Issue')}**")
        response_parts.append(f"Category: {issue.get('category', 'Unknown')} | Severity: {issue.get('severity', 'Unknown').upper()}")
        response_parts.append("")
        
        # Symptoms confirmation
        symptoms = issue.get("symptoms", [])
        if isinstance(symptoms, str):
            symptoms = symptoms.split("|")
        
        if symptoms:
            response_parts.append("**Symptoms you might be experiencing:**")
            for symptom in symptoms[:3]:  # Show top 3
                response_parts.append(f"• {symptom.strip()}")
            response_parts.append("")
        
        # Diagnostic steps
        diagnostic_steps = issue.get("diagnostic_steps", [])
        if isinstance(diagnostic_steps, str):
            diagnostic_steps = diagnostic_steps.split("|")
        
        if diagnostic_steps:
            response_parts.append("**Let's diagnose this step by step:**")
            for i, step in enumerate(diagnostic_steps[:3], 1):  # Show first 3 steps
                response_parts.append(f"{i}. {step.strip()}")
            response_parts.append("")
        
        # Solution 1
        sol1_title = issue.get("solution_1_title", "")
        sol1_steps = issue.get("solution_1_steps", "")
        sol1_type = issue.get("solution_1_type", "")
        
        if sol1_title and sol1_steps:
            response_parts.append(f"**Solution 1: {sol1_title}** ({sol1_type})")
            response_parts.append(f"Steps: {sol1_steps}")
            response_parts.append("")
        
        # Solution 2 (if available)
        sol2_title = issue.get("solution_2_title", "")
        sol2_steps = issue.get("solution_2_steps", "")
        
        if sol2_title and sol2_steps:
            response_parts.append(f"**Alternative Solution: {sol2_title}**")
            response_parts.append(f"Steps: {sol2_steps}")
            response_parts.append("")
        
        # Prevention tips
        prevention = issue.get("prevention", [])
        if isinstance(prevention, str):
            prevention = prevention.split("|")
        
        if prevention:
            response_parts.append("**Prevention Tips:**")
            for tip in prevention:
                if tip.strip():
                    response_parts.append(f"• {tip.strip()}")
        
        response_parts.append("\n📝 **Need more help?** Let me know which step you need clarification on, or if the issue persists.")
        
        return "\n".join(response_parts)
    
    def _generate_general_diagnostic_response(self, chat_request: ChatRequest) -> str:
        """Generate general diagnostic response using LLM"""
        messages = [{
            "role": "user",
            "content": f"""A user is reporting this issue with the NEO system:

"{chat_request.message}"

Provide troubleshooting guidance:
1. What might be causing this
2. Step-by-step diagnostic steps
3. Possible solutions
4. Prevention tips"""
        }]
        
        return self.llm_service.generate_response(
            messages=messages,
            system_prompt=self.system_prompt,
            max_tokens=800,
            temperature=0.7
        )
    
    def _generate_diagnostic_actions(self, matching_issues: List[Dict[str, Any]]) -> List[str]:
        """Generate suggested actions based on matching issues"""
        if not matching_issues:
            return [
                "Describe your issue in more detail",
                "Check system logs",
                "Contact support"
            ]
        
        actions = []
        for issue in matching_issues[:2]:
            category = issue.get("category", "")
            if category == "database":
                actions.append("Check database connection")
            elif category == "scheduler":
                actions.append("Verify scheduler status")
            elif category == "mining":
                actions.append("Review mining parameters")
        
        actions.append("View detailed diagnostics")
        return actions[:3]
    
    def _analyze_sql_results(self, query: str, results: List[Dict], issue: Dict) -> str:
        """Analyze SQL query results and provide intelligent insights"""
        try:
            query_lower = query.lower()
            row_count = len(results)
            analysis_parts = []
            
            # Analyze based on query patterns
            if 'task_master' in query_lower:
                if row_count > 0:
                    analysis_parts.append(f"⚠️ **Found {row_count} pending/stuck task(s)**")
                    # Check for specific statuses
                    if results and isinstance(results[0], dict):
                        statuses = [r.get('STATUS', r.get('status', 'unknown')) for r in results[:5]]
                        analysis_parts.append(f"   Status(es): {', '.join(str(s) for s in set(statuses))}")
                else:
                    analysis_parts.append(f"✅ **No stuck tasks found** - Task assignment looks normal")
            
            elif 'order_bin_mapping' in query_lower or 'pick_wave' in query_lower or 'put_wave' in query_lower:
                if row_count > 0:
                    analysis_parts.append(f"⚠️ **Found {row_count} pending bin(s) in wave**")
                    if results and isinstance(results[0], dict):
                        # Check for bin IDs
                        bin_ids = [r.get('bin_id', r.get('BIN_ID', 'unknown')) for r in results[:5]]
                        analysis_parts.append(f"   Affected bins: {', '.join(str(b) for b in bin_ids[:3])}{'...' if len(bin_ids) > 3 else ''}")
                else:
                    analysis_parts.append(f"✅ **No pending bins** - Wave processing looks normal")
            
            elif 'hw_conveyer_master' in query_lower or 'conveyer' in query_lower:
                if row_count > 0:
                    analysis_parts.append(f"⚠️ **Found {row_count} conveyer request(s)**")
                    if results and isinstance(results[0], dict):
                        # Check request types
                        req_types = [r.get('PICK_request', r.get('pick_request', 'unknown')) for r in results[:5]]
                        analysis_parts.append(f"   Request type(s): {', '.join(str(t) for t in set(req_types))}")
                else:
                    analysis_parts.append(f"✅ **No pending conveyer requests** - Station communication normal")
            
            elif 'bot_master' in query_lower or 'bot' in query_lower:
                if row_count > 0:
                    analysis_parts.append(f"📊 **Found {row_count} bot(s) matching criteria**")
                    if results and isinstance(results[0], dict):
                        # Check bot statuses
                        if 'STATUS' in results[0] or 'status' in results[0]:
                            statuses = [r.get('STATUS', r.get('status', 'unknown')) for r in results[:5]]
                            analysis_parts.append(f"   Status(es): {', '.join(str(s) for s in set(statuses))}")
                else:
                    analysis_parts.append(f"✅ **No bots found with this issue**")
            
            elif 'alarm' in query_lower:
                if row_count > 0:
                    analysis_parts.append(f"🚨 **Found {row_count} active alarm(s)**")
                    if results and isinstance(results[0], dict):
                        alarm_types = [r.get('alarm_type', r.get('ALARM_TYPE', 'unknown')) for r in results[:3]]
                        analysis_parts.append(f"   Alarm(s): {', '.join(str(a) for a in alarm_types)}")
                else:
                    analysis_parts.append(f"✅ **No active alarms**")
            
            else:
                # Generic analysis
                if row_count > 0:
                    analysis_parts.append(f"📊 **Found {row_count} record(s)** - Review the data below for details")
                else:
                    analysis_parts.append(f"✅ **No records found** - This area looks normal")
            
            # Add recommendation based on severity
            if row_count > 0 and issue.get('severity', '').lower() == 'high':
                analysis_parts.append(f"\n🔴 **Action Required:** This is a HIGH severity issue - immediate attention needed")
            elif row_count > 5:
                analysis_parts.append(f"\n⚠️ **Multiple issues detected** - Consider bulk resolution or developer escalation")
            
            return "\n".join(analysis_parts) if analysis_parts else "No specific insights available"
            
        except Exception as e:
            logger.error(f"Error analyzing SQL results: {e}")
            return f"Analysis unavailable (found {len(results)} records)"
    
    def check_system_health(self) -> SystemHealthStatus:
        """
        Check overall system health
        
        Returns:
            System health status with component statuses and issues
        """
        # This is a placeholder - would connect to actual system monitoring
        components = {
            "database": "healthy",
            "api": "healthy",
            "scheduler": "healthy",
            "mining_engine": "healthy"
        }
        
        return SystemHealthStatus(
            overall_status="healthy",
            components=components,
            issues=[]
        )
    
    def get_issue_by_id(self, issue_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific issue by ID"""
        for issue in self.issues_db:
            if issue.get("issue_id") == issue_id:
                return issue
        return None
    
    def get_issues_by_category(self, category: str) -> List[Dict[str, Any]]:
        """Get all issues in a specific category"""
        return [issue for issue in self.issues_db if issue.get("category") == category]
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get diagnostic service statistics"""
        categories = {}
        severities = {}
        
        for issue in self.issues_db:
            cat = issue.get("category", "unknown")
            sev = issue.get("severity", "unknown")
            categories[cat] = categories.get(cat, 0) + 1
            severities[sev] = severities.get(sev, 0) + 1
        
        return {
            "total_issues": len(self.issues_db),
            "categories": categories,
            "severities": severities,
            "llm_provider": self.llm_service.get_provider_info()
        }

