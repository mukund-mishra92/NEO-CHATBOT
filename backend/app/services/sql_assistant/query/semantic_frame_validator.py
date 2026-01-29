

class SemanticFrameValidator:
    def __init__(self, schema_parser):
        self.schema_parser = schema_parser

    def validate_and_repair(self, frame):
        """
        Ensures:
        - base_table is a real table
        - dimensions are tables (not columns)
        - columns are moved to correct slots
        """

        # 1️⃣ Validate base table
        if not self.schema_parser.validate_table_exists(frame.base_table):
            raise ValueError(f"Invalid base table: {frame.base_table}")

        repaired_dimensions = []

        for dim in frame.dimensions:
            # If dimension is a column, not a table
            if not self.schema_parser.validate_table_exists(dim):
                # Try to find which table owns this column
                owning_table = self._find_table_for_column(dim)
                if owning_table:
                    repaired_dimensions.append(owning_table)
                else:
                    raise ValueError(f"Invalid dimension: {dim}")
            else:
                repaired_dimensions.append(dim)

        frame.dimensions = list(set(repaired_dimensions))
        return frame

    def _find_table_for_column(self, column_name):
        for table in self.schema_parser.get_available_tables():
            if self.schema_parser.validate_column_exists(table, column_name):
                return table
        return None
