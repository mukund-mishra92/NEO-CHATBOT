"""
Conversation Context Module
Extracts context from conversation history
"""

import logging
import re
from typing import Dict, Any, List, Optional, Set

logger = logging.getLogger(__name__)


class ConversationContext:
    """
    Extracts important context from conversation history
    """
    
    def __init__(self, session_cache, rlhf_service=None):
        """
        Initialize conversation context extractor
        
        Args:
            session_cache: SessionCache instance
            rlhf_service: RLHFService instance (optional)
        """
        self.session_cache = session_cache
        self.rlhf_service = rlhf_service
        logger.info("✅ ConversationContext initialized")
    
    def extract_conversation_context(self, conversation_history: Optional[List], 
                                    session_id: Optional[str],
                                    schema_parser=None) -> Dict[str, Any]:
        """
        Extract context from conversation history
        
        Args:
            conversation_history: List of previous messages
            session_id: Current session ID
            schema_parser: SchemaParser instance for table extraction
            
        Returns:
            Dict with tables_used, corrections, successful_queries, etc.
        """
        context = {
            'tables_used': set(),
            'columns_mentioned': {},
            'corrections': [],
            'successful_queries': [],
            'failed_tables': [],
            'previous_results': [],
            'key_info': []
        }
        
        # Get session-specific data
        if session_id:
            context['corrections'].extend(self.session_cache.get_corrections(session_id))
            context['failed_tables'].extend(self.session_cache.get_failed_tables(session_id))
            
            # Get cached successful queries with results
            recent_queries = self.session_cache.get_session_queries(session_id, limit=3)
            for query_info in recent_queries:
                context['previous_results'].append({
                    'question': query_info['question'],
                    'sql': query_info['sql'],
                    'results_count': query_info.get('results_count', 0),
                    'sample_data': query_info.get('sample_data', [])
                })
        
        # Process conversation history
        if conversation_history:
            self._process_conversation_history(
                conversation_history, context, schema_parser)
        
        # Get RLHF corrections if available
        if not conversation_history and self.rlhf_service:
            self._get_rlhf_corrections(context)
        
        logger.info(f"📚 Extracted context: {len(context['tables_used'])} tables, "
                   f"{len(context['corrections'])} corrections")
        
        return context
    
    def _process_conversation_history(self, conversation_history: List, 
                                     context: Dict[str, Any],
                                     schema_parser=None):
        """Process conversation history for context"""
        for msg in conversation_history[-10:]:  # Last 10 messages
            content = msg.content.lower() if hasattr(msg, 'content') else str(msg).lower()
            
            # Extract table names
            if schema_parser:
                table_names = schema_parser.extract_table_names()
                for table in table_names:
                    if table.lower() in content:
                        context['tables_used'].add(table)
            
            # Detect corrections
            corrections = self._detect_corrections(content)
            context['corrections'].extend(corrections)
            
            # Detect domain-specific clarifications
            key_info = self._detect_key_info(content)
            if key_info:
                context['key_info'].append(key_info)
    
    def _detect_corrections(self, content: str) -> List[Dict[str, Any]]:
        """Detect user corrections in message"""
        corrections = []
        
        correction_patterns = [
            (r'(\w+)\s+is\s+wrong.*?correct\s+is\s+(\w+)', 'column_name'),
            (r'(\w+)\s+is\s+wrong.*?use\s+(\w+)', 'column_name'),
            (r'not\s+(\w+).*?should\s+be\s+(\w+)', 'column_name'),
            (r'use\s+(\w+)\s+instead\s+of\s+(\w+)', 'column_name'),
            (r'column\s+is\s+(\w+)\s+not\s+(\w+)', 'column_name'),
        ]
        
        for pattern, correction_type in correction_patterns:
            matches = re.finditer(pattern, content, re.IGNORECASE)
            for match in matches:
                if match.lastindex >= 2:
                    corrections.append({
                        'wrong': match.group(2) if 'not' in pattern else match.group(1),
                        'correct': match.group(1) if 'column is' in pattern else match.group(2),
                        'type': correction_type
                    })
        
        return corrections
    
    def _detect_key_info(self, content: str) -> Optional[str]:
        """Detect important domain-specific clarifications"""
        if any(kw in content for kw in ['empty bin', 'available bin', 'free bin']):
            return "User asking about empty/available bins - check ARTICLE_ID='no-sku'"
        
        if 'virtual quantity' in content or 'quantity is 0 not means' in content:
            return "Important: Quantity=0 doesn't mean bin is empty (virtual allocation)"
        
        return None
    
    def _get_rlhf_corrections(self, context: Dict[str, Any]):
        """Get corrections from RLHF service"""
        try:
            rlhf_corrections = self.rlhf_service.get_sql_corrections(limit=10)
            for rlhf_corr in rlhf_corrections:
                comment = rlhf_corr.get('comment', '')
                if 'wrong' in comment.lower() and 'correct' in comment.lower():
                    context['key_info'].append(f"Past correction: {comment[:100]}")
        except Exception as e:
            logger.warning(f"Could not retrieve RLHF corrections: {e}")
    
    def build_context_prompt(self, context: Dict[str, Any]) -> str:
        """
        Build prompt section from context
        
        Args:
            context: Extracted context dict
            
        Returns:
            Formatted context prompt string
        """
        prompt_parts = []
        
        # Corrections
        if context['corrections']:
            prompt_parts.append("\n🔧 USER CORRECTIONS (CRITICAL - MUST FOLLOW):")
            for corr in context['corrections']:
                prompt_parts.append(f"  - Use '{corr['correct']}' NOT '{corr['wrong']}'")
        
        # Failed tables
        if context['failed_tables']:
            prompt_parts.append("\n🚨 BLACKLISTED TABLES (DO NOT USE):")
            prompt_parts.append("⚠️ USER SAID THESE TABLES ARE INVALID:")
            for failed in context['failed_tables']:
                prompt_parts.append(f"  - ❌ {failed['table']} ({failed['reason']})")
            prompt_parts.append("\n  🔄 Find alternative tables instead!")
        
        # Previous results
        if context['previous_results']:
            prompt_parts.append("\n📊 PREVIOUS QUERY RESULTS:")
            for i, prev in enumerate(context['previous_results'], 1):
                prompt_parts.append(f"  {i}. Q: {prev['question'][:60]}")
                prompt_parts.append(f"     SQL: {prev['sql'][:80]}...")
                prompt_parts.append(f"     Results: {prev['results_count']} rows")
        
        # Key info
        if context['key_info']:
            prompt_parts.append("\n💡 IMPORTANT CONTEXT:")
            for info in context['key_info']:
                prompt_parts.append(f"  - {info}")
        
        # Tables discussed
        if context['tables_used']:
            tables_str = ', '.join(sorted(context['tables_used']))
            prompt_parts.append(f"\n📋 TABLES DISCUSSED: {tables_str}")
        
        return "\n".join(prompt_parts) if prompt_parts else ""
