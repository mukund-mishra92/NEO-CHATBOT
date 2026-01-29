# """
# Query Generator Module
# Generates SQL queries from natural language using LLM
# """

# import logging
# from typing import Optional, Dict, Any

# logger = logging.getLogger(__name__)


# class QueryGenerator:
#     """
#     Generates SQL queries from natural language questions
#     """
    
#     def __init__(self, llm_service, prompt_builder):
#         """
#         Initialize query generator
        
#         Args:
#             llm_service: LLM service for generation
#             prompt_builder: Prompt builder for system prompts
#         """
#         self.llm_service = llm_service
#         self.prompt_builder = prompt_builder
#         logger.info("✅ QueryGenerator initialized")
    
#     def generate_sql_with_strategy(self, question: str, strategy: str, 
#                                    context: Optional[Dict[str, Any]] = None) -> Optional[str]:
#         """
#         Generate SQL with different strategies
        
#         Args:
#             question: User's natural language question
#             strategy: Generation strategy ('direct', 'with_context', 'simplified')
#             context: Optional conversation context
            
#         Returns:
#             Generated SQL query or None
#         """
#         try:
#             # Get system prompt with schema and context
#             system_prompt = self.prompt_builder.build_system_prompt(question, context)
            
#             # Build user prompt based on strategy
#             user_prompt = self._build_user_prompt(question, strategy)
            
#             # Generate response
#             messages = [{"role": "user", "content": user_prompt}]
            
#             response = self.llm_service.generate_response(
#                 messages=messages,
#                 system_prompt=system_prompt,
#                 max_tokens=300,
#                 temperature=0.1  # Low temperature for deterministic SQL
#             )
            
#             # Strip markdown code fences if present
#             sql_query = response.strip()
#             if sql_query.startswith('```sql'):
#                 sql_query = sql_query[6:]  # Remove ```sql
#             elif sql_query.startswith('```'):
#                 sql_query = sql_query[3:]  # Remove ```
#             if sql_query.endswith('```'):
#                 sql_query = sql_query[:-3]  # Remove trailing ```
#             sql_query = sql_query.strip()
            
#             logger.info(f"🤖 Generated SQL with strategy: {strategy}")
#             logger.info(f"📝 SQL Query: {sql_query[:200]}..." if len(sql_query) > 200 else f"📝 SQL Query: {sql_query}")
#             # Return in expected format with dict
#             return {'sql': sql_query, 'strategy': strategy}
            
#         except Exception as e:
#             logger.error(f"❌ SQL generation error with strategy {strategy}: {e}")
#             return None
    
# #     def _build_user_prompt(self, question: str, strategy: str) -> str:
# #         """Build user prompt based on strategy"""
# #         if strategy == 'direct':
# #             return f"Convert to SQL: {question}"
# #         elif strategy == 'with_context':
# #             return f"""User question: {question}

# # Generate MySQL query to answer this question. Return ONLY the SQL."""
# #         else:  # simplified
# #             return f"Generate simple SQL for: {question}. Keep it basic with proper table names."
    
# #     def generate_sql_suggestions(self, query: str) -> list[str]:
# #         """
# #         Generate suggested follow-up actions
        
# #         Args:
# #             query: Original user query
            
# #         Returns:
# #             List of suggestions
# #         """
# #         suggestions = []
# #         query_lower = query.lower()
        
# #         if "top" in query_lower or "best" in query_lower:
# #             suggestions.extend([
# #                 "Add time period filter",
# #                 "View detailed breakdown",
# #                 "Export results to CSV"
# #             ])
# #         elif "count" in query_lower or "how many" in query_lower:
# #             suggestions.extend([
# #                 "View distribution over time",
# #                 "Compare with previous period",
# #                 "Show detailed list"
# #             ])
# #         else:
# #             suggestions.extend([
# #                 "Refine date range",
# #                 "Add additional filters",
# #                 "View related data"
# #             ])
        
# #         return suggestions[:3]
#     def _build_user_prompt(self, question: str, strategy: str) -> str:
#         """
#         Build user prompt based on strategy.
#         IMPORTANT: LLM must NOT generate JOINs.
#         """
#         base_rules = """
#     CRITICAL RULES (MUST FOLLOW):
#     - DO NOT use JOIN
#     - DO NOT reference more than ONE table
#     - Use ONLY one table in FROM clause
#     - DO NOT guess relationships
#     - DO NOT invent tables or columns
#     - Return ONLY valid MySQL SELECT query
#     - No explanation, no markdown
#     """

#         if strategy == 'direct':
#             return f"""
#     {base_rules}
#     Convert the following question into a SINGLE-TABLE SQL query.

#     Question:
#     {question}
#     """

#         elif strategy == 'with_context':
#             return f"""
#     {base_rules}
#     Using the most relevant SINGLE table, write a SQL query.

#     Question:
#     {question}
#     """

#         else:  # simplified
#             return f"""
#     {base_rules}
#     Write the MOST BASIC single-table SQL query possible.

#     Question:
#     {question}
#     """
"""
Query Generator Module
Generates SQL queries from natural language using LLM
(PHASE 1: JOIN-SAFE VERSION)
"""

import logging
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)


class QueryGenerator:
    """
    Generates SQL queries from natural language questions
    (Restricted to SINGLE-TABLE SQL)
    """

    def __init__(self, llm_service, prompt_builder):
        self.llm_service = llm_service
        self.prompt_builder = prompt_builder
        logger.info("✅ QueryGenerator initialized (JOIN-SAFE)")

    def generate_sql_with_strategy(
        self,
        question: str,
        strategy: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Optional[Dict[str, Any]]:
        try:
            system_prompt = self.prompt_builder.build_system_prompt(
                question, context
            )

            user_prompt = self._build_user_prompt(question, strategy)

            messages = [{"role": "user", "content": user_prompt}]

            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=300,
                temperature=0.1
            )

            sql_query = response.strip()

            # Strip markdown fences
            if sql_query.startswith('```sql'):
                sql_query = sql_query[6:]
            elif sql_query.startswith('```'):
                sql_query = sql_query[3:]
            if sql_query.endswith('```'):
                sql_query = sql_query[:-3]

            sql_query = sql_query.strip()

            # 🔒 ENFORCE SINGLE-TABLE SQL
            sql_query = self._strip_joins(sql_query)

            logger.info(f"🤖 Generated SQL (JOIN-SAFE): {strategy}")
            logger.info(
                f"📝 SQL Query: {sql_query[:200]}..."
                if len(sql_query) > 200 else f"📝 SQL Query: {sql_query}"
            )

            return {"sql": sql_query, "strategy": strategy}

        except Exception as e:
            logger.error(
                f"❌ SQL generation error with strategy {strategy}: {e}"
            )
            return None

    def _build_user_prompt(self, question: str, strategy: str) -> str:
        base_rules = """
CRITICAL RULES (MUST FOLLOW):
- DO NOT use JOIN
- DO NOT reference more than ONE table
- Use ONLY one table in FROM clause
- DO NOT infer relationships
- DO NOT invent tables or columns
- Return ONLY valid MySQL SELECT query
- No explanation, no markdown
"""

        if strategy == 'direct':
            return f"""
{base_rules}
Convert the following question into a SINGLE-TABLE SQL query.

Question:
{question}
"""

        elif strategy == 'with_context':
            return f"""
{base_rules}
Using the most relevant SINGLE table, write a SQL query.

Question:
{question}
"""

        else:
            return f"""
{base_rules}
Write the MOST BASIC single-table SQL query possible.

Question:
{question}
"""

    def _strip_joins(self, sql: str) -> str:
        import re

        sql = re.sub(
            r"\bJOIN\b[\s\S]*?\bON\b[\s\S]*?(?=\bWHERE\b|\bGROUP\b|\bORDER\b|\bLIMIT\b|$)",
            "",
            sql,
            flags=re.IGNORECASE
        )

        return sql.strip()

