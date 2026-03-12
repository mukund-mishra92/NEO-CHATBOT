from typing import List, Dict, Callable
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity


class TableSelector:
    """
    Select relevant tables based on keywords. from here to 
    Date 03-03-206 : Implementing Hybrid Semantic Table Selector
        - Combine keyword matching with semantic similarity
        final_score =
                    0.6 * semantic_embedding_similarity
                        + 0.2 * lexical_score
                        + 0.1 * category_boost
                        + 0.1 * entity_match_boost
    """

    def __init__(
        self,
        schema: Dict[str, List[str]],
        embedding_fn: Callable[[str], List[float]],
        table_metadata: Dict[str, Dict] = None
    ):
        self.schema = schema
        self.embedding_fn = embedding_fn
        self.table_metadata = table_metadata or {}

        # Precompute table embeddings
        self.table_texts = {}
        self.table_embeddings = {}

        for table, columns in self.schema.items():
            description = self.table_metadata.get(table, {}).get("description", "")
            text = f"{table} {description} {' '.join(columns)}"
            self.table_texts[table] = text
            self.table_embeddings[table] = np.array(
                self.embedding_fn(text)
            )

    def select(self, question: str, max_tables: int = 10) -> List[str]:

        question_lower = question.lower()
        query_emb = np.array(self.embedding_fn(question))

        scores = []

        for table, columns in self.schema.items():

            # -----------------------------
            # 1️⃣ Semantic similarity
            # -----------------------------
            table_emb = self.table_embeddings[table]
            semantic_score = cosine_similarity(
                [query_emb], [table_emb]
            )[0][0]

            # -----------------------------
            # 2️⃣ Lexical score (keep old logic)
            # -----------------------------
            lexical_score = 0

            if table.lower() in question_lower:
                lexical_score += 3

            for col in columns:
                if col.lower() in question_lower:
                    lexical_score += 0.5

            # Normalize lexical
            lexical_score = lexical_score / 5.0

            # -----------------------------
            # 3️⃣ Category Boost (if metadata exists)
            # -----------------------------
            category = self.table_metadata.get(table, {}).get("category", "")

            category_boost = 1.0
            if "master" in category and any(
                w in question_lower for w in ["current", "latest", "status"]
            ):
                category_boost = 1.2

            if "log" in category and any(
                w in question_lower for w in ["history", "trend", "past"]
            ):
                category_boost = 1.3

            # -----------------------------
            # 4️⃣ Final Score
            # -----------------------------
            final_score = (
                0.6 * semantic_score
                + 0.2 * lexical_score
            ) * category_boost

            scores.append((table, final_score))

        scores.sort(key=lambda x: x[1], reverse=True)

        return [t for t, _ in scores[:max_tables]]
    
    # def __init__(self, schema: Dict[str, List[str]]):
    #     self.schema = schema

    # def select(self, question: str, max_tables: int = 5) -> List[str]:
    #     question_lower = question.lower()
    #     scores = []

    #     for table, columns in self.schema.items():
    #         score = 0
    #         if table.lower() in question_lower:
    #             score += 5

    #         for col in columns:
    #             if col.lower() in question_lower:
    #                 score += 1

    #         if score > 0:
    #             scores.append((table, score))

    #     scores.sort(key=lambda x: x[1], reverse=True)
    #     return [t for t, _ in scores[:max_tables]]
