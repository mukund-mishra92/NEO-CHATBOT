"""
Intent Classification Service
Classifies user queries into the correct chatbot service:
  - knowledge_base: Documentation, manuals, code, features, how-things-work questions
  - sql_assistant: Data queries, KPIs, metrics, counts, reports, database lookups
  - semi_auto_diagnostic: Problem reports, troubleshooting, bot issues, errors, something not working
"""

import logging
import re
import time
import json
from typing import Dict, Optional, Tuple

from .llm_service import LLMService

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Keyword / pattern heuristics (fast path – no LLM call needed)
# ---------------------------------------------------------------------------

# Semi-auto diagnostic patterns: problems, errors, troubleshooting
_DIAGNOSTIC_PATTERNS = [
    # Bot problems
    r"\bbot\s*\d+\b.*\b(not\s+moving|stuck|stopped|error|fault|issue|problem|offline|down)\b",
    r"\b(not\s+moving|stuck|stopped|offline|down|jammed|fault|malfunction|failure)\b.*\bbot\b",
    r"\bbot[-\s]?\d+\b.*\b(battery|charging|navigation|obstacle|collision)\b",
    # Equipment failures  
    r"\b(conveyor|belt|station|charger|sensor|motor|wheel)\b.*\b(jammed|stuck|broken|not\s+working|failed|error|fault|issue|problem)\b",
    r"\b(jammed|stuck|broken|not\s+working|failed|error|fault)\b.*\b(conveyor|belt|station|charger|sensor|motor|wheel)\b",
    # Troubleshooting language
    r"\b(troubleshoot|diagnose|diagnos(is|tic)|fix|repair|resolve|debug)\b.*\b(bot|station|conveyor|error|issue|problem|fault)\b",
    r"\b(bot|station|conveyor|system)\b.*\b(troubleshoot|diagnose|fix|repair|resolve)\b",
    # Error/issue descriptions
    r"\b(error\s+code|alarm|alert|warning)\b\s*[:# ]?\s*\w+",
    r"\b(something|it|system|bot)\s+(is|isn't|isnt|is\s+not)\s+(wrong|broken|down|failing|not\s+working)\b",
    r"\bwhy\s+(is|isn't|does|doesn't)\s+(the\s+)?(bot|station|conveyor|system)\b.*\b(work|move|respond|charging|running)\b",
    # SOP-related
    r"\bsop\b",
    r"\bstep[\s-]?by[\s-]?step\b.*\b(diagnos|troubleshoot|fix|resolve)\b",
]

# SQL assistant patterns: data queries, KPIs, metrics
_SQL_PATTERNS = [
    # Direct KPI/metric language
    r"\b(throughput|tph|utilization|idle\s*time|inactive\s*hours?|uptime|downtime|efficiency|productivity|ipp)\b",
    r"\b(kpi|metric|average|total|count|sum|min|max|rate|percentage|ratio)\b",
    # Data query language
    r"\b(how\s+many|how\s+much|what\s+is\s+the|what\s+are\s+the|show\s+me|get\s+me|give\s+me|list\s+all|display|fetch|retrieve)\b.*\b(data|number|count|total|orders?|bots?|picks?|puts?|tasks?|stations?|transactions?)\b",
    r"\b(show|get|give|list|display|fetch|retrieve|find|pull)\b.*\b(data|report|numbers?|stats?|statistics?|results?|records?)\b",
    # Time-range queries
    r"\b(today|yesterday|last\s+week|last\s+month|this\s+week|this\s+month|past\s+\d+\s+(hours?|days?|weeks?|months?))\b.*\b(data|throughput|orders?|picks?|puts?|bots?|kpi|metric|count)\b",
    r"\b(data|throughput|orders?|picks?|puts?|bots?|kpi|metric|count)\b.*\b(today|yesterday|last\s+week|last\s+month|from|between|since)\b",
    # Database entities
    r"\b(orders?\s+fulfil|fulfilment|fulfillment|pick\s+rate|put\s+rate|order\s+rate)\b",
    r"\b(active\s+bots?|bot\s+status|fleet\s+status|bot\s+count)\b",
    r"\b(per\s+hour|per\s+day|per\s+shift|per\s+bot|per\s+station)\b",
    # SQL-specific
    r"\b(query|sql|database|table|column|report|dashboard)\b.*\b(data|result|run|execute|generate)\b",
    # Comparison/ranking
    r"\b(compare|comparison|rank|ranking|top\s+\d+|bottom\s+\d+|best|worst|highest|lowest)\b.*\b(bot|station|throughput|kpi|performance)\b",
]

# Knowledge base patterns: documentation, how things work, features
_KB_PATTERNS = [
    # Documentation questions
    r"\b(what\s+is|what\s+are|explain|describe|tell\s+me\s+about|how\s+does|how\s+do|how\s+to)\b.*\b(neo|system|module|feature|function|class|method|service|component|architecture)\b",
    r"\b(documentation|manual|guide|tutorial|reference|specification|proposal)\b",
    # Code questions
    r"\b(code|class|method|function|implementation|interface|api|endpoint|module|namespace)\b.*\b(show|explain|describe|find|where|how)\b",
    r"\b(show|explain|describe|find|where|how)\b.*\b(code|class|method|function|implementation|source)\b",
    r"\b(c#|csharp|\.net|dotnet|python)\b.*\b(code|class|method|function|implementation)\b",
    # General knowledge questions
    r"\b(what|which|where|who|when)\b.*\b(is|are|was|were|does|do)\b.*\b(neo|fleet|manager|conveyor|system|warehouse|robot)\b",
    r"\b(safety|guideline|procedure|protocol|best\s+practice|standard)\b",
    r"\b(can\s+you\s+explain|please\s+explain|i\s+want\s+to\s+know|i\s+need\s+to\s+understand)\b",
]

# Compile all patterns for efficiency
_DIAGNOSTIC_COMPILED = [re.compile(p, re.IGNORECASE) for p in _DIAGNOSTIC_PATTERNS]
_SQL_COMPILED = [re.compile(p, re.IGNORECASE) for p in _SQL_PATTERNS]
_KB_COMPILED = [re.compile(p, re.IGNORECASE) for p in _KB_PATTERNS]


# ---------------------------------------------------------------------------
# LLM classification prompt
# ---------------------------------------------------------------------------

_CLASSIFICATION_SYSTEM_PROMPT = """You are an intent classifier for the NEO Fleet Manager chatbot system.
Your job is to classify user queries into exactly ONE of three categories:

1. **knowledge_base** — The user is asking about documentation, how things work, features, code, 
   system architecture, manuals, guides, SOPs (informational only), safety procedures, or general 
   knowledge about the NEO system. These are "tell me about X" or "how does X work" questions.

2. **sql_assistant** — The user wants DATA from the database: KPIs, metrics, counts, reports, 
   statistics, throughput numbers, bot activity data, order fulfillment rates, utilization %, etc.
   These are "show me the numbers" or "what is today's throughput" questions. If the user asks for
   any specific quantity, number, metric, or data report, choose this.

3. **semi_auto_diagnostic** — The user is reporting a PROBLEM, describing an ERROR, or asking for 
   help TROUBLESHOOTING something that is broken or not working correctly. Examples: "Bot 1234 is 
   not moving", "conveyor belt jammed", "station error code E-401", "why isn't the charger working".
   These are "something is wrong, help me fix it" queries.

Rules:
- If the query mentions a specific problem, fault, error, or something not working → semi_auto_diagnostic
- If the query asks for data, numbers, metrics, KPIs, or reports → sql_assistant
- If the query asks how something works, what something is, or for documentation → knowledge_base
- For greetings like "hi", "hello", "hey" → knowledge_base (the KB service handles general chat)
- If ambiguous between sql_assistant and knowledge_base, prefer sql_assistant if numbers/data are requested
- If ambiguous between semi_auto_diagnostic and knowledge_base, look for problem indicators (not working, error, fault, stuck, broken)

Respond with ONLY a JSON object in this exact format:
{"intent": "<category>", "confidence": <0.0-1.0>, "reasoning": "<brief explanation>"}

Do NOT include any other text outside the JSON object."""

_CLASSIFICATION_FEW_SHOT = [
    {"role": "user", "content": "What is the throughput for today?"},
    {"role": "assistant", "content": '{"intent": "sql_assistant", "confidence": 0.95, "reasoning": "Asking for throughput data for today - this is a KPI/metric query"}'},
    {"role": "user", "content": "Bot 1234 is not moving"},
    {"role": "assistant", "content": '{"intent": "semi_auto_diagnostic", "confidence": 0.97, "reasoning": "Reporting a specific bot problem - bot not moving, needs troubleshooting"}'},
    {"role": "user", "content": "How does the NEO conveyor system work?"},
    {"role": "assistant", "content": '{"intent": "knowledge_base", "confidence": 0.95, "reasoning": "Asking for an explanation of how the system works - informational question"}'},
    {"role": "user", "content": "Show me the pick rate for last week at FRK"},
    {"role": "assistant", "content": '{"intent": "sql_assistant", "confidence": 0.96, "reasoning": "Requesting specific data (pick rate) for a time period - database query"}'},
    {"role": "user", "content": "Station 5 conveyor belt is jammed"},
    {"role": "assistant", "content": '{"intent": "semi_auto_diagnostic", "confidence": 0.98, "reasoning": "Reporting equipment problem - conveyor belt jammed, needs diagnostic"}'},
    {"role": "user", "content": "What is NEO Fleet Manager?"},
    {"role": "assistant", "content": '{"intent": "knowledge_base", "confidence": 0.96, "reasoning": "Asking what the system is - general knowledge/documentation question"}'},
    {"role": "user", "content": "How many active bots are there right now?"},
    {"role": "assistant", "content": '{"intent": "sql_assistant", "confidence": 0.93, "reasoning": "Asking for a count of active bots - this requires a database query"}'},
    {"role": "user", "content": "Error code E-401 on charger station 3"},
    {"role": "assistant", "content": '{"intent": "semi_auto_diagnostic", "confidence": 0.97, "reasoning": "Reporting an error code on equipment - needs troubleshooting"}'},
    {"role": "user", "content": "Explain the bot navigation algorithm"},
    {"role": "assistant", "content": '{"intent": "knowledge_base", "confidence": 0.94, "reasoning": "Asking for technical explanation of an algorithm - documentation question"}'},
    {"role": "user", "content": "IPP for all bots today"},
    {"role": "assistant", "content": '{"intent": "sql_assistant", "confidence": 0.95, "reasoning": "Requesting IPP (Items Per Pick) metric data - KPI query"}'},
    {"role": "user", "content": "The system is showing an alarm and bots have stopped"},
    {"role": "assistant", "content": '{"intent": "semi_auto_diagnostic", "confidence": 0.96, "reasoning": "Describing a system alarm with stopped bots - active problem needing diagnosis"}'},
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": '{"intent": "knowledge_base", "confidence": 0.90, "reasoning": "Greeting - routed to knowledge_base which handles general conversation"}'},
]


class IntentClassifier:
    """
    Classifies user queries to determine which chatbot service should handle them.
    
    Uses a two-tier approach:
    1. Fast keyword/regex heuristics for confident matches (no LLM cost)
    2. LLM-based classification for ambiguous queries
    """

    # Confidence threshold: if heuristic score >= this, skip LLM
    HEURISTIC_CONFIDENCE_THRESHOLD = 0.80
    
    # If heuristic produces multiple high-scoring categories, use LLM
    HEURISTIC_AMBIGUITY_GAP = 0.3  # Minimum gap between top and second choice

    def __init__(self):
        self.llm_service = LLMService()
        logger.info("✅ IntentClassifier initialized")

    def classify(self, query: str) -> Dict:
        """
        Classify a user query into one of the three service categories.
        
        Args:
            query: The user's message text
            
        Returns:
            Dict with keys:
              - intent: str ("knowledge_base", "sql_assistant", "semi_auto_diagnostic")
              - confidence: float (0.0 - 1.0)
              - method: str ("heuristic" or "llm")
              - reasoning: str
        """
        start_time = time.time()
        query_clean = query.strip()
        
        # Handle empty/trivial queries
        if not query_clean or len(query_clean) < 2:
            return {
                "intent": "knowledge_base",
                "confidence": 0.90,
                "method": "default",
                "reasoning": "Empty or trivial query - routed to knowledge_base"
            }

        # Tier 1: Heuristic classification
        heuristic_result = self._heuristic_classify(query_clean)
        
        if heuristic_result:
            top_intent, top_score = heuristic_result[0]
            second_score = heuristic_result[1][1] if len(heuristic_result) > 1 else 0.0
            gap = top_score - second_score
            
            if top_score >= self.HEURISTIC_CONFIDENCE_THRESHOLD and gap >= self.HEURISTIC_AMBIGUITY_GAP:
                elapsed = time.time() - start_time
                logger.info(
                    f"🎯 Intent classified (heuristic, {elapsed:.3f}s): "
                    f"{top_intent} ({top_score:.2f}) for: '{query_clean[:80]}...'"
                )
                return {
                    "intent": top_intent,
                    "confidence": min(top_score, 0.95),  # Cap heuristic confidence
                    "method": "heuristic",
                    "reasoning": f"Keyword match: {top_intent} (score={top_score:.2f}, gap={gap:.2f})"
                }
        
        # Tier 2: LLM classification
        llm_result = self._llm_classify(query_clean)
        elapsed = time.time() - start_time
        logger.info(
            f"🎯 Intent classified (LLM, {elapsed:.3f}s): "
            f"{llm_result['intent']} ({llm_result['confidence']:.2f}) for: '{query_clean[:80]}...'"
        )
        return llm_result

    def _heuristic_classify(self, query: str) -> list:
        """
        Score the query against keyword patterns for each category.
        Returns sorted list of (intent, score) tuples.
        """
        scores = {
            "semi_auto_diagnostic": self._pattern_score(query, _DIAGNOSTIC_COMPILED),
            "sql_assistant": self._pattern_score(query, _SQL_COMPILED),
            "knowledge_base": self._pattern_score(query, _KB_COMPILED),
        }
        
        # Sort by score descending
        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        return ranked
    
    def _pattern_score(self, query: str, patterns: list) -> float:
        """
        Calculate a confidence score based on how many patterns match.
        Returns a score between 0.0 and 1.0.
        """
        if not patterns:
            return 0.0
        
        matches = sum(1 for p in patterns if p.search(query))
        
        if matches == 0:
            return 0.0
        
        # Scoring: first match gives 0.60, each additional adds diminishing returns
        # 1 match → 0.60, 2 → 0.75, 3 → 0.85, 4+ → 0.90+
        if matches == 1:
            return 0.60
        elif matches == 2:
            return 0.75
        elif matches == 3:
            return 0.85
        else:
            return min(0.95, 0.85 + (matches - 3) * 0.03)

    def _llm_classify(self, query: str) -> Dict:
        """
        Use LLM to classify the query when heuristics are insufficient.
        """
        try:
            messages = list(_CLASSIFICATION_FEW_SHOT)  # Copy few-shot examples
            messages.append({"role": "user", "content": query})
            
            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt=_CLASSIFICATION_SYSTEM_PROMPT,
                max_tokens=150,
                temperature=0.0  # Deterministic classification
            )
            
            # Parse JSON response
            result = self._parse_llm_response(response)
            if result:
                return {
                    "intent": result["intent"],
                    "confidence": result.get("confidence", 0.85),
                    "method": "llm",
                    "reasoning": result.get("reasoning", "LLM classification")
                }
            
            # Fallback if parsing fails
            logger.warning(f"⚠️ Could not parse LLM classification response: {response[:200]}")
            return {
                "intent": "knowledge_base",
                "confidence": 0.50,
                "method": "llm_fallback",
                "reasoning": f"LLM response unparseable, defaulting to knowledge_base"
            }
            
        except Exception as e:
            logger.error(f"❌ LLM classification failed: {e}")
            # Fall back to best heuristic or default
            heuristic = self._heuristic_classify(query)
            if heuristic and heuristic[0][1] > 0.0:
                return {
                    "intent": heuristic[0][0],
                    "confidence": heuristic[0][1] * 0.8,  # Discount without LLM confirmation
                    "method": "heuristic_fallback",
                    "reasoning": f"LLM failed, using heuristic: {heuristic[0][0]}"
                }
            return {
                "intent": "knowledge_base",
                "confidence": 0.40,
                "method": "error_fallback",
                "reasoning": f"All classification failed, defaulting to knowledge_base"
            }
    
    def _parse_llm_response(self, response: str) -> Optional[Dict]:
        """Parse the JSON response from the LLM classifier."""
        try:
            # Try direct JSON parse
            result = json.loads(response.strip())
            if self._validate_result(result):
                return result
        except json.JSONDecodeError:
            pass
        
        # Try extracting JSON from the response text
        try:
            json_match = re.search(r'\{[^}]+\}', response)
            if json_match:
                result = json.loads(json_match.group())
                if self._validate_result(result):
                    return result
        except (json.JSONDecodeError, AttributeError):
            pass
        
        return None
    
    def _validate_result(self, result: Dict) -> bool:
        """Validate the classification result has the expected format."""
        valid_intents = {"knowledge_base", "sql_assistant", "semi_auto_diagnostic"}
        return (
            isinstance(result, dict)
            and result.get("intent") in valid_intents
            and isinstance(result.get("confidence", 0), (int, float))
        )


# ---------------------------------------------------------------------------
# Singleton accessor
# ---------------------------------------------------------------------------

_classifier_instance: Optional[IntentClassifier] = None


def get_intent_classifier() -> IntentClassifier:
    """Get or create the singleton IntentClassifier instance."""
    global _classifier_instance
    if _classifier_instance is None:
        _classifier_instance = IntentClassifier()
    return _classifier_instance
