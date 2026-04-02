from typing import Tuple, Dict, List, Any
from .synonym_resolver import SynonymResolver
from .entity_resolver import EntityResolver
from .tenant_resolver import TenantResolver
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)


class QueryPreprocessor:
    """
    Runs normalization steps before SQL generation.
    Supports both single and multi-tenant query processing with embedding-based extraction.
    """

    def __init__(self):
        self.synonym_resolver = SynonymResolver()
        self.entity_resolver = EntityResolver()
        
        # Only initialize if multi-tenant mode is enabled
        if settings.MULTI_TENANT_ENABLED:
            try:
                self.tenant_resolver = TenantResolver(data_dir=settings.DATA_DIR)
                logger.info("✅ Multi-tenant mode ENABLED with embedding-based extraction")
            except Exception as e:
                logger.error(f"❌ Failed to initialize TenantResolver: {e}")
                self.tenant_resolver = None
        else:
            self.tenant_resolver = None
            logger.info("ℹ️ Multi-tenant mode DISABLED")

    def process(self, question: str) -> Tuple[str, Dict[str, Any]]:
        """
        Process user query with intelligent tenant extraction.
        
        Returns:
            (normalized_question, entities_dict)
            
        entities_dict structure:
            - For single tenant: {"host_location": ["FRK"], "_multi_tenant": False}
            - For multi tenant: {"host_location": ["FRK", "SHAKTI"], "_multi_tenant": True}
            - For all sites: {"host_location": ["FRK", "SHAKTI", ...], "_all_sites": True}
        """
        # Step 1: Entity extraction (SKUs, dates, etc.)
        entities = self.entity_resolver.resolve(question)

        # --------------------------------------------------
        # 🔥 STEP 2: TENANT EXTRACTION (Multi-tenant aware)
        # --------------------------------------------------
        if settings.MULTI_TENANT_ENABLED and self.tenant_resolver:
            self._extract_tenants(question, entities)
        else:
            # Single-tenant mode: no host_location filtering
            entities["_multi_tenant"] = False
            logger.debug("Single-tenant mode: no location filtering applied")

        # Step 3: Substitute canonical IDs (SKU normalization, etc.)
        substituted = self.entity_resolver.substitute(question, entities)

        # Step 4: Synonym normalization
        final_question = self.synonym_resolver.normalize(substituted)

        return final_question, entities

    def _extract_tenants(self, question: str, entities: Dict[str, Any]):
        """
        Extract tenant(s) from query with support for:
        - Single site queries: "Show alarms at FRK"
        - Multi-site queries: "Compare FRK and SHAKTI"
        - All sites queries: "Show across all locations"
        - Location breakdown queries: "segregate location wise"
        """
        question_lower = question.lower()
        
        # --------------------------------------------------
        # 🔥 CASE 1: "ALL SITES" Query
        # --------------------------------------------------
        if self._is_all_sites_query(question_lower):
            all_tenants = self.tenant_resolver.get_all_tenants()
            entities[settings.TENANT_COLUMN] = all_tenants
            entities["_multi_tenant"] = True
            entities["_all_sites"] = True
            logger.info(f"✅ All sites query detected: {len(all_tenants)} sites")
            return

        # --------------------------------------------------
        # 🔥 CASE 1b: LOCATION BREAKDOWN Query (segregate/group-by/location-wise)
        # These are cross-location queries where user wants data split PER location
        # --------------------------------------------------
        if self._is_location_breakdown_query(question_lower):
            all_tenants = self.tenant_resolver.get_all_tenants()
            entities[settings.TENANT_COLUMN] = all_tenants
            entities["_multi_tenant"] = True
            entities["_all_sites"] = True
            entities["_location_breakdown"] = True  # Hint: GROUP BY host-location
            logger.info(f"✅ Location breakdown query detected: will GROUP BY {settings.TENANT_COLUMN}")
            return

        # --------------------------------------------------
        # 🔥 CASE 2: MULTI-SITE Query (AND/OR/COMPARE)
        # --------------------------------------------------
        is_multi_tenant = self.tenant_resolver.detect_multi_tenant_intent(question)
        
        if is_multi_tenant:
            threshold = settings.TENANT_EXTRACTION_THRESHOLD
            tenant_ids, matches = self.tenant_resolver.extract_all_tenants(question, threshold=threshold)
            
            if tenant_ids:
                entities[settings.TENANT_COLUMN] = tenant_ids
                entities["_multi_tenant"] = True
                entities["_all_sites"] = False
                logger.info(f"✅ Multi-tenant query: {tenant_ids}")
                
                # Store confidence for logging
                entities["_tenant_confidence"] = {m["tenant_id"]: m["confidence"] for m in matches}
            else:
                # No tenants found in multi-tenant context
                self._apply_default_tenant(entities, question)

        # --------------------------------------------------
        # 🔥 CASE 3: SINGLE-SITE Query
        # --------------------------------------------------
        else:
            threshold = settings.TENANT_EXTRACTION_THRESHOLD
            tenant_id, confidence, top_matches = self.tenant_resolver.extract_tenant(question, threshold=threshold)
            
            if tenant_id and confidence >= threshold:
                entities[settings.TENANT_COLUMN] = [tenant_id]
                entities["_multi_tenant"] = False
                entities["_all_sites"] = False
                entities["_tenant_confidence"] = {tenant_id: confidence}
                logger.info(f"✅ Single tenant: {tenant_id} (confidence: {confidence:.2f})")
            else:
                # Do not force a guessed site when extraction confidence is below threshold.
                # Fall back to all-sites to avoid silently narrowing the query to the wrong tenant.
                if self.tenant_resolver:
                    all_tenants = self.tenant_resolver.get_all_tenants()
                    entities[settings.TENANT_COLUMN] = all_tenants
                    entities["_multi_tenant"] = True
                    entities["_all_sites"] = True
                    if top_matches:
                        best = top_matches[0]
                        logger.warning(
                            f"⚠️ Low-confidence tenant detection ignored: {best['tenant_id']} "
                            f"(score: {best['confidence']:.2f}, threshold: {threshold}). "
                            f"Falling back to all-sites."
                        )
                    else:
                        logger.warning(
                            f"⚠️ No location detected (best confidence: {confidence:.2f}). Falling back to all-sites."
                        )
                else:
                    logger.warning(f"⚠️ No location detected (best confidence: {confidence:.2f}). Applying default strategy.")
                    self._apply_default_tenant(entities, question)
                logger.debug(f"Top matches: {top_matches[:3]}")

    def _is_all_sites_query(self, query_lower: str) -> bool:
        """Check if query asks for all sites/locations"""
        all_sites_keywords = [
            "all sites", "all locations", "all warehouses", "all plants",
            "all facilities", "every site", "every location", "every warehouse",
            "across all", "company-wide", "organization-wide", "entire network",
            "in the system", "in our system", "in the entire system",
            "whole system", "entire system", "system wide", "system-wide",
        ]
        return any(keyword in query_lower for keyword in all_sites_keywords)

    def _is_location_breakdown_query(self, query_lower: str) -> bool:
        """
        Detect if query asks for a BREAKDOWN/GROUPING by location.
        These are queries where user wants data separated per location.

        Examples:
            - "segregate this location wise"  → True
            - "group by location"             → True
            - "breakdown by site"             → True
            - "per location stats"            → True
            - "location-wise count"           → True
            - "split by location"             → True
        """
        breakdown_keywords = [
            "location wise", "location-wise", "locationwise",
            "site wise", "site-wise", "sitewise",
            "per location", "per site",
            "by location", "by site",
            "group by location", "group by site",
            "segregate", "breakdown by", "break down by",
            "split by location", "split by site",
            "each location", "each site",
            "location-level", "site-level",
            "location based", "site based",
        ]
        return any(keyword in query_lower for keyword in breakdown_keywords)
    
    def _is_aggregate_query(self, query_lower: str) -> bool:
        """
        Detect if query is asking for aggregate/summary data that typically spans all sites.
        
        Production logic: Identifies queries with aggregate intent (total, count, sum, average)
        that should return data across ALL sites when no specific location is mentioned.
        
        Examples:
            - "total number of alarms today" → True (aggregate query)
            - "show alarm code 1234" → False (specific query)
            - "count all bots" → True (aggregate query)
            - "average response time" → True (aggregate query)
            - "list bot names" → False (specific query)
        
        Args:
            query_lower: Lowercased user query
            
        Returns:
            bool: True if query has aggregate intent
        """
        # Count/Total keywords - queries asking "how many" or "what's the total"
        count_keywords = [
            "total", "grand total", "overall total", "total number", "total count",
            "count", "count of", "count all", "how many", "number of",
            "quantity", "quantity of"
        ]
        
        # Aggregation function keywords - mathematical operations
        aggregation_keywords = [
            "sum", "sum of", "combined", "aggregate", "aggregated",
            "average", "mean", "avg", "median",
            "maximum", "max", "minimum", "min",
            "statistics", "stats", "summary", "report"
        ]
        
        # All-inclusive keywords - queries across entire dataset
        inclusive_keywords = [
            "all", "entire", "whole", "complete", "every",
            "organization", "company", "global", "overall"
        ]
        
        # Comparative keywords - usually need data from multiple sites
        comparative_keywords = [
            "compare", "comparison", "versus", "vs", "vs.",
            "difference between", "differences", "contrast"
        ]
        
        # Trend/Analysis keywords - typically cross-site analysis
        analysis_keywords = [
            "trend", "trending", "pattern", "analysis",
            "distribution", "breakdown", "overview"
        ]
        
        # Combine all keyword categories
        aggregate_patterns = (
            count_keywords + 
            aggregation_keywords + 
            inclusive_keywords + 
            comparative_keywords + 
            analysis_keywords
        )
        
        # Check if any aggregate keyword present in query
        has_aggregate_keyword = any(keyword in query_lower for keyword in aggregate_patterns)
        
        # Additional heuristic: Detect SQL aggregate functions mentioned
        sql_aggregates = ["count(", "sum(", "avg(", "max(", "min(", "group by"]
        has_sql_aggregate = any(agg in query_lower for agg in sql_aggregates)
        
        return has_aggregate_keyword or has_sql_aggregate

    def _apply_default_tenant(self, entities: Dict[str, Any], question: str):
        """
        Apply default tenant strategy based on configured behavior.
        
        Production-grade logic with three modes:
        1. "smart_aggregate": Uses ALL sites for aggregate queries, DEFAULT_TENANT for specific queries
        2. "all_sites": Always uses ALL sites when location not specified
        3. "default_only": Always uses DEFAULT_TENANT (strict mode)
        
        This implements intelligent business logic that matches user intent:
        - "total alarms today" → ALL sites (user wants organization-wide total)
        - "show alarm 1234" → DEFAULT_TENANT (user wants specific record)
        
        Args:
            entities: Dictionary to populate with tenant information
            question: Original user query for intent analysis
        """
        behavior = settings.TENANT_DEFAULT_BEHAVIOR
        question_lower = question.lower()
        
        logger.debug(f"🔍 Applying default tenant strategy: {behavior}")
        
        # ============================================================
        # MODE 1: SMART AGGREGATE (RECOMMENDED for production)
        # ============================================================
        if behavior == "smart_aggregate":
            # Intelligent decision: Detect if query asks for aggregate/summary data
            if self._is_aggregate_query(question_lower):
                # Query has aggregate intent → Use ALL sites
                if self.tenant_resolver:
                    all_tenants = self.tenant_resolver.get_all_tenants()
                    entities[settings.TENANT_COLUMN] = all_tenants
                    entities["_multi_tenant"] = True
                    entities["_all_sites"] = True
                    logger.info(
                        f"🧠 Smart aggregate detected: Using ALL {len(all_tenants)} sites "
                        f"(Query: '{question[:60]}...')\n"
                        f"   Reason: Aggregate keywords detected in query"
                    )
                else:
                    logger.warning("⚠️ TenantResolver not available, falling back to default tenant")
                    self._apply_single_default_tenant(entities)
            else:
                # Specific/detailed query → Use DEFAULT_TENANT only
                self._apply_single_default_tenant(entities)
                logger.info(
                    f"📍 Specific query detected: Using default tenant ({settings.DEFAULT_TENANT})\n"
                    f"   Reason: No aggregate keywords found"
                )
        
        # ============================================================
        # MODE 2: ALL SITES (Always query all locations)
        # ============================================================
        elif behavior == "all_sites":
            if self.tenant_resolver:
                all_tenants = self.tenant_resolver.get_all_tenants()
                entities[settings.TENANT_COLUMN] = all_tenants
                entities["_multi_tenant"] = True
                entities["_all_sites"] = True
                logger.info(f"🌐 All-sites mode: Using ALL {len(all_tenants)} sites (forced by config)")
            else:
                logger.warning("⚠️ TenantResolver not available, falling back to default tenant")
                self._apply_single_default_tenant(entities)
        
        # ============================================================
        # MODE 3: DEFAULT ONLY (Strict single-tenant mode)
        # ============================================================
        else:  # default_only
            if settings.DEFAULT_TENANT:
                self._apply_single_default_tenant(entities)
                logger.info(f"📍 Default-only mode: Using {settings.DEFAULT_TENANT} (forced by config)")
            else:
                # STRICT MODE: No fallback, require explicit site mention
                if self.tenant_resolver:
                    available_sites = self.tenant_resolver.get_all_tenants()
                    raise ValueError(
                        f"Could not determine site/location from query. "
                        f"Please specify one of: {', '.join(available_sites)}"
                    )
                else:
                    raise ValueError("Could not determine site/location and no default configured.")
    
    def _apply_single_default_tenant(self, entities: Dict[str, Any]):
        """Helper method to apply single default tenant.
        
        Note: We keep the case as-is from settings.DEFAULT_TENANT.
        The downstream _map_tenant_to_actual_values() step will resolve
        it to the exact DB value via embedding similarity.
        """
        entities[settings.TENANT_COLUMN] = [settings.DEFAULT_TENANT]
        entities["_multi_tenant"] = False
        entities["_all_sites"] = False
