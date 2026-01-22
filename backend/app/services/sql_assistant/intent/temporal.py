"""
Temporal Classifier Module
Classifies temporal scope (historical vs current state)
"""

import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)


class TemporalClassifier:
    """
    Classifies whether query needs historical log tables or current state tables
    """
    
    def __init__(self):
        """Initialize temporal classifier"""
        self.historical_indicators = [
            'check the log', 'from log', 'in the log', 'historical',
            'have done', 'has done', 'have performed', 'has performed',
            'have completed', 'has completed', 'was doing', 'were doing',
            'did', 'performed', 'completed', 'finished',
            'till now', 'till today', 'till date', 'until now', 'up to now',
            'since', 'from', 'between', 'in the past', 'previously',
            'all the task performed', 'all task done', 'all tasks executed',
            'total', 'all time', 'ever', 'lifetime', 'complete history',
            'how many times', 'number of times', 'count of',
            'audit', 'track', 'trace', 'history of', 'record of'
        ]
        
        self.current_indicators = [
            'is doing', 'are doing', 'is performing', 'are performing',
            'is running', 'are running', 'is executing', 'are executing',
            'current', 'currently', 'now', 'right now', 'at the moment',
            'present', 'today', 'active', 'ongoing', 'in progress',
            'assigned to', 'allocated to', 'working on',
            'latest', 'most recent', 'newest', 'last assigned'
        ]
        
        logger.info("✅ TemporalClassifier initialized")
    
    def classify_temporal_scope(self, query: str) -> Dict[str, Any]:
        """
        Classify temporal scope of query
        
        Args:
            query: User's natural language question
            
        Returns:
            Dict with scope, confidence, indicators, table_preference
        """
        query_lower = query.lower()
        
        # Find matching indicators
        historical_matches = [ind for ind in self.historical_indicators 
                            if ind in query_lower]
        current_matches = [ind for ind in self.current_indicators 
                         if ind in query_lower]
        
        # Calculate scores
        historical_score = len(historical_matches)
        current_score = len(current_matches)
        
        # Determine scope
        if historical_score > current_score:
            scope = 'historical'
            table_preference = 'log'
            confidence = min(0.95, 0.6 + (historical_score * 0.1))
        elif current_score > historical_score:
            scope = 'current'
            table_preference = 'current'
            confidence = min(0.95, 0.6 + (current_score * 0.1))
        elif historical_score == current_score and historical_score > 0:
            scope = 'both'
            table_preference = 'both'
            confidence = 0.5
        else:
            # Default based on verb tense
            if any(word in query_lower for word in ['has', 'have', 'had', 'was', 'were', 'did']):
                scope = 'historical'
                table_preference = 'log'
                confidence = 0.4
            else:
                scope = 'current'
                table_preference = 'current'
                confidence = 0.5
        
        logger.info(f"🕐 Temporal scope: {scope} (confidence: {confidence:.2f})")
        
        return {
            'scope': scope,
            'confidence': confidence,
            'historical_indicators': historical_matches,
            'current_indicators': current_matches,
            'table_preference': table_preference
        }
    
    def build_temporal_table_guidance(self, temporal_info: Dict[str, Any], query: str) -> str:
        """
        Build guidance for LLM about table selection based on temporal scope
        
        Args:
            temporal_info: Temporal classification results
            query: Original query
            
        Returns:
            Formatted guidance string
        """
        if not temporal_info:
            return ""
        
        scope = temporal_info.get('scope', 'current')
        preference = temporal_info.get('table_preference', 'current')
        confidence = temporal_info.get('confidence', 0.5)
        
        guidance_parts = []
        
        if scope == 'historical' and confidence > 0.6:
            guidance_parts.extend([
                "\n" + "="*80,
                "🕐 TEMPORAL SCOPE DETECTED: HISTORICAL/PAST QUERY",
                "="*80,
                "\n⚠️⚠️⚠️ CRITICAL TABLE SELECTION RULE ⚠️⚠️⚠️",
                f"User Query: \"{query}\"",
                f"\nDetected indicators: {', '.join(temporal_info.get('historical_indicators', []))}",
                f"\n✅ USE LOG/HISTORICAL TABLES for this query:",
                "   - task_detail_log (NOT task_detail) → For ALL tasks performed till now",
                "   - bot_master_log (NOT bot_master) → For historical bot states",
                "   - bin_info_master_log → For historical bin states",
                "   - order_line_log → For historical order data",
                "\n❌ DO NOT use current state tables like:",
                "   - task_detail (only shows current/active tasks)",
                "   - bot_master (only shows current bot state)",
                "\n💡 REASON: User asked for COMPLETE HISTORY, not just current state",
                f"   Confidence: {confidence:.0%}",
                "="*80 + "\n"
            ])
            
        elif scope == 'current' and confidence > 0.6:
            guidance_parts.extend([
                "\n" + "="*80,
                "⏱️ TEMPORAL SCOPE DETECTED: CURRENT STATE QUERY",
                "="*80,
                "\n⚠️ CRITICAL TABLE SELECTION RULE",
                f"User Query: \"{query}\"",
                f"\nDetected indicators: {', '.join(temporal_info.get('current_indicators', []))}",
                f"\n✅ USE CURRENT STATE TABLES for this query:",
                "   - task_detail → For current/active tasks",
                "   - bot_master → For current bot states",
                "   - bin_info_master → For current bin states",
                "\n❌ DO NOT use log tables (they contain historical data)",
                f"   Confidence: {confidence:.0%}",
                "="*80 + "\n"
            ])
        
        return "\n".join(guidance_parts)
