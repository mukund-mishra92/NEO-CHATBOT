from typing import Tuple, Dict, List, Any
from .synonym_resolver import SynonymResolver
from .entity_resolver import EntityResolver
from .tenant_resolver import TenantResolver
from app.core.config import settings
import logging
import re

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
            - For single tenant: {"host_location": ["SITE_A"], "_multi_tenant": False}
            - For multi tenant: {"host_location": ["FRK", "SHAKTI"], "_multi_tenant": True}
            - For all sites: {"host_location": ["FRK", "SHAKTI", ...], "_all_sites": True}
        """
        # Step 1: Normalize date/time phrases and extract date/time entities
        normalized_question = self._normalize_date_phrases(question)
        normalized_question = self._normalize_time_phrases(normalized_question)

        entities = self.entity_resolver.resolve(normalized_question)

        # Extract date/time entities for downstream logic
        # IMPORTANT: Always set these keys, even if empty, so downstream validation works
        try:
            extracted_dates = self._extract_dates(normalized_question)
        except Exception as e:
            logger.warning(f"⚠️ Date extraction error: {e}. Continuing without dates.")
            extracted_dates = []
        entities["requested_dates"] = extracted_dates

        try:
            extracted_times = self._extract_times(normalized_question)
        except Exception as e:
            logger.warning(f"⚠️ Time extraction error: {e}. Continuing without times.")
            extracted_times = []
        entities["requested_times"] = extracted_times

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
            # Lower bar for 'any signal' — catches known-location words that scored below threshold
            # 0.30 prevents generic words ('system', 'today', 'current') from falsely matching
            low_signal_threshold = 0.30
            tenant_id, confidence, top_matches = self.tenant_resolver.extract_tenant(question, threshold=threshold)
            
            if tenant_id and confidence >= threshold:
                entities[settings.TENANT_COLUMN] = [tenant_id]
                entities["_multi_tenant"] = False
                entities["_all_sites"] = False
                entities["_tenant_confidence"] = {tenant_id: confidence}
                logger.info(f"✅ Single tenant: {tenant_id} (confidence: {confidence:.2f})")
            elif top_matches and top_matches[0]["confidence"] >= low_signal_threshold:
                # User mentioned something that looks like a location but scored below threshold.
                # Use the best candidate instead of falling back to _apply_default_tenant,
                # which could incorrectly go all-sites when "how many/total" is in the query.
                best = top_matches[0]
                entities[settings.TENANT_COLUMN] = [best["tenant_id"]]
                entities["_multi_tenant"] = False
                entities["_all_sites"] = False
                entities["_tenant_confidence"] = {best["tenant_id"]: best["confidence"]}
                logger.warning(
                    f"⚠️ Low confidence match used: {best['tenant_id']} "
                    f"(score: {best['confidence']:.2f}, threshold: {threshold}). "
                    f"Location was mentioned — skipping all-sites fallback."
                )
            else:
                # No location signal at all — use smart aggregate or default
                logger.warning(f"⚠️ No location detected (best confidence: {confidence:.2f}). Applying default strategy.")
                logger.debug(f"Top matches: {top_matches[:3]}")
                self._apply_default_tenant(entities, question)

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
        """
        breakdown_keywords = [
            "per location", "per site", "location-wise", "site-wise", "by location",
            "breakdown by location", "split by site", "group by location", "by host-location"
        ]
        return any(keyword in query_lower for keyword in breakdown_keywords)

    def _normalize_date_phrases(self, text: str) -> str:
        """Normalize date phrases like 'seventh april' to '7 april'."""
        ordinals = {
            "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
            "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
            "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
            "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
            "nineteenth": 19, "twentieth": 20, "twenty first": 21, "twenty-first": 21,
            "twenty second": 22, "twenty-second": 22, "twenty third": 23,
            "twenty-third": 23, "twenty fourth": 24, "twenty-fourth": 24,
            "twenty fifth": 25, "twenty-fifth": 25, "twenty sixth": 26,
            "twenty-sixth": 26, "twenty seventh": 27, "twenty-seventh": 27,
            "twenty eighth": 28, "twenty-eighth": 28, "twenty ninth": 29,
            "twenty-ninth": 29, "thirtieth": 30, "thirty first": 31,
            "thirty-first": 31
        }

        def repl(match):
            key = match.group(0).lower()
            return str(ordinals.get(key, key))

        pattern = r"\b(" + "|".join(re.escape(k) for k in ordinals.keys()) + r")\b"
        return re.sub(pattern, repl, text, flags=re.IGNORECASE)

    def _extract_dates(self, text: str) -> List[str]:
        """Extract candidate dates from question and return ISO strings."""
        try:
            from dateutil import parser as dateutil_parser
        except ImportError:
            logger.error("⚠️ dateutil not available for date extraction")
            return []

        res = []

        # Normalize to replace ordinals (e.g., 'seventh april' -> '7 april')
        normalized = self._normalize_date_phrases(text)
        
        # Also clean up numeric ordinals like "23th" -> "23"
        # Handles patterns like 1st, 2nd, 3rd, 4th, 21st, 23rd, etc.
        normalized = re.sub(r'\b(\d{1,2})(?:st|nd|rd|th)\b', r'\1', normalized, flags=re.IGNORECASE)

        # Known date token patterns
        patterns = [
            r"\b\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{4}\b",
            r"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2},?\s+\d{4}\b",
            r"\b\d{4}-\d{2}-\d{2}\b",
            r"\b\d{1,2}/\d{1,2}/\d{4}\b",
            r"\b\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b",
        ]

        candidates = []
        for p in patterns:
            try:
                candidates += re.findall(p, normalized, flags=re.IGNORECASE)
            except Exception as e:
                logger.debug(f"Date pattern {p} failed: {e}")
                continue

        # Keep unique and preserve order
        seen = set()
        for item in candidates:
            normalized_item = item.strip()
            if normalized_item.lower() in seen:
                continue
            seen.add(normalized_item.lower())
            try:
                dt = dateutil_parser.parse(normalized_item, dayfirst=True, yearfirst=False, fuzzy=True)
                iso = dt.date().isoformat()
                res.append(iso)
                logger.debug(f"✅ Extracted date: {normalized_item} → {iso}")
            except Exception as e:
                # Catch ALL exceptions
                logger.debug(f"⚠️ Could not parse date '{normalized_item}': {type(e).__name__}: {e}")
                continue

        return res

    def _is_location_breakdown_query(self, query_lower: str) -> bool:
        """
        Detect if query asks for a BREAKDOWN/GROUPING by location.

        Examples:
            - "segregate this location wise"
            - "group by location"
            - "breakdown by site"
            - "per location stats"
            - "location-wise count"
            - "split by location"
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

    def _normalize_time_phrases(self, text: str) -> str:
        """Normalize common time phrases to numeric timestamps."""
        try:
            repl = {
                "midnight": "00:00",
                "noon": "12:00",
                "half past": "30 minutes past",
                "quarter past": "15 minutes past",
                "quarter to": "45 minutes to",
                "at night": "PM",
                "in the morning": "AM",
                "in the evening": "PM",
                "in the afternoon": "PM",
            }

            output = text
            for key, val in repl.items():
                try:
                    output = re.sub(rf"\b{re.escape(key)}\b", val, output, flags=re.IGNORECASE)
                except Exception as e:
                    logger.debug(f"Failed to normalize '{key}': {e}")
                    continue

            # normalize 12-hour times without minutes ("3 pm" -> "3:00 pm")
            output = re.sub(r"\b(\d{1,2})\s*(am|pm)\b", r"\1:00 \2", output, flags=re.IGNORECASE)

            # normalize 24-hour without seconds ("1530" -> "15:30") for explicit run-together patterns
            output = re.sub(r"\b(\d{2})(\d{2})\b", r"\1:\2", output)

            return output
        except Exception as e:
            logger.warning(f"⚠️ Time phrase normalization error: {e}. Returning original text.")
            return text

    def _extract_times(self, text: str) -> List[str]:
        """Extract times from question and return HH:MM (24-hour) strings."""
        try:
            from dateutil import parser as dateutil_parser
        except ImportError:
            logger.error("⚠️ dateutil not available for time extraction")
            return []

        res = []

        # time patterns include hh:mm, h:mm am/pm, hh am/pm
        patterns = [
            r"\b\d{1,2}:\d{2}\s*(?:am|pm|AM|PM)?\b",
            r"\b\d{1,2}\s*(?:am|pm|AM|PM)\b",
            r"\b\d{1,2}:\d{2}\b",
        ]

        candidates = []
        for p in patterns:
            try:
                candidates += re.findall(p, text, flags=re.IGNORECASE)
            except Exception as e:
                logger.debug(f"Pattern {p} failed: {e}")
                continue

        seen = set()
        for item in candidates:
            normalized_item = item.strip()
            if normalized_item.lower() in seen:
                continue
            seen.add(normalized_item.lower())
            try:
                dt = dateutil_parser.parse(normalized_item, fuzzy=True)
                time_iso = dt.time().strftime("%H:%M")
                res.append(time_iso)
                logger.debug(f"✅ Extracted time: {normalized_item} → {time_iso}")
            except Exception as e:
                # Catch ALL exceptions: ValueError, OverflowError, ParserError, TypeError, etc.
                logger.debug(f"⚠️ Could not parse time '{normalized_item}': {type(e).__name__}: {e}")
                continue

        return res

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
