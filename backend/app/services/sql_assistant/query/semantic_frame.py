from typing import List, Optional


class SemanticFrame:
    def __init__(
        self,
        base_table: str,
        dimensions: List[str],
        metrics: List[str],
        filters: List[str],
        group_by: List[str],
        order_by: List[str],
        limit: Optional[int] = None
    ):
        self.base_table = base_table
        self.dimensions = dimensions
        self.metrics = metrics
        self.filters = filters
        self.group_by = group_by
        self.order_by = order_by
        self.limit = limit
