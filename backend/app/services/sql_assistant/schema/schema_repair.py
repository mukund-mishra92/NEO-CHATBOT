class SchemaRepairService:
    def __init__(self, schema_graph):
        self.schema_graph = schema_graph

    def repair_table(self, unknown_table: str) -> str | None:
        """
        Deterministically map unknown table to closest known table
        using schema graph connectivity.
        """

        # Heuristic 1: semantic containment
        for known in self.schema_graph.get_all_tables():
            if unknown_table.replace("_", "") in known.replace("_", ""):
                return known

        # Heuristic 2: highest connectivity
        candidates = [
            (t, self.schema_graph.get_table_connectivity(t))
            for t in self.schema_graph.get_all_tables()
        ]

        candidates.sort(key=lambda x: x[1], reverse=True)
        return candidates[0][0] if candidates else None
