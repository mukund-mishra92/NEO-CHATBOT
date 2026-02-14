from typing import List, Dict


class TableSelector:
    """
    Select relevant tables based on keywords.
    """

    def __init__(self, schema: Dict[str, List[str]]):
        self.schema = schema

    def select(self, question: str, max_tables: int = 5) -> List[str]:
        question_lower = question.lower()
        scores = []

        for table, columns in self.schema.items():
            score = 0
            if table.lower() in question_lower:
                score += 5

            for col in columns:
                if col.lower() in question_lower:
                    score += 1

            if score > 0:
                scores.append((table, score))

        scores.sort(key=lambda x: x[1], reverse=True)
        return [t for t, _ in scores[:max_tables]]
