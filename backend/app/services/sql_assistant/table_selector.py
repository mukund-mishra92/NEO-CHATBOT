from typing import List, Dict
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity
from app.services.embedding_service import embedding_service
import logging

logger = logging.getLogger(__name__)


class TableSelector:
    """
    Hybrid Semantic Table Selector

    final_score =
        0.6 * semantic_similarity
      + 0.2 * lexical_score
      + 0.1 * category_bonus
      + 0.1 * entity_bonus
    """

    def __init__(
        self,
        schema: Dict[str, List[str]],
        table_metadata: Dict[str, Dict] = None
    ):
        self.schema = schema
        self.table_metadata = table_metadata or {}

        # Pre-lowercase schema once
        self.schema_lower = {
            table: [col.lower() for col in columns]
            for table, columns in self.schema.items()
        }

        self.table_embeddings = {}

        logger.info("🔄 Batch embedding schema tables...")

        table_names = []
        texts = []

        for table, columns in self.schema.items():
            table_names.append(table)
            texts.append(self._build_table_text(table, columns))

        try:
            embeddings = embedding_service.embed_batch(texts)
            for table, emb in zip(table_names, embeddings):
                self.table_embeddings[table] = emb  # already normalized
        except Exception as e:
            logger.error(f"❌ Schema embedding failed: {e}")
            for table in table_names:
                self.table_embeddings[table] = None

        logger.info(f"✅ TableSelector initialized with {len(self.schema)} tables")

    # ----------------------------------------------------------
    # TEXT BUILDER
    # ----------------------------------------------------------
    def _build_table_text(self, table: str, columns: List[str]) -> str:

        meta = self.table_metadata.get(table, {})

        description = meta.get("description", "")
        business_attrs = meta.get("key_business_attributes", [])
        joins = meta.get("frequently_joined_with", [])
        analytics = meta.get("supports_analytics", [])
        self_sufficient = meta.get("self_sufficient_for", [])
        not_needed = meta.get("not_needed_for", [])
        category = meta.get("category", "")

        parts = [
            f"TABLE: {table}",
            f"CATEGORY: {category}" if category else "",
            f"DESCRIPTION: {description}",
            f"BUSINESS ATTRIBUTES: {' '.join(business_attrs)}" if business_attrs else "",
            f"SELF-SUFFICIENT FOR: {' '.join(self_sufficient)}" if self_sufficient else "",
            f"COMMON JOINS: {' '.join(joins)}" if joins else "",
            f"ANALYTICS: {' '.join(analytics)}" if analytics else "",
            f"NOT NEEDED FOR: {' '.join(not_needed)}" if not_needed else "",
            f"COLUMNS: {' '.join(columns)}",
        ]
        return "\n".join(p for p in parts if p)

    # ----------------------------------------------------------
    # MAIN SELECTION LOGIC
    # ----------------------------------------------------------
    def select(self, question: str, max_tables: int = 10) -> List[str]:

        question_lower = question.lower()

        try:
            query_emb = embedding_service.embed(question)
        except Exception as e:
            logger.warning(f"⚠️ Query embedding failed: {e}")
            query_emb = None

        scores = []

        for table, columns in self.schema.items():

            # -----------------------------
            # 1️⃣ Semantic similarity
            # -----------------------------
            semantic_score = 0.0
            table_emb = self.table_embeddings.get(table)

            if query_emb is not None and table_emb is not None:
                try:
                    semantic_score = cosine_similarity(
                        [query_emb], [table_emb]
                    )[0][0]
                except Exception:
                    semantic_score = 0.0

            # -----------------------------
            # 2️⃣ Lexical score
            # -----------------------------
            lexical_score = 0.0

            if table.lower() in question_lower:
                lexical_score += 3.0

            for col in self.schema_lower[table]:
                if col in question_lower:
                    lexical_score += 0.5

            lexical_score = lexical_score / 5.0

            # -----------------------------
            # 3️⃣ Category bonus
            # -----------------------------
            category_bonus = 0.0
            category = self.table_metadata.get(table, {}).get("category", "")

            if "master" in category and any(
                w in question_lower for w in ["current", "latest", "status"]
            ):
                category_bonus += 0.2

            if ("log" in category or table.lower().endswith("_log")) and any(
                w in question_lower for w in ["history", "trend", "past",
                                               "previous", "earlier", "before",
                                               "last", "old"]
            ):
                category_bonus += 0.3

            # -----------------------------
            # 4️⃣ Entity bonus (capped)
            # -----------------------------
            entity_bonus = 0.0
            matched_cols = sum(
                1 for col in self.schema_lower[table]
                if col in question_lower
            )

            if matched_cols > 0:
                entity_bonus = min(0.15, 0.05 * matched_cols)

            # -----------------------------
            # Final score
            # -----------------------------
            final_score = (
                0.6 * semantic_score
                + 0.2 * lexical_score
                + 0.1 * category_bonus
                + 0.1 * entity_bonus
            )

            scores.append((table, final_score))

            logger.debug(
                f"[TABLE_RANK] {table} | "
                f"semantic={semantic_score:.4f}, "
                f"lexical={lexical_score:.4f}, "
                f"cat={category_bonus:.4f}, "
                f"entity={entity_bonus:.4f}, "
                f"final={final_score:.4f}"
            )

        scores.sort(key=lambda x: x[1], reverse=True)

        selected = [t for t, _ in scores[:max_tables]]

        logger.info(f"🔍 Top {max_tables} tables selected: {selected}")

        return selected