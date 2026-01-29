"""
Dimension Table Resolver
Suggests better dimension tables when direct paths fail
"""

import logging

logger = logging.getLogger(__name__)


class DimensionTableResolver:
    """
    Resolves dimension tables that are reachable from base table
    Suggests alternatives when requested dimensions are unreachable
    """
    
    def __init__(self, schema_parser, schema_graph):
        self.schema_parser = schema_parser
        self.schema_graph = schema_graph
    
    def find_alternative_dimensions(self, base_table: str, target_columns: list) -> dict:
        """
        Find alternative dimension tables that:
        1. Have the target columns
        2. Are reachable from base_table via JOIN path
        
        Args:
            base_table: The current base table
            target_columns: List of column names needed
        
        Returns:
            {
                'column_name': {
                    'table': 'alternative_table',
                    'path': ['base', 'intermediate', 'target'],
                    'confidence': 0.95
                }
            }
        """
        alternatives = {}
        
        for column in target_columns:
            # Find all tables that have this column
            candidate_tables = []
            
            for table in self.schema_parser.get_available_tables():
                if self.schema_parser.validate_column_exists(table, column):
                    # Check if there's a JOIN path from base to this table
                    path = self.schema_graph.get_join_path(base_table, table)
                    
                    if path:
                        # Calculate confidence based on path length
                        confidence = 1.0 / len(path)  # Shorter path = higher confidence
                        candidate_tables.append({
                            'table': table,
                            'path': path,
                            'confidence': confidence
                        })
            
            # Pick best candidate (shortest path)
            if candidate_tables:
                best = max(candidate_tables, key=lambda x: x['confidence'])
                alternatives[column] = best
                logger.info(
                    f"✅ Found alternative for {column}: {best['table']} "
                    f"(path length: {len(best['path'])})"
                )
            else:
                logger.warning(f"⚠️ No reachable table found for column: {column}")
        
        return alternatives
    
    def get_reachable_tables(self, base_table: str, max_hops: int = 3) -> set:
        """
        Get all tables reachable from base_table within max_hops
        Useful for filtering dimension suggestions
        
        Args:
            base_table: Starting table
            max_hops: Maximum JOIN depth (default 3)
        
        Returns:
            Set of reachable table names
        """
        reachable = {base_table}
        
        # BFS to find all reachable tables
        current_level = {base_table}
        
        for hop in range(max_hops):
            next_level = set()
            
            for table in current_level:
                # Check all possible JOIN paths from this table
                for target in self.schema_parser.get_available_tables():
                    if target in reachable:
                        continue
                    
                    path = self.schema_graph.get_join_path(table, target)
                    if path and len(path) <= 2:  # Direct connection
                        next_level.add(target)
                        reachable.add(target)
            
            if not next_level:
                break
            
            current_level = next_level
        
        logger.info(f"📊 Found {len(reachable)} tables reachable from {base_table} within {max_hops} hops")
        return reachable
