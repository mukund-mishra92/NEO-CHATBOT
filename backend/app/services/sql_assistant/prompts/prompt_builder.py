"""
Prompt Builder Module
Constructs system prompts with schema, context, and guidance
"""

import logging
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)


class PromptBuilder:
    """
    Builds dynamic system prompts with schema and context
    """
    
    def __init__(self, schema_discovery, intent_classifier, temporal_classifier,
                 conversation_context):
        """
        Initialize prompt builder
        
        Args:
            schema_discovery: SchemaDiscovery instance
            intent_classifier: IntentClassifier instance
            temporal_classifier: TemporalClassifier instance
            conversation_context: ConversationContext instance
        """
        self.schema_discovery = schema_discovery
        self.intent_classifier = intent_classifier
        self.temporal_classifier = temporal_classifier
        self.conversation_context = conversation_context
        logger.info("✅ PromptBuilder initialized")
    
    def build_system_prompt(self, query: str, context: Optional[Dict[str, Any]] = None) -> str:
        """
        Build comprehensive system prompt
        
        Args:
            query: User's natural language question
            context: Optional conversation context
            
        Returns:
            Complete system prompt string
        """
        try:
            # Classify intent and entities
            intent_info = self.intent_classifier.classify_query_intent(query)
            
            # Get entity tables
            entity_tables = self.intent_classifier.get_tables_for_entities(
                intent_info['entities'])
            
            # Get relevant schema
            schema = self.schema_discovery.get_relevant_schema(
                query, intent_info, entity_tables, max_tables=10)
            
            # Build temporal guidance
            temporal_info = intent_info.get('temporal_scope', 
                                           self.temporal_classifier.classify_temporal_scope(query))
            temporal_guidance = self.temporal_classifier.build_temporal_table_guidance(
                temporal_info, query)
            
            # Build context prompt
            context_prompt = ""
            if context:
                context_prompt = self.conversation_context.build_context_prompt(context)
            
            # Build query guidance
            query_guidance = self._build_query_guidance(intent_info)
            
            # Assemble full prompt
            prompt = self._assemble_prompt(
                context_prompt, temporal_guidance, query_guidance, schema)
            
            logger.info(f"📝 Built system prompt ({len(prompt)} chars)")
            return prompt
            
        except Exception as e:
            logger.error(f"Error building system prompt: {e}")
            return self._get_default_prompt()
    
    def _build_query_guidance(self, intent_info: Dict[str, Any]) -> str:
        """Build query-specific guidance"""
        guidance_parts = ["\n🎯 QUERY ANALYSIS & GUIDANCE:"]
        
        # Metadata query
        if intent_info.get('is_metadata_query'):
            guidance_parts.extend([
                "  🔍 METADATA QUERY - User wants schema info!",
                "  • Use INFORMATION_SCHEMA.COLUMNS",
                "  • WHERE TABLE_SCHEMA = DATABASE()",
                "  • Use DISTINCT to avoid duplicates"
            ])
            return "\n".join(guidance_parts)
        
        # Intent-specific guidance
        intent = intent_info['intent']
        if intent == 'count':
            guidance_parts.append("  • User wants COUNT → Use COUNT(*) or COUNT(DISTINCT)")
        elif intent == 'aggregate':
            guidance_parts.append("  • User wants aggregation → Use SUM(), AVG(), MIN(), MAX()")
        elif intent == 'retrieve':
            guidance_parts.append("  • User wants data retrieval → Use SELECT with proper columns")
        
        # Time filter
        if intent_info['time_filter']:
            guidance_parts.append("  • Time filter → Use INSERTED_TIMESTAMP, DATE_SUB()")
        
        return "\n".join(guidance_parts)
    
    def _assemble_prompt(self, context_prompt: str, temporal_guidance: str,
                        query_guidance: str, schema: str) -> str:
        """Assemble complete prompt"""
        return f"""You are a SQL expert for the NEO Warehouse Management System.

{context_prompt}

{temporal_guidance}

⚠️⚠️⚠️ CRITICAL RULES ⚠️⚠️⚠️
1. ONLY USE TABLES THAT EXIST in the schema below
2. ONLY USE COLUMNS that exist in those tables
3. CHECK FILTER VALUES match actual database data
4. Use MySQL syntax (DATE_SUB(), NOW(), LIMIT)
5. Always include LIMIT clause (default 100, max 1000)
6. Return ONLY the SQL query, no explanations
⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️

{query_guidance}

{schema}

EXAMPLE PATTERNS:

-- Count query:
SELECT COUNT(*) AS count FROM table_name WHERE condition;

-- Aggregate query:
SELECT category, SUM(amount) AS total 
FROM table_name 
WHERE date >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY category 
ORDER BY total DESC 
LIMIT 10;

-- Retrieve query:
SELECT col1, col2, col3 
FROM table_name 
WHERE condition 
ORDER BY col1 
LIMIT 100;

-- Multi-table JOIN:
SELECT t1.col1, t2.col2 
FROM table1 t1 
JOIN table2 t2 ON t1.id = t2.id 
WHERE condition 
LIMIT 100;

Return ONLY the SQL query."""
    
    def _get_default_prompt(self) -> str:
        """Fallback prompt"""
        return """You are a SQL expert. Generate MySQL queries.
        
Rules:
- Use MySQL syntax
- Include LIMIT clause
- Return only SQL, no explanations"""
