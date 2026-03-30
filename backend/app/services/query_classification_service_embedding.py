"""
Enhanced Query Classification Service with Embedding-Based Similarity

This version implements:
1. Semantic similarity using sentence-transformers embeddings
2. Proper bifurcation between reviewed and unreviewed queries
3. Only reuses user-verified "correct" queries
4. Backward compatible with existing data
5. Falls back to SequenceMatcher if embeddings unavailable

Key Improvements:
- Added "user_reviewed" field to track manual review status
- Only "correct" AND "user_reviewed" queries are used for similarity matching
- Vectorized similarity search for better performance
- Persistent embedding cache for fast startup

Dependencies:
    pip install sentence-transformers numpy scikit-learn
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

# Embedding model configuration
EMBEDDING_MODEL_NAME = "all-MiniLM-L6-v2"  # 22MB, 384-dim, fast inference


class QueryClassificationServiceEmbedding:
    """
    Enhanced query classification service with embedding-based similarity search.
    
    Features:
    - Semantic similarity via embeddings (cosine similarity)
    - User review tracking to prevent unverified query reuse
    - Pattern learning from successful queries
    - Graceful fallback to SequenceMatcher
    - Persistent embedding cache
    """
    
    def __init__(self, storage_path: Path):
        """Initialize the service"""
        self.storage_path = storage_path
        self.storage_path.mkdir(parents=True, exist_ok=True)
        
        # File paths
        self.queries_file = self.storage_path / "classified_queries.jsonl"
        self.patterns_file = self.storage_path / "learned_patterns.json"
        # Centralised embeddings folder
        _embeddings_dir = self.storage_path.parent / "embeddings"
        _embeddings_dir.mkdir(parents=True, exist_ok=True)
        self.embeddings_file = _embeddings_dir / "query_embeddings.npz"
        
        # In-memory caches
        self.classified_queries_cache: List[Dict[str, Any]] = []
        self.patterns_cache: Dict = {}
        
        # Embedding state
        self._model = None
        self._embedding_matrix: Optional[np.ndarray] = None
        self._embedding_ids: List[str] = []
        self._embedding_ready = False
        
        # Load data
        self._load_classified_queries()
        self._load_patterns()
        self._init_embedding_model()
        
        logger.info(
            f"✅ QueryClassificationService (Embedding Edition) initialized\n"
            f"   - Total queries: {len(self.classified_queries_cache)}\n"
            f"   - User reviewed: {sum(1 for q in self.classified_queries_cache if q.get('user_reviewed', False))}\n"
            f"   - Correct & reviewed: {sum(1 for q in self.classified_queries_cache if q.get('classification') == 'correct' and q.get('user_reviewed', False))}\n"
            f"   - Embedding ready: {self._embedding_ready}\n"
            f"   - Indexed embeddings: {len(self._embedding_ids)}"
        )
    
    # ═══════════════════════════════════════════════════════════════════════
    # EMBEDDING MODEL INITIALIZATION
    # ═══════════════════════════════════════════════════════════════════════
    
    def _init_embedding_model(self):
        """Load sentence-transformers model and build/restore embedding index"""
        try:
            from sentence_transformers import SentenceTransformer
            
            logger.info(f"⏳ Loading embedding model: {EMBEDDING_MODEL_NAME}...")
            self._model = SentenceTransformer(EMBEDDING_MODEL_NAME)
            self._embedding_ready = True
            logger.info(f"✅ Embedding model loaded successfully")
            
            # Try to restore persisted embeddings
            restored = self._load_embeddings_from_disk()
            
            # Compute embeddings for any new queries
            self._build_missing_embeddings()
            
        except ImportError:
            logger.warning(
                "⚠️  sentence-transformers not installed. "
                "Falling back to SequenceMatcher.\n"
                "Install: pip install sentence-transformers"
            )
        except Exception as e:
            logger.warning(f"⚠️  Could not load embedding model: {e}. Using SequenceMatcher fallback.")
    
    def _load_embeddings_from_disk(self) -> bool:
        """Load saved embedding matrix from disk"""
        if not self.embeddings_file.exists():
            logger.debug("No saved embeddings found - will build fresh")
            return False
        
        try:
            data = np.load(str(self.embeddings_file), allow_pickle=True)
            self._embedding_matrix = data["matrix"]
            self._embedding_ids = data["ids"].tolist()
            logger.info(f"💾 Restored {len(self._embedding_ids)} embeddings from disk")
            return True
        except Exception as e:
            logger.warning(f"⚠️  Could not load saved embeddings: {e}")
            return False
    
    def _save_embeddings_to_disk(self):
        """Persist embedding matrix to disk"""
        if self._embedding_matrix is None or len(self._embedding_ids) == 0:
            return
        
        try:
            np.savez_compressed(
                str(self.embeddings_file),
                matrix=self._embedding_matrix,
                ids=np.array(self._embedding_ids, dtype=object)
            )
            logger.debug(f"💾 Saved {len(self._embedding_ids)} embeddings to disk")
        except Exception as e:
            logger.warning(f"⚠️  Could not save embeddings: {e}")
    
    def _build_missing_embeddings(self):
        """Compute embeddings for queries not yet in the index"""
        if not self._embedding_ready:
            return
        
        indexed_ids = set(self._embedding_ids)
        
        # Only index user-reviewed queries (to save computation)
        missing = [
            q for q in self.classified_queries_cache
            if q["query_id"] not in indexed_ids and q.get("user_reviewed", False)
        ]
        
        if not missing:
            logger.debug("No new queries to index")
            return
        
        logger.info(f"🔄 Computing embeddings for {len(missing)} new queries...")
        
        texts = [q["user_query"] for q in missing]
        ids = [q["query_id"] for q in missing]
        
        vecs = self._encode_batch(texts)
        self._append_to_index(ids, vecs)
        self._save_embeddings_to_disk()
        
        logger.info(f"✅ Embedding index now has {len(self._embedding_ids)} entries")
    
    def _append_to_index(self, ids: List[str], vecs: np.ndarray):
        """Append new vectors to the embedding index"""
        if self._embedding_matrix is None:
            self._embedding_matrix = vecs
            self._embedding_ids = list(ids)
        else:
            self._embedding_matrix = np.vstack([self._embedding_matrix, vecs])
            self._embedding_ids.extend(ids)
    
    def _add_single_to_index(self, query_id: str, text: str):
        """Add a single query to the embedding index"""
        if not self._embedding_ready:
            return
        
        try:
            vec = self._encode_batch([text])
            self._append_to_index([query_id], vec)
            self._save_embeddings_to_disk()
        except Exception as e:
            logger.warning(f"⚠️  Could not index embedding for {query_id}: {e}")
    
    def _encode_batch(self, texts: List[str]) -> np.ndarray:
        """
        Encode a list of strings into embeddings.
        Returns normalized (L2) embeddings for cosine similarity via dot product.
        """
        vecs = self._model.encode(
            texts,
            batch_size=64,
            show_progress_bar=False,
            convert_to_numpy=True,
            normalize_embeddings=True  # L2 normalize → cosine = dot product
        )
        return vecs.astype(np.float32)
    
    # ═══════════════════════════════════════════════════════════════════════
    # PUBLIC API - STORE
    # ═══════════════════════════════════════════════════════════════════════
    
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
        """
        Store a query with its generated SQL.
        
        IMPORTANT: Stored queries are marked as NOT reviewed by default.
        They will NOT be used for similarity matching until manually classified.
        """
        try:
            query_id = f"{session_id}_{datetime.now().strftime('%Y%m%d%H%M%S%f')}"
            
            query_record = {
                "query_id": query_id,
                "timestamp": datetime.now().isoformat(),
                "session_id": session_id,
                "user_query": user_query,
                "generated_sql": generated_sql,
                "execution_status": execution_status,
                "rows_returned": rows_returned,
                "confidence": confidence,
                "tables_used": tables_used,
                "classification": "unclassified",
                "user_reviewed": False,  # KEY CHANGE: Not reviewed yet
                "classification_timestamp": None,
                "classification_notes": None,
                "corrected_sql": None,
                "metadata": metadata or {}
            }
            
            # Append to file
            with open(self.queries_file, "a", encoding="utf-8") as f:
                f.write(json.dumps(query_record, ensure_ascii=False) + "\n")
            
            # Update cache
            self.classified_queries_cache.append(query_record)
            
            # Do NOT index embedding yet (wait for user review)
            
            logger.info(f"📝 Stored query {query_id} (awaiting review)")
            return query_id
            
        except Exception as e:
            logger.error(f"❌ Error storing query: {e}")
            return ""
    
    # ═══════════════════════════════════════════════════════════════════════
    # PUBLIC API - CLASSIFY
    # ═══════════════════════════════════════════════════════════════════════
    
    def classify_query(
        self,
        query_id: str,
        classification: str,
        notes: Optional[str] = None,
        corrected_sql: Optional[str] = None
    ) -> bool:
        """
        Manually classify a query.
        
        This marks the query as user_reviewed=True and enables it for similarity matching
        if classified as 'correct'.
        """
        try:
            valid_classifications = ['correct', 'incorrect', 'needs_review']
            if classification not in valid_classifications:
                logger.error(f"Invalid classification: {classification}")
                return False
            
            # Read all queries
            queries = []
            with open(self.queries_file, "r", encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        queries.append(json.loads(line))
            
            # Find and update the query
            updated = False
            target_query = None
            
            for query in queries:
                if query['query_id'] == query_id:
                    query['classification'] = classification
                    query['user_reviewed'] = True  # KEY CHANGE: Mark as reviewed
                    query['classification_timestamp'] = datetime.now().isoformat()
                    query['classification_notes'] = notes
                    if corrected_sql:
                        query['corrected_sql'] = corrected_sql
                    updated = True
                    target_query = query
                    break
            
            if not updated:
                logger.warning(f"Query {query_id} not found")
                return False
            
            # Write back to file
            with open(self.queries_file, "w", encoding="utf-8") as f:
                for query in queries:
                    f.write(json.dumps(query, ensure_ascii=False) + "\n")
            
            # Reload cache
            self._load_classified_queries()
            
            # If classified as correct, index the embedding and learn patterns
            if classification == 'correct' and target_query:
                self._add_single_to_index(query_id, target_query['user_query'])
                self._learn_from_correct_query(target_query)
            
            logger.info(f"✅ Query {query_id} classified as: {classification} (user_reviewed=True)")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error classifying query: {e}")
            return False
    
    # ═══════════════════════════════════════════════════════════════════════
    # PUBLIC API - FIND SIMILAR (CORE METHOD)
    # ═══════════════════════════════════════════════════════════════════════
    
    def find_similar_classified_query(
        self,
        user_query: str,
        similarity_threshold: float = 0.85
    ) -> Optional[Dict[str, Any]]:
        """
        Find a semantically similar query that is:
        1. Classified as 'correct'
        2. Marked as user_reviewed=True
        
        This ensures only verified, correct queries are reused.
        
        Uses embedding-based cosine similarity if available, otherwise falls back
        to SequenceMatcher.
        
        Args:
            user_query: The incoming user query
            similarity_threshold: Minimum similarity score (0.0-1.0)
                                 For embeddings: 0.85 is recommended
                                 For SequenceMatcher: 0.80-0.90 works well
        
        Returns:
            Best matching query dict with 'similarity_score' added, or None
        """
        try:
            # Filter to correct AND user-reviewed queries only
            correct_and_reviewed = {
                q["query_id"]: q
                for q in self.classified_queries_cache
                if q["classification"] == "correct" and q.get("user_reviewed", False)
            }
            
            if not correct_and_reviewed:
                logger.debug("No correct & reviewed queries available for matching")
                return None
            
            # ─── EMBEDDING-BASED PATH ───────────────────────────────────────
            if (
                self._embedding_ready
                and self._model is not None
                and self._embedding_matrix is not None
                and len(self._embedding_ids) > 0
            ):
                # Encode incoming query
                query_vec = self._encode_batch([user_query])[0]  # (D,)
                
                # Filter index to only correct & reviewed queries
                valid_ids = list(correct_and_reviewed.keys())
                id_to_idx = {qid: i for i, qid in enumerate(self._embedding_ids)}
                
                valid_indices = [
                    id_to_idx[qid]
                    for qid in valid_ids
                    if qid in id_to_idx
                ]
                
                if not valid_indices:
                    logger.debug("No embeddings indexed for correct & reviewed queries yet")
                    # Fall through to SequenceMatcher
                else:
                    # Get submatrix of valid embeddings
                    sub_matrix = self._embedding_matrix[valid_indices]  # (M, D)
                    
                    # Vectorized cosine similarity (already normalized, so dot product)
                    scores = sub_matrix.dot(query_vec)  # (M,)
                    
                    best_local_idx = int(np.argmax(scores))
                    best_score = float(scores[best_local_idx])
                    
                    if best_score >= similarity_threshold:
                        best_qid = valid_ids[best_local_idx]
                        best_match = correct_and_reviewed[best_qid]
                        
                        logger.info(
                            f"🎯 Semantic match found (score={best_score:.3f})\n"
                            f"   Query: '{user_query[:60]}...'\n"
                            f"   Match: '{best_match['user_query'][:60]}...'"
                        )
                        
                        return {**best_match, "similarity_score": best_score}
                    
                    logger.debug(f"No semantic match above threshold (best={best_score:.3f})")
                    return None
            
            # ─── FALLBACK: SequenceMatcher ──────────────────────────────────
            logger.debug("Using SequenceMatcher fallback")
            query_normalized = user_query.lower().strip()
            best_match = None
            best_score = 0.0
            
            for q in correct_and_reviewed.values():
                score = SequenceMatcher(
                    None,
                    query_normalized,
                    q["user_query"].lower().strip()
                ).ratio()
                
                if score > best_score and score >= similarity_threshold:
                    best_score = score
                    best_match = q
            
            if best_match:
                logger.info(f"🎯 SequenceMatcher match (score={best_score:.3f})")
                return {**best_match, "similarity_score": best_score}
            
            return None
            
        except Exception as e:
            logger.error(f"❌ Error finding similar query: {e}")
            return None
    
    # ═══════════════════════════════════════════════════════════════════════
    # PUBLIC API - QUERIES & STATS
    # ═══════════════════════════════════════════════════════════════════════
    
    def get_unclassified_queries(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get queries awaiting classification (user_reviewed=False)"""
        try:
            unclassified = [
                q for q in self.classified_queries_cache
                if not q.get("user_reviewed", False)
            ]
            unclassified.sort(key=lambda x: x["timestamp"], reverse=True)
            return unclassified[:limit]
        except Exception as e:
            logger.error(f"❌ Error getting unclassified queries: {e}")
            return []
    
    def get_high_confidence_queries(
        self, min_confidence: float = 0.5, limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get high-confidence queries for review"""
        try:
            high_conf = [
                q for q in self.classified_queries_cache
                if q.get("confidence", 0) >= min_confidence
            ]
            high_conf.sort(
                key=lambda x: (-x.get("confidence", 0), x["timestamp"]),
                reverse=True
            )
            return high_conf[:limit]
        except Exception as e:
            logger.error(f"❌ Error getting high confidence queries: {e}")
            return []
    
    def get_classification_stats(self) -> Dict[str, Any]:
        """Get classification statistics"""
        try:
            total = len(self.classified_queries_cache)
            stats = {
                "total_queries": total,
                "user_reviewed": sum(1 for q in self.classified_queries_cache if q.get("user_reviewed", False)),
                "awaiting_review": sum(1 for q in self.classified_queries_cache if not q.get("user_reviewed", False)),
                "correct": sum(1 for q in self.classified_queries_cache if q["classification"] == "correct"),
                "incorrect": sum(1 for q in self.classified_queries_cache if q["classification"] == "incorrect"),
                "needs_review": sum(1 for q in self.classified_queries_cache if q["classification"] == "needs_review"),
                "correct_and_reviewed": sum(1 for q in self.classified_queries_cache 
                                           if q["classification"] == "correct" and q.get("user_reviewed", False)),
                "embedding_ready": self._embedding_ready,
                "embeddings_indexed": len(self._embedding_ids),
            }
            
            classified_total = stats["correct"] + stats["incorrect"]
            stats["accuracy"] = stats["correct"] / classified_total if classified_total > 0 else 0.0
            
            return stats
        except Exception as e:
            logger.error(f"❌ Error getting stats: {e}")
            return {}
    
    def export_training_dataset(self, output_path: Path) -> bool:
        """Export correct queries as training data"""
        try:
            training_data = []
            
            for query in self.classified_queries_cache:
                if query["classification"] == "correct" and query.get("user_reviewed", False):
                    training_data.append({
                        "user_query": query["user_query"],
                        "correct_sql": query["generated_sql"],
                        "tables_used": query["tables_used"],
                        "confidence": query.get("confidence", 0),
                        "classification": "correct"
                    })
                elif query["classification"] == "incorrect" and query.get("corrected_sql"):
                    training_data.append({
                        "user_query": query["user_query"],
                        "incorrect_sql": query["generated_sql"],
                        "correct_sql": query["corrected_sql"],
                        "tables_used": query["tables_used"],
                        "classification": "corrected",
                        "notes": query.get("classification_notes")
                    })
            
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(training_data, f, indent=2, ensure_ascii=False)
            
            logger.info(f"✅ Exported {len(training_data)} training examples to {output_path}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error exporting training data: {e}")
            return False
    
    # ═══════════════════════════════════════════════════════════════════════
    # PRIVATE - DATA LOADING
    # ═══════════════════════════════════════════════════════════════════════
    
    def _load_classified_queries(self):
        """Load queries from disk, migrating old format if needed"""
        try:
            if not self.queries_file.exists():
                logger.info("📁 No queries file found - will create on first store")
                return
            
            self.classified_queries_cache = []
            needs_migration = False
            
            with open(self.queries_file, "r", encoding="utf-8-sig") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            query = json.loads(line)
                            
                            # Migrate old format: add user_reviewed field if missing
                            if "user_reviewed" not in query:
                                # If already classified (not unclassified), assume it was reviewed
                                query["user_reviewed"] = query.get("classification") != "unclassified"
                                needs_migration = True
                            
                            self.classified_queries_cache.append(query)
                        except json.JSONDecodeError as e:
                            logger.warning(f"⚠️  Skipping invalid JSON line: {e}")
            
            logger.info(f"✅ Loaded {len(self.classified_queries_cache)} queries")
            
            # Save migrated data
            if needs_migration:
                logger.info("🔄 Migrating old query format to include user_reviewed field...")
                with open(self.queries_file, "w", encoding="utf-8") as f:
                    for query in self.classified_queries_cache:
                        f.write(json.dumps(query, ensure_ascii=False) + "\n")
                logger.info("✅ Migration complete")
                
        except Exception as e:
            logger.error(f"❌ Error loading queries: {e}")
            self.classified_queries_cache = []
    
    def _load_patterns(self):
        """Load learned patterns from disk"""
        try:
            if not self.patterns_file.exists():
                self.patterns_cache = {
                    "entity_table_patterns": {},
                    "intent_sql_patterns": {},
                    "common_joins": []
                }
                return
            
            with open(self.patterns_file, "r", encoding="utf-8") as f:
                self.patterns_cache = json.load(f)
                
        except Exception as e:
            logger.error(f"❌ Error loading patterns: {e}")
            self.patterns_cache = {}
    
    def _save_patterns(self):
        """Save learned patterns to disk"""
        try:
            with open(self.patterns_file, "w", encoding="utf-8") as f:
                json.dump(self.patterns_cache, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error(f"❌ Error saving patterns: {e}")
    
    # ═══════════════════════════════════════════════════════════════════════
    # PRIVATE - LEARNING
    # ═══════════════════════════════════════════════════════════════════════
    
    def _learn_from_correct_query(self, query: Dict[str, Any]):
        """Extract patterns from a correct query"""
        try:
            user_query = query["user_query"].lower()
            sql = query["generated_sql"]
            tables = query["tables_used"]
            
            # Extract entities
            entities = self._extract_entities(user_query)
            for entity in entities:
                if entity not in self.patterns_cache["entity_table_patterns"]:
                    self.patterns_cache["entity_table_patterns"][entity] = {}
                for table in tables:
                    count = self.patterns_cache["entity_table_patterns"][entity].get(table, 0)
                    self.patterns_cache["entity_table_patterns"][entity][table] = count + 1
            
            # Extract intent
            intent = self._detect_intent(user_query)
            if intent:
                if intent not in self.patterns_cache["intent_sql_patterns"]:
                    self.patterns_cache["intent_sql_patterns"][intent] = []
                
                self.patterns_cache["intent_sql_patterns"][intent].append({
                    "query": user_query[:100],
                    "sql_pattern": self._extract_sql_pattern(sql),
                    "tables": tables
                })
            
            self._save_patterns()
            logger.debug(f"📚 Learned patterns from query: {query['query_id']}")
            
        except Exception as e:
            logger.error(f"❌ Error learning from query: {e}")
    
    def _extract_entities(self, query: str) -> List[str]:
        """Extract entity types from query"""
        entities = []
        entity_keywords = {
            "bot": ["bot", "robot", "agv", "agent"],
            "task": ["task", "job", "assignment"],
            "bin": ["bin", "location", "storage"],
            "order": ["order", "shipment", "delivery"],
            "sku": ["sku", "article", "product", "item"],
            "station": ["station", "workstation"],
            "wave": ["wave", "pick", "put"],
        }
        
        for entity, keywords in entity_keywords.items():
            if any(kw in query for kw in keywords):
                entities.append(entity)
        
        return entities
    
    def _detect_intent(self, query: str) -> Optional[str]:
        """Detect query intent"""
        if any(w in query for w in ["count", "how many", "number of"]):
            return "count"
        if any(w in query for w in ["list", "show", "get all", "give me", "display"]):
            return "list"
        if any(w in query for w in ["completed", "finished", "done"]):
            return "historical"
        if any(w in query for w in ["current", "active", "running"]):
            return "current_state"
        return None
    
    def _extract_sql_pattern(self, sql: str) -> str:
        """Extract SQL pattern by replacing values with placeholders"""
        pattern = re.sub(r"'[^']*'", "'?'", sql)
        pattern = re.sub(r"\b\d+\b", "?", pattern)
        return pattern[:200]
