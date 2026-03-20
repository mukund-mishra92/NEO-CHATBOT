"""
Tenant Resolver - Embedding-based host_location extraction
Uses semantic similarity for intelligent multi-tenant query support
"""
import numpy as np
from sentence_transformers import SentenceTransformer
from typing import Optional, Dict, List, Tuple
import json
import os
import logging
from pathlib import Path

logger = logging.getLogger(__name__)


class TenantResolver:
    """
    Embedding-based tenant/host_location extraction from natural language queries.
    Uses semantic similarity to match user queries to known tenant identifiers.
    Supports single and multi-tenant queries.
    """

    def __init__(self, data_dir: Path = None):
        """
        Initialize TenantResolver with sentence-transformers model.
        
        Args:
            data_dir: Directory to store embeddings (default: backend/data)
        """
        try:
            self.model = SentenceTransformer('all-MiniLM-L6-v2')
            logger.info("✅ Loaded sentence-transformers model for tenant extraction")
        except Exception as e:
            logger.error(f"❌ Failed to load sentence-transformers: {e}")
            self.model = None
        
        self.data_dir = data_dir or Path("data")
        self.embeddings_path = self.data_dir / "tenant_embeddings.npz"
        self.metadata_path = self.data_dir / "tenant_metadata.json"
        self.mappings_path = self.data_dir / "tenant_value_mappings.json"
        
        self.tenant_embeddings = None
        self.tenant_metadata = None
        self.predefined_mappings = self._load_predefined_mappings()
        
        if self.model:
            self._load_or_create_embeddings()

    def _load_predefined_mappings(self) -> Dict[str, str]:
        """Load predefined tenant value mappings from JSON configuration"""
        try:
            if self.mappings_path.exists():
                with open(self.mappings_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    mappings = config.get("mappings", {})
                    logger.info(f"✅ Loaded {len(mappings)} predefined tenant mappings")
                    return mappings
            else:
                logger.warning(f"⚠️ Mappings file not found: {self.mappings_path}")
                return {}
        except Exception as e:
            logger.error(f"❌ Failed to load tenant mappings: {e}")
            return {}

    def _load_or_create_embeddings(self):
        """Load pre-computed tenant embeddings or create new ones"""
        if self.embeddings_path.exists() and self.metadata_path.exists():
            try:
                data = np.load(str(self.embeddings_path))
                self.tenant_embeddings = data['embeddings']
                
                with open(self.metadata_path, 'r', encoding='utf-8') as f:
                    self.tenant_metadata = json.load(f)
                
                logger.info(f"✅ Loaded {len(self.tenant_metadata)} tenant variations from cache")
            except Exception as e:
                logger.warning(f"⚠️ Error loading embeddings: {e}. Creating new ones.")
                self._create_embeddings()
        else:
            logger.info("📝 Creating tenant embeddings for first time...")
            self._create_embeddings()

    def _create_embeddings(self):
        """
        Create embeddings for all known tenant variations.
        Expandable configuration for easy addition of new sites.
        """
        # 🔥 Comprehensive tenant variations - CUSTOMIZE FOR YOUR SITES
        tenant_variations = {
            # ===== FRK Site =====
            "FRK": [
                "frk", "frk location", "frk site", "frk warehouse", "frk plant",
                "at frk", "in frk", "from frk", "for frk",
                "frk facility", "frk depot", "f r k",
                # Faruknagar / Farrukhpur variants
                "faruknagar", "farruknagar", "farukhnagar",
                "faruk nagar", "farrukh nagar", "faruk",
                "at faruknagar", "in faruknagar", "from faruknagar",
                "faruknagar location", "faruknagar site", "faruknagar warehouse",
                "falcon", "falcon site", "falcon location",
            ],
            
            # ===== SHAKTI Site =====
            "SHAKTI": [
                "shakti", "shakti location", "shakti site", "shakti warehouse", 
                "shakti plant", "at shakti", "in shakti", "from shakti",
                "for shakti", "shakti facility", "shakti depot"
            ],
            
            # ===== Generic Site Variations =====
            "SITE_A": [
                "site a", "site-a", "sitea", "site 1", "first site",
                "warehouse a", "warehouse-a", "warehouse 1", "wh a",
                "plant a", "location a", "facility a", "depot a",
                "at site a", "in site a", "from site a"
            ],
            
            "SITE_B": [
                "site b", "site-b", "siteb", "site 2", "second site",
                "warehouse b", "warehouse-b", "warehouse 2", "wh b",
                "plant b", "location b", "facility b", "depot b",
                "at site b", "in site b", "from site b"
            ],
            
            "SITE_C": [
                "site c", "site-c", "sitec", "site 3", "third site",
                "warehouse c", "warehouse-c", "warehouse 3", "wh c",
                "plant c", "location c", "facility c", "depot c",
                "at site c", "in site c", "from site c"
            ],
            
            "SITE_D": [
                "site d", "site-d", "sited", "site 4", "fourth site",
                "warehouse d", "warehouse-d", "warehouse 4", "wh d",
                "plant d", "location d", "facility d", "depot d",
                "at site d", "in site d", "from site d"
            ],
            
            # ===== Location-based (if applicable) =====
            "MUMBAI": [
                "mumbai", "bombay", "mumbai warehouse", "mumbai site", 
                "mumbai plant", "mumbai location", "mumbai facility",
                "in mumbai", "at mumbai", "from mumbai", "mumbai depot"
            ],
            
            "DELHI": [
                "delhi", "new delhi", "delhi warehouse", "delhi site",
                "delhi plant", "delhi location", "delhi facility",
                "in delhi", "at delhi", "from delhi", "ncr"
            ],
            
            "BANGALORE": [
                "bangalore", "bengaluru", "bangalore warehouse", "bangalore site",
                "bangalore plant", "blr", "in bangalore", "at bangalore",
                "bengaluru facility"
            ],
            
            "PUNE": [
                "pune", "pune warehouse", "pune site", "pune plant",
                "pune location", "in pune", "at pune", "from pune"
            ]
        }

        # Flatten to list for embedding
        all_variations = []
        metadata = []

        for tenant_id, variations in tenant_variations.items():
            for variation in variations:
                all_variations.append(variation.lower())
                metadata.append({
                    "tenant_id": tenant_id,
                    "variation": variation.lower()
                })

        # Generate embeddings
        logger.info(f"🔄 Encoding {len(all_variations)} tenant variations...")
        embeddings = self.model.encode(all_variations, show_progress_bar=False)

        # Save
        self.data_dir.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(str(self.embeddings_path), embeddings=embeddings)
        
        with open(self.metadata_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2)

        self.tenant_embeddings = embeddings
        self.tenant_metadata = metadata
        
        unique_tenants = len(set(m['tenant_id'] for m in metadata))
        logger.info(f"✅ Created tenant embeddings: {unique_tenants} unique tenants")

    def _extract_location_phrase(self, query: str) -> str:
        """
        Extract location-specific phrase from query to improve matching.
        
        Examples:
            "total alarms at shakti site" → "at shakti site"
            "alarms logged at location bangalore" → "location bangalore"  
            "count in mumbai" → "in mumbai"
            "frk warehouse data" → "frk warehouse"
        
        Returns:
            Extracted location phrase or original query if no pattern found
        """
        import re
        query_lower = query.lower()
        
        # Patterns to extract location context (ordered by specificity)
        location_patterns = [
            r'(?:at|in|from|for)\s+(?:location\s+)?(\w+(?:\s+\w+){0,2})',  # "at location X", "in X"
            r'(?:location|site|warehouse|plant|facility)\s+(\w+)',          # "location X", "site X"
            r'(\w+)\s+(?:location|site|warehouse|plant|facility)',          # "X site", "X warehouse"
        ]
        
        for pattern in location_patterns:
            match = re.search(pattern, query_lower)
            if match:
                # Return the matched phrase with context
                return match.group(0)
        
        # If no pattern found, return original query
        return query_lower

    def _predefined_mapping_lookup(self, query_lower: str) -> Optional[str]:
        """
        Stage 0: Check predefined mappings before embedding.
        Scans the query for any known mapping key and returns the
        corresponding tenant_id (from tenant_metadata) immediately.
        
        This is the highest-priority path — explicit aliases always win.
        
        Returns tenant_id string if found, else None.
        """
        if not self.predefined_mappings:
            return None
        
        # Sort keys longest-first so "farrukh nagar" matches before "faruk"
        for mapping_key in sorted(self.predefined_mappings.keys(), key=len, reverse=True):
            if mapping_key in query_lower:
                mapped_db_value = self.predefined_mappings[mapping_key].lower()
                
                # Find the tenant_id in metadata whose lowercase matches the DB value
                tenant_ids = set(
                    m["tenant_id"] for m in (self.tenant_metadata or [])
                )
                for tid in tenant_ids:
                    if tid.lower() == mapped_db_value:
                        logger.info(
                            f"✅ Stage 0 predefined match: '{mapping_key}' → tenant_id='{tid}' "
                            f"(DB value: '{mapped_db_value}')"
                        )
                        return tid
        return None

    def extract_tenant(self, query: str, threshold: float = 0.65) -> Tuple[Optional[str], float, List[Dict]]:
        """
        Extract SINGLE tenant from query (for simple queries).
        
        Args:
            query: User's natural language query
            threshold: Minimum similarity score (0-1)
            
        Returns:
            (tenant_id, confidence_score, top_matches)
        """
        if not self.model or self.tenant_embeddings is None:
            logger.warning("⚠️ Tenant resolver not initialized, returning None")
            return None, 0.0, []
        
        query_lower = query.lower()

        # ── Stage 0: Predefined mapping fast-path (highest priority) ──────────
        predefined_tid = self._predefined_mapping_lookup(query_lower)
        if predefined_tid:
            return predefined_tid, 1.0, [{"tenant_id": predefined_tid, "variation": query_lower, "confidence": 1.0}]
        # ─────────────────────────────────────────────────────────────────────
        
        # 🔥 NEW: Extract location-specific phrase to improve matching
        location_phrase = self._extract_location_phrase(query_lower)
        
        # Use location phrase for embedding (falls back to full query if no pattern found)
        query_embedding = self.model.encode([location_phrase])[0]
        
        logger.debug(f"Location phrase: '{location_phrase}' (from: '{query_lower[:50]}...')")

        # Calculate cosine similarities
        similarities = np.dot(self.tenant_embeddings, query_embedding) / (
            np.linalg.norm(self.tenant_embeddings, axis=1) * np.linalg.norm(query_embedding)
        )

        # Get top 5 matches
        top_indices = np.argsort(similarities)[-5:][::-1]
        top_matches = [
            {
                "tenant_id": self.tenant_metadata[idx]["tenant_id"],
                "variation": self.tenant_metadata[idx]["variation"],
                "confidence": float(similarities[idx])
            }
            for idx in top_indices
        ]

        # Get best match
        best_match = top_matches[0]

        if best_match["confidence"] >= threshold:
            return best_match["tenant_id"], best_match["confidence"], top_matches
        else:
            return None, best_match["confidence"], top_matches

    def extract_all_tenants(self, query: str, threshold: float = 0.65) -> Tuple[List[str], List[Dict]]:
        """
        Extract ALL tenants mentioned in query (for multi-site queries).
        
        Args:
            query: User's natural language query
            threshold: Minimum similarity score
            
        Returns:
            (list_of_tenant_ids, all_matches_with_confidence)
        """
        if not self.model or self.tenant_embeddings is None:
            logger.warning("⚠️ Tenant resolver not initialized, returning empty list")
            return [], []
        
        query_lower = query.lower()

        # ── Stage 0: Predefined mapping fast-path ────────────────────────────
        predefined_tid = self._predefined_mapping_lookup(query_lower)
        if predefined_tid:
            return [predefined_tid], [{"tenant_id": predefined_tid, "confidence": 1.0}]
        # ─────────────────────────────────────────────────────────────────────
        
        # 🔥 NEW: Extract location-specific phrase to improve matching
        location_phrase = self._extract_location_phrase(query_lower)
        query_embedding = self.model.encode([location_phrase])[0]
        
        logger.debug(f"Location phrase: '{location_phrase}' (from: '{query_lower[:50]}...')")
        
        # Calculate similarities
        similarities = np.dot(self.tenant_embeddings, query_embedding) / (
            np.linalg.norm(self.tenant_embeddings, axis=1) * np.linalg.norm(query_embedding)
        )
        
        # Get ALL matches above threshold
        matches = []
        seen_tenants = {}  # tenant_id -> best confidence
        
        for idx, similarity in enumerate(similarities):
            if similarity >= threshold:
                tenant_id = self.tenant_metadata[idx]["tenant_id"]
                
                # Keep highest confidence for each tenant
                if tenant_id not in seen_tenants or similarity > seen_tenants[tenant_id]:
                    seen_tenants[tenant_id] = similarity
        
        # Build matches list
        for tenant_id, confidence in seen_tenants.items():
            matches.append({
                "tenant_id": tenant_id,
                "confidence": float(confidence)
            })
        
        # Sort by confidence
        matches.sort(key=lambda x: x["confidence"], reverse=True)
        tenant_ids = [m["tenant_id"] for m in matches]
        
        if tenant_ids:
            logger.info(f"🔍 Multi-tenant extraction: {tenant_ids}")
        
        return tenant_ids, matches

    def detect_multi_tenant_intent(self, query: str) -> bool:
        """
        Detect if query asks for multiple sites.
        Looks for conjunctions and comparison keywords.
        """
        multi_keywords = [
            " and ", " & ", " or ", " both ", " all sites", 
            " all locations", " across ", " between ", " all warehouses",
            " every ", " each site", " all plants", " all facilities",
            " compare ", " comparison ", " versus ", " vs ", " vs."
        ]
        
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in multi_keywords)

    def get_all_tenants(self) -> List[str]:
        """Get list of all unique tenant IDs"""
        if not self.tenant_metadata:
            return []
        return list(set(meta["tenant_id"] for meta in self.tenant_metadata))

    def add_tenant_variation(self, tenant_id: str, variations: List[str]):
        """
        Dynamically add new tenant variations (for learning from corrections).
        
        Args:
            tenant_id: The correct tenant identifier
            variations: List of new query phrases to associate with this tenant
        """
        if not self.model or self.tenant_metadata is None:
            logger.warning("⚠️ Cannot add variations, tenant resolver not initialized")
            return
        
        # Add to metadata
        for variation in variations:
            self.tenant_metadata.append({
                "tenant_id": tenant_id,
                "variation": variation.lower()
            })

        # Re-compute embeddings
        all_variations = [meta["variation"] for meta in self.tenant_metadata]
        self.tenant_embeddings = self.model.encode(all_variations, show_progress_bar=False)

        # Save updated
        np.savez_compressed(str(self.embeddings_path), embeddings=self.tenant_embeddings)
        with open(self.metadata_path, 'w', encoding='utf-8') as f:
            json.dump(self.tenant_metadata, f, indent=2)
        
        logger.info(f"✅ Added {len(variations)} new variations for tenant {tenant_id}")

    def fetch_actual_tenant_values(self, db_config: Dict, tenant_column: str, table_name: str = "bot_alarm_log") -> List[str]:
        """
        Query distinct values from the tenant column in the database.
        
        Args:
            db_config: Database connection configuration
            tenant_column: Column name (e.g., "host-location")
            table_name: Table to query (default: bot_alarm_log)
        
        Returns:
            List of distinct tenant values from database (e.g., ['FRK', 'BLR', 'SHAKTI'])
        """
        try:
            import mysql.connector
            
            conn = mysql.connector.connect(**db_config)
            cursor = conn.cursor()
            
            # Query distinct values (escape column name with backticks)
            query = f"SELECT DISTINCT `{tenant_column}` FROM {table_name} WHERE `{tenant_column}` IS NOT NULL"
            cursor.execute(query)
            
            # Fetch all distinct values
            results = cursor.fetchall()
            actual_values = [row[0] for row in results if row[0]]
            
            cursor.close()
            conn.close()
            
            logger.info(f"✅ Fetched {len(actual_values)} distinct tenant values from database: {actual_values}")
            return actual_values
            
        except Exception as e:
            logger.error(f"❌ Failed to fetch actual tenant values: {e}")
            return []

    def map_to_actual_value(self, extracted_tenant: str, actual_values: List[str], threshold: float = 0.5) -> Optional[str]:
        """
        Map extracted tenant name to actual database value using multiple strategies:
        1. Exact match (case-insensitive)
        2. Predefined mappings (e.g., "bangalore" → "BLR")
        3. Fuzzy string matching (for abbreviations)
        4. Embedding similarity (fallback)
        
        Examples:
            "BANGALORE" → "BLR"
            "SHAKTI" → "SHAKTI" (exact match)
            "MUMBAI" → "MUM"
        
        Args:
            extracted_tenant: Tenant extracted from query (e.g., "BANGALORE")
            actual_values: Distinct values from database (e.g., ["FRK", "BLR", "SHAKTI"])
            threshold: Minimum similarity score (0-1)
        
        Returns:
            Mapped database value or None if no match
        """
        if not actual_values:
            return None
        
        extracted_lower = extracted_tenant.lower()
        
        # ===== STRATEGY 1: EXACT MATCH (case-insensitive) =====
        for actual_value in actual_values:
            if actual_value.lower() == extracted_lower:
                logger.debug(f"✅ Exact match: '{extracted_tenant}' → '{actual_value}'")
                return actual_value
        
        # ===== STRATEGY 2: PREDEFINED MAPPINGS =====
        # Load from configuration file (backend/data/tenant_value_mappings.json)
        if self.predefined_mappings and extracted_lower in self.predefined_mappings:
            mapped_value = self.predefined_mappings[extracted_lower]
            # Verify it exists in actual values
            if mapped_value in actual_values:
                logger.info(f"✅ Mapped via predefined: '{extracted_tenant}' → '{mapped_value}'")
                return mapped_value
            else:
                logger.warning(f"⚠️ Predefined mapping '{extracted_tenant}'→'{mapped_value}' not in DB values")
        
        # ===== STRATEGY 3: FUZZY STRING MATCHING =====
        # Useful for partial matches and typos
        try:
            from difflib import SequenceMatcher
            
            best_ratio = 0.0
            best_match = None
            
            for actual_value in actual_values:
                # Try matching against actual value
                ratio = SequenceMatcher(None, extracted_lower, actual_value.lower()).ratio()
                
                if ratio > best_ratio:
                    best_ratio = ratio
                    best_match = actual_value
            
            # If fuzzy match is strong enough (>0.6), use it
            if best_ratio > 0.6:
                logger.info(f"✅ Fuzzy matched: '{extracted_tenant}' → '{best_match}' (ratio: {best_ratio:.3f})")
                return best_match
        
        except Exception as e:
            logger.debug(f"Fuzzy matching failed: {e}")
        
        # ===== STRATEGY 4: EMBEDDING SIMILARITY (fallback) =====
        if self.model:
            logger.debug(f"🔍 No match found, trying embeddings for '{extracted_tenant}'...")
            
            # Encode extracted tenant and actual values
            extracted_embedding = self.model.encode([extracted_lower])[0]
            actual_embeddings = self.model.encode([v.lower() for v in actual_values])
            
            # Calculate cosine similarities
            similarities = np.dot(actual_embeddings, extracted_embedding) / (
                np.linalg.norm(actual_embeddings, axis=1) * np.linalg.norm(extracted_embedding)
            )
            
            # Find best match
            best_idx = np.argmax(similarities)
            best_confidence = float(similarities[best_idx])
            best_match = actual_values[best_idx]
            
            if best_confidence >= threshold:
                logger.info(f"✅ Embedding matched: '{extracted_tenant}' → '{best_match}' (confidence: {best_confidence:.3f})")
                return best_match
        
        # No match found
        logger.warning(f"⚠️ No mapping found for '{extracted_tenant}'")
        return None
