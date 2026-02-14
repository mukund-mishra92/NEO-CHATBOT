"""
Intelligent Diagnostic Service - AI-Powered Root Cause Analysis
Combines RAG, SQL analysis, and LLM reasoning for smart troubleshooting
"""

import logging
import uuid
from typing import List, Dict, Any, Optional
from pathlib import Path

from ..llm_service import LLMService
from ..vector_store_service import VectorStoreService
from ..obselete_files.sql_assistant_integrated import SQLAssistantService
from ..diagnostic.diagnostic_support_service import DiagnosticSupportService
from ...models.schemas import ChatRequest, ChatResponse, ChatbotType
from ...utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class IntelligentDiagnosticService:
    """
    AI-powered diagnostic service that:
    1. Understands user's problem description
    2. Generates diagnostic SQL queries
    3. Executes queries and analyzes results
    4. Searches documentation for context
    5. Provides intelligent root cause analysis and solutions
    """
    
    def __init__(self):
        """Initialize intelligent diagnostic service"""
        self.llm_service = LLMService()
        self.vector_store = VectorStoreService()
        self.sql_service = SQLAssistantService()
        self.support_service = DiagnosticSupportService()
        self.session_manager = get_session_manager()
        
        # Self-improving loop configuration
        self.max_refinement_iterations = 3  # Maximum diagnosis refinement loops
        self.judge_confidence_threshold = 0.85  # Stop if judge confidence exceeds this
        
        # Load actual database schema for validation
        self.available_tables = self._get_available_tables()
        self.bot_related_tables = self._get_bot_related_tables()
        logger.info(f"✅ Loaded {len(self.available_tables)} tables, {len(self.bot_related_tables)} bot-related")
        
        self.diagnostic_prompt = """You are an expert NEO Warehouse Management System diagnostic engineer.

Your job is to:
1. Understand the user's problem description
2. Generate appropriate SQL diagnostic queries to check the system state
3. Analyze the query results to find root causes
4. Provide clear, actionable solutions

You have access to:
- The NEO database (can run SELECT queries)
- Historical support logs
- Technical documentation
- System architecture knowledge

Be methodical and thorough. Always verify your hypothesis with data before concluding."""

        logger.info("✅ Intelligent Diagnostic Service initialized")
    
    def _get_available_tables(self) -> List[str]:
        """Get list of all available tables from database schema"""
        try:
            schema_info = self.sql_service.get_schema_info()
            all_tables = schema_info.get('tables', [])
            logger.info(f"📋 Retrieved {len(all_tables)} tables from schema")
            return all_tables
        except Exception as e:
            logger.error(f"❌ Error getting schema tables: {e}")
            return []
    
    def _get_bot_related_tables(self) -> List[str]:
        """Filter tables that are related to bots, tasks, stations, etc."""
        if not self.available_tables:
            return []
        
        # Keywords to identify relevant tables
        keywords = ['bot', 'task', 'station', 'wave', 'order', 'bin', 'pick', 'put', 'inventory']
        
        bot_tables = []
        for table in self.available_tables:
            table_lower = table.lower()
            if any(keyword in table_lower for keyword in keywords):
                bot_tables.append(table)
        
        logger.info(f"🤖 Found {len(bot_tables)} bot-related tables: {bot_tables[:10]}")
        return bot_tables
    
    def _validate_table_exists(self, table_name: str) -> bool:
        """Check if a table actually exists in the database"""
        return table_name in self.available_tables
    
    def _filter_valid_tables(self, table_names: List[str]) -> List[str]:
        """Filter list of table names to only include existing tables"""
        valid_tables = [t for t in table_names if self._validate_table_exists(t)]
        invalid_tables = [t for t in table_names if not self._validate_table_exists(t)]
        
        if invalid_tables:
            logger.warning(f"⚠️ Filtered out non-existent tables: {invalid_tables}")
        
        return valid_tables
    
    def _get_table_columns(self, table_name: str) -> List[str]:
        """Get list of all column names for a specific table"""
        try:
            if not self._validate_table_exists(table_name):
                logger.warning(f"⚠️ Table {table_name} does not exist")
                return []
            
            # Get schema from SQL service
            schema_parser = self.sql_service.schema_parser
            if hasattr(schema_parser, 'tables') and table_name in schema_parser.tables:
                columns = [col['field'] for col in schema_parser.tables[table_name]]
                logger.info(f"📋 Retrieved {len(columns)} columns for table {table_name}")
                return columns
            else:
                logger.warning(f"⚠️ No schema found for table {table_name}")
                return []
        except Exception as e:
            logger.error(f"❌ Error getting columns for table {table_name}: {e}")
            return []
    
    def _validate_column_exists(self, table_name: str, column_name: str) -> bool:
        """Check if a column exists in the specified table"""
        columns = self._get_table_columns(table_name)
        return column_name.upper() in [col.upper() for col in columns]
    
    def _validate_query_columns(self, query: str, table_name: str) -> tuple[bool, List[str]]:
        """
        Validate that all columns in a query exist in the table
        
        Returns:
            Tuple of (all_valid: bool, invalid_columns: List[str])
        """
        try:
            # Extract column names from SELECT clause
            import re
            select_match = re.search(r'SELECT\s+(.*?)\s+FROM', query, re.IGNORECASE | re.DOTALL)
            if not select_match:
                return True, []  # Can't validate, assume OK
            
            select_clause = select_match.group(1)
            
            # Handle SELECT *, COUNT(*), etc.
            if '*' in select_clause and 'COUNT' not in select_clause.upper():
                return True, []
            
            # Extract column names (handle aliases with AS)
            columns = []
            for part in select_clause.split(','):
                part = part.strip()
                # Remove AS aliases
                if ' AS ' in part.upper():
                    part = part.split(' AS ')[0].strip()
                # Remove aggregate functions
                part = re.sub(r'\w+\s*\((.*?)\)', r'\1', part)
                # Remove table prefix (e.g., bm.BOT_ID -> BOT_ID)
                if '.' in part:
                    part = part.split('.')[-1]
                # Clean up
                part = part.strip('()')
                if part and part != '*':
                    columns.append(part)
            
            # Validate each column
            table_columns = self._get_table_columns(table_name)
            invalid_columns = []
            
            for col in columns:
                if not self._validate_column_exists(table_name, col):
                    invalid_columns.append(col)
            
            if invalid_columns:
                logger.warning(f"⚠️ Invalid columns in query for {table_name}: {invalid_columns}")
                logger.info(f"✓ Available columns: {table_columns}")
                return False, invalid_columns
            
            return True, []
            
        except Exception as e:
            logger.error(f"❌ Error validating query columns: {e}")
            return True, []  # Don't block on validation errors
    
    def _get_distinct_column_values(self, table_name: str, column_name: str, limit: int = 50) -> List[str]:
        """Query database to get actual distinct values for a column"""
        try:
            if not self._validate_table_exists(table_name):
                return []
            if not self._validate_column_exists(table_name, column_name):
                return []
            
            # Use SQL service to query for distinct values
            query = f"SELECT DISTINCT {column_name} FROM {table_name} WHERE {column_name} IS NOT NULL LIMIT {limit};"
            results, error = self.sql_service._execute_query_safe(query)
            
            if error:
                logger.error(f"Error querying distinct values for {table_name}.{column_name}: {error}")
                return []
            
            values = [str(row.get(column_name)) for row in results if row.get(column_name) is not None]
            logger.info(f"📊 Found {len(values)} distinct values for {table_name}.{column_name}")
            return values
            
        except Exception as e:
            logger.error(f"Error getting distinct values: {e}")
            return []
    
    def _extract_where_conditions(self, sql_query: str) -> List[tuple]:
        """Extract column=value conditions from WHERE clause"""
        try:
            import re
            where_match = re.search(r'WHERE\s+(.+?)(?:GROUP BY|ORDER BY|LIMIT|HAVING|;|$)', sql_query, re.IGNORECASE | re.DOTALL)
            if not where_match:
                return []
            
            where_clause = where_match.group(1)
            pattern = r"([\w.]+)\s*=\s*['\"]([ ^'\"]+)['\"]"
            matches = re.findall(pattern, where_clause, re.IGNORECASE)
            
            conditions = []
            for col_ref, value in matches:
                col_name = col_ref.split('.')[-1] if '.' in col_ref else col_ref
                conditions.append((col_name.upper(), value))
            
            return conditions
        except Exception as e:
            logger.error(f"Error extracting WHERE conditions: {e}")
            return []
    
    def _validate_query_value_filters(self, query: str, table_name: str) -> tuple[bool, List[dict]]:
        """Validate that filter values in WHERE clause exist in the database"""
        try:
            conditions = self._extract_where_conditions(query)
            if not conditions:
                return True, []
            
            invalid_values = []
            for column_name, filter_value in conditions:
                if self._validate_column_exists(table_name, column_name):
                    actual_values = self._get_distinct_column_values(table_name, column_name)
                    if actual_values:
                        actual_values_upper = [v.upper() for v in actual_values]
                        if filter_value.upper() not in actual_values_upper:
                            invalid_values.append({
                                'table': table_name,
                                'column': column_name,
                                'filter_value': filter_value,
                                'actual_values': actual_values[:15]
                            })
            
            if invalid_values:
                logger.warning(f"⚠️ Query uses filter values that don't exist in database")
                for issue in invalid_values:
                    logger.warning(f"  ❌ {issue['table']}.{issue['column']} = '{issue['filter_value']}' (not found)")
                    logger.warning(f"     ✓ Actual values: {issue['actual_values']}")
                return False, invalid_values
            
            return True, []
            
        except Exception as e:
            logger.error(f"Error validating query values: {e}")
            return True, []
    
    def _judge_diagnosis_quality(
        self,
        problem: str,
        solution: Dict[str, Any],
        diagnostic_data: List[Dict],
        historical_matches: List[Dict],
        iteration: int
    ) -> Dict[str, Any]:
        """
        LLM acts as a judge to evaluate diagnosis quality and suggest improvements
        
        Args:
            problem: User's problem description
            solution: Current diagnosis solution
            diagnostic_data: Results from diagnostic queries
            historical_matches: Historical similar issues
            iteration: Current refinement iteration
            
        Returns:
            Dict with judgment including quality assessment and improvement suggestions
        """
        try:
            # Prepare diagnostic summary for judge
            diagnostic_summary = self._prepare_diagnostic_summary_for_judge(diagnostic_data)
            
            judge_prompt = f"""You are an expert diagnostic quality evaluator for the NEO Warehouse Management System.

**User's Problem:** {problem}

**Current Diagnosis Response:**
{solution['response'][:800]}...

**Diagnostic Data Collected:**
{diagnostic_summary}

**Historical Similar Issues:** {len(historical_matches)} found

**Current Iteration:** {iteration}/{self.max_refinement_iterations}

**AVAILABLE DATABASE TABLES:**
{', '.join(self.available_tables[:50])}... (and {len(self.available_tables) - 50} more)

**BOT-RELATED TABLES:**
{', '.join(self.bot_related_tables)}

**CRITICAL: Verify all mentioned tables actually exist in the database above!**

**Evaluate the diagnosis quality:**

0. **Table Validity**: Are all mentioned table names in the available tables list? (CRITICAL CHECK)
0.5. **Column Validity**: Are all mentioned column names valid for their respective tables? (CRITICAL CHECK)
1. **Accuracy**: Does the diagnosis correctly identify the root cause based on data?
2. **Data Support**: Is the conclusion backed by actual diagnostic query results?
3. **Solution Clarity**: Are the steps clear, specific, and actionable?
4. **Completeness**: Were the right diagnostic queries run? Are we missing critical checks?
5. **Relevance**: Does the solution address the user's actual problem?

**Respond in JSON format:**
{{
    "is_satisfactory": true/false,
    "confidence": 0.0-1.0,
    "issues": ["issue 1", "issue 2", ...],
    "suggestions": ["suggestion 1", "suggestion 2", ...],
    "missing_diagnostics": ["additional query 1", "additional query 2", ...] or null,
    "improved_approach": "description of better approach or null"
}}

**Rules:**
- **If response mentions non-existent tables, set is_satisfactory=false with confidence=0.3**
- If confidence >= 0.85 AND diagnosis is data-backed, set is_satisfactory=true
- If diagnostic queries failed or returned no data, suggest alternative queries
- If solution is generic/vague, suggest specific improvements
- **missing_diagnostics must use ONLY tables from the available tables list above**
"""

            response = self.llm_service.generate_response(
                messages=[{"role": "user", "content": judge_prompt}],
                system_prompt="You are an expert diagnostic quality judge. Be critical but constructive. Return valid JSON only.",
                max_tokens=800,
                temperature=0.2
            )
            
            # Parse JSON response
            import json
            json_text = response.strip()
            if "```json" in json_text:
                json_text = json_text.split("```json")[1].split("```")[0].strip()
            elif "```" in json_text:
                json_text = json_text.split("```")[1].split("```")[0].strip()
            
            judgment = json.loads(json_text)
            
            logger.info(f"🧑‍⚖️ Diagnosis Judge (iteration {iteration}): satisfactory={judgment.get('is_satisfactory')}, confidence={judgment.get('confidence'):.2f}")
            
            return judgment
            
        except Exception as e:
            logger.error(f"❌ Error in diagnosis judgment: {e}")
            return {
                'is_satisfactory': True,
                'confidence': 0.5,
                'issues': [f"Judge error: {str(e)}"],
                'suggestions': [],
                'missing_diagnostics': None,
                'improved_approach': None
            }
    
    def _prepare_diagnostic_summary_for_judge(self, diagnostic_data: List[Dict]) -> str:
        """Prepare concise summary of diagnostic results for judge"""
        summary_parts = []
        
        successful = [d for d in diagnostic_data if d.get('success')]
        failed = [d for d in diagnostic_data if not d.get('success')]
        with_data = [d for d in successful if d.get('row_count', 0) > 0]
        empty = [d for d in successful if d.get('row_count', 0) == 0]
        
        summary_parts.append(f"**Total Queries:** {len(diagnostic_data)}")
        summary_parts.append(f"- Successful: {len(successful)}")
        summary_parts.append(f"- With Data: {len(with_data)}")
        summary_parts.append(f"- Empty Results: {len(empty)}")
        summary_parts.append(f"- Failed: {len(failed)}")
        
        if with_data:
            summary_parts.append(f"\n**Queries with Data:**")
            for d in with_data[:3]:
                summary_parts.append(f"- {d['purpose']}: {d['row_count']} rows")
                if d.get('data'):
                    summary_parts.append(f"  Sample: {str(d['data'][0])[:100]}...")
        
        if failed:
            summary_parts.append(f"\n**Failed Queries:**")
            for d in failed[:2]:
                summary_parts.append(f"- {d['purpose']}: {d.get('error', 'Unknown error')[:80]}")
        
        return "\n".join(summary_parts)
    
    def _refine_diagnosis_with_feedback(
        self,
        problem: str,
        problem_analysis: Dict,
        judgment: Dict,
        previous_diagnostic_data: List[Dict],
        historical_matches: List[Dict],
        doc_context: str
    ) -> Dict[str, Any]:
        """
        Generate improved diagnosis based on judge feedback
        
        Args:
            problem: User's problem
            problem_analysis: Analyzed problem components
            judgment: Judge's feedback
            previous_diagnostic_data: Previous diagnostic results
            historical_matches: Historical issues
            doc_context: Documentation context
            
        Returns:
            Improved diagnostic data or None
        """
        try:
            # Check if judge suggested additional diagnostics
            missing_diagnostics = judgment.get('missing_diagnostics', [])
            
            additional_queries = []
            
            # Convert judge suggestions to query format
            if missing_diagnostics:
                for diag in missing_diagnostics:
                    if isinstance(diag, dict):
                        additional_queries.append(diag)
                    elif isinstance(diag, str) and 'SELECT' in diag.upper():
                        additional_queries.append({
                            'purpose': 'Additional diagnostic based on judge feedback',
                            'query': diag
                        })
            
            # Execute additional queries if suggested
            if additional_queries:
                logger.info(f"🔄 Running {len(additional_queries)} additional diagnostic queries based on judge feedback")
                additional_results = self._execute_diagnostic_queries(additional_queries)
                
                # Combine with previous results
                combined_data = previous_diagnostic_data + additional_results
                
                return {
                    'diagnostic_data': combined_data,
                    'has_new_data': True
                }
            
            # No additional queries, just re-synthesize with judge's improvement suggestions
            return {
                'diagnostic_data': previous_diagnostic_data,
                'has_new_data': False,
                'judge_suggestions': judgment.get('suggestions', [])
            }
            
        except Exception as e:
            logger.error(f"❌ Error refining diagnosis: {e}")
            return None
    
    def _classify_user_intent(self, query: str) -> Dict[str, Any]:
        """
        Classify what type of response the user expects based on their question.
        
        Returns:
            Dict with intent_type and response_format guidance
        """
        try:
            classification_prompt = f"""Classify this user query to determine what type of response they expect:

User Query: "{query}"

Classify into ONE of these intent types:

1. **DATA_QUERY**: User wants to see raw data/query results (e.g., "show me all bots", "what tasks are pending")
2. **EXPLAIN_CRITERIA**: User wants to understand how system checks/determines something (e.g., "what is your criteria", "how do you check")
3. **TROUBLESHOOT**: User has a problem and needs diagnosis (e.g., "bots not coming", "why is this stuck")
4. **RECOMMENDATION**: User wants advice/best practices (e.g., "what should I check", "how can I prevent")
5. **SHOW_QUERY**: User wants to see the SQL query being used (e.g., "show me the query", "what query are you running")

Also determine what to include in response:
- show_sql_query: true/false (show the SQL query being used)
- show_data_table: true/false (show query results in table format)
- show_analysis: true/false (show root cause analysis)
- show_solution: true/false (show solution steps)
- response_style: "data_focused" | "explanation" | "diagnostic" | "advisory"

Respond in JSON:
{{
    "intent_type": "...",
    "show_sql_query": true/false,
    "show_data_table": true/false,
    "show_analysis": true/false,
    "show_solution": true/false,
    "response_style": "...",
    "reasoning": "brief explanation of classification"
}}"""

            messages = [{"role": "user", "content": classification_prompt}]
            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt="You are an expert at understanding user intent in technical support contexts.",
                max_tokens=300,
                temperature=0.2
            )
            
            # Parse JSON response
            import json
            import re
            
            # Extract JSON from potential markdown wrapping
            json_match = re.search(r'```(?:json)?\s*({.*?})\s*```', response, re.DOTALL)
            if json_match:
                response = json_match.group(1)
            
            intent_data = json.loads(response)
            logger.info(f"🎯 Intent classified: {intent_data['intent_type']} - {intent_data['reasoning']}")
            return intent_data
            
        except Exception as e:
            logger.warning(f"⚠️ Intent classification failed: {e}, defaulting to TROUBLESHOOT")
            # Default to full diagnostic response
            return {
                "intent_type": "TROUBLESHOOT",
                "show_sql_query": False,
                "show_data_table": False,
                "show_analysis": True,
                "show_solution": True,
                "response_style": "diagnostic",
                "reasoning": "Defaulted due to classification error"
            }
    
    def diagnose_problem(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Main diagnostic workflow with self-improving loop and session memory:
        0. Get or create session and retrieve conversation history
        1. Classify user intent to determine response format
        2. Understand the problem
        3. Check historical issues
        4. Generate diagnostic queries
        5. Execute and analyze
        6. Search documentation
        7. Synthesize solution (with dynamic formatting and context awareness)
        8. LOOP: Judge evaluates and suggests improvements
        9. Return best diagnosis found with session memory
        """
        try:
            problem = chat_request.message
            logger.info(f"🔍 Starting intelligent diagnosis: {problem[:80]}...")
            
            # Step 0: Get session and retrieve conversation history
            session_id = chat_request.session_id
            conversation_history = []
            
            if session_id:
                session = self.session_manager.get_session(session_id)
                if session:
                    conversation_history = session.get('conversation_history', [])
                    logger.info(f"📚 Retrieved {len(conversation_history)} messages from session {session_id}")
            
            # Build context summary from history
            context_summary = self._build_context_from_history(conversation_history)
            
            # Step 1: Classify user intent to determine response format
            intent_classification = self._classify_user_intent(problem)
            logger.info(f"🎯 Response format: {intent_classification.get('response_style', 'diagnostic')}")
            
            # Step 2: Extract key information from problem description
            problem_analysis = self._analyze_problem_description(problem)
            
            # Step 3: Check historical support logs for similar issues
            historical_matches = self.support_service.search_issue(problem, None)
            
            # Step 4: Generate initial diagnostic SQL queries
            diagnostic_queries = self._generate_diagnostic_queries(problem_analysis, historical_matches)
            
            # Step 5: Execute queries and collect data
            diagnostic_data = self._execute_diagnostic_queries(diagnostic_queries)
            
            # Step 6: Search documentation for relevant context
            doc_context = self._search_documentation(problem, problem_analysis)
            
            # ========================================
            # SELF-IMPROVING DIAGNOSTIC LOOP
            # ========================================
            
            best_confidence = 0.0
            best_solution = None
            current_diagnostic_data = diagnostic_data
            refinement_history = []
            
            for refinement_iteration in range(1, self.max_refinement_iterations + 1):
                logger.info(f"🔁 Diagnosis refinement iteration {refinement_iteration}/{self.max_refinement_iterations}")
                
                # Step 7: Synthesize solution with context awareness
                solution = self._synthesize_solution(
                    problem=problem,
                    problem_analysis=problem_analysis,
                    historical_matches=historical_matches,
                    diagnostic_data=diagnostic_data,
                    doc_context=doc_context,
                    intent_classification=intent_classification,
                    context_summary=context_summary  # Pass conversation context
                )
                
                current_confidence = solution['confidence']
                
                # Track best solution
                if current_confidence > best_confidence:
                    best_confidence = current_confidence
                    best_solution = solution
                
                # Step 8: Judge evaluates diagnosis quality
                judgment = self._judge_diagnosis_quality(
                    problem=problem,
                    solution=solution,
                    diagnostic_data=current_diagnostic_data,
                    historical_matches=historical_matches,
                    iteration=refinement_iteration
                )
                
                # Track refinement history
                refinement_history.append({
                    'iteration': refinement_iteration,
                    'confidence': current_confidence,
                    'judge_confidence': judgment.get('confidence', 0.0),
                    'is_satisfactory': judgment.get('is_satisfactory', False),
                    'issues': judgment.get('issues', []),
                    'suggestions': judgment.get('suggestions', []),
                    'missing_diagnostics': judgment.get('missing_diagnostics')
                })
                
                judge_confidence = judgment.get('confidence', 0.0)
                is_satisfactory = judgment.get('is_satisfactory', False)
                
                logger.info(f"🧑‍⚖️ Judge: satisfactory={is_satisfactory}, confidence={judge_confidence:.2f}")
                
                # Exit condition 1: Judge is satisfied with high confidence
                if is_satisfactory and judge_confidence >= self.judge_confidence_threshold:
                    logger.info(f"✅ Judge satisfied with high confidence ({judge_confidence:.2f}) - stopping diagnosis refinement")
                    break
                
                # Exit condition 2: Last iteration
                if refinement_iteration >= self.max_refinement_iterations:
                    logger.info(f"🛑 Reached max iterations ({self.max_refinement_iterations}) - using best diagnosis")
                    break
                
                # Exit condition 3: Very high confidence
                if current_confidence >= 0.90:
                    logger.info(f"✅ Very high confidence ({current_confidence:.2f}) - stopping refinement")
                    break
                
                # Step 8: Refine diagnosis based on judge feedback
                if not is_satisfactory or judge_confidence < self.judge_confidence_threshold:
                    refinement_result = self._refine_diagnosis_with_feedback(
                        problem=problem,
                        problem_analysis=problem_analysis,
                        judgment=judgment,
                        previous_diagnostic_data=current_diagnostic_data,
                        historical_matches=historical_matches,
                        doc_context=doc_context
                    )
                    
                    if refinement_result and refinement_result.get('has_new_data'):
                        # Got new diagnostic data, use it for next iteration
                        current_diagnostic_data = refinement_result['diagnostic_data']
                        logger.info(f"✨ Collected additional diagnostic data, continuing refinement")
                    elif refinement_result and refinement_result.get('judge_suggestions'):
                        # Re-synthesize with judge suggestions incorporated
                        logger.info(f"🔄 Re-synthesizing with judge suggestions")
                        # Add judge suggestions to the synthesis prompt via doc_context
                        judge_guidance = "\n\n**JUDGE FEEDBACK:**\n" + "\n".join(
                            f"- {s}" for s in refinement_result['judge_suggestions']
                        )
                        doc_context = doc_context + judge_guidance
                    else:
                        logger.info(f"⚠️ Could not refine diagnosis further - stopping")
                        break
            
            # Use best solution found
            final_solution = best_solution if best_solution else solution
            
            # Log refinement process
            if len(refinement_history) > 1:
                logger.info(f"📈 Diagnosis refinement summary: {len(refinement_history)} iterations, final confidence: {best_confidence:.2f}")
            
            # Add refinement note to response if iterations occurred
            final_response = final_solution['response']
            if len(refinement_history) > 1:
                refinement_note = f"\n\n🔄 **Diagnosis Refined:** Analyzed through {len(refinement_history)} iterations for comprehensive accuracy.\n"
                final_response = refinement_note + final_response
            
            # ========================================
            # END OF SELF-IMPROVING LOOP
            # ========================================
            
            return ChatResponse(
                response=final_response,
                chatbot_type=ChatbotType.DIAGNOSTIC,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                confidence_score=best_confidence,
                sources=final_solution.get('sources', []),
                suggested_actions=[
                    "What should I check next?",
                    "Can you show me the detailed query results?",
                    "How can I prevent this in the future?"
                ],
                metadata={
                    'refinement_iterations': len(refinement_history),
                    'refinement_history': refinement_history if len(refinement_history) > 1 else None
                }
            )
            
        except Exception as e:
            logger.error(f"❌ Error in intelligent diagnosis: {e}", exc_info=True)
            return ChatResponse(
                response=f"I encountered an error while diagnosing the issue: {str(e)}. Please try rephrasing your problem or contact support.",
                chatbot_type=ChatbotType.DIAGNOSTIC,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                confidence_score=0.0
            )
    
    def _build_context_from_history(self, conversation_history: List[Dict[str, Any]]) -> str:
        """
        Build a comprehensive context summary from conversation history for better understanding
        """
        if not conversation_history or len(conversation_history) < 2:
            return ""
        
        context_parts = []
        
        # Include ALL previous messages (not just last 4) for full context
        for i, msg in enumerate(conversation_history[:-1], 1):  # Exclude the current message
            role = msg.get('role', 'unknown').upper()
            content = msg.get('content', '').strip()
            
            if content:
                # Include more content for better context (up to 300 chars)
                if len(content) > 300:
                    content = content[:300] + "..."
                
                context_parts.append(f"[{role} - Message {i}]: {content}")
        
        if context_parts:
            return "\\n".join(context_parts[-8:])  # Last 8 messages for comprehensive context
        
        return ""
    
    def _analyze_problem_description(self, problem: str) -> Dict[str, Any]:
        """Use LLM to extract structured information from problem description"""
        try:
            analysis_prompt = f"""Analyze this NEO system issue and extract key information:

Problem: "{problem}"

**AVAILABLE DATABASE TABLES (use ONLY these):**
{', '.join(self.available_tables)}

**BOT-RELATED TABLES:**
{', '.join(self.bot_related_tables)}

Extract and categorize:
1. Component Type: (bot, station, task, wave, communication, database, other)
2. Symptom: (stuck, not responding, failed, timeout, error, missing, incorrect)
3. Affected Entity: (specific bot ID, station ID, wave ID, or general)
4. Severity: (critical, high, medium, low)
5. Likely Tables: (which database tables should we check?)
6. Keywords: (key terms for documentation search)

Respond in JSON format:
{{
    "component": "...",
    "symptom": "...",
    "entity": "...",
    "severity": "...",
    "likely_tables": ["table1", "table2"],
    "keywords": ["keyword1", "keyword2"]
}}"""

            messages = [{"role": "user", "content": analysis_prompt}]
            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt="You are a NEO system diagnostic expert. Extract structured information from problem descriptions.",
                max_tokens=500,
                temperature=0.3
            )
            
            # Parse JSON response
            import json
            try:
                analysis = json.loads(response)
            except:
                # Fallback to basic analysis
                problem_lower = problem.lower()
                analysis = {
                    "component": "bot" if "bot" in problem_lower else "station" if "station" in problem_lower else "unknown",
                    "symptom": "not_responding" if "not responding" in problem_lower else "stuck" if "stuck" in problem_lower else "unknown",
                    "entity": "general",
                    "severity": "high" if any(word in problem_lower for word in ["critical", "urgent", "stuck", "stopped"]) else "medium",
                    "likely_tables": ["task_master", "bot_master", "order_bin_mapping"],
                    "keywords": problem_lower.split()[:5]
                }
            
            logger.info(f"📊 Problem analysis: {analysis}")
            return analysis
            
        except Exception as e:
            logger.error(f"Error analyzing problem: {e}")
            return {
                "component": "unknown",
                "symptom": "unknown",
                "entity": "general",
                "severity": "medium",
                "likely_tables": [],
                "keywords": []
            }
    
    def _generate_diagnostic_queries(self, problem_analysis: Dict, historical_matches: List[Dict]) -> List[Dict[str, str]]:
        """Generate SQL queries to diagnose the issue using ONLY valid tables"""
        queries = []
        component = problem_analysis.get('component', '')
        symptom = problem_analysis.get('symptom', '')
        
        # Bot-related diagnostics (validate table names first)
        if 'bot' in component.lower() or 'stuck' in symptom.lower():
            # Check for bot_master table
            if self._validate_table_exists('bot_master'):
                # Validate columns before adding query
                test_query = "SELECT COUNT(*) as total_bots, SUM(CASE WHEN STATUS='ACTIVE' THEN 1 ELSE 0 END) as active_bots FROM bot_master;"
                columns_valid, invalid_cols = self._validate_query_columns(test_query, 'bot_master')
                
                # Also validate filter values
                values_valid, invalid_vals = self._validate_query_value_filters(test_query, 'bot_master')
                
                if columns_valid and values_valid:
                    queries.append({
                        "purpose": "Check bot inventory and status",
                        "query": test_query
                    })
                elif not columns_valid:
                    logger.warning(f"⚠️ Query uses invalid columns for bot_master: {invalid_cols}")
                    # Use simple count instead
                    queries.append({
                        "purpose": "Check bot inventory",
                        "query": "SELECT COUNT(*) as total_bots FROM bot_master;"
                    })
                elif not values_valid:
                    logger.warning(f"⚠️ Query uses invalid filter values: {invalid_vals}")
                    # Use query without filters
                    queries.append({
                        "purpose": "Check bot inventory",
                        "query": "SELECT COUNT(*) as total_bots FROM bot_master;"
                    })
            else:
                logger.warning("⚠️ Table 'bot_master' not found, looking for alternatives...")
                # Try to find bot-related tables
                for table in self.bot_related_tables:
                    if 'bot' in table.lower() and 'master' in table.lower():
                        queries.append({
                            "purpose": f"Check bot status using {table}",
                            "query": f"SELECT * FROM {table} LIMIT 10;"
                        })
                        break
            
            # Add more bot queries only if tables exist
            if self._validate_table_exists('task_master'):
                queries.extend([
                    {
                        "purpose": "Check active and pending tasks",
                        "query": "SELECT STATUS, COUNT(*) as count FROM task_master GROUP BY STATUS;"
                    },
                    {
                        "purpose": "Check recent bot assignments",
                        "query": "SELECT * FROM task_master WHERE STATUS IN ('ASSIGNED', 'IN_PROGRESS') LIMIT 5;"
                    }
                ])
        
        # Station-related diagnostics (validate tables)
        if 'station' in component.lower() or 'pick' in symptom.lower():
            if self._validate_table_exists('station_pick_task_master'):
                queries.append({
                    "purpose": "Check station pick tasks",
                    "query": "SELECT STATUS, COUNT(*) as count FROM station_pick_task_master GROUP BY STATUS;"
                })
            
            if self._validate_table_exists('order_bin_mapping'):
                queries.extend([
                    {
                        "purpose": "Check pending bin mappings",
                        "query": "SELECT * FROM order_bin_mapping WHERE STATUS = 'PENDING' LIMIT 5;"
                    },
                    {
                        "purpose": "Check POST_ON_STATION bins",
                        "query": "SELECT * FROM order_bin_mapping WHERE BIN_LOCATION = 'POST_ON_STATION' LIMIT 5;"
                    }
                ])
        
        # General system health - always check (if table exists)
        if self._validate_table_exists('task_master'):
            queries.append({
                "purpose": "Check overall system task status",
                "query": "SELECT COUNT(*) as total_tasks FROM task_master;"
            })
        
        # Log which tables we're actually using
        tables_used = set()
        for q in queries:
            # Extract table names from queries (simple regex)
            import re
            matches = re.findall(r'FROM\s+(\w+)', q['query'], re.IGNORECASE)
            tables_used.update(matches)
        
        logger.info(f"✅ Generated {len(queries)} queries using valid tables: {tables_used}")
        
        logger.info(f"Generated {len(queries)} diagnostic queries for {component}/{symptom}")
        return queries
    
    def _execute_diagnostic_queries(self, queries: List[Dict[str, str]]) -> List[Dict[str, Any]]:
        """Execute all diagnostic queries and collect results"""
        results = []
        
        for query_info in queries:
            try:
                query = query_info['query']
                purpose = query_info['purpose']
                
                logger.info(f"🔍 Executing: {purpose}")
                
                # Execute using SQL service
                query_results, error = self.sql_service._execute_query_safe(query)
                
                if error:
                    # Query failed (table doesn't exist, syntax error, etc.)
                    logger.warning(f"⚠️ Query failed: {error}")
                    results.append({
                        "purpose": purpose,
                        "query": query,
                        "success": False,
                        "error": error,
                        "row_count": 0,
                        "data": [],
                        "is_empty": False  # Failed vs empty
                    })
                else:
                    # Query succeeded
                    row_count = len(query_results)
                    is_empty = row_count == 0
                    
                    results.append({
                        "purpose": purpose,
                        "query": query,
                        "success": True,
                        "error": None,
                        "row_count": row_count,
                        "data": query_results[:20],  # Limit to first 20 rows
                        "is_empty": is_empty
                    })
                    
                    if is_empty:
                        logger.info(f"⚠️ Query succeeded but returned 0 records")
                    else:
                        logger.info(f"✅ Found {row_count} records")
                
            except Exception as e:
                logger.error(f"Error executing query: {e}")
                results.append({
                    "purpose": purpose,
                    "query": query,
                    "success": False,
                    "error": str(e),
                    "row_count": 0,
                    "data": [],
                    "is_empty": False
                })
        
        return results
    
    def _search_documentation(self, problem: str, problem_analysis: Dict) -> str:
        """Search documentation for relevant context"""
        try:
            # Create enhanced search query
            keywords = problem_analysis.get('keywords', [])
            component = problem_analysis.get('component', '')
            search_query = f"{problem} {component} {' '.join(keywords[:3])}"
            
            # Get embedding and search
            query_embedding = self.llm_service.generate_embedding(search_query)
            search_results = self.vector_store.search(query_embedding, top_k=5)
            
            # Format context
            context_parts = []
            for i, result in enumerate(search_results[:3], 1):
                context_parts.append(f"[Doc {i}] {result['content'][:300]}...")
            
            return "\n\n".join(context_parts) if context_parts else "No relevant documentation found."
            
        except Exception as e:
            logger.error(f"Error searching documentation: {e}")
            return "Documentation search unavailable."
    
    def _synthesize_solution(self, problem: str, problem_analysis: Dict, 
                                   historical_matches: List[Dict], diagnostic_data: List[Dict],
                                   doc_context: str, intent_classification: Dict[str, Any] = None,
                                   context_summary: str = "") -> Dict[str, Any]:
        """Use LLM to synthesize all data into intelligent root cause analysis with session context"""
        try:
            # Build comprehensive context for LLM - START with session context for continuity
            synthesis_prompt = ""
            
            # ========================================
            # SESSION CONTEXT GOES FIRST - MOST IMPORTANT!
            # ========================================
            if context_summary:
                synthesis_prompt += f"""
╔══════════════════════════════════════════════════════════════════════════════╗
║  📚 CONVERSATION HISTORY - YOU MUST CONSIDER THIS CONTEXT!                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
{context_summary}

⚠️ CRITICAL INSTRUCTION:
You are continuing an ongoing conversation. The user has already discussed topics above.
When answering, you MUST:
1. Reference previous questions/answers if relevant
2. Build upon what was already discussed
3. Avoid repeating information already provided
4. Acknowledge the context of the conversation

"""
            
            # Now add the diagnostic prompt
            synthesis_prompt += f"""{self.diagnostic_prompt}

**USER'S CURRENT QUESTION:**
{problem}

**PROBLEM ANALYSIS:**
Component: {problem_analysis.get('component')}
Symptom: {problem_analysis.get('symptom')}
Severity: {problem_analysis.get('severity')}
"""
            
            synthesis_prompt += """
**DIAGNOSTIC QUERY RESULTS:**
"""
            
            # Add diagnostic data - only successful queries
            successful_queries = [r for r in diagnostic_data if r['success'] and r['row_count'] > 0]
            failed_queries = [r for r in diagnostic_data if not r['success']]
            
            if successful_queries:
                synthesis_prompt += f"\n\n**DIAGNOSTIC DATA ({len(successful_queries)} queries successful):**\n"
                for result in successful_queries:
                    synthesis_prompt += f"\n{'-' * 40}\n"
                    synthesis_prompt += f"Query: {result['purpose']}\n"
                    synthesis_prompt += f"Found: {result['row_count']} records\n"
                    if result['row_count'] > 0:
                        synthesis_prompt += f"Sample: {result['data'][:3]}\n"
            else:
                synthesis_prompt += f"\n\n**NOTE:** No diagnostic queries returned data. Provide general troubleshooting advice.\n"
            
            # Add historical context
            if historical_matches:
                synthesis_prompt += f"\n\n**HISTORICAL SIMILAR ISSUES:**\n"
                for i, match in enumerate(historical_matches[:2], 1):
                    synthesis_prompt += f"\n{i}. {match['problem']}\n"
                    synthesis_prompt += f"   Solution: {match['solution'][:200]}...\n"
            
            # Add documentation context
            synthesis_prompt += f"\n\n**RELEVANT DOCUMENTATION:**\n{doc_context}\n"
            
            # Add schema information for table validation
            synthesis_prompt += f"\n\n**AVAILABLE DATABASE TABLES (use ONLY these):**\n"
            synthesis_prompt += f"Total: {len(self.available_tables)} tables\n"
            synthesis_prompt += f"Bot-related: {', '.join(self.bot_related_tables)}\n"
            
            # Add detailed schema for key bot tables with actual columns and values
            synthesis_prompt += f"\n\n**KEY TABLE SCHEMAS (for suggesting queries):**\n"
            
            # bot_master schema with actual columns and values
            if self._validate_table_exists('bot_master'):
                bot_columns = self._get_table_columns('bot_master')
                synthesis_prompt += f"\nbot_master columns: {', '.join(bot_columns)}\n"
                # Get actual STATUS values
                status_values = self._get_distinct_column_values('bot_master', 'STATUS')
                if status_values:
                    synthesis_prompt += f"  - STATUS values: {', '.join(status_values)} (NOT 'active', 'inactive', etc.)\n"
            
            # task_master schema
            if self._validate_table_exists('task_master'):
                task_columns = self._get_table_columns('task_master')
                synthesis_prompt += f"\ntask_master columns: {', '.join(task_columns[:15])}...\n"
            
            synthesis_prompt += f"\n**CRITICAL RULES:**\n"
            synthesis_prompt += f"1. DO NOT mention tables that are not in the available tables list!\n"
            synthesis_prompt += f"2. DO NOT suggest columns that don't exist in the table schema!\n"
            synthesis_prompt += f"3. DO NOT use filter values that don't exist in the actual data!\n"
            synthesis_prompt += f"4. When suggesting SQL queries, use ONLY the columns and values listed above!\n"
            synthesis_prompt += f"5. Example: Use 'STATUS' not 'bot_status', use 'ENABLED' not 'active'\n"
            
            # Request response based on user intent
            if not intent_classification:
                intent_classification = {
                    "intent_type": "TROUBLESHOOT",
                    "show_sql_query": False,
                    "show_data_table": False,
                    "show_analysis": True,
                    "show_solution": True,
                    "response_style": "diagnostic"
                }
            
            intent_type = intent_classification.get('intent_type', 'TROUBLESHOOT')
            response_style = intent_classification.get('response_style', 'diagnostic')
            
            # Dynamic formatting based on intent
            if intent_type == 'DATA_QUERY':
                synthesis_prompt += """

**RESPONSE FORMAT (DATA_QUERY):**
Provide a brief answer showing the relevant data. If you ran queries, present results in a clear table or list format.
Be concise - just answer what they asked for.
"""
            
            elif intent_type == 'EXPLAIN_CRITERIA':
                synthesis_prompt += """

**RESPONSE FORMAT (EXPLAIN_CRITERIA):**
Explain HOW the system checks/determines this. Show:
1. The criteria used (e.g., SQL query logic)
2. What fields/tables are checked
3. Thresholds or conditions applied

Be explanatory and technical. Show the actual SQL query if relevant.
"""
            
            elif intent_type == 'SHOW_QUERY':
                synthesis_prompt += """

**RESPONSE FORMAT (SHOW_QUERY):**
Show the actual SQL query being used. Explain what each part does.
Format as:
```sql
[the query]
```
Then briefly explain the logic.
"""
            
            elif intent_type == 'RECOMMENDATION':
                synthesis_prompt += """

**RESPONSE FORMAT (RECOMMENDATION):**
Provide actionable recommendations:
1. What to check (with specific queries/tables)
2. Best practices to follow
3. How to prevent issues

Be advisory and forward-looking.
"""
            
            else:  # TROUBLESHOOT (default diagnostic format)
                synthesis_prompt += """

**PROVIDE A CONCISE DIAGNOSIS (MAX 300 WORDS):**

## Root Cause
[1-2 sentences: What's wrong based on the data]

## What I Found
[3-4 bullet points of actual findings from queries]

## Solution
[3-5 numbered steps to fix it]

## Next Steps
[2-3 immediate actions]

Be specific and concise. Reference actual data. Skip generic advice about schema.
"""

            # Generate response
            messages = [{"role": "user", "content": synthesis_prompt}]
            response_text = self.llm_service.generate_response(
                messages=messages,
                system_prompt=self.diagnostic_prompt,
                max_tokens=2000,
                temperature=0.5
            )
            
            # Calculate confidence based on data quality
            confidence = self._calculate_confidence(diagnostic_data, historical_matches)
            
            return {
                "response": response_text,
                "confidence": confidence,
                "sources": []
            }
            
        except Exception as e:
            logger.error(f"Error synthesizing solution: {e}")
            return {
                "response": f"I was able to gather diagnostic data but encountered an error synthesizing the solution: {str(e)}",
                "confidence": 0.3,
                "sources": []
            }
    
    def _calculate_confidence(self, diagnostic_data: List[Dict], historical_matches: List[Dict]) -> float:
        """Calculate confidence score based on available data"""
        confidence = 0.5  # Base confidence
        
        # Increase confidence if queries succeeded
        successful_queries = sum(1 for d in diagnostic_data if d['success'])
        total_queries = len(diagnostic_data)
        if total_queries > 0:
            confidence += 0.2 * (successful_queries / total_queries)
        
        # Increase if we found relevant data
        queries_with_data = sum(1 for d in diagnostic_data if d.get('row_count', 0) > 0)
        if queries_with_data > 0:
            confidence += 0.2
        
        # Increase if historical matches exist
        if historical_matches and len(historical_matches) > 0:
            confidence += 0.1
        
        return min(confidence, 0.95)  # Cap at 95%

