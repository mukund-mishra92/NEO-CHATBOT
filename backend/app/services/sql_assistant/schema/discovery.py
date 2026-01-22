"""
Schema Discovery Module
Intelligent schema selection, JOIN path detection, and relevance scoring
"""

import logging
import re
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)


class SchemaDiscovery:
    """
    Discovers relevant schema elements for queries
    Finds tables, JOINs, and relationships
    """
    
    def __init__(self, schema_parser, llm_service=None):
        """
        Initialize schema discovery
        
        Args:
            schema_parser: SchemaParser instance
            llm_service: LLMService for intelligent JOIN detection (optional)
        """
        self.schema_parser = schema_parser
        self.llm_service = llm_service
        logger.info("✅ SchemaDiscovery initialized")
    
    def get_relevant_schema(self, query: str, intent_info: Dict[str, Any], 
                           entity_tables: Dict[str, List[str]], max_tables: int = 10) -> str:
        """
        Get relevant schema for query based on intent and entities
        
        Args:
            query: User's natural language query
            intent_info: Intent classification results
            entity_tables: Mapping of entities to tables
            max_tables: Maximum tables to include
            
        Returns:
            Formatted schema string with relevant tables and JOIN hints
        """
        try:
            # Combine all relevant tables from entities
            relevant_tables = set()
            for entity, tables in entity_tables.items():
                relevant_tables.update(tables)
            
            # Also try keyword matching as fallback
            query_lower = query.lower()
            keywords = re.findall(r'\b\w+\b', query_lower)
            
            for keyword in keywords:
                matching_tables = self.schema_parser.schema_parser.search_tables(keyword)
                relevant_tables.update(matching_tables[:2])
            
            # If no tables found, include most common tables
            if not relevant_tables:
                common_tables = [
                    'wms_to_wcs_order_line_request_data',
                    'sku_recommendations',
                    'mining_job_logs',
                    'bin_velocity_scores',
                    'article_proximity_score',
                    'alarm_master',
                    'bin_configuration'
                ]
                all_tables = self.schema_parser.extract_table_names()
                for table in common_tables:
                    if table in all_tables:
                        relevant_tables.add(table)
            
            # Limit to max_tables
            relevant_tables = list(relevant_tables)[:max_tables]
            
            # Get JOIN paths if multiple tables
            join_hints = []
            if len(relevant_tables) > 1:
                join_paths = self.get_join_paths(relevant_tables)
                if join_paths:
                    join_hints = self._format_join_hints(join_paths)
            
            # Build compact schema
            schema = self._build_schema_string(
                relevant_tables, join_hints, intent_info)
            
            logger.info(f"📋 Selected {len(relevant_tables)} relevant tables")
            return schema
            
        except Exception as e:
            logger.error(f"Error getting relevant schema: {e}")
            return self._get_default_schema()
    
    def get_join_paths(self, tables: List[str]) -> List[Dict[str, Any]]:
        """
        Three-tier JOIN detection strategy:
        TIER 1: Predefined relationships (95% confidence)
        TIER 2: Schema discovery (75% confidence)
        TIER 3: LLM detection (60% confidence)
        """
        all_join_paths = []
        
        # TIER 1: Predefined relationships
        predefined = self._get_predefined_joins(tables)
        all_join_paths.extend(predefined)
        
        # TIER 2: Auto-discover from schema
        discovered = self._discover_joins_from_schema(tables)
        all_join_paths.extend(discovered)
        
        # TIER 3: LLM-based detection (if available)
        if self.llm_service:
            llm_joins = self._detect_implicit_joins_with_llm(tables)
            all_join_paths.extend(llm_joins)
        
        return all_join_paths
    
    def _get_predefined_joins(self, tables: List[str]) -> List[Dict[str, Any]]:
        """Predefined JOIN relationships from production experience"""
        relationships = [
            {
                'table1': 'wms_to_wcs_order_line_request_data',
                'table2': 'sku_master',
                'join_on': 'ARTICLE_ID = SKU_ID',
                'description': 'Orders to SKU details',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'order_bin_mapping',
                'table2': 'bin_info_master',
                'join_on': 'BIN_ID = BIN_ID',
                'description': 'Order bin mapping to bin details',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'task_master',
                'table2': 'bot_master',
                'join_on': 'BOT_ID = BOT_ID',
                'description': 'Tasks assigned to bots',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'pick_wave_order_mapping',
                'table2': 'wms_to_wcs_order_line_request_data',
                'join_on': 'ORDER_ID = ORDER_ID',
                'description': 'Wave orders to order details',
                'confidence': 0.95,
                'source': 'predefined'
            }
        ]
        
        # Filter to only include relevant tables
        relevant_joins = []
        for rel in relationships:
            if rel['table1'] in tables and rel['table2'] in tables:
                relevant_joins.append(rel)
        
        return relevant_joins
    
    def _discover_joins_from_schema(self, tables: List[str]) -> List[Dict[str, Any]]:
        """Auto-discover JOINs based on matching column names"""
        discovered_joins = []
        
        for i, table1 in enumerate(tables):
            cols1 = self.schema_parser.get_table_columns(table1)
            
            for table2 in tables[i+1:]:
                cols2 = self.schema_parser.get_table_columns(table2)
                
                # Find matching column names
                common_cols = set(cols1) & set(cols2)
                
                for col in common_cols:
                    # Prioritize columns that look like keys
                    if any(x in col.upper() for x in ['ID', 'CODE', 'KEY']):
                        discovered_joins.append({
                            'table1': table1,
                            'table2': table2,
                            'join_on': f'{col} = {col}',
                            'description': f'Auto-discovered via {col}',
                            'confidence': 0.75,
                            'source': 'schema_discovery'
                        })
        
        return discovered_joins
    
    def _detect_implicit_joins_with_llm(self, tables: List[str]) -> List[Dict[str, Any]]:
        """Use LLM to detect implicit JOIN relationships"""
        if not self.llm_service or len(tables) < 2:
            return []
        
        try:
            # Get table schemas
            schemas = []
            for table in tables:
                cols = self.schema_parser.get_table_columns(table)
                schemas.append(f"{table}: {', '.join(cols[:10])}")
            
            prompt = f"""Analyze these database tables and suggest JOIN relationships:

{chr(10).join(schemas)}

Return ONLY valid JSON array of JOIN suggestions with this format:
[{{"table1": "table_a", "table2": "table_b", "join_on": "column = column", "description": "reason"}}]

Focus on semantic relationships even if column names don't match exactly."""
            
            response = self.llm_service.generate_response(
                messages=[{"role": "user", "content": prompt}],
                max_tokens=500
            )
            
            # Parse JSON response
            import json
            joins = json.loads(response)
            
            # Add metadata
            for join in joins:
                join['confidence'] = 0.60
                join['source'] = 'llm_detection'
            
            logger.info(f"🤖 LLM detected {len(joins)} implicit JOINs")
            return joins
            
        except Exception as e:
            logger.warning(f"⚠️ LLM JOIN detection failed: {e}")
            return []
    
    def _format_join_hints(self, join_paths: List[Dict[str, Any]]) -> List[str]:
        """Format JOIN paths into readable hints"""
        hints = ["\n🔗 INTELLIGENT JOIN PATH DETECTION (Three-Tier Strategy):"]
        hints.append("   TIER 1: Experience-based (95%) → Production joins")
        hints.append("   TIER 2: Schema discovery (75%) → Auto-detected")
        hints.append("   TIER 3: LLM detection (60%) → AI-suggested")
        hints.append("\n📍 SUGGESTED JOIN PATHS:")
        
        # Group by source
        predefined = [j for j in join_paths if j.get('source') == 'predefined']
        discovered = [j for j in join_paths if j.get('source') == 'schema_discovery']
        llm_detected = [j for j in join_paths if j.get('source') == 'llm_detection']
        
        if predefined:
            hints.append("  ✅ TIER 1 - PREDEFINED (Use first!):")
            for join in predefined:
                conf = int(join.get('confidence', 0.95) * 100)
                hints.append(f"     • {join['table1']} JOIN {join['table2']} ON {join['join_on']}")
                hints.append(f"       {join['description']} [{conf}%]")
        
        if discovered:
            hints.append("  📊 TIER 2 - AUTO-DISCOVERED:")
            for join in discovered:
                conf = int(join.get('confidence', 0.75) * 100)
                hints.append(f"     • {join['table1']} JOIN {join['table2']} ON {join['join_on']}")
                hints.append(f"       {join['description']} [{conf}%]")
        
        if llm_detected:
            hints.append("  🤖 TIER 3 - LLM-DETECTED (Verify):")
            for join in llm_detected:
                conf = int(join.get('confidence', 0.60) * 100)
                hints.append(f"     • {join['table1']} JOIN {join['table2']} ON {join['join_on']}")
                hints.append(f"       {join['description']} [{conf}%]")
        
        return hints
    
    def _build_schema_string(self, relevant_tables: List[str], 
                            join_hints: List[str], intent_info: Dict[str, Any]) -> str:
        """Build formatted schema string"""
        entities_str = ', '.join(intent_info.get('entities', [])) or 'general'
        schema_lines = [
            f"📊 Database Schema (Intent: {intent_info.get('intent', 'unknown')}, "
            f"Entities: {entities_str})"
        ]
        
        if join_hints:
            schema_lines.extend(join_hints)
        
        schema_lines.append("\n📋 RELEVANT TABLES:")
        
        for table in relevant_tables:
            cols = self.schema_parser.get_table_columns(table)
            schema_lines.append(f"\n{table}:")
            schema_lines.append(f"  Columns: {', '.join(cols[:15])}")
            
            if len(cols) > 15:
                schema_lines.append(f"  ... and {len(cols) - 15} more")
        
        return "\n".join(schema_lines)
    
    def _get_default_schema(self) -> str:
        """Fallback schema when discovery fails"""
        return "Database schema unavailable - using general knowledge"
    
    def suggest_alternative_tables(self, failed_table: str, context: str) -> List[str]:
        """Suggest alternative tables based on failed table and context"""
        try:
            suggestions = []
            all_tables = self.schema_parser.extract_table_names()
            
            # Extract keywords from context
            keywords = set(re.findall(r'\b\w{4,}\b', context.lower()))
            
            # Find similar table names
            failed_lower = failed_table.lower()
            for table in all_tables:
                table_lower = table.lower()
                
                if table_lower == failed_lower:
                    continue
                
                score = 0
                
                # Same prefix/suffix
                if any(part in table_lower for part in failed_lower.split('_') if len(part) > 3):
                    score += 2
                
                # Contains context keywords
                cols = self.schema_parser.get_table_columns(table)
                table_text = f"{table} {' '.join(cols)}"
                matching = keywords & set(re.findall(r'\b\w{4,}\b', table_text.lower()))
                score += len(matching)
                
                if score > 0:
                    suggestions.append((table, score))
            
            # Sort by score
            suggestions.sort(key=lambda x: x[1], reverse=True)
            return [table for table, score in suggestions[:3]]
            
        except Exception as e:
            logger.error(f"Error suggesting alternative tables: {e}")
            return []
