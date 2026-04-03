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
            
            # Step 4+5: Retrieve relevant documents
            # PRIMARY: ChromaDB RAG Pipeline (hybrid vector + BM25 + rerank)
            # FALLBACK: Legacy JSON vector store
            if self.rag_pipeline is not None:
                logger.info("🔗 Using ChromaDB RAG Pipeline for retrieval")
                top_k = 8 if not has_attached_document else 4
                rag_result = self.rag_pipeline.retrieve_context(
                    chat_request.message, top_k=top_k
                )
                # Convert RAG results to KB service format
                kb_context = rag_result["context"]
                source_documents = self._extract_source_documents_from_rag(rag_result)
                filtered_results = self._convert_rag_to_legacy_format(rag_result)

                # Content optimization — trim RAG context to stay within token budget
                kb_context = self.content_optimizer.optimize_rag_context(
                    kb_context, chat_request.message, max_tokens=6000
                )
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
                    top_k=8 if not has_attached_document else 4,
                    max_tokens=6000,
                    filter_metadata=vector_filter,
                    min_similarity=0.25,
                    diversify=True,
                    max_chunks_per_source=3,
                )
                
                filtered_results = self._filter_and_rerank(search_results, chat_request.message)

                # Content optimization — trim legacy chunks to reduce token usage
                filtered_results = self.content_optimizer.optimize_chunks(
                    filtered_results, chat_request.message,
                    target_length="medium", max_chunk_length=800,
                )

                kb_context = self._build_context(filtered_results)
                source_documents = self._extract_source_documents(filtered_results)

            # Step 6.5: If attached document exists, build combined context (doc = primary, KB = secondary)
            if has_attached_document:
                # Truncate document to fit in context window
                doc_excerpt = attached_doc_text[:40000] if len(attached_doc_text) > 40000 else attached_doc_text
                context = f"""╔══════════════════════════════════════════════════════════════════════════════╗
║  📎 PRIMARY SOURCE: Uploaded Document - {attached_filename}                  
╚══════════════════════════════════════════════════════════════════════════════╝

{doc_excerpt}

╔══════════════════════════════════════════════════════════════════════════════╗
║  📚 SUPPLEMENTARY: Knowledge Base (background context)                       
╚══════════════════════════════════════════════════════════════════════════════╝

{kb_context if kb_context else '(No additional knowledge base context found)'}"""

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

            # ── Brevity intent detection (Issues 2 & 3) ──────────────────────────
            # Detect if user asked for summary/precise answer, either in current
            # query or in conversation history (e.g. "told you, give me summary only")
            brevity_mode = self._detect_brevity_intent(chat_request.message, conversation_history)
            if brevity_mode:
                logger.info("✂️ Brevity mode ON — short/summary response requested")

            # Gather display images for LLM figure-awareness
            # Suppress images entirely in brevity mode — they add noise, not value
            if brevity_mode:
                display_images = []
            else:
                display_images = rag_result.get("images", []) if self.rag_pipeline is not None else []

            # Phase 7: Build structured answer plan from retrieved evidence
            # Skip answer plan in brevity mode (it encourages long structured responses)
            answer_plan = None
            if self.rag_pipeline is not None and not has_attached_document and not brevity_mode:
                retrieved_chunks = rag_result.get("retrieved_chunks", [])
                answer_plan = self.answer_planner.plan(
                    chat_request.message,
                    retrieved_chunks,
                    images=display_images,
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
            
            # Increase max_tokens when processing attached documents (richer answers needed)
            if has_attached_document and not brevity_mode:
                max_tokens = max(max_tokens, 2000)
            
            response_text = self.llm_service.generate_response(
                messages=messages,
                system_prompt=self._get_adaptive_system_prompt(query_type, brevity_mode=brevity_mode),
                max_tokens=max_tokens,
                temperature=temperature
            )
            
            # Format response based on query type
            response_text = self._format_adaptive_response(response_text, query_type)

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
        """Get system prompt based on query type"""
        
        base_prompt = """You are NEO Assistant, an expert on the NEO Warehouse Management System and Falcon Autotech products.

RESPONSE QUALITY RULES:
- Write naturally and authoritatively — you ARE the domain expert
- Structure content DYNAMICALLY based on information richness — do NOT follow rigid templates
- Use clean markdown: ## for section headings, **bold** for key terms, bullet points for lists
- Add blank lines between sections for readability
- Cite source documents naturally in-line: "According to [Document Name]..." or "(Source: Document Name)"
- Do NOT add a separate "Source References" or "Sources:" section at the end — weave citations into the text
- When figures are listed in the context, reference them naturally: "The carrier design (Figure 1) shows..." or "As illustrated in Figure 2..."
- Be SPECIFIC with data — include dimensions, capacities, percentages, model numbers when available
- Never repeat the same information in different sections
- Keep a professional, confident tone throughout
"""

        # ── BREVITY MODE OVERRIDE ────────────────────────────────────────────────
        # The user has explicitly asked for a summary, brief, or precise answer.
        # All other formatting rules are subordinate to this instruction.
        if brevity_mode:
            return """You are NEO Assistant, an expert on the NEO Warehouse Management System.

⚠️ STRICT BREVITY MODE — The user has asked for a SHORT, PRECISE, or SUMMARY answer.

MANDATORY RULES — NO EXCEPTIONS:
1. Respond in 3–5 bullet points OR 2–3 short sentences — nothing more.
2. Do NOT write sections, headings, or detailed explanations.
3. Do NOT repeat yourself or add background context unless critical.
4. Do NOT include figures, source blocks, or "Additional Details" notes.
5. If the user's follow-up message says "summary only", "precise", "told you", "stop giving long answers" — honour that completely.
6. Every word must earn its place. Cut anything decorative.

FORMAT EXAMPLE (correct):
• [Key point 1]
• [Key point 2]
• [Key point 3]

Cite the source at the end in one short parenthetical: (Source: DocumentName)
"""
        
        if query_type == "SIMPLE_FACT":
            return base_prompt + """

TASK: Provide a direct, concise answer in 1-3 sentences.

RULES:
- Answer directly without unnecessary context
- No lengthy explanations unless asked
- No forced formatting with sections
- If it's a yes/no question, start with yes or no
- Cite the document source in [brackets] at the end

Example:
Q: "What is NEO?"
A: "NEO is an Automated Storage and Retrieval System (ASRS) that uses autonomous robots to store and retrieve bins efficiently. [NEO System Documentation]"
"""
        
        elif query_type == "DEFINITION":
            return base_prompt + """

TASK: Provide a clear definition followed by brief context.

FORMAT:
**Definition:** [Clear, concise definition in 1-2 sentences]

**Context:** [Brief explanation of why it matters or how it's used - 2-3 sentences]

[Source: Document name]
"""
        
        elif query_type == "PROCEDURAL":
            return base_prompt + """

TASK: Provide step-by-step instructions.

FORMAT:
**How to [Task]:**

1. [First step]
2. [Second step]
3. [Continue...]

**Important Notes:**
• [Any warnings or prerequisites]
• [Special considerations]

[Source: Document name]
"""
        
        elif query_type == "COMPARISON":
            return base_prompt + """

TASK: Provide a structured comparison.

FORMAT:
**Key Differences:**

| Aspect | Option A | Option B |
|--------|----------|----------|
| [Feature] | [Detail] | [Detail] |

**Summary:** [Which is better for what use case]

[Source: Document name]
"""
        
        elif query_type == "CODE_QUERY":
            return base_prompt + """

TASK: Provide detailed code information with context.

FORMAT:
**📁 File:** [Filename and path if available]

**📝 Purpose:** [What this code does - 1-2 sentences]

**🔧 Key Components:**
• **Class:** [ClassName]
• **Methods:** [List important methods]
• **Properties:** [Key properties if relevant]

**💻 Implementation:**
```csharp
[Show relevant code snippet - focus on key logic]
```

**📋 Explanation:**
[Explain what the code does step by step]

**🔗 Related Components:**
[What other classes/services this interacts with]

**💡 Usage Example:**
[How to use or call this code if applicable]

[Source: Filename]
"""
        
        elif query_type == "GENERATIVE":
            return base_prompt + """

TASK: Explain that you cannot generate new content, but can help with existing documentation.

RESPONSE STRATEGY:
1. Politely explain you can only provide information from existing documentation
2. Offer to share relevant examples/templates from the docs
3. Suggest what specific information you CAN provide

Be helpful, not rigid. Offer alternatives.
"""
        
        else:  # EXPLORATORY
            return base_prompt + """

TASK: Provide a comprehensive, intelligent, and well-structured response.

APPROACH:
- Open with an engaging 2-3 sentence summary that captures the core concept
- Organise into LOGICAL sections using ## headings — choose heading names that FIT the content (e.g. "## How It Works", "## Technical Specifications", "## Key Advantages"), NOT generic ones like "Key Points" or "Additional Details"
- Mix formatting NATURALLY: paragraphs for explanations, bullets for features/specs, numbered lists for sequential processes, markdown tables for comparisons or specifications
- When technical specifications are available (dimensions, weights, speeds, capacities), present them in a clean markdown table or formatted spec block
- If figures are available, reference them IN CONTEXT where they add value: "The sorter track layout (Figure 1) demonstrates..." — don't just list them
- CONNECT ideas — explain WHY things work the way they do, not just WHAT they are
- End with a practical insight or key takeaway — something actionable or memorable
- Vary sentence length and structure for readability — avoid monotonous bullet-only responses
- Do NOT include a separate sources section at the end — cite sources inline only
"""
    
    def _get_llm_parameters(self, query_type: str, *, has_images: bool = False, brevity_mode: bool = False) -> tuple:
        """Get max_tokens and temperature based on query type"""
        
        params = {
            "SIMPLE_FACT": (400, 0.2),      # Short, focused
            "DEFINITION": (600, 0.3),       # Medium, precise
            "PROCEDURAL": (1200, 0.3),      # Detailed, structured
            "COMPARISON": (1000, 0.3),      # Analytical
            "GENERATIVE": (500, 0.5),       # Helpful redirection
            "CODE_QUERY": (1500, 0.3),      # Code-heavy
            "EXPLORATORY": (2000, 0.35),    # Comprehensive, dynamic
        }
        
        tokens, temp = params.get(query_type, (1200, 0.35))

        # Hard cap for brevity/summary mode — forces the LLM to be concise
        if brevity_mode:
            return 400, 0.2
        
        # Boost tokens when images are available — LLM needs room for figure references
        if has_images:
            tokens = min(tokens + 300, 3000)
        
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
        context_instruction = ""
        if conversation_history and len(conversation_history) > 1:
            # Build a context summary from previous messages
            history_parts = []
            for msg in conversation_history[-8:-1]:  # Last 7 messages, excluding current
                role = msg.get('role', 'unknown').upper()
                content = msg.get('content', '')
                # Summarize long content
                if len(content) > 300:
                    content = content[:300] + "..."
                history_parts.append(f"[{role}]: {content}")
            
            if history_parts:
                context_instruction = f"""
╔══════════════════════════════════════════════════════════════════════════════╗
║  📚 CONVERSATION HISTORY - YOU MUST CONSIDER THIS CONTEXT!                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
{chr(10).join(history_parts)}

⚠️ CRITICAL: This is a CONTINUING CONVERSATION. Build upon previous answers!
"""
                # Add as a system-like message at the start
                messages.append({
                    "role": "user",
                    "content": context_instruction
                })
                messages.append({
                    "role": "assistant", 
                    "content": "I understand. I'll consider our previous conversation when answering your next question."
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
            doc_priority_note = f"""
⚠️ IMPORTANT: The user has attached a document ("{attached_name}").
- The UPLOADED DOCUMENT (marked as PRIMARY SOURCE) is the main source of truth.
- Answer primarily from the uploaded document content.
- Use the SUPPLEMENTARY Knowledge Base context only to add extra background or fill gaps.
- If the answer is found in the uploaded document, cite it as the source.
"""

        if query_type == "SIMPLE_FACT":
            user_message = f"""{doc_priority_note}Documentation:
{context}

Question: {chat_request.message}

Provide a direct, concise answer in 1-3 sentences. No extra formatting."""
        
        elif query_type == "GENERATIVE":
            if has_attached_doc:
                # With an attached document, allow generating answers FROM the document
                user_message = f"""{doc_priority_note}Documentation:
{context}

User Request: {chat_request.message}

Answer using the uploaded document as the primary source. Be comprehensive and helpful."""
            else:
                user_message = f"""Documentation Available:
{context}

User Request: {chat_request.message}

The user is asking you to GENERATE/CREATE new content. You cannot do this.

Instead:
1. Politely explain you can only reference existing documentation
2. Offer relevant examples or templates from the documentation
3. Ask what specific information from existing docs would be helpful

Be conversational and helpful, not robotic."""
        
        else:
            image_context = self._build_image_context(images or [])
            # Phase 7: Inject structured answer plan when available
            plan_context = ""
            if answer_plan:
                plan_context = f"\n\n{answer_plan.to_prompt_context()}\n"
            user_message = f"""{doc_priority_note}Documentation:
{context}
{image_context}{plan_context}
Question: {chat_request.message}

Provide a clear, intelligent, well-structured answer using the documentation above.{' Follow the ANSWER PLAN sections to organize your response.' if answer_plan else ' Structure the response dynamically to match the content — use the formatting approach best suited to the information available.'}"""

        # ── Apply brevity override at the message level ─────────────────────────
        # Regardless of query type, when brevity_mode is on, replace the user
        # message with a strict summary-only instruction so the LLM can't drift.
        if brevity_mode:
            user_message = f"""Documentation (for reference):
{context[:3000]}

Question: {chat_request.message}

⚠️ BREVITY REQUIRED: Give me a SHORT answer — maximum 3–5 bullet points or 2–3 sentences.
Do NOT write headings, background sections, long paragraphs, or extra context.
Stick strictly to the actual answer. Cite the source in one short line at the end."""

        messages.append({
            "role": "user",
            "content": user_message
        })
        
        return messages
    
    def _format_adaptive_response(self, response_text: str, query_type: str) -> str:
        """Format and polish response — clean up common LLM artefacts."""
        
        # Minimal formatting for simple facts
        if query_type == "SIMPLE_FACT":
            response_text = re.sub(r'\n{2,}', '\n', response_text)
            return response_text.strip()
        
        # Remove any trailing "Sources:" block the LLM may have added despite instructions
        response_text = re.sub(
            r'\n+(?:#{1,3}\s*)?(?:Source\s*References?|Sources?)\s*:?\s*\n'
            r'(?:[-•*]?\s*\[?[^\n]+\]?\n?)+\s*$',
            '', response_text, flags=re.IGNORECASE
        )
        
        # Collapse 3+ newlines into double
        response_text = re.sub(r'\n{3,}', '\n\n', response_text)
        
        # Remove leading/trailing whitespace
        response_text = response_text.strip()
        
        return response_text

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

