"""
Knowledge Base Service - Document Q&A using RAG (Retrieval-Augmented Generation)
Answers questions about NEO documentation, code, and proposals
"""

import logging
import re
import json
import time
import uuid
from typing import List, Dict, Any, Optional
from pathlib import Path
from .vector_store_service import VectorStoreService
from .content_optimizer import ContentOptimizer
from .response_cache import ResponseCache
from .query_analytics import QueryAnalytics
from app.services.llm_service import LLMService  # shared llm_service at services root
from ..rlhf_service import RLHFService
from ..diagnostic.diagnostic_support_service import DiagnosticSupportService
from ..answer_planner import AnswerPlanner
from ..response_structurer import ResponseStructurer
from ...prompts.prompt_registry import registry as prompt_registry
from ...models.schemas import ChatRequest, ChatResponse, SourceDocument, ChatbotType, MessageRole
from ...utils.session_manager import get_session_manager, SessionType
from ...core.config import settings

# RAG Pipeline (ChromaDB-backed hybrid retrieval)
try:
    from app.ingetion.pipeline import RAGPipeline
    RAG_AVAILABLE = True
except ImportError:
    RAG_AVAILABLE = False

logger = logging.getLogger(__name__)


class KnowledgeBaseService:
    """
    Service for Knowledge Base Chatbot
    Uses RAG to answer questions about NEO documentation
    """
    
    def __init__(self):
        """Initialize knowledge base service"""
        self.llm_service = LLMService()
        self.vector_store = VectorStoreService()  # Legacy JSON vector store (fallback)
        self.rlhf_service = RLHFService()
        self.diagnostic_service = DiagnosticSupportService()  # Add diagnostic support
        self.session_manager = get_session_manager()
        self.answer_planner = AnswerPlanner()  # Phase 7: structured answer planning
        self.response_structurer = ResponseStructurer()  # Phase 8: structured response format

        # ── New: Content Optimizer, Response Cache, Analytics ──
        self.content_optimizer = ContentOptimizer(self.llm_service)
        self.response_cache = ResponseCache(ttl_seconds=3600)  # 1-hour TTL
        self.query_analytics = QueryAnalytics()

        # ── ChromaDB RAG Pipeline (primary retrieval) ──
        self.rag_pipeline = None
        if RAG_AVAILABLE:
            try:
                from pathlib import Path
                chroma_dir = str(Path(__file__).resolve().parents[4] / "data" / "chroma_db")
                self.rag_pipeline = RAGPipeline(
                    chroma_persist_dir=chroma_dir,
                    enable_images=settings.MULTIMODAL_IMAGES_ENABLED,
                    enable_ocr=False,
                    llm_service=self.llm_service,
                    max_display_images=settings.MULTIMODAL_MAX_DISPLAY_IMAGES,
                    enable_vision_descriptions=settings.MULTIMODAL_VISION_DESCRIPTIONS,
                )
                status = self.rag_pipeline.get_status()
                if status["total_chunks"] > 0:
                    logger.info(f"✅ RAG Pipeline (ChromaDB) active: {status['total_chunks']} chunks")
                else:
                    logger.warning("⚠️ RAG Pipeline initialized but ChromaDB is empty — will fall back to JSON vector store")
                    self.rag_pipeline = None
            except Exception as e:
                logger.warning(f"⚠️ RAG Pipeline init failed, falling back to JSON vector store: {e}")
                self.rag_pipeline = None
        
        self.system_prompt = """You are NEO Assistant, an expert on the NEO Warehouse Management System.

Your knowledge base includes:
- NEO system documentation and user manuals
- Technical specifications and proposals
- **C# codebase** from NEO Fleet Manager (classes, methods, implementations)
- Code examples and implementations
- Standard Operating Procedures (SOPs)
- Safety guidelines and best practices
- **Diagnostic Support Database** - Real troubleshooting solutions for bot and station issues

Response Guidelines:
1. **Structure your answers clearly** with headings and sections
2. **Use formatting** - bullet points, numbered lists, bold/italic for emphasis
3. **Be specific and accurate** - cite document/file names when referencing information
4. **Provide context** - explain technical terms when needed
5. **Be concise yet comprehensive** - break complex topics into digestible parts
6. **Include code examples** when relevant - show actual implementation details
7. **For code queries**: Explain the code's purpose, key methods, and how it fits in the system
8. **For troubleshooting**: Check diagnostic database first for known issues and solutions
9. **If information is incomplete**, clearly state what's missing
9. **Use professional tone** - helpful, clear, and authoritative
10. **Do not use additional image in the end** - junk images that are not relevant to the answer should be avoided. Only include images that directly support the response.
11. **Check for duplicate images** - if two images are the same, only include one in the response.

Formatting Standards:
- Use **bold** for key terms, class names, and section headers
- Use bullet points (•) or numbered lists for multi-item information
- Use line breaks between sections for readability
- Include relevant document/file references in [brackets]
- Use code blocks (```csharp, ```python) for code snippets
- For code answers: Show class name, method signatures, and key logic

Code Response Format:
When answering code questions, structure your response as:
1. **What it does**: Brief overview
2. **Location**: File path and class name
3. **Key Methods/Properties**: List important members
4. **Implementation Details**: Show relevant code snippets
5. **Usage Example**: How to use/call this code
6. **Related Components**: What other classes/methods it interacts with

Always prioritize clarity and user understanding."""

        logger.info("✅ Knowledge Base Service initialized")
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process user query using RAG (Retrieval-Augmented Generation)
        
        Steps:
        1. Get or create session for conversation memory
        2. Check for attached document context (primary source)
        3. Classify query type (factual, generative, conversational, unanswerable)
        4. Generate embedding for user query
        5. Search vector store for relevant documents (secondary source)
        6. Build adaptive context based on query type
        7. Generate response with appropriate strategy
        8. Store conversation in session
        
        Args:
            chat_request: User's chat request
            
        Returns:
            Chat response with answer and sources
        """
        start_time = time.time()
        _cached = False
        try:
            logger.info(f"🔍 Processing knowledge base query: {chat_request.message[:50]}...")
            
            # Step 1: Get session for context (already created/managed by endpoint)
            session_id = chat_request.session_id
            if session_id:
                # Session is already managed by endpoint, just get context
                conversation_history = self.session_manager.get_context_for_llm(session_id, max_messages=10)
            else:
                conversation_history = []

            # Step 1.5: Check for attached document (in-chat uploaded doc as primary source)
            attached_doc_text = None
            attached_filename = None
            has_attached_document = False
            if chat_request.context and isinstance(chat_request.context, dict):
                attached_doc_text = chat_request.context.get("attached_document")
                attached_filename = chat_request.context.get("attached_filename", "uploaded document")
                if attached_doc_text:
                    has_attached_document = True
                    logger.info(f"📎 Attached document detected: {attached_filename} ({len(attached_doc_text)} chars)")

            # Check if any knowledge base has documents
            has_kb_content = (
                self.rag_pipeline is not None
                or len(self.vector_store.documents) > 0
            )
            if not has_attached_document and not has_kb_content:
                return self._handle_empty_knowledge_base(chat_request)
            
            # Step 2: Check if this is a troubleshooting query
            is_troubleshooting = self._is_troubleshooting_query(chat_request.message)
            if is_troubleshooting:
                logger.info("🔧 Detected troubleshooting query, checking diagnostic database...")
                diagnostic_result = self._handle_diagnostic_query(chat_request)
                if diagnostic_result:
                    # Just return - endpoint handles session management
                    return diagnostic_result

            # Step 2.5: Check response cache (skip when attached-doc or active conversation)
            if not has_attached_document and len(conversation_history) <= 1:
                cached = self.response_cache.get(chat_request.message)
                if cached:
                    logger.info("🚀 Returning cached KB response")
                    _cached = True
                    resp = ChatResponse(**cached)
                    resp.session_id = session_id or resp.session_id
                    # Log a cache-hit metric
                    self.query_analytics.log_query(
                        query=chat_request.message,
                        response_time_ms=(time.time() - start_time) * 1000,
                        confidence_score=resp.confidence_score or 0.0,
                        num_sources=len(resp.sources) if resp.sources else 0,
                        cached=True,
                    )
                    return resp
            
            # Step 3: Classify query type
            query_type = self._classify_query(chat_request.message)
            logger.info(f"📊 Query classified as: {query_type}")

            # ── V1: Query-type-aware retrieval budget ─────────────────────────────
            top_k = self._get_query_top_k(query_type, has_attached_document)

            # Step 4+5: Retrieve relevant documents
            # PRIMARY: ChromaDB RAG Pipeline (hybrid vector + BM25 + rerank)
            # FALLBACK: Legacy JSON vector store
            rag_confidence = 1.0  # default; overridden below from RAG result
            if self.rag_pipeline is not None:
                logger.info("🔗 Using ChromaDB RAG Pipeline for retrieval")
                rag_result = self.rag_pipeline.retrieve_context(
                    chat_request.message, top_k=top_k
                )
                rag_confidence = rag_result.get("confidence", 1.0)

                # ── V1: Hard similarity filter — drop low-quality chunks ──────────
                raw_chunks = rag_result.get("retrieved_chunks", [])
                quality_chunks = self.content_optimizer.filter_and_deduplicate(
                    raw_chunks, score_threshold=0.35, max_chunks=top_k
                )
                # Rebuild context from quality chunks only (NOT the flat context string)
                kb_context = self._build_crisp_context(quality_chunks, query_type)
                source_documents = self._extract_source_documents_from_rag(rag_result)
                filtered_results = self._convert_chunks_to_legacy_format(quality_chunks)
                logger.info(f"🎯 Chunks after quality filter: {len(raw_chunks)} → {len(quality_chunks)}")
            else:
                logger.info("📦 Using legacy JSON vector store for retrieval")
                # Generate query embedding
                query_embedding = self.llm_service.generate_embedding(chat_request.message)

                # Search with balanced category distribution
                vector_filter = None
                if chat_request.context and isinstance(chat_request.context, dict):
                    vector_filter = {k: v for k, v in chat_request.context.items()
                                    if k not in ("attached_document", "attached_filename")}
                    if not vector_filter:
                        vector_filter = None

                search_results = self.vector_store.search_with_token_budget(
                    query_embedding=query_embedding,
                    top_k=top_k,
                    max_tokens=3000,
                    filter_metadata=vector_filter,
                    min_similarity=0.35,
                    diversify=True,
                    max_chunks_per_source=2,
                )

                filtered_results = self._filter_and_rerank(search_results, chat_request.message)

                # Content optimization — trim legacy chunks
                filtered_results = self.content_optimizer.optimize_chunks(
                    filtered_results, chat_request.message,
                    target_length="concise", max_chunk_length=500,
                )

                kb_context = self._build_crisp_context_from_legacy(filtered_results, query_type)
                source_documents = self._extract_source_documents(filtered_results)

            # ── V7: Confidence routing ─────────────────────────────────────────────
            if rag_confidence < 0.4 and not has_attached_document:
                logger.warning(f"⚠️ Low retrieval confidence ({rag_confidence:.2f}) — asking for clarification")
                return ChatResponse(
                    response="I couldn't find specific information about that in the knowledge base. Could you rephrase your question or provide more context? For example, which NEO system component or feature are you asking about?",
                    chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                    session_id=chat_request.session_id or str(uuid.uuid4()),
                    sources=[],
                    confidence_score=rag_confidence,
                    suggested_actions=["Ask about NEO ASRS system", "Ask about specific components", "Try the SQL Assistant for data queries"]
                )

            # Step 6.5: If attached document exists, build focused context (smart excerpt, not full dump)
            if has_attached_document:
                # ── V8: Extract only relevant portions (max 6000 chars) ──────────
                doc_excerpt = self._extract_relevant_doc_excerpt(
                    attached_doc_text, chat_request.message, max_chars=6000
                )
                context = f"""[DOCUMENT: {attached_filename}]
{doc_excerpt}

[KNOWLEDGE BASE]
{kb_context if kb_context else '(no additional context)'}"""

                # Add uploaded doc as a source
                source_documents.insert(0, SourceDocument(
                    document_name=attached_filename,
                    content_snippet=attached_doc_text[:200] + "...",
                    relevance_score=1.0,
                    page_number=None,
                    document_type=Path(attached_filename).suffix.lstrip('.') if attached_filename else "document"
                ))
            else:
                context = kb_context

            # Step 7: Get conversation history for context
            if not conversation_history:
                conversation_history = self.session_manager.get_context_for_llm(session_id, max_messages=10) if session_id else []

            # ── Brevity intent detection ──────────────────────────────────────────
            brevity_mode = self._detect_brevity_intent(chat_request.message, conversation_history)
            if brevity_mode:
                logger.info("✂️ Brevity mode ON — short/summary response requested")

            # ── Image gate — content-aware, not keyword-only ─────────────────────
            raw_images = rag_result.get("images", []) if self.rag_pipeline is not None else []
            # Image cap: troubleshooting gets 3 images (wiring diagrams, alarm panels);
            # all other types get 2 to avoid visual overload.
            _img_cap = 3 if query_type == "TROUBLESHOOTING" else 2
            if brevity_mode or not self._should_include_images(chat_request.message, raw_images):
                display_images = []
            else:
                display_images = raw_images[:_img_cap]

            # Phase 7: Build structured answer plan (skip in brevity mode)
            answer_plan = None
            if self.rag_pipeline is not None and not has_attached_document and not brevity_mode:
                retrieved_chunks = rag_result.get("retrieved_chunks", [])
                answer_plan = self.answer_planner.plan(
                    chat_request.message,
                    retrieved_chunks,
                    images=display_images,
                    query_type_hint=query_type,  # pass KB classification as hint
                )

            # Step 8: Generate response using LLM with adaptive strategy
            messages = self._build_adaptive_messages(
                chat_request, context, query_type, conversation_history,
                images=display_images,
                answer_plan=answer_plan,
                brevity_mode=brevity_mode,
            )

            # Adjust LLM parameters based on query type
            max_tokens, temperature = self._get_llm_parameters(query_type, has_images=bool(display_images), brevity_mode=brevity_mode)

            # Small boost for attached doc — needs slightly more to cover both sources
            if has_attached_document and not brevity_mode:
                max_tokens = min(max_tokens + 200, 1600)
            
            response_text = self.llm_service.generate_response(
                messages=messages,
                system_prompt=self._get_adaptive_system_prompt(query_type, brevity_mode=brevity_mode),
                max_tokens=max_tokens,
                temperature=temperature
            )
            
            # Format response based on query type
            response_text = self._format_adaptive_response(
                response_text, query_type, has_images=bool(display_images)
            )

            # Phase 8: Build structured response
            # Use the already-filtered display_images (respects brevity_mode suppression)
            display_images_list = display_images
            structured = self.response_structurer.structure(
                response_text,
                answer_plan=answer_plan,
                source_documents=source_documents,
                images=display_images_list,
            )
            
            # Note: Session message management is handled by the endpoint, not here
            
            # Calculate confidence based on source relevance
            confidence = self._calculate_confidence(filtered_results)
            
            # Record for RLHF learning
            try:
                self.rlhf_service.record_feedback(
                    chatbot_type="knowledge_base",
                    query=chat_request.message,
                    response=response_text,
                    feedback_type="neutral",  # Auto-logged on generation
                    rating=None,
                    comment=f"Auto-generated ({query_type} query)",
                    metadata={
                        "query_type": query_type,
                        "confidence": confidence,
                        "source_count": len(source_documents),
                        "document_names": [doc.document_name for doc in source_documents[:3]]
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to record RLHF feedback: {e}")
            
            final_response = ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=source_documents,
                confidence_score=confidence,
                suggested_actions=self._generate_suggested_actions(chat_request.message, response_text),
                images=display_images_list,   # Already filtered (empty in brevity mode)
                structured_response=structured,
            )

            # ── Cache the response (only for non-attached, high-confidence, non-brevity) ──
            # Brevity-mode responses are intent-specific and should not pollute the cache
            if not has_attached_document and not brevity_mode and confidence >= 0.5:
                try:
                    self.response_cache.set(
                        chat_request.message,
                        final_response.dict() if hasattr(final_response, 'dict') else final_response.model_dump(),
                    )
                except Exception as cache_err:
                    logger.warning(f"⚠️ Cache store failed: {cache_err}")

            # ── Log analytics ──
            elapsed_ms = (time.time() - start_time) * 1000
            self.query_analytics.log_query(
                query=chat_request.message,
                response_time_ms=elapsed_ms,
                confidence_score=confidence,
                num_sources=len(source_documents),
                cached=False,
                query_type=query_type,
            )

            return final_response
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"❌ Error processing knowledge base query: {error_msg}", exc_info=True)
            logger.error(f"Query was: {chat_request.message}")
            logger.error(f"Error type: {type(e).__name__}")
            # Log error to analytics
            self.query_analytics.log_query(
                query=chat_request.message,
                response_time_ms=(time.time() - start_time) * 1000,
                confidence_score=0.0,
                num_sources=0,
                error=error_msg,
            )
            return ChatResponse(
                response=f"I apologize, but I encountered an error while processing your question. Error: {error_msg}. Please try rephrasing or contact support.",
                chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=[],
                confidence_score=0.0
            )
    
    def _classify_query(self, query: str) -> str:
        """
        Classify query type to determine response strategy
        
        Types:
        - SIMPLE_FACT: Simple factual questions (What is X? How many? When?)
        - DEFINITION: Asking for definition/explanation (What does X mean?)
        - PROCEDURAL: How-to questions requiring steps (How to X?)
        - COMPARISON: Comparing multiple things (X vs Y, difference between)
        - EXPLORATORY: Open-ended exploration (Tell me about X)
        - GENERATIVE: Creating new content (Generate/Create/Write)
        - UNANSWERABLE: Questions outside knowledge base scope
        """
        query_lower = query.lower().strip()
        
        # ── TROUBLESHOOTING / ERROR HANDLING — highest priority ─────────────
        # Must be checked BEFORE procedural, because troubleshooting queries
        # often contain "how to" but need a very different response structure.
        troubleshooting_patterns = [
            r'\berror\b', r'\balarm\b', r'\bfault\b', r'\bfailure\b',
            r'\bnot\s+working\b', r'\bnot\s+achieved\b', r'\bnot\s+reached\b',
            r'\bstuck\b', r'\bstopped\b', r'\bcannot\b', r'\bcan\'t\b',
            r'\bwhat\s+to\s+do\b', r'\bhow\s+to\s+fix\b', r'\bhow\s+to\s+(resolve|recover)\b',
            r'\btroubleshoot\b', r'\brecovery\s+(procedure|step)\b',
            r'\bE\d{3,}\b',        # alarm/error codes like E001, E123
            r'\b(red|yellow)\s+(led|light|indicator)\b',  # LED alarm states
            r'\b(emergency|e-stop|estop)\b',
        ]
        for pattern in troubleshooting_patterns:
            if re.search(pattern, query_lower):
                return "TROUBLESHOOTING"

        # Simple fact queries (short answers)
        simple_fact_patterns = [
            r'^what is (the |a )?(\w+)\??$',  # "What is X?"
            r'^how many\b',  # "How many..."
            r'^when (was|is|did)\b',  # "When..."
            r'^where (is|are)\b',  # "Where..."
            r'^who (is|are)\b',  # "Who..."
            r'^which\b',  # "Which..."
            r'^(yes|no),?\s',  # Yes/No questions
            r'\?(yes|no)\??$',  # Ending with yes/no
        ]
        
        for pattern in simple_fact_patterns:
            if re.search(pattern, query_lower):
                return "SIMPLE_FACT"
        
        # Code-related queries
        code_patterns = [
            r'\bclass\b', r'\bmethod\b', r'\bfunction\b', r'\bcode\b',
            r'\bimplementation\b', r'\bcontroller\b', r'\bservice\b',
            r'\b(show|find|get|display)\s+(me\s+)?(the\s+)?code\b',
            r'\bhow\s+is\s+\w+\s+(implemented|coded|written)\b',
            r'\bsource\s+code\b', r'\b\.cs\b', r'\bc#\b'
        ]
        
        for pattern in code_patterns:
            if re.search(pattern, query_lower):
                return "CODE_QUERY"
        
        # Definition queries
        if any(phrase in query_lower for phrase in [
            "what does", "define", "definition of", "meaning of", "what is meant by"
        ]):
            return "DEFINITION"
        
        # Procedural queries (step-by-step)
        if any(phrase in query_lower for phrase in [
            "how to", "how do i", "how can i", "steps to", "procedure for", 
            "process of", "way to", "method to"
        ]):
            return "PROCEDURAL"
        
        # Comparison queries
        if any(phrase in query_lower for phrase in [
            " vs ", " versus ", "difference between", "compare", "comparison",
            "better than", "advantages of", "disadvantages of"
        ]):
            return "COMPARISON"
        
        # Generative queries (cannot be answered from docs)
        if any(phrase in query_lower for phrase in [
            "generate", "create a", "write a", "make a", "design a",
            "develop a", "build me", "give me a new"
        ]):
            return "GENERATIVE"
        
        # Exploratory queries (detailed explanations)
        if any(phrase in query_lower for phrase in [
            "tell me about", "explain", "describe", "overview of",
            "information about", "details about", "all about"
        ]):
            return "EXPLORATORY"
        
        # Default to exploratory for longer queries
        return "EXPLORATORY" if len(query.split()) > 5 else "SIMPLE_FACT"
    
    def _get_adaptive_system_prompt(self, query_type: str, *, brevity_mode: bool = False) -> str:
        """Delegate to the PromptRegistry — all prompt text lives in backend/app/prompts/."""
        return prompt_registry.get_system_prompt(query_type, brevity_mode=brevity_mode)
    
    def _get_llm_parameters(self, query_type: str, *, has_images: bool = False, brevity_mode: bool = False) -> tuple:
        """Get max_tokens and temperature based on query type.
        
        Budgets are sized to the realistic answer length for each query type.
        Not artificially capped — the system prompt controls verbosity instead.
        Code queries need room for actual code; exploratory queries need room
        for multi-section answers when warranted.
        """
        params = {
            #                        tokens  temp
            "SIMPLE_FACT":     (300,   0.2),  # 1–4 sentences
            "DEFINITION":      (350,   0.2),  # definition + context
            "PROCEDURAL":      (700,   0.2),  # full step list, notes
            "COMPARISON":      (600,   0.2),  # table + summary
            "GENERATIVE":      (300,   0.3),  # short redirect
            "CODE_QUERY":      (1200,  0.15), # code can be long
            "EXPLORATORY":     (900,   0.3),  # multi-section when deserved
            "TROUBLESHOOTING": (1000,  0.15), # structured steps + causes + warnings
        }

        tokens, temp = params.get(query_type, (600, 0.25))

        # Hard cap for brevity/summary mode
        if brevity_mode:
            return 280, 0.2

        # Give a bit more headroom when images are present (figure captions + references)
        if has_images:
            tokens = min(tokens + 200, 1400)

        return tokens, temp
    
    def _build_image_context(self, images: List[Dict[str, Any]]) -> str:
        """Format image metadata so the LLM can reference figures in its response."""
        if not images:
            return ""

        parts = ["\n📷 AVAILABLE FIGURES (reference as 'Figure 1', 'Figure 2', etc. where relevant):"]
        for i, img in enumerate(images, 1):
            caption = (img.get("caption") or "").strip()
            source = img.get("source_document", "")
            page = img.get("page_number", 0)

            desc = f"  Figure {i}"
            if caption:
                # Truncate long captions
                if len(caption) > 120:
                    caption = caption[:117] + "..."
                desc += f": {caption}"
            meta_bits = []
            if source:
                meta_bits.append(source)
            if page:
                meta_bits.append(f"page {page}")
            if meta_bits:
                desc += f" ({', '.join(meta_bits)})"
            parts.append(desc)

        parts.append("")
        return "\n".join(parts)

    def _build_adaptive_messages(self, chat_request: ChatRequest, context: str, query_type: str, conversation_history: List[Dict[str, str]] = None, *, images: Optional[List[Dict[str, Any]]] = None, answer_plan=None, brevity_mode: bool = False) -> List[Dict[str, str]]:
        """Build messages with adaptive prompting based on query type, with conversation context FIRST"""
        messages = []
        
        # ========================================
        # STEP 1: Add conversation history FIRST for context
        # This ensures LLM understands the ongoing conversation
        # ========================================
        if conversation_history and len(conversation_history) > 1:
            history_parts = []
            for msg in conversation_history[-8:-1]:  # last 7, excluding current
                role = msg.get('role', 'unknown').upper()
                content = msg.get('content', '')
                if len(content) > 300:
                    content = content[:300] + "..."
                history_parts.append(f"[{role}]: {content}")

            context_instruction = prompt_registry.render_conversation_context(history_parts)
            if context_instruction:
                messages.append({"role": "user", "content": context_instruction})
                messages.append({
                    "role": "assistant",
                    "content": "I understand. I'll consider our previous conversation when answering your next question.",
                })
        
        # ========================================
        # STEP 2: Build query-specific prompt
        # ========================================
        
        # Check if there's an attached document (primary source)
        has_attached_doc = (chat_request.context and isinstance(chat_request.context, dict)
                            and chat_request.context.get("attached_document"))
        doc_priority_note = ""
        if has_attached_doc:
            attached_name = chat_request.context.get("attached_filename", "uploaded document")
            doc_priority_note = prompt_registry.render_attached_doc_prefix(attached_name)

        # Cap context before injection — budget scales to query complexity
        _ctx_budgets = {
            "SIMPLE_FACT":     1800, "DEFINITION":  1800, "GENERATIVE":  1800,
            "PROCEDURAL":      3500, "COMPARISON":  3000,
            "CODE_QUERY":      4000, "EXPLORATORY": 3500,
            "TROUBLESHOOTING": 4000,  # needs full error descriptions + step sequences
        }
        _ctx_limit = _ctx_budgets.get(query_type, 2500)
        ctx_for_msg = context[:_ctx_limit] if len(context) > _ctx_limit else context

        # ── Build user message via PromptRegistry ─────────────────────────────
        image_context = self._build_image_context(images or []) if images else ""
        plan_context = answer_plan.to_prompt_context() if answer_plan else ""

        user_message = prompt_registry.render_user_message(
            query_type,
            context=ctx_for_msg,
            question=chat_request.message,
            image_context=image_context,
            plan_context=plan_context,
            doc_prefix=doc_priority_note,
            has_attached_doc=bool(has_attached_doc),
            brevity_mode=brevity_mode,
        )

        messages.append({
            "role": "user",
            "content": user_message
        })
        
        return messages
    
    def _format_adaptive_response(self, response_text: str, query_type: str, *, has_images: bool = False) -> str:
        """Format and polish response — clean up common LLM artefacts."""

        # Minimal formatting for simple facts
        if query_type == "SIMPLE_FACT":
            response_text = re.sub(r'\n{2,}', '\n', response_text)
            return response_text.strip()

        # ── Strip hallucinated "share a photo" invitations ──────────────────────────────
        response_text = re.sub(
            r'[^\n]*(?:share|send|provide|attach|upload)\s+(?:a\s+)?(?:photo|screenshot|image|picture|snap)[^\n]*\n?',
            '', response_text, flags=re.IGNORECASE
        )

        # ── Strip phantom figure references when no images were returned ─────────────
        # The LLM reads "Figure 1" from chunk text and hallucinates it as a visible image.
        # If display_images is empty, remove any Figure reference sentence/fragment.
        if not has_images:
            # Remove sentences/fragments that reference figure numbers
            response_text = re.sub(
                r'[^.!?\n]*\bFigure\s+\d+[^.!?\n]*[.!?]?',
                '', response_text, flags=re.IGNORECASE
            )
            # Remove orphaned page-image references like "(page 12 image)" or "refer to page 7 image"
            response_text = re.sub(
                r'[^.!?\n]*\bpage\s+\d+\s+image[^.!?\n]*[.!?]?',
                '', response_text, flags=re.IGNORECASE
            )

        # ── Deduplicate repeated same-source citations ──────────────────────────────
        # If the same source appears 3+ times, collapse to one citation at the end.
        source_pattern = re.compile(
            r'\(Source:\s*([^)]+)\)',
            re.IGNORECASE
        )
        all_sources = source_pattern.findall(response_text)
        if all_sources:
            from collections import Counter
            counts = Counter(s.strip() for s in all_sources)
            # For any source cited 3+ times: strip all inline copies, append once at end
            for src, count in counts.items():
                if count >= 3:
                    escaped = re.escape(src)
                    response_text = re.sub(
                        rf'\(Source:\s*{escaped}\)',
                        '', response_text, flags=re.IGNORECASE
                    )
                    response_text = response_text.rstrip() + f'\n\n(Source: {src})'

        # Remove any trailing "Sources:" block the LLM may have added
        response_text = re.sub(
            r'\n+(?:#{1,3}\s*)?(?:Source\s*References?|Sources?)\s*:?\s*\n'
            r'(?:[-•*]?\s*\[?[^\n]+\]?\n?)+\s*$',
            '', response_text, flags=re.IGNORECASE
        )

        # Collapse 3+ newlines into double
        response_text = re.sub(r'\n{3,}', '\n\n', response_text)

        # Clean up blank lines left by stripping
        response_text = re.sub(r'\n[ \t]*\n[ \t]*\n', '\n\n', response_text)

        return response_text.strip()

    # ══════════════════════════════════════════════════════════════════════════
    #  V1-V8 Optimization Helpers
    # ══════════════════════════════════════════════════════════════════════════

    def _get_query_top_k(self, query_type: str, has_attached: bool = False) -> int:
        """V1: Return retrieval budget based on query type.
        Less context → better signal-to-noise → crisper answers.
        """
        if has_attached:
            return 3
        budgets = {
            "SIMPLE_FACT":     3,
            "DEFINITION":      3,
            "PROCEDURAL":      4,
            "COMPARISON":      5,
            "CODE_QUERY":      4,
            "EXPLORATORY":     5,
            "GENERATIVE":      3,
            "TROUBLESHOOTING": 6,  # more chunks — errors need steps + causes + images
        }
        return budgets.get(query_type, 4)

    # Image score thresholds
    _IMAGE_SCORE_ALWAYS   = 0.90   # ≥ this → always include, clearly relevant
    _IMAGE_SCORE_NEVER    = 0.40   # <  this → only include if query explicitly needs visuals
    # Between thresholds → 3-signal content-aware logic

    _EXPLICIT_VISUAL = {
        "diagram", "flow", "layout", "chart", "figure", "image", "picture",
        "schematic", "map", "drawing", "visual", "illustration", "photo",
        "what does it look", "how does it look", "show me",
    }
    _VISUAL_QUERY_PHRASES = {
        "how does", "how is", "explain", "describe", "overview",
        "what is the process", "architecture", "structure", "design",
        "how to", "steps", "workflow", "setup",
    }

    def _should_include_images(self, query: str, retrieved_images: list = None) -> bool:
        """Decide whether to surface images to the LLM in this response.

        Score-tier logic (applied before content-aware signals):
          ≥ 0.90  → always include (highly confident the image is relevant)
          < 0.40  → only include if query explicitly asks for a visual
          0.40–0.90 → 3-signal content-aware gate:
              1. Query explicitly asks for a visual
              2. Query type naturally benefits from visuals
              3. Image caption / source shares ≥2 meaningful words with the query
        """
        if not retrieved_images:
            return False

        q_lower = query.lower()
        q_words = {w for w in re.findall(r"\b\w{4,}\b", q_lower)}

        # ── Score-tier pre-check ──────────────────────────────────
        scores = [img.get("relevance_score", 0.0) for img in retrieved_images]
        max_score = max(scores) if scores else 0.0

        # Always include — at least one image is highly relevant
        if max_score >= self._IMAGE_SCORE_ALWAYS:
            return True

        # Troubleshooting queries: lower the bar — wiring diagrams, LED states,
        # alarm panels in images are almost always useful for error resolution.
        # Treat mid-confidence images (≥0.35) as always-include for these queries.
        _TROUBLESHOOTING_SIGNALS = {
            "error", "alarm", "fault", "failure", "stuck", "not working",
            "fix", "resolve", "recover", "troubleshoot", "e-stop", "estop",
        }
        if any(sig in q_lower for sig in _TROUBLESHOOTING_SIGNALS) and max_score >= 0.35:
            return True

        # Low confidence — only include for explicit visual queries
        if max_score < self._IMAGE_SCORE_NEVER:
            return any(t in q_lower for t in self._EXPLICIT_VISUAL)

        # ── Mid-confidence: 3-signal content-aware gate ──────────
        # Signal 1 — explicit visual request in query
        if any(t in q_lower for t in self._EXPLICIT_VISUAL):
            return True

        # Signal 2 — query type naturally benefits from visuals
        if any(ph in q_lower for ph in self._VISUAL_QUERY_PHRASES):
            return True

        # Signal 3 — at least one retrieved image is content-relevant
        for img in retrieved_images[:3]:
            caption = (img.get("caption") or "").lower()
            src = (img.get("source_document") or img.get("source_path") or "").lower()
            combined = caption + " " + src
            img_words = {w for w in re.findall(r"\b\w{4,}\b", combined)}
            if len(q_words & img_words) >= 2:
                return True

        return False

    def _build_crisp_context(self, chunks: list, query_type: str) -> str:
        """Build numbered context from reranked chunks with query-type-aware sizing.
        Simple queries get smaller excerpts; complex queries get more content.
        """
        if not chunks:
            return "No relevant documentation found."

        # Per-chunk size and total budget scale with answer complexity
        _budgets = {
            "SIMPLE_FACT":     (350, 1800), "DEFINITION":  (350, 1800),
            "GENERATIVE":      (350, 1800), "PROCEDURAL":  (600, 3500),
            "COMPARISON":      (550, 3000), "CODE_QUERY":  (700, 4000),
            "EXPLORATORY":     (600, 3500),
            "TROUBLESHOOTING": (650, 4000),  # full error descriptions needed
        }
        chunk_char_limit, total_budget = _budgets.get(query_type, (500, 2500))
        parts: list = []
        used = 0

        for i, chunk in enumerate(chunks, 1):
            content = (chunk.content or "").strip()
            if not content:
                continue
            # Trim to per-chunk limit
            if len(content) > chunk_char_limit:
                content = content[:chunk_char_limit] + "…"
            if used + len(content) > total_budget:
                break
            source = Path(chunk.source_path).name if getattr(chunk, "source_path", None) else "doc"
            parts.append(f"[{i}] ({source})\n{content}")
            used += len(content)

        return "\n\n".join(parts) if parts else "No relevant documentation found."

    def _build_crisp_context_from_legacy(self, results: list, query_type: str) -> str:
        """Same as _build_crisp_context but for legacy vector-store format."""
        if not results:
            return "No relevant documentation found."

        _budgets = {
            "SIMPLE_FACT":     (350, 1800), "DEFINITION":  (350, 1800),
            "GENERATIVE":      (350, 1800), "PROCEDURAL":  (600, 3500),
            "COMPARISON":      (550, 3000), "CODE_QUERY":  (700, 4000),
            "EXPLORATORY":     (600, 3500),
            "TROUBLESHOOTING": (650, 4000),
        }
        chunk_char_limit, total_budget = _budgets.get(query_type, (500, 2500))
        parts: list = []
        used = 0

        for i, result in enumerate(results, 1):
            doc = result.get("document", result)
            content = (doc.get("content", "") or "").strip()
            if not content:
                continue
            if len(content) > chunk_char_limit:
                content = content[:chunk_char_limit] + "…"
            if used + len(content) > total_budget:
                break
            source = doc.get("metadata", {}).get("filename", "doc")
            parts.append(f"[{i}] ({source})\n{content}")
            used += len(content)

        return "\n\n".join(parts) if parts else "No relevant documentation found."

    def _convert_chunks_to_legacy_format(self, chunks: list) -> list:
        """Convert RetrievedChunk list to legacy search_results format for confidence calc."""
        results = []
        for chunk in chunks:
            results.append({
                "similarity": chunk.score,
                "boosted_similarity": chunk.score,
                "document": {
                    "content": chunk.content,
                    "metadata": {
                        "filename": Path(chunk.source_path).name if getattr(chunk, "source_path", None) else "unknown",
                        "category": chunk.metadata.get("category", "unknown") if hasattr(chunk, "metadata") else "unknown",
                    }
                }
            })
        return results

    def _extract_relevant_doc_excerpt(self, doc_text: str, query: str, max_chars: int = 6000) -> str:
        """V8: Extract the most query-relevant portion of an attached document
        instead of dumping the entire text.
        Uses simple sentence-level keyword matching (no embeddings needed).
        """
        if not doc_text:
            return ""
        if len(doc_text) <= max_chars:
            return doc_text

        # Split into paragraphs
        paragraphs = [p.strip() for p in doc_text.split("\n\n") if len(p.strip()) > 40]
        q_words = {w.lower() for w in re.findall(r"\b\w{3,}\b", query) if len(w) > 3}

        def _score(para: str) -> int:
            pl = para.lower()
            return sum(1 for w in q_words if w in pl)

        scored = sorted(enumerate(paragraphs), key=lambda t: _score(t[1]), reverse=True)

        kept: list = []
        chars_used = 0
        for orig_idx, para in scored:
            if chars_used + len(para) > max_chars:
                break
            kept.append((orig_idx, para))
            chars_used += len(para)

        # Re-order by original position for coherence
        kept.sort(key=lambda t: t[0])
        excerpt = "\n\n".join(p for _, p in kept)
        logger.info(f"📄 Doc excerpt: {len(doc_text):,} → {len(excerpt):,} chars (query-relevant)")
        return excerpt

    # ── Brevity Intent Detection ──────────────────────────────────────────────
    def _detect_brevity_intent(self, query: str, conversation_history: list) -> bool:
        """Return True when the user (now or recently) requested a short/summary response."""

        QUERY_TRIGGERS = {
            "briefly", "brief", "precisely", "in brief", "in short", "in summary",
            "summarize", "summarise", "give me a summary", "give summary",
            "summary only", "just summary", "only summary", "short answer",
            "quick answer", "concise", "to the point", "keep it short",
            "don't go long", "don't be verbose", "be concise", "be brief",
            "short response", "short version", "tl;dr", "tldr",
        }

        HISTORY_TRIGGERS = {
            "summary only", "give me summary", "give summary", "be brief",
            "be concise", "told you", "stop giving long", "too long",
            "shorter", "just summary", "only summary", "precise only",
            "in short", "in brief", "keep it short", "don't go long",
            "short answer", "brief answer", "briefly", "concise answer",
        }

        q = query.lower().strip()

        # ── 1. Check the current query ────────────────────────────────────────
        if any(trigger in q for trigger in QUERY_TRIGGERS):
            return True

        # ── 2. Check the last 4 turns (user + assistant) of conversation ──────
        recent = conversation_history[-8:] if len(conversation_history) > 8 else conversation_history
        for turn in recent:
            role = turn.get("role", "")
            content = (turn.get("content") or "").lower()
            if role == "user" and any(trigger in content for trigger in HISTORY_TRIGGERS):
                return True

        return False

    def _handle_empty_knowledge_base(self, chat_request: ChatRequest) -> ChatResponse:
        """Handle case when no documents are in knowledge base"""
        return ChatResponse(
            response="""I don't have any documents in my knowledge base yet. 

To enable document Q&A:
1. Place your documentation files (PDF, DOCX, TXT) in: app/modules/neo_chatbot/data/documents/
2. Run the document ingestion process to index them
3. Then I'll be able to answer questions about your documentation!

Currently I can still help with:
- Database queries (SQL Assistant)
- System diagnostics and troubleshooting
- General NEO system questions (with limited context)

What would you like help with?""",
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
            session_id=chat_request.session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            suggested_actions=["Add documents to knowledge base", "Try SQL Assistant", "Ask about diagnostics"]
        )
    
    def _build_context(self, search_results: List[Dict[str, Any]]) -> str:
        """Build context string from search results with improved formatting"""
        if not search_results:
            return "No relevant documentation found."
        
        context_parts = []
        for i, result in enumerate(search_results, 1):
            doc = result["document"]
            filename = doc['metadata'].get('filename', 'Unknown')
            category = doc['metadata'].get('category', 'Unknown')
            similarity = result['similarity']
            content = doc['content']
            
            # Include more content for high-relevance documents
            max_length = 800 if similarity > 0.5 else 500
            content_preview = content[:max_length]
            if len(content) > max_length:
                content_preview += "..."
            
            context_parts.append(f"""
[Document {i}] {filename}
Category: {category} | Relevance: {similarity:.1%}

{content_preview}
{'─' * 80}
""")
        
        return "\n".join(context_parts)
    
    def _filter_and_rerank(self, search_results: List[Dict[str, Any]], query: str) -> List[Dict[str, Any]]:
        """Filter and re-rank search results based on query relevance"""
        if not search_results:
            return []
        
        # Filter out very low similarity results
        filtered = [r for r in search_results if r['similarity'] > 0.2]
        
        # Re-rank by combining similarity with keyword matching
        query_keywords = set(query.lower().split())
        
        for result in filtered:
            content_lower = result['document']['content'].lower()
            keyword_matches = sum(1 for kw in query_keywords if kw in content_lower)
            
            # Boost score if content has many query keywords
            keyword_boost = min(keyword_matches * 0.05, 0.15)
            result['boosted_similarity'] = min(result['similarity'] + keyword_boost, 1.0)
        
        # Sort by boosted similarity
        filtered.sort(key=lambda x: x.get('boosted_similarity', x['similarity']), reverse=True)
        
        # Return top 5 most relevant
        return filtered[:5]
    
    def _extract_source_documents(self, search_results: List[Dict[str, Any]]) -> List[SourceDocument]:
        """Extract source documents from search results"""
        sources = []
        for result in search_results:
            doc = result["document"]
            sources.append(SourceDocument(
                document_name=doc['metadata'].get('filename', 'Unknown'),
                content_snippet=doc['content'][:200] + "..." if len(doc['content']) > 200 else doc['content'],
                relevance_score=result['similarity'],
                page_number=doc['metadata'].get('page_number'),
                document_type=doc['metadata'].get('category', 'unknown')
            ))
        return sources
    
    def _calculate_confidence(self, search_results: List[Dict[str, Any]]) -> float:
        """Calculate confidence score based on search results quality"""
        if not search_results:
            return 0.0
        
        # Weighted confidence calculation
        # - Top result has most weight
        # - Consider number of high-quality results
        # - Penalize if only low-similarity results
        
        similarities = [r.get('boosted_similarity', r['similarity']) for r in search_results]
        
        if not similarities:
            return 0.0
        
        # Weight top results more heavily
        weights = [0.4, 0.3, 0.2, 0.1][:len(similarities)]
        weights.extend([0.05] * (len(similarities) - len(weights)))
        
        weighted_score = sum(s * w for s, w in zip(similarities, weights))
        
        # Boost confidence if we have multiple high-quality results
        high_quality_count = sum(1 for s in similarities if s > 0.5)
        quality_boost = min(high_quality_count * 0.05, 0.15)
        
        final_confidence = min(weighted_score + quality_boost, 1.0)
        
        return round(final_confidence, 2)
    
    def _generate_suggested_actions(self, query: str, response_text: str = "") -> List[str]:
        """Generate 4 short follow-up bubbles using AI based on user query and answer."""

        query_text = (query or "").strip()
        response = (response_text or "").strip()

        topic_match = re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{2,}", query_text.lower())
        topic = topic_match[0] if topic_match else "neo"

        system_prompt = (
            "You generate next-question bubbles for a chatbot UI. "
            "Output ONLY valid JSON: an array of exactly 4 strings. "
            "Each string must be a follow-up question, natural English, 4 to 5 words, and end with '?'. "
            "Questions must be context-aware from the user question and assistant answer. "
            "Avoid generic, repetitive, or ungrammatical phrasing."
        )

        user_prompt = (
            f"User question:\n{query_text}\n\n"
            f"Assistant answer:\n{response[:1800]}\n\n"
            "Return JSON array only."
        )

        def _sanitize(raw_items: List[str]) -> List[str]:
            cleaned: List[str] = []
            for item in raw_items:
                text = " ".join(str(item or "").strip().split())
                text = re.sub(r"^[\-\d\.)\s]+", "", text)
                if not text:
                    continue

                if not text.endswith("?"):
                    text = f"{text}?"

                words = [w for w in re.findall(r"[A-Za-z0-9']+\??", text) if w]
                if len(words) > 5:
                    text = " ".join(words[:5]).rstrip("?") + "?"
                elif len(words) < 4:
                    filler = ["in", "NEO"]
                    while len(words) < 4 and filler:
                        words.append(filler.pop(0))
                    text = " ".join(words).rstrip("?") + "?"

                if text not in cleaned:
                    cleaned.append(text)
                if len(cleaned) == 4:
                    break

            fallback = [
                f"Can you expand {topic}?",
                f"Any examples for {topic}?",
                f"How is {topic} used?",
                f"What about {topic} next?"
            ]

            for item in fallback:
                if item not in cleaned:
                    cleaned.append(item)
                if len(cleaned) == 4:
                    break

            return cleaned[:4]

        try:
            ai_output = self.llm_service.generate_response(
                messages=[{"role": "user", "content": user_prompt}],
                system_prompt=system_prompt,
                max_tokens=180,
                temperature=0.4
            )

            parsed: List[str] = []
            try:
                loaded = json.loads(ai_output)
                if isinstance(loaded, list):
                    parsed = [str(x) for x in loaded]
            except Exception:
                lines = [ln.strip(" -*\t") for ln in (ai_output or "").splitlines() if ln.strip()]
                parsed = [ln for ln in lines if "?" in ln]

            return _sanitize(parsed)

        except Exception as e:
            logger.warning(f"⚠️ AI suggested bubbles generation failed: {e}")
            return _sanitize([])
    
    def add_document(
        self,
        filename: str,
        content: str,
        category: str,
        additional_metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Add document to knowledge base
        
        Args:
            filename: Document filename
            content: Document text content
            category: Document category (documentation, code, proposal, support)
            additional_metadata: Additional metadata
            
        Returns:
            Success status
        """
        try:
            # Generate unique document ID
            doc_id = str(uuid.uuid4())
            
            # Generate embedding
            embedding = self.llm_service.generate_embedding(content)
            
            # Prepare metadata
            metadata = {
                "filename": filename,
                "category": category,
                **(additional_metadata or {})
            }
            
            # Add to vector store
            self.vector_store.add_document(
                document_id=doc_id,
                content=content,
                embedding=embedding,
                metadata=metadata
            )
            
            logger.info(f"✅ Added document to knowledge base: {filename}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error adding document to knowledge base: {e}")
            return False
    
    def _is_troubleshooting_query(self, query: str) -> bool:
        """Detect if query is asking for troubleshooting help"""
        troubleshooting_keywords = [
            'error', 'issue', 'problem', 'stuck', 'not working', 'failed', 'stopped',
            'unable to', 'cannot', 'can\'t', 'won\'t', 'troubleshoot', 'debug', 'fix',
            'alarm', 'stopped', 'bot stuck', 'station', 'lidar', 'buffer', 'maintenance',
            'e-stop', 'emergency', 'recovery', 'manual mode', 'hmi', 'teleoperation'
        ]
        
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in troubleshooting_keywords)
    
    def _handle_diagnostic_query(self, chat_request: ChatRequest) -> Optional[ChatResponse]:
        """Handle troubleshooting queries using diagnostic database"""
        try:
            # Search diagnostic database
            matches = self.diagnostic_service.search_issue(
                query=chat_request.message,
                issue_type=None  # Search both BOT and STATION level
            )
            
            if not matches:
                return None  # Fall back to normal RAG
            
            # Take top 3 matches
            top_matches = matches[:3]
            
            # Build diagnostic response
            response_parts = [
                "## 🔧 Diagnostic Support\n",
                f"I found {len(top_matches)} known solution(s) for similar issues:\n"
            ]
            
            for i, match in enumerate(top_matches, 1):
                severity_emoji = "🔴" if match['severity'].lower() == "high" else "🟡" if match['severity'].lower() == "medium" else "🟢"
                
                response_parts.append(f"\n### Solution {i}: {match['problem']}")
                response_parts.append(f"\n{severity_emoji} **Severity:** {match['severity']}")
                response_parts.append(f"\n**Type:** {match['type'].replace('_', ' ')}")
                response_parts.append(f"\n\n**Solution Steps:**")
                
                # Format solution steps
                solution_lines = match['solution'].split('.')
                for step in solution_lines:
                    step = step.strip()
                    if step:
                        response_parts.append(f"\n- {step}")
                
                # Add SQL query if available
                if match.get('sql_query') and match['sql_query'].strip():
                    response_parts.append(f"\n\n**SQL Query for Diagnosis:**")
                    response_parts.append(f"\n```sql\n{match['sql_query']}\n```")
                
                # Add developer escalation note
                if match.get('reported_to_dev', '').upper() == 'Y':
                    response_parts.append(f"\n\n⚠️ *Note: This issue may require developer attention if not resolved.*")
                
                response_parts.append("\n" + "-" * 60)
            
            # Add general advice
            response_parts.append("\n\n### 📋 General Troubleshooting Tips:")
            response_parts.append("\n1. Always check bot status and alarms first")
            response_parts.append("\n2. Verify task assignments in task_master")
            response_parts.append("\n3. Check bot communication via IP ping")
            response_parts.append("\n4. Try RECOVERY before NON-RECOVERY")
            response_parts.append("\n5. Document the issue for future reference")
            
            response_text = "".join(response_parts)
            
            # Create source documents from matches
            sources = [
                SourceDocument(
                    document_name=f"Diagnostic DB - {match['type']}",
                    content_snippet=match['problem'][:200],
                    relevance_score=match['relevance_score'] / 100.0,
                    page_number=match['id'],
                    document_type="diagnostic"
                )
                for match in top_matches
            ]
            
            return ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.KNOWLEDGE_BASE,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=sources,
                confidence_score=0.95,  # High confidence for exact matches
                suggested_actions=[
                    "Show me SQL queries for bot diagnostics",
                    "What are common station-level issues?",
                    "How do I use HMI teleoperation mode?"
                ]
            )
            
        except Exception as e:
            logger.error(f"❌ Error in diagnostic query handling: {e}", exc_info=True)
            return None  # Fall back to normal RAG
    
    def _extract_source_documents_from_rag(self, rag_result: Dict[str, Any]) -> List[SourceDocument]:
        """Convert RAG pipeline sources to SourceDocument list."""
        sources = []
        for src in rag_result.get("sources", []):
            # src is a Source dataclass from ingetion.models
            doc_name = getattr(src, 'document_title', '') or Path(getattr(src, 'source_path', '')).name
            page_nums = getattr(src, 'page_numbers', [])
            section = getattr(src, 'section', '')
            sources.append(SourceDocument(
                document_name=doc_name,
                content_snippet=section[:200] if section else doc_name,
                relevance_score=getattr(src, 'relevance_score', 0.5),
                page_number=page_nums[0] if page_nums else None,
                document_type="rag_chroma"
            ))
        return sources

    def _convert_rag_to_legacy_format(self, rag_result: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Convert RAG retrieved chunks to legacy search_results format for confidence calc."""
        results = []
        for chunk in rag_result.get("retrieved_chunks", []):
            results.append({
                "similarity": chunk.score,
                "boosted_similarity": chunk.score,
                "document": {
                    "content": chunk.content,
                    "metadata": {
                        "filename": Path(chunk.source_path).name if chunk.source_path else "unknown",
                        "category": chunk.metadata.get("category", "unknown"),
                    }
                }
            })
        return results

    def get_statistics(self) -> Dict[str, Any]:
        """Get knowledge base statistics"""
        stats = self.vector_store.get_statistics()
        stats["llm_provider"] = self.llm_service.get_provider_info()
        
        # Add ChromaDB stats if available
        if self.rag_pipeline:
            try:
                rag_status = self.rag_pipeline.get_status()
                stats["chroma_db"] = {
                    "active": True,
                    "total_chunks": rag_status["total_chunks"],
                    "collections": rag_status["collections"],
                    "persist_directory": rag_status["persist_directory"],
                }
            except Exception:
                stats["chroma_db"] = {"active": False}
        else:
            stats["chroma_db"] = {"active": False}
        
        return stats

