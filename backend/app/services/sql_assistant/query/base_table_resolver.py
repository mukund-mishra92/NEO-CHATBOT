class BaseTableResolver:
    def __init__(self, schema_parser, schema_graph):
        self.schema_parser = schema_parser
        self.schema_graph = schema_graph

    def resolve(self, frame, user_question: str) -> str:
        """Get the best base table (primary candidate)"""
        scores = self._score_all_tables(frame, user_question)
        
        if not scores:
            raise ValueError("Could not resolve base table")

        # Pick highest score
        return max(scores, key=scores.get)
    
    def get_alternative_base_tables(self, frame, user_question: str, exclude_tables=None) -> list:
        """
        Get ranked list of alternative base tables
        Used when primary base table fails JOIN path resolution
        
        Returns: [(table_name, score), ...] sorted by score descending
        """
        exclude_tables = exclude_tables or []
        scores = self._score_all_tables(frame, user_question)
        
        # Remove excluded tables
        for table in exclude_tables:
            scores.pop(table, None)
        
        # Sort by score descending
        sorted_tables = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        return sorted_tables
    
    def _score_all_tables(self, frame, user_question: str) -> dict:
        """Score all tables based on frame and question"""
        scores = {}

        # Candidate tables = all tables
        for table in self.schema_parser.get_available_tables():
            score = 0

            # 1️⃣ Filter ownership
            for f in frame.filters:
                col = f.split()[0] if ' ' in f else f
                if self.schema_parser.validate_column_exists(table, col):
                    score += 3

            # 2️⃣ Metric ownership
            for m in frame.metrics:
                if "(" in m:
                    continue
                if self.schema_parser.validate_column_exists(table, m):
                    score += 2

            # 3️⃣ Semantic match with question
            if table.lower().replace("_", " ") in user_question.lower():
                score += 3

            # 4️⃣ Schema graph centrality (lightweight)
            connectivity = self.schema_graph.get_table_connectivity(table)
            score += connectivity * 0.1
            
            # 5️⃣ Dimension ownership (NEW)
            for dim in frame.dimensions:
                if self.schema_parser.validate_column_exists(table, dim):
                    score += 2

            if score > 0:
                scores[table] = score
        
        return scores
