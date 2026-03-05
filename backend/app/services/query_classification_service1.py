"""
Query Classification Service

Stores all user queries with generated SQL and allows manual classification
for building a training dataset. Uses classified queries to improve future
query generation through EMBEDDING-BASED semantic similarity.

KEY FEATURES:
- Stores ALL queries (classified and unclassified) in classified_queries.jsonl
- Only queries with classification="correct" are used for similarity matching
- Embeddings are created ONLY for correct queries (not unclassified ones)
- Embeddings are rebuilt from correct queries on every service startup
- query_embeddings.npz is updated whenever queries are classified as correct

Dependencies:
    pip install sentence-transformers numpy

Model used: all-MiniLM-L6-v2
    - 22MB, 384-dim embeddings
    - Fast local inference (no API calls, no cost)
    - Strong semantic quality for short warehouse NL queries
    - Falls back to SequenceMatcher if model fails to load
"""

import json
import logging
import numpy as np
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional
from difflib import SequenceMatcher
import re

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# EMBEDDING MODEL
# ---------------------------------------------------------------------------
EMBEDDING_MODEL_NAME = "all-MiniLM-L6-v2"


def _cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Compute cosine similarity between two unit-normalised vectors."""
    dot = np.dot(a, b)
    norm = np.linalg.norm(a) * np.linalg.norm(b)
    if norm == 0:
        return 0.0
    return float(dot / norm)


def _cosine_similarity_matrix(query_vec: np.ndarray, matrix: np.ndarray) -> np.ndarray:
    """
    Vectorised cosine similarity between one query vector and an (N, D) matrix.
    Returns shape (N,) scores. Much faster than looping when N > 50.
    """
    norms = np.linalg.norm(matrix, axis=1)          # (N,)
    query_norm = np.linalg.norm(query_vec)
    denom = norms * query_norm                        # (N,)
    denom[denom == 0] = 1e-9                          # avoid division by zero
    scores = matrix.dot(query_vec) / denom            # (N,)
    return scores


class QueryClassificationService:
    """
    Service for storing, classifying, and learning from SQL queries.

    Features:
    - Stores all user queries with generated SQL
    - Manual classification (correct / incorrect / needs_review)
    - Embedding-based semantic similarity for reusing proven queries
    - Pattern learning from successful queries
    - Graceful fallback to SequenceMatcher if embedding model is unavailable
    
    Embedding Behavior:
    - Only queries with classification='correct' are indexed
    - Embeddings are rebuilt from all correct queries on service startup
    - query_embeddings.npz is automatically updated when queries are marked correct
    - Unclassified queries are NOT indexed to prevent incorrect reuse
    """

    # ------------------------------------------------------------------
    # INIT
    # ------------------------------------------------------------------
    def __init__(self, storage_path: Path):
        self.storage_path = storage_path
        self.storage_path.mkdir(parents=True, exist_ok=True)

        # File paths
        self.queries_file      = self.storage_path / "classified_queries.jsonl"
        self.patterns_file     = self.storage_path / "learned_patterns.json"
        self.embeddings_file   = self.storage_path / "query_embeddings.npz"   # numpy compressed

        # In-memory cache
        self.classified_queries_cache: List[Dict[str, Any]] = []
        self.patterns_cache: Dict = {}

        # Embedding state
        self._model = None                          # SentenceTransformer instance
        self._embedding_matrix: Optional[np.ndarray] = None   # (N, D)
        self._embedding_ids: List[str] = []         # parallel list of query_ids
        self._embedding_ready = False

        # Load data
        self._load_classified_queries()
        self._load_patterns()
        self._init_embedding_model()

        logger.info(
            f"✅ QueryClassificationService initialized | "
            f"{len(self.classified_queries_cache)} classified queries | "
            f"embedding_ready={self._embedding_ready}"
        )

    # ------------------------------------------------------------------
    # EMBEDDING MODEL INIT
    # ------------------------------------------------------------------
    def _init_embedding_model(self):
        """
        Load SentenceTransformer model and rebuild embedding index from correct queries.
        Always rebuilds on startup to ensure sync with classification changes.
        Silently falls back to SequenceMatcher if library is unavailable.
        """
        try:
            from sentence_transformers import SentenceTransformer
            self._model = SentenceTransformer(EMBEDDING_MODEL_NAME)
            self._embedding_ready = True
            logger.info(f"🧠 Loaded embedding model: {EMBEDDING_MODEL_NAME}")

            # Always rebuild embeddings from correct queries on startup
            self._rebuild_embeddings_from_correct_queries()

        except ImportError:
            logger.warning(
                "⚠️  sentence-transformers not installed. "
                "Falling back to SequenceMatcher similarity. "
                "Run: pip install sentence-transformers numpy"
            )
        except Exception as e:
            logger.warning(f"⚠️  Could not load embedding model: {e}. Falling back to SequenceMatcher.")

    # ------------------------------------------------------------------
    # EMBEDDING PERSISTENCE
    # ------------------------------------------------------------------
    def _load_embeddings_from_disk(self) -> bool:
        """Load saved embedding matrix and id list. Returns True on success."""
        if not self.embeddings_file.exists():
            return False
        try:
            data = np.load(str(self.embeddings_file), allow_pickle=True)
            self._embedding_matrix = data["matrix"]                          # (N, D)
            self._embedding_ids    = data["ids"].tolist()                    # list[str]
            logger.info(f"💾 Restored {len(self._embedding_ids)} embeddings from disk")
            return True
        except Exception as e:
            logger.warning(f"⚠️  Could not load saved embeddings: {e}")
            return False

    def _save_embeddings_to_disk(self):
        """Persist embedding matrix and id list to disk."""
        if self._embedding_matrix is None or len(self._embedding_ids) == 0:
            return
        try:
            np.savez_compressed(
                str(self.embeddings_file),
                matrix=self._embedding_matrix,
                ids=np.array(self._embedding_ids, dtype=object)
            )
        except Exception as e:
            logger.warning(f"⚠️  Could not save embeddings: {e}")

    # ------------------------------------------------------------------
    # EMBEDDING INDEX MANAGEMENT
    # ------------------------------------------------------------------
    def _rebuild_embeddings_from_correct_queries(self):
        """
        Rebuild embedding index from ALL queries classified as 'correct'.
        Called on service startup to ensure embeddings are always in sync.
        Only correct queries are indexed - unclassified queries are NOT indexed.
        """
        if not self._embedding_ready:
            return

        # Get all queries with classification == "correct"
        correct_queries = [
            q for q in self.classified_queries_cache
            if q["classification"] == "correct"
        ]

        if not correct_queries:
            logger.info("📊 No correct queries to index yet")
            self._embedding_matrix = None
            self._embedding_ids = []
            return

        logger.info(f"🔄 Building embeddings for {len(correct_queries)} correct queries…")

        texts = [q["user_query"] for q in correct_queries]
        ids   = [q["query_id"]   for q in correct_queries]

        new_vecs = self._encode_batch(texts)         # (M, D)

        # Replace the entire index
        self._embedding_matrix = new_vecs
        self._embedding_ids = ids
        
        self._save_embeddings_to_disk()
        logger.info(f"✅ Embedding index rebuilt with {len(self._embedding_ids)} correct queries")

    def _append_to_index(self, ids: List[str], vecs: np.ndarray):
        """Append new (ids, vectors) to the in-memory index."""
        if self._embedding_matrix is None:
            self._embedding_matrix = vecs
            self._embedding_ids    = list(ids)
        else:
            self._embedding_matrix = np.vstack([self._embedding_matrix, vecs])
            self._embedding_ids.extend(ids)

    def _add_single_to_index(self, query_id: str, text: str):
        """Encode one query and add to index. Called after store_query."""
        if not self._embedding_ready:
            return
        try:
            vec = self._encode_batch([text])          # (1, D)
            self._append_to_index([query_id], vec)
            self._save_embeddings_to_disk()
        except Exception as e:
            logger.warning(f"⚠️  Could not index embedding for {query_id}: {e}")

    def _update_index_entry(self, query_id: str, new_text: str):
        """
        Replace an existing embedding (e.g. after update_query changes the text).
        """
        if not self._embedding_ready or query_id not in self._embedding_ids:
            return
        try:
            idx = self._embedding_ids.index(query_id)
            vec = self._encode_batch([new_text])      # (1, D)
            self._embedding_matrix[idx] = vec[0]
            self._save_embeddings_to_disk()
        except Exception as e:
            logger.warning(f"⚠️  Could not update embedding for {query_id}: {e}")

    # ------------------------------------------------------------------
    # ENCODING HELPERS
    # ------------------------------------------------------------------
    def _encode_batch(self, texts: List[str]) -> np.ndarray:
        """
        Encode a list of strings → (N, D) float32 array.
        Normalises vectors so cosine similarity == dot product.
        """
        vecs = self._model.encode(
            texts,
            batch_size=64,
            show_progress_bar=False,
            convert_to_numpy=True,
            normalize_embeddings=True,   # L2 normalise → cosine = dot product
        )
        return vecs.astype(np.float32)

    # ------------------------------------------------------------------
    # SIMILARITY
    # ------------------------------------------------------------------
    def _calculate_similarity(self, str1: str, str2: str) -> float:
        """
        Semantic similarity via embeddings, or SequenceMatcher as fallback.
        This function is kept for backward-compat but find_similar_classified_query
        now uses the vectorised matrix path for performance.
        """
        if self._embedding_ready and self._model is not None:
            try:
                vecs = self._encode_batch([str1, str2])   # (2, D)
                return float(np.dot(vecs[0], vecs[1]))    # already normalised → cosine
            except Exception:
                pass
        # Fallback
        return SequenceMatcher(None, str1, str2).ratio()

    # ------------------------------------------------------------------
    # PUBLIC: STORE
    # ------------------------------------------------------------------
    def store_query(
        self,
        session_id: str,
        user_query: str,
        generated_sql: str,
        execution_status: str,
        rows_returned: int,
        confidence: float,
        tables_used: List[str],
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        try:
            query_id = f"{session_id}_{datetime.now().strftime('%Y%m%d%H%M%S%f')}"

            query_record = {
                "query_id":               query_id,
                "timestamp":              datetime.now().isoformat(),
                "session_id":             session_id,
                "user_query":             user_query,
                "generated_sql":          generated_sql,
                "execution_status":       execution_status,
                "rows_returned":          rows_returned,
                "confidence":             confidence,
                "tables_used":            tables_used,
                "classification":         "unclassified",
                "classification_timestamp": None,
                "classification_notes":   None,
                "corrected_sql":          None,
                "metadata":               metadata or {}
            }

            with open(self.queries_file, "a", encoding="utf-8") as f:
                f.write(json.dumps(query_record, ensure_ascii=False) + "\n")

            self.classified_queries_cache.append(query_record)

            # Note: Embeddings are NOT created for unclassified queries
            # They will be indexed only when classified as "correct"

            logger.info(
                f"📝 Stored query {query_id} "
                f"(cache: {len(self.classified_queries_cache)} queries)"
            )
            return query_id

        except Exception as e:
            logger.error(f"❌ Error storing query: {e}")
            return ""

    # ------------------------------------------------------------------
    # PUBLIC: CLASSIFY
    # ------------------------------------------------------------------
    def classify_query(
        self,
        query_id: str,
        classification: str,
        notes: Optional[str] = None,
        corrected_sql: Optional[str] = None
    ) -> bool:
        try:
            valid_classifications = ['correct', 'incorrect', 'needs_review']
            if classification not in valid_classifications:
                logger.error(f"Invalid classification: {classification}")
                return False

            queries = []
            with open(self.queries_file, "r", encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        queries.append(json.loads(line))

            updated = False
            target_query = None
            for query in queries:
                if query['query_id'] == query_id:
                    query['classification']           = classification
                    query['classification_timestamp'] = datetime.now().isoformat()
                    query['classification_notes']     = notes
                    if corrected_sql:
                        query['corrected_sql'] = corrected_sql
                    updated = True
                    target_query = query
                    break

            if not updated:
                logger.warning(f"Query {query_id} not found")
                return False

            with open(self.queries_file, "w", encoding="utf-8") as f:
                for query in queries:
                    f.write(json.dumps(query, ensure_ascii=False) + "\n")

            self._load_classified_queries()

            if classification == 'correct' and target_query:
                self._learn_from_correct_query(target_query)
                # Index embedding when query is classified as correct
                self._add_single_to_index(query_id, target_query['user_query'])
                logger.info(f"🔍 Added embedding for correct query: {query_id}")

            logger.info(f"✅ Query {query_id} classified as: {classification}")
            return True

        except Exception as e:
            logger.error(f"❌ Error classifying query: {e}")
            return False

    # ------------------------------------------------------------------
    # PUBLIC: UPDATE
    # ------------------------------------------------------------------
    def update_query(
        self,
        query_id: str,
        user_query: Optional[str] = None,
        generated_sql: Optional[str] = None,
        notes: Optional[str] = None
    ) -> bool:
        try:
            queries = []
            with open(self.queries_file, "r", encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        queries.append(json.loads(line))

            updated = False
            new_text = None
            for query in queries:
                if query['query_id'] == query_id:
                    if user_query is not None:
                        query['user_query'] = user_query
                        new_text = user_query          # will re-index embedding
                    if generated_sql is not None:
                        query['generated_sql'] = generated_sql
                    if notes is not None:
                        if 'update_notes' not in query['metadata']:
                            query['metadata']['update_notes'] = []
                        query['metadata']['update_notes'].append({
                            'timestamp': datetime.now().isoformat(),
                            'note': notes
                        })
                    query['metadata']['last_updated'] = datetime.now().isoformat()
                    updated = True
                    break

            if not updated:
                logger.warning(f"Query {query_id} not found")
                return False

            with open(self.queries_file, "w", encoding="utf-8") as f:
                for query in queries:
                    f.write(json.dumps(query, ensure_ascii=False) + "\n")

            self._load_classified_queries()

            # Re-index embedding if query text changed
            if new_text is not None:
                self._update_index_entry(query_id, new_text)

            logger.info(f"✅ Query {query_id} updated successfully")
            return True

        except Exception as e:
            logger.error(f"❌ Error updating query: {e}")
            return False

    # ------------------------------------------------------------------
    # PUBLIC: FIND SIMILAR  ←  CORE UPGRADED METHOD
    # ------------------------------------------------------------------
    def find_similar_classified_query(
        self,
        user_query: str,
        similarity_threshold: float = 0.85
    ) -> Optional[Dict[str, Any]]:
        """
        Find a semantically similar query classified as 'correct'.

        Uses vectorised cosine similarity over all indexed embeddings (O(N) dot
        products via numpy, very fast even at 10k+ queries).

        Falls back to SequenceMatcher if the embedding model is not available.

        Note on threshold:
            Embedding cosine scores are typically in [0.7, 1.0] for near-duplicate
            warehouse queries. The default 0.85 is a good starting point.
            SequenceMatcher scores are NOT comparable — if you switch between modes
            the threshold will behave differently, so keep embedding model installed.
        """
        try:
            # Collect correct queries and their ids
            correct_queries = {
                q["query_id"]: q
                for q in self.classified_queries_cache
                if q["classification"] == "correct"
            }

            if not correct_queries:
                return None

            # ── EMBEDDING PATH ─────────────────────────────────────────────
            if (
                self._embedding_ready
                and self._model is not None
                and self._embedding_matrix is not None
                and len(self._embedding_ids) > 0
            ):
                # Encode the incoming query
                query_vec = self._encode_batch([user_query])[0]   # (D,)

                # Filter matrix to only 'correct' rows
                correct_ids = list(correct_queries.keys())
                id_to_row   = {qid: idx for idx, qid in enumerate(self._embedding_ids)}

                valid_rows = [
                    id_to_row[qid]
                    for qid in correct_ids
                    if qid in id_to_row
                ]

                if not valid_rows:
                    # No correct queries have been indexed yet — fall through
                    pass
                else:
                    sub_matrix = self._embedding_matrix[valid_rows]     # (M, D)
                    scores     = _cosine_similarity_matrix(query_vec, sub_matrix)   # (M,)

                    best_local_idx = int(np.argmax(scores))
                    best_score     = float(scores[best_local_idx])

                    if best_score >= similarity_threshold:
                        best_qid   = correct_ids[best_local_idx]
                        best_match = correct_queries[best_qid]

                        logger.info(
                            f"🎯 Semantic match found (cosine={best_score:.3f}) | "
                            f"Query: '{user_query[:55]}…' ← '{best_match['user_query'][:55]}…'"
                        )
                        return {**best_match, "similarity_score": best_score}

                    logger.debug(
                        f"No semantic match above {similarity_threshold} "
                        f"(best={best_score:.3f})"
                    )
                    return None

            # ── FALLBACK: SequenceMatcher ───────────────────────────────────
            logger.debug("Using SequenceMatcher fallback for similarity")
            query_normalized = user_query.lower().strip()
            best_match = None
            best_score = 0.0

            for q in correct_queries.values():
                score = SequenceMatcher(
                    None, query_normalized, q["user_query"].lower().strip()
                ).ratio()
                if score > best_score and score >= similarity_threshold:
                    best_score = score
                    best_match = q

            if best_match:
                logger.info(f"🎯 SequenceMatcher match (score={best_score:.2f})")
                return {**best_match, "similarity_score": best_score}

            return None

        except Exception as e:
            logger.error(f"❌ Error finding similar query: {e}")
            return None

    # ------------------------------------------------------------------
    # PUBLIC: QUERIES / STATS
    # ------------------------------------------------------------------
    def get_unclassified_queries(self, limit: int = 50) -> List[Dict[str, Any]]:
        try:
            unclassified = [
                q for q in self.classified_queries_cache
                if q["classification"] == "unclassified"
            ]
            unclassified.sort(key=lambda x: x["timestamp"], reverse=True)
            return unclassified[:limit]
        except Exception as e:
            logger.error(f"❌ Error getting unclassified queries: {e}")
            return []

    def get_high_confidence_queries(
        self, min_confidence: float = 0.5, limit: int = 50
    ) -> List[Dict[str, Any]]:
        try:
            high_confidence = [
                q for q in self.classified_queries_cache
                if q.get("confidence", 0) >= min_confidence
            ]
            high_confidence.sort(
                key=lambda x: (-x.get("confidence", 0), x["timestamp"]), reverse=True
            )
            return high_confidence[:limit]
        except Exception as e:
            logger.error(f"❌ Error getting high confidence queries: {e}")
            return []

    def get_classification_stats(self) -> Dict[str, Any]:
        try:
            total = len(self.classified_queries_cache)
            stats = {
                "total_queries":    total,
                "correct":          0,
                "incorrect":        0,
                "needs_review":     0,
                "unclassified":     0,
                "accuracy":         0.0,
                "embedding_indexed": len(self._embedding_ids),
                "embedding_ready":   self._embedding_ready,
            }
            for q in self.classified_queries_cache:
                c = q["classification"]
                if c in stats:
                    stats[c] += 1
            classified_total = stats["correct"] + stats["incorrect"]
            if classified_total > 0:
                stats["accuracy"] = stats["correct"] / classified_total
            
            # Note: embedding_indexed should equal correct queries count
            stats["correct_queries_available"] = stats["correct"]
            
            return stats
        except Exception as e:
            logger.error(f"❌ Error getting stats: {e}")
            return {}

    def export_training_dataset(self, output_path: Path) -> bool:
        try:
            training_data = []
            for query in self.classified_queries_cache:
                if query["classification"] == "correct":
                    training_data.append({
                        "user_query":  query["user_query"],
                        "correct_sql": query["generated_sql"],
                        "tables_used": query["tables_used"],
                        "classification": "correct"
                    })
                elif query["classification"] == "incorrect" and query.get("corrected_sql"):
                    training_data.append({
                        "user_query":    query["user_query"],
                        "incorrect_sql": query["generated_sql"],
                        "correct_sql":   query["corrected_sql"],
                        "tables_used":   query["tables_used"],
                        "classification": "corrected",
                        "notes":         query.get("classification_notes")
                    })
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(training_data, f, indent=2)
            logger.info(f"✅ Exported {len(training_data)} training examples to {output_path}")
            return True
        except Exception as e:
            logger.error(f"❌ Error exporting training data: {e}")
            return False

    # ------------------------------------------------------------------
    # PRIVATE: LOAD / SAVE
    # ------------------------------------------------------------------
    def _load_classified_queries(self):
        try:
            if not self.queries_file.exists():
                logger.info("📁 No classified queries file found – will create on first store")
                return
            self.classified_queries_cache = []
            with open(self.queries_file, "r", encoding="utf-8-sig") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            self.classified_queries_cache.append(json.loads(line))
                        except json.JSONDecodeError as je:
                            logger.error(f"⚠️ Skipping invalid JSON line: {je}")
            logger.info(f"✅ Loaded {len(self.classified_queries_cache)} classified queries")
        except Exception as e:
            logger.error(f"❌ Error loading classified queries: {e}")
            self.classified_queries_cache = []

    def _load_patterns(self):
        try:
            if not self.patterns_file.exists():
                self.patterns_cache = {
                    "entity_table_patterns": {},
                    "intent_sql_patterns":   {},
                    "common_joins":          []
                }
                return
            with open(self.patterns_file, "r", encoding="utf-8") as f:
                self.patterns_cache = json.load(f)
        except Exception as e:
            logger.error(f"❌ Error loading patterns: {e}")
            self.patterns_cache = {}

    def _save_patterns(self):
        try:
            with open(self.patterns_file, "w", encoding="utf-8") as f:
                json.dump(self.patterns_cache, f, indent=2)
        except Exception as e:
            logger.error(f"❌ Error saving patterns: {e}")

    # ------------------------------------------------------------------
    # PRIVATE: LEARNING
    # ------------------------------------------------------------------
    def _learn_from_correct_query(self, query: Dict[str, Any]):
        try:
            user_query = query["user_query"].lower()
            sql        = query["generated_sql"]
            tables     = query["tables_used"]

            entities = self._extract_entities(user_query)
            for entity in entities:
                ep = self.patterns_cache["entity_table_patterns"]
                if entity not in ep:
                    ep[entity] = {}
                for table in tables:
                    ep[entity][table] = ep[entity].get(table, 0) + 1

            intent = self._detect_intent(user_query)
            if intent:
                ip = self.patterns_cache["intent_sql_patterns"]
                if intent not in ip:
                    ip[intent] = []
                ip[intent].append({
                    "query":       user_query[:100],
                    "sql_pattern": self._extract_sql_pattern(sql),
                    "tables":      tables
                })

            self._save_patterns()
            logger.debug(f"📚 Learned patterns from query: {query['query_id']}")
        except Exception as e:
            logger.error(f"❌ Error learning from query: {e}")

    # ------------------------------------------------------------------
    # PRIVATE: UTILS
    # ------------------------------------------------------------------
    def _extract_entities(self, query: str) -> List[str]:
        entities = []
        entity_keywords = {
            "bot":   ["bot", "robot", "agv", "agent"],
            "task":  ["task", "job", "assignment"],
            "bin":   ["bin", "location", "storage"],
            "order": ["order", "shipment", "delivery"],
            "sku":   ["sku", "article", "product", "item"]
        }
        for entity, keywords in entity_keywords.items():
            if any(kw in query for kw in keywords):
                entities.append(entity)
        return entities

    def _detect_intent(self, query: str) -> Optional[str]:
        if any(w in query for w in ["count", "how many", "number of"]):
            return "count"
        if any(w in query for w in ["list", "show", "get all", "give me"]):
            return "list"
        if any(w in query for w in ["completed", "finished", "done"]):
            return "historical"
        if any(w in query for w in ["current", "active", "running"]):
            return "current_state"
        return None

    def _extract_sql_pattern(self, sql: str) -> str:
        pattern = re.sub(r"'[^']*'", "'?'", sql)
        pattern = re.sub(r"\b\d+\b", "?", pattern)
        return pattern[:200]