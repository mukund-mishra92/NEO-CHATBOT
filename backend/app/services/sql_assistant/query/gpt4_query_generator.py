"""
GPT-4 Query Generator - Layer 1
Generates SQL queries directly using GPT-4 with full schema context
"""

import json
import logging
from typing import Dict, Any, Optional, Tuple
from datetime import datetime
import re

from ....core.config import settings

logger = logging.getLogger(__name__)


class GPT4QueryGenerator:
    """
    Layer 1: Primary SQL query generation using GPT-4 with complete schema
    - Uses full schema information for context
    - Generates complete SQL queries (not semantic frames)
    - Optimized for accuracy with detailed prompts
    """

    def __init__(self, llm_service, schema_parser, schema_graph):
        self.llm = llm_service
        self.schema_parser = schema_parser
        self.schema_graph = schema_graph
        
    def generate_query(
        self,
        question: str,
        conversation_history: Optional[list] = None,
        attempt: int = 1,
        previous_error: Optional[str] = None
    ) -> Tuple[str, Dict[str, Any]]:
        """
        Generate SQL query using GPT-4 with full schema context
        
        Args:
            question: User's natural language question
            conversation_history: Previous conversation for context
            attempt: Attempt number (1 for first, 2+ for retries)
            previous_error: Error from previous attempt (for retry guidance)
            
        Returns:
            Tuple of (sql_query, metadata)
        """
        start_time = datetime.now()
        
        # Build schema context sized to fit prompt/token budgets
        schema_info = self._build_schema_context(question)
        
        # Build prompt based on attempt
        if attempt == 1:
            prompt = self._build_initial_prompt(question, schema_info, conversation_history)
            model = settings.SQL_ASSISTANT_PRIMARY_MODEL
            temperature = settings.SQL_ASSISTANT_PRIMARY_TEMPERATURE
            thinking_mode = "off"
        else:
            prompt = self._build_retry_prompt(question, schema_info, previous_error)
            model = settings.SQL_ASSISTANT_RETRY_MODEL
            temperature = settings.SQL_ASSISTANT_RETRY_TEMPERATURE
            thinking_mode = settings.SQL_ASSISTANT_RETRY_THINKING_MODE
            
        logger.info(f"🤖 Using model: {model} (Attempt {attempt}) | thinking={thinking_mode}")
        
        # Generate SQL query
        try:
            response = self.llm.generate_response(
                messages=[{"role": "user", "content": prompt}],
                temperature=temperature,
                max_tokens=2000,
                model_override=model,
                thinking_mode=thinking_mode,
            )
            
            # Extract SQL from response
            sql_query = self._extract_sql(response)
            
            # Build metadata
            metadata = {
                "model": model,
                "attempt": attempt,
                "generation_time": (datetime.now() - start_time).total_seconds(),
                "temperature": temperature,
                "has_retry_context": previous_error is not None
            }
            
            logger.info(f"✅ Generated SQL in {metadata['generation_time']:.2f}s")
            logger.info(f"📝 SQL: {sql_query[:200]}...")
            
            return sql_query, metadata
            
        except Exception as e:
            logger.error(f"❌ Failed to generate SQL: {e}")
            raise

    def _build_schema_context(self, question: str) -> Dict[str, Any]:
        """Build a prompt-sized schema context relevant to the question.

        Prioritization strategy:
        1. Always include core/hub tables (orders, items, SKU, bot, etc.)
        2. Score tables by keyword relevance (with smart matching)
        3. Add relationship neighbors for JOIN paths
        4. Boost tables with many foreign key connections
        """
        all_tables = list(self.schema_parser.get_available_tables())
        if not all_tables:
            return {"tables": {}, "relationships": []}

        # Define core tables that should always be prioritized
        core_table_patterns = {
            'order': ['order_master', 'order_item', 'order_item_master', 'wave_order_master'],
            'item': ['item_master', 'order_item', 'order_item_master', 'item_info'],
            'sku': ['sku_master', 'sku_info', 'article_registered'],
            'bot': ['bot_master', 'bot_alarm_log', 'bot_charging_bit_log'],
            'warehouse': ['warehouse_master', 'zone_master', 'location_master'],
            'bin': ['bin_info_master', 'bin_configuration'],
            'rack': ['rack_master', 'rack_info'],
            'pick': ['pick_list', 'pick_master', 'picker_master'],
            'inventory': ['inventory_master', 'stock_master', 'inventory_info'],
        }

        # Build keyword synonyms for better matching
        keyword_synonyms = {
            'order': ['orders', 'ordering', 'purchase', 'wave'],
            'item': ['items', 'product', 'products', 'article', 'articles'],
            'sku': ['skus', 'article', 'product'],
            'bot': ['bots', 'robot', 'robots', 'agv'],
            'warehouse': ['wh', 'warehouses', 'facility'],
            'pick': ['picking', 'picker', 'pickers', 'picked'],
            'bin': ['bins', 'storage'],
            'rack': ['racks', 'racking'],
        }

        scored = []
        q = (question or "").lower()
        q_tokens = set([t for t in re.split(r"[^a-zA-Z0-9_]+", q) if t and len(t) > 2])

        for table in all_tables:
            score = 0.0
            t_low = table.lower()
            
            # Check if it's a core table
            is_core = False
            for patterns in core_table_patterns.values():
                if table in patterns:
                    score += 10.0  # High priority for core tables
                    is_core = True
                    break
            
            # Exact table name match
            if t_low in q:
                score += 8.0
            
            # Check for core keywords in table name
            for keyword, synonyms in keyword_synonyms.items():
                if keyword in t_low or any(syn in t_low for syn in synonyms):
                    # Boost if the keyword or synonym is in the question
                    if keyword in q or any(syn in q for syn in synonyms):
                        score += 5.0
                        break
            
            # Token matching with smarter scoring
            table_parts = t_low.replace('_', ' ').split()
            for tok in q_tokens:
                # Exact token in table name
                if tok in table_parts:
                    score += 2.0
                # Partial token match (for plurals, etc.)
                elif any(tok in part or part in tok for part in table_parts):
                    score += 1.0
            
            # Column matching
            cols = self.schema_parser.get_table_columns(table)
            col_matches = 0
            for c in cols:
                c_low = c.lower()
                if c_low in q:
                    score += 1.5
                    col_matches += 1
                for tok in q_tokens:
                    if tok and tok in c_low:
                        score += 0.3
                        col_matches += 1
            
            # Boost tables with many matching columns
            if col_matches > 3:
                score += 2.0
            
            # Calculate relationship centrality (tables with many FKs are hubs)
            if self.schema_graph and hasattr(self.schema_graph, "tables"):
                node = self.schema_graph.tables.get(table)
                if node:
                    fk_count = len(getattr(node, "foreign_keys", []) or [])
                    if fk_count > 0:
                        score += min(fk_count * 0.5, 3.0)  # Cap at +3.0
            
            scored.append((table, score))

        # Sort by score
        scored.sort(key=lambda x: x[1], reverse=True)

        max_tables = settings.SQL_ASSISTANT_SCHEMA_MAX_TABLES
        
        # Select tables with positive scores, or top N if no matches
        seed_tables = [t for t, s in scored if s > 0][:max_tables]
        if not seed_tables:
            seed_tables = [t for t, _ in scored[: min(max_tables, 10)]]
        
        logger.info(f"📊 Table selection: {len(seed_tables)} tables (top 5: {[t for t in seed_tables[:5]]})")

        # Add 1-hop relationship neighbors to help JOINs
        selected = set(seed_tables)
        relationships = []
        if self.schema_graph and hasattr(self.schema_graph, "tables"):
            for t in list(seed_tables):
                node = self.schema_graph.tables.get(t)
                if not node:
                    continue
                for edge in getattr(node, "foreign_keys", []) or []:
                    rel = {
                        "from_table": t,
                        "from_column": edge.from_column,
                        "to_table": edge.to_table,
                        "to_column": edge.to_column,
                    }
                    if rel not in relationships:
                        relationships.append(rel)
                    
                    # Add the related table if we have room
                    if edge.to_table not in selected and len(selected) < max_tables:
                        selected.add(edge.to_table)
                
                if len(selected) >= max_tables:
                    break
        
        # Build table information with columns, prioritizing important columns
        tables_info: Dict[str, Any] = {}
        for t in list(selected)[:max_tables]:
            col_dicts = []
            max_cols = settings.SQL_ASSISTANT_SCHEMA_MAX_COLUMNS_PER_TABLE

            # SchemaParser stores raw columns at schema_parser.schema_parser.tables[table]
            raw = None
            if getattr(self.schema_parser, "schema_parser", None) and hasattr(self.schema_parser.schema_parser, "tables"):
                raw = self.schema_parser.schema_parser.tables.get(t)

            all_cols = []
            if isinstance(raw, list):
                all_cols = raw
            else:
                # Fallback: get column names only
                cols = self.schema_parser.get_table_columns(t)
                all_cols = [{"field": c, "type": "unknown", "null": "YES"} for c in cols]
            
            # Prioritize important columns (IDs, keys, common business fields)
            priority_patterns = ['_id', '_key', '_code', '_name', '_status', '_type', '_date', '_time', '_qty', '_quantity', '_amount']
            priority_cols = []
            regular_cols = []
            
            for col in all_cols:
                col_name = col.get("field", "").lower()
                is_priority = any(pattern in col_name for pattern in priority_patterns)
                
                col_dict = {
                    "name": col.get("field"),
                    "type": col.get("type", "unknown"),
                    "nullable": col.get("null", "YES") != "NO",
                }
                
                if is_priority:
                    priority_cols.append(col_dict)
                else:
                    regular_cols.append(col_dict)
            
            # Take priority columns first, then fill with regular columns
            col_dicts = priority_cols + regular_cols
            col_dicts = col_dicts[:max_cols]

            tables_info[t] = {"columns": col_dicts}

        return {"tables": tables_info, "relationships": relationships}

    def _build_initial_prompt(
        self,
        question: str,
        schema_info: Dict[str, Any],
        conversation_history: Optional[list]
    ) -> str:
        """Build initial prompt for first attempt"""
        
        # Format schema information
        schema_text = self._format_schema_for_prompt(schema_info)
        
        # Add conversation context if available
        context_text = ""
        if conversation_history:
            context_text = "\n## Conversation Context:\n"
            for msg in conversation_history[-3:]:  # Last 3 messages
                role = msg.get("role", "user")
                content = msg.get("content", "")
                context_text += f"{role}: {content}\n"
        
        prompt = f"""You are an expert SQL query generator for a warehouse management system (NEO).

## Your Task:
Generate a COMPLETE, EXECUTABLE SQL query for MySQL 8.0 to answer the user's question.

## Database Schema:
{schema_text}

## Important Guidelines:
1. Use ONLY tables and columns that exist in the schema above
2. Use proper JOIN syntax with explicit ON clauses
3. Follow the foreign key relationships provided
4. Use table aliases for clarity (e.g., bm for bot_master)
5. Include appropriate WHERE clauses for filters
6. Add ORDER BY for meaningful sorting
7. Use LIMIT to prevent excessive results (default: 100)
8. Format dates properly (use DATE_FORMAT if needed)
9. Handle NULL values appropriately
10. Return ONLY the SQL query, no explanations

## Best Practices:
- Prefer INNER JOIN unless outer join is specifically needed
- Use aggregate functions (COUNT, SUM, AVG) when appropriate
- Group by all non-aggregated columns
- Use DISTINCT only when necessary
- Optimize for performance (avoid SELECT *)
{context_text}
## User Question:
{question}

## SQL Query (return ONLY the query, starting with SELECT):"""

        return prompt

    def _build_retry_prompt(
        self,
        question: str,
        schema_info: Dict[str, Any],
        previous_error: str
    ) -> str:
        """Build retry prompt with error feedback for extended thinking"""
        
        schema_text = self._format_schema_for_prompt(schema_info)
        
        prompt = f"""You are an expert SQL query generator. Your previous attempt failed with an error.

## Previous Error:
{previous_error}

## Database Schema:
{schema_text}

## User Question:
{question}

## Your Task:
Carefully analyze the error above and generate a CORRECTED SQL query that:
1. Fixes the specific error mentioned
2. Uses correct table and column names from the schema
3. Follows proper JOIN syntax
4. Is executable on MySQL 8.0

Think step-by-step:
1. What caused the error?
2. Which tables should be involved?
3. What are the correct column names?
4. What JOINs are needed?
5. What is the correct SQL syntax?

Return ONLY the corrected SQL query (no explanation):"""

        return prompt

    def _format_schema_for_prompt(self, schema_info: Dict[str, Any]) -> str:
        """Format schema information for prompt"""
        schema_lines = []
        
        # Tables and columns
        schema_lines.append("### Tables and Columns:")
        for table_name, table_data in schema_info.get("tables", {}).items():
            cols = table_data["columns"]
            col_list = ", ".join([f"{c['name']} ({c['type']})" for c in cols])
            schema_lines.append(f"- **{table_name}**: {col_list}")
        
        # Relationships
        if schema_info.get("relationships"):
            schema_lines.append("\n### Foreign Key Relationships:")
            for rel in schema_info["relationships"]:
                schema_lines.append(
                    f"- {rel['from_table']}.{rel['from_column']} → "
                    f"{rel['to_table']}.{rel['to_column']}"
                )
        
        return "\n".join(schema_lines)

    # (Removed old o1-specific path; retries now use the configured retry model with optional thinking_mode)

    def _extract_sql(self, response: str) -> str:
        """Extract SQL query from LLM response"""
        import re
        
        # Remove markdown code blocks
        sql = response.strip()
        
        # Try to extract from ```sql code block
        sql_match = re.search(r'```sql\s*(.*?)\s*```', sql, re.DOTALL | re.IGNORECASE)
        if sql_match:
            sql = sql_match.group(1)
        else:
            # Try generic code block
            code_match = re.search(r'```\s*(.*?)\s*```', sql, re.DOTALL)
            if code_match:
                sql = code_match.group(1)
        
        # Remove any leading/trailing whitespace
        sql = sql.strip()
        
        # Remove any trailing semicolon
        if sql.endswith(';'):
            sql = sql[:-1]
        
        # Validate it starts with SELECT/WITH
        if not (sql.upper().startswith('SELECT') or sql.upper().startswith('WITH')):
            # Try to find SELECT statement
            select_match = re.search(r'(SELECT.*)', sql, re.DOTALL | re.IGNORECASE)
            if select_match:
                sql = select_match.group(1)
            else:
                raise ValueError(f"Could not extract valid SQL query from response: {response[:200]}")
        
        return sql
