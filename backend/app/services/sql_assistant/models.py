from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass
class SQLGenerationResult:
    sql: str
    confidence: float
    explanation: str
    assumptions: List[str]
    metadata: Dict[str, Any]


@dataclass
class SQLExecutionResult:
    rows: List[Dict[str, Any]]
    row_count: int
    execution_time_ms: int
    executed_sql: Optional[str] = None
