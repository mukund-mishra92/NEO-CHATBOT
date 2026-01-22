"""
Intent Classifier Module
Classifies query intent and extracts entities
"""

import logging
from typing import Dict, Any, List

logger = logging.getLogger(__name__)


class IntentClassifier:
    """
    Classifies user query intent and identifies entities
    """
    
    def __init__(self):
        """Initialize intent classifier"""
        self.entity_map = self._build_entity_map()
        logger.info("✅ IntentClassifier initialized")
    
    def classify_query_intent(self, query: str) -> Dict[str, Any]:
        """
        Classify query intent and extract entities
        
        Args:
            query: User's natural language question
            
        Returns:
            Dict with intent, entities, operations, flags
        """
        query_lower = query.lower()
        
        # Check for metadata query
        is_metadata = self._is_metadata_query(query_lower)
        
        # Detect intent
        intent = self._detect_intent(query_lower, is_metadata)
        
        # Detect entities
        entities = self._detect_entities(query_lower)
        
        # Detect operations
        operations = self._detect_operations(query_lower)
        
        # Detect flags
        time_filter = self._has_time_filter(query_lower)
        join_needed = len(entities) > 1 or self._needs_join(query_lower)
        
        return {
            'intent': intent,
            'entities': entities,
            'operations': operations,
            'time_filter': time_filter,
            'join_needed': join_needed,
            'is_metadata_query': is_metadata
        }
    
    def _is_metadata_query(self, query_lower: str) -> bool:
        """Check if query is about schema metadata"""
        metadata_phrases = [
            'column names', 'columns in', 'columns available', 'what columns',
            'describe table', 'show columns', 'table structure', 'schema of',
            'fields in', 'list columns', 'show fields', 'what fields',
            'show me all the column', 'show me all column'
        ]
        return any(phrase in query_lower for phrase in metadata_phrases)
    
    def _detect_intent(self, query_lower: str, is_metadata: bool) -> str:
        """Detect query intent"""
        if is_metadata:
            return 'metadata'
        elif any(word in query_lower for word in ['how many', 'count', 'number of', 'total']):
            return 'count'
        elif any(word in query_lower for word in ['sum', 'total quantity', 'total amount']):
            return 'aggregate'
        elif any(word in query_lower for word in ['average', 'mean', 'avg']):
            return 'aggregate'
        elif any(word in query_lower for word in ['show', 'list', 'get', 'display', 'details']):
            return 'retrieve'
        else:
            return 'retrieve'  # default
    
    def _detect_entities(self, query_lower: str) -> List[str]:
        """Detect domain entities"""
        entities = []
        
        for entity, keywords in self.entity_map.items():
            if any(kw in query_lower for kw in keywords):
                entities.append(entity)
        
        return entities
    
    def _detect_operations(self, query_lower: str) -> List[str]:
        """Detect SQL operations"""
        operations = []
        
        if 'count' in query_lower or 'how many' in query_lower:
            operations.append('count')
        if 'sum' in query_lower or 'total' in query_lower:
            operations.append('sum')
        if 'average' in query_lower or 'avg' in query_lower:
            operations.append('average')
        if 'group' in query_lower or 'by' in query_lower:
            operations.append('group_by')
        
        return operations
    
    def _has_time_filter(self, query_lower: str) -> bool:
        """Check if query has temporal filter"""
        return any(word in query_lower for word in [
            'today', 'yesterday', 'week', 'month', 'year', 
            'recent', 'last', 'past'
        ])
    
    def _needs_join(self, query_lower: str) -> bool:
        """Check if query likely needs JOIN"""
        return any(phrase in query_lower for phrase in [
            'with', 'and', 'along with', 'including', 'details of'
        ])
    
    def _build_entity_map(self) -> Dict[str, List[str]]:
        """Build entity to keyword mapping"""
        return {
            'bin': ['bin', 'bins', 'location', 'zone', 'aisle', 'rack'],
            'bot': ['bot', 'bots', 'robot', 'agv', 'charging', 'battery'],
            'order': ['order', 'orders', 'shipment', 'delivery'],
            'wave': ['wave', 'waves', 'pick_wave', 'put_wave'],
            'sku': ['sku', 'article', 'product', 'item'],
            'inventory': ['inventory', 'stock', 'live_inventory'],
            'pick': ['pick', 'picks', 'picking', 'picker'],
            'put': ['put', 'puts', 'putting', 'putaway'],
            'station': ['station', 'stations', 'workstation'],
            'task': ['task', 'tasks', 'job', 'jobs'],
            'alarm': ['alarm', 'alarms', 'alert', 'error'],
            'maintenance': ['maintenance', 'repair', 'service'],
            'user': ['user', 'users', 'operator', 'picker'],
            'charging': ['charging', 'charge', 'battery'],
            'log': ['log', 'logs', 'history', 'audit'],
            'velocity': ['velocity', 'speed', 'frequency']
        }
    
    def get_tables_for_entities(self, entities: List[str]) -> Dict[str, List[str]]:
        """
        Get relevant tables for detected entities
        
        Args:
            entities: List of entity names
            
        Returns:
            Dict mapping entities to table names
        """
        entity_table_map = {
            'bin': ['bin_info_master', 'bin_configuration', 'bin_velocity_scores'],
            'bot': ['bot_master', 'bot_alarm_log', 'robot_charge_log'],
            'order': ['wms_to_wcs_order_line_request_data', 'order_bin_mapping'],
            'sku': ['sku_master', 'sku_recommendations', 'article_proximity_score'],
            'task': ['task_master', 'task_detail', 'task_detail_log'],
            'alarm': ['alarm_master', 'bot_alarm_log'],
            'inventory': ['live_inventory_master', 'live_inventory_master_log']
        }
        
        result = {}
        for entity in entities:
            if entity in entity_table_map:
                result[entity] = entity_table_map[entity]
        
        return result
