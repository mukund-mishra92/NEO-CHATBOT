"""
Agentic AI Service - Multi-Agent System with LangGraph
Implements a two-agent verification system where:
1. Response Agent generates initial answer from RAG context
2. Verification Agent validates and improves the response
"""

import logging
import os
from typing import Dict, Any, List, TypedDict, Annotated, Optional
from operator import add

# LangChain imports - with error handling
try:
    from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
    from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
    from langchain_core.output_parsers import StrOutputParser
    LANGCHAIN_AVAILABLE = True
except ImportError as e:
    logging.warning(f"LangChain not available: {e}. Install with: pip install langchain langchain-core")
    LANGCHAIN_AVAILABLE = False

# LangGraph imports - with error handling
try:
    from langgraph.graph import StateGraph, END
    from langgraph.graph.message import add_messages
    LANGGRAPH_AVAILABLE = True
except ImportError as e:
    logging.warning(f"LangGraph not available: {e}. Install with: pip install langgraph")
    LANGGRAPH_AVAILABLE = False

# Local imports
from .llm_service import LLMService
from .vector_store_service import VectorStoreService
from ..models.schemas import ChatRequest, ChatResponse, SourceDocument, MessageRole

logger = logging.getLogger(__name__)


class AgentState(TypedDict):
    """State passed between agents in the graph"""
    messages: Annotated[List, add_messages]  # Conversation history
    query: str  # User query
    rag_context: str  # Retrieved context from vector store
    source_documents: List[SourceDocument]  # Source documents for citation
    format_decision: str  # Format decision from format agent
    format_instructions: str  # Detailed format instructions
    user_constraints: Dict[str, Any]  # User's explicit requirements (word count, format, etc.)
    initial_response: str  # Response from first agent
    verified_response: str  # Verified response from second agent
    verification_notes: str  # Verification agent's notes
    verification_passed: bool  # Whether verification passed
    verification_issues: List[str]  # Issues found during verification
    confidence_score: float  # Overall confidence
    needs_verification: bool  # Whether verification is needed
    iteration_count: int  # Track number of iterations (for feedback loop)
    max_iterations: int  # Maximum iterations allowed


class AgenticService:
    """
    Multi-Agent Service using LangGraph
    Implements a verification workflow with two specialized agents
    """
    
    def __init__(self):
        """Initialize agentic service with LangChain components"""
        self.llm_service = LLMService()
        self.vector_store = VectorStoreService()
        
        # Check if dependencies are available
        if not LANGCHAIN_AVAILABLE or not LANGGRAPH_AVAILABLE:
            logger.error("❌ LangChain/LangGraph not available. Agentic mode will not work.")
            logger.error("Install with: pip install langchain langchain-core langchain-groq langgraph")
            self.llm = None
            self._graph = None
            self._graph_initialized = False
            return
        
        # Initialize LangChain LLM based on available provider
        self.llm = self._initialize_langchain_llm()
        
        # Lazy initialization: graph will be built on first use
        self._graph = None
        self._graph_initialized = False
        
        logger.info("✅ Agentic AI Service initialized (graph will be built on first query)")
    
    @property
    def graph(self):
        """Lazy-load the agent graph on first access"""
        if not LANGGRAPH_AVAILABLE:
            logger.error("❌ LangGraph not available. Cannot build agent graph.")
            return None
            
        if not self._graph_initialized:
            try:
                logger.info("🔨 Building agent graph on first use...")
                self._graph = self._build_agent_graph()
                self._graph_initialized = True
                logger.info("✅ Agent graph built successfully")
            except Exception as e:
                logger.error(f"❌ Error building agent graph: {e}", exc_info=True)
                # Don't raise - allow fallback to traditional mode
                self._graph = None
        return self._graph
    
    def _initialize_langchain_llm(self):
        """Initialize LangChain LLM wrapper based on available provider"""
        try:
            # Try Groq first (fastest)
            groq_key = os.getenv("GROQ_API_KEY") or os.getenv("GROK_API_KEY")
            if groq_key:
                from langchain_groq import ChatGroq
                llm = ChatGroq(
                    api_key=groq_key,
                    model="llama-3.3-70b-versatile",  # Updated to current model
                    temperature=0.7,
                    max_tokens=2000
                )
                logger.info("✅ Using Groq LLM for agents (llama-3.3-70b-versatile)")
                return llm
            
            # Fallback to OpenAI
            openai_key = os.getenv("OPENAI_API_KEY")
            if openai_key:
                from langchain_openai import ChatOpenAI
                llm = ChatOpenAI(
                    api_key=openai_key,
                    model="gpt-4-turbo-preview",
                    temperature=0.7,
                    max_tokens=2000
                )
                logger.info("✅ Using OpenAI LLM for agents")
                return llm
            
            # If no API available, use mock
            logger.warning("⚠️ No LLM API available for agents. Add GROQ_API_KEY or OPENAI_API_KEY")
            return None
            
        except Exception as e:
            logger.error(f"❌ Error initializing LangChain LLM: {e}")
            return None
    
    def _build_agent_graph(self) -> StateGraph:
        """
        Build the LangGraph workflow with three agents:
        1. Format Decision Agent: Determines optimal response format
        2. Response Agent: Generates answer in determined format
        3. Verification Agent: Validates and improves the answer
        """
        # Create workflow graph
        workflow = StateGraph(AgentState)
        
        # Add agent nodes
        workflow.add_node("format_decision_agent", self._format_decision_agent_node)
        workflow.add_node("response_agent", self._response_agent_node)
        workflow.add_node("verification_agent", self._verification_agent_node)
        workflow.add_node("finalize", self._finalize_node)
        
        # Define edges (workflow flow)
        workflow.set_entry_point("format_decision_agent")
        
        # After format decision, go to response agent
        workflow.add_edge("format_decision_agent", "response_agent")
        
        # After response agent, decide if verification is needed
        workflow.add_conditional_edges(
            "response_agent",
            self._should_verify,
            {
                "verify": "verification_agent",
                "skip_verify": "finalize"
            }
        )
        
        # After verification, check if it passed or needs feedback
        workflow.add_conditional_edges(
            "verification_agent",
            self._check_verification_result,
            {
                "passed": "finalize",
                "retry": "response_agent",  # FEEDBACK LOOP: Send back to response agent
                "max_iterations": "finalize"  # Stop after max iterations
            }
        )
        
        # Finalize is the end
        workflow.add_edge("finalize", END)
        
        # Compile the graph
        app = workflow.compile()
        
        logger.info("✅ Agent workflow graph compiled (3-agent system)")
        return app
    
    def _format_decision_agent_node(self, state: AgentState) -> AgentState:
        """
        Format Decision Agent: Analyzes query and determines optimal response format
        
        Responsibilities:
        - Detect user's format preferences (single line, paragraph, summary, etc.)
        - Extract constraints (word count, bullet points, etc.)
        - Determine optimal format based on query complexity
        - Provide clear formatting instructions to Response Agent
        """
        try:
            logger.info("📐 Format Decision Agent analyzing query...")
            
            if not self.llm:
                # Default format
                state["format_decision"] = "structured_paragraphs"
                state["format_instructions"] = "Use structured paragraphs with headers and bullet points."
                state["user_constraints"] = {}
                return state
            
            # Build prompt for intelligent format analysis (ChatGPT-style)
            format_prompt = ChatPromptTemplate.from_messages([
                ("system", """You analyze queries to understand HOW the answer should be presented - naturally adapting like ChatGPT does.

**Think About**:

1. **Query Intent**:
   - Quick fact check (what/when/who) → concise, direct
   - Explanation needed (how/why) → natural explanation with context
   - Seeking list ("types", "features", "components") → list when clear items exist
   - Process question ("how to", "steps") → sequential if procedural
   - Deep dive ("explain in detail", "architecture") → comprehensive

2. **User's Explicit Requests** (ALWAYS respect):
   - Word limits: "in 50 words", "briefly", "summarize"
   - Format: "bullet points", "list", "step by step"
   - Depth: "detailed", "overview", "quick answer"

3. **Natural Adaptation** (like ChatGPT):
   - Don't force rigid structures
   - Let content dictate format
   - Mix styles if helpful (paragraph + list)
   - Be brief when appropriate, thorough when needed
   - Natural flow over template adherence

**Respond with JSON**:
{{
    "response_approach": "<describe how to answer this - be specific about what makes sense>",
    "length": "brief|moderate|detailed",
    "use_lists": true/false,
    "use_structure": "none|light|full",
    "word_limit": <number or null>,
    "tone": "concise|conversational|technical",
    "special_notes": "<any other guidance>"
}}

**Examples**:
Query: "What is a sorter?"
→ brief, no lists, light structure, conversational - just explain what it is

Query: "How does the NEO system work?"  
→ moderate, maybe light structure, conversational - explain naturally with key points

Query: "List all conveyor types in the system"
→ moderate, use_lists: true if types exist in docs, concise - organize clearly

Query: {query}

Analyze naturally:"""),
                ("human", "How should I present the answer to this query?")
            ])
            
            # Generate format decision
            chain = format_prompt | self.llm | StrOutputParser()
            
            format_response = chain.invoke({
                "query": state["query"]
            })
            
            # Parse the format decision
            import json
            try:
                format_data = json.loads(format_response)
            except:
                # Fallback to adaptive
                format_data = {
                    "response_approach": "Answer naturally based on query needs",
                    "length": "moderate",
                    "use_lists": False,
                    "use_structure": "light",
                    "word_limit": None,
                    "tone": "conversational",
                    "special_notes": ""
                }
            
            # Build natural guidance (not rigid templates)
            format_instructions = self._build_natural_guidance(format_data)
            
            state["format_decision"] = format_data.get("response_approach", "adaptive")
            state["format_instructions"] = format_instructions
            state["user_constraints"] = {
                "length": format_data.get("length"),
                "word_limit": format_data.get("word_limit"),
                "use_lists": format_data.get("use_lists"),
                "tone": format_data.get("tone"),
                "special_notes": format_data.get("special_notes", "")
            }
            state["messages"].append(AIMessage(content=f"[Format Agent]: {format_data.get('length')} response with {format_data.get('tone')} tone"))
            
            logger.info(f"✅ Format Decision: {format_data.get('length')} (limit: {format_data.get('word_limit') or 'none'})")
            
            return state
            
        except Exception as e:
            logger.error(f"❌ Format Decision Agent error: {e}", exc_info=True)
            # Default format on error
            state["format_decision"] = "structured_paragraphs"
            state["format_instructions"] = "Use structured paragraphs with headers."
            state["user_constraints"] = {}
            return state
    
    def _build_natural_guidance(self, format_data: dict) -> str:
        """Build natural guidance for Response Agent (ChatGPT-style adaptation)"""
        
        guidance_parts = []
        
        # Start with the response approach
        approach = format_data.get("response_approach", "Answer naturally")
        guidance_parts.append(f"**Approach**: {approach}")
        
        # Length guidance
        length = format_data.get("length", "moderate")
        length_guide = {
            "brief": "Keep it concise - answer directly in 1-3 sentences unless more depth is clearly needed",
            "moderate": "Provide a clear, complete answer - typically 3-6 sentences or a short paragraph",
            "detailed": "Give a thorough, comprehensive response with context, details, and examples"
        }
        guidance_parts.append(f"**Length**: {length_guide.get(length, 'Adapt naturally to the query needs')}")
        
        # Structure guidance
        use_structure = format_data.get("use_structure", "light")
        if use_structure == "full":
            guidance_parts.append("**Structure**: Use clear sections with **bold headers** if covering multiple aspects")
        elif use_structure == "light":
            guidance_parts.append("**Structure**: Light structure - use **bold** for key terms, short paragraphs for readability")
        else:
            guidance_parts.append("**Structure**: Minimal - flow naturally like a conversation")
        
        # List usage
        if format_data.get("use_lists"):
            guidance_parts.append("**Lists**: Use bullet points (•) when listing distinct items/features/types - makes it clearer")
        else:
            guidance_parts.append("**Lists**: Only use lists if naturally listing multiple distinct items - otherwise prose")
        
        # Tone
        tone = format_data.get("tone", "conversational")
        tone_guide = {
            "concise": "Be direct and efficient with words - no fluff",
            "conversational": "Write naturally like explaining to a colleague - clear but friendly",
            "technical": "Use precise technical language with specifications and exact terms"
        }
        guidance_parts.append(f"**Tone**: {tone_guide.get(tone, 'Professional and clear')}")
        
        # Word limit if specified
        word_limit = format_data.get("word_limit")
        if word_limit:
            guidance_parts.append(f"**Word Limit**: ~{word_limit} words maximum - be concise")
        
        # Special notes
        special = format_data.get("special_notes", "")
        if special:
            guidance_parts.append(f"**Note**: {special}")
        
        # Always include these fundamentals
        guidance_parts.append("""
**Fundamentals** (always apply):
- Answer from the provided context ONLY
- Cite sources naturally: "According to Document 3..." or "(Document 3, Page 16)"
- Use specific details, numbers, model names from documents
- If context doesn't cover it, say "The documentation doesn't specify [topic]"
- NO markdown artifacts (```, Implementation:, etc.)
- NO invented information or assumptions
- Write like a human expert, not a document processor""")
        
        return "\n\n".join(guidance_parts)
    
    def _response_agent_node(self, state: AgentState) -> AgentState:
        """
        Response Agent: Generates initial answer based on RAG context
        
        Responsibilities:
        - Analyze user query and context
        - Generate comprehensive initial response
        - Cite sources appropriately
        - Structure information clearly
        """
        try:
            logger.info("🤖 Response Agent processing query...")
            
            if not self.llm:
                # Fallback to traditional method
                state["initial_response"] = "Error: No LLM available for agent"
                state["needs_verification"] = False
                return state
            
            # Build prompt for response agent (ChatGPT-style natural)
            response_prompt = ChatPromptTemplate.from_messages([
                ("system", """You are an expert on the NEO Warehouse Management System. Answer questions based on the provided documentation.

**How to Answer** (like ChatGPT):
1. **Understand the question** - What does the user really want to know?
2. **Find the information** - Look in the context provided below
3. **Answer naturally** - Write like you're explaining to a colleague, not reading from docs
4. **Be accurate** - Only use information from the context, cite sources when helpful
5. **Adapt your style** - Match the question's needs (brief vs detailed, technical vs accessible)

**Core Principles**:
- Use ONLY information from the provided context
- When you reference information, mention the source naturally: "According to Document 3..." or "(Document 3, Page 16)"
- If the context doesn't have the answer, be honest: "The documentation doesn't cover [specific topic]"
- Write in complete sentences with natural flow
- Use **bold** for key terms when it helps readability
- Use bullet points (•) when listing distinct items makes sense
- Be specific: "24,000 PPH throughput" not "high throughput"

**What NOT to do**:
- Don't invent information not in the context
- Don't use meta-text like "Implementation:" or "markdown" labels
- Don't include code block markers (```) unless showing actual code
- Don't list "types" or "categories" unless they're explicitly in the documents
- Don't be overly formal or robotic - write naturally

**Response Guidance**:
{format_instructions}

**Context** (documentation about NEO system):
{rag_context}

Answer this question naturally:"""),
                ("human", "{query}")
            ])
            
            # Generate response
            chain = response_prompt | self.llm | StrOutputParser()
            
            initial_response = chain.invoke({
                "query": state["query"],
                "rag_context": state["rag_context"],
                "format_instructions": state.get("format_instructions", "Use clear structure with headers and bullet points.")
            })
            
            state["initial_response"] = initial_response
            state["messages"].append(AIMessage(content=f"[Response Agent]: {initial_response}"))
            
            logger.info(f"✅ Response Agent generated answer ({len(initial_response)} chars)")
            
            # Determine if verification is needed (complex queries need verification)
            state["needs_verification"] = self._determine_verification_need(
                state["query"], 
                initial_response
            )
            
            return state
            
        except Exception as e:
            logger.error(f"❌ Response Agent error: {e}", exc_info=True)
            state["initial_response"] = f"Error in Response Agent: {str(e)}"
            state["needs_verification"] = False
            return state
    
    def _verification_agent_node(self, state: AgentState) -> AgentState:
        """
        Verification Agent: Validates and improves the initial response
        
        Responsibilities:
        - Fact-check against provided context
        - Identify gaps or inaccuracies
        - Improve clarity and structure
        - Enhance with additional relevant details
        - Ensure proper citations
        """
        try:
            logger.info("🔍 Verification Agent validating response...")
            
            if not self.llm:
                state["verified_response"] = state["initial_response"]
                state["verification_notes"] = "Verification skipped: No LLM available"
                return state
            
            # Build prompt for verification agent (ChatGPT-style quality check)
            verification_prompt = ChatPromptTemplate.from_messages([
                ("system", """You're the quality checker. Review the response and make it excellent.

**Your Job**:
Read the initial response and improve it while keeping what works well.

**Check These Things**:

1. **Accuracy** - Most important
   - Every fact MUST come from the context below
   - If something isn't in the context, remove it or note "The documentation doesn't cover [topic]"
   - Check numbers, specifications, component names match exactly
   - Remove any invented "types" or categories not explicitly in docs

2. **Completeness**
   - Did we answer the whole question?
   - Are there relevant details in the context we should add?
   - Are specific model numbers, capacities, or specs mentioned in docs that we missed?

3. **Natural Writing**
   - Does it read smoothly like a human wrote it?
   - Are citations natural? ("According to Document 3..." not awkward references)
   - Remove any meta-text like "Implementation:" or markdown artifacts (```)
   - Fix any robotic or template-like phrasing

4. **Style Match**
   - Follow the guidance: {format_instructions}
   - Respect any word limits or user preferences: {user_constraints}
   - Maintain the intended approach: {format_decision}

**What Makes a Great Response**:
✓ Accurate (everything traceable to context)
✓ Complete (answers the full question)
✓ Natural (reads like a person explaining, not docs regurgitation)
✓ Specific (real numbers, names, details from docs)
✓ Clean (no artifacts, meta-text, or awkward formatting)
✓ Well-cited (sources mentioned naturally when helpful)

**Context** (the source of truth):
{rag_context}

**Original Question**:
{query}

**Initial Response to Review**:
{initial_response}

Provide the improved version:"""),
                ("human", "Review and improve this response.")
            ])
            
            # Generate verified response
            chain = verification_prompt | self.llm | StrOutputParser()
            
            verified_response = chain.invoke({
                "query": state["query"],
                "rag_context": state["rag_context"],
                "initial_response": state["initial_response"],
                "format_instructions": state.get("format_instructions", "Use clear structure."),
                "format_decision": state.get("format_decision", "structured_paragraphs"),
                "user_constraints": str(state.get("user_constraints", {}))
            })
            
            # Step 2: VALIDATION - Check if the verified response passes quality checks
            validation_result = self._validate_response(
                query=state["query"],
                response=verified_response,
                context=state["rag_context"]
            )
            
            state["verified_response"] = verified_response
            state["verification_passed"] = validation_result["passed"]
            state["verification_issues"] = validation_result["issues"]
            state["verification_notes"] = validation_result["notes"]
            state["messages"].append(AIMessage(content=f"[Verification Agent]: {verified_response}"))
            
            if validation_result["passed"]:
                logger.info(f"✅ Verification PASSED ({len(verified_response)} chars)")
            else:
                logger.warning(f"⚠️ Verification FAILED: {', '.join(validation_result['issues'])}")
            
            return state
            
        except Exception as e:
            logger.error(f"❌ Verification Agent error: {e}", exc_info=True)
            state["verified_response"] = state["initial_response"]
            state["verification_passed"] = False
            state["verification_issues"] = [f"Verification error: {str(e)}"]
            state["verification_notes"] = f"Verification failed: {str(e)}"
            return state
    
    def _finalize_node(self, state: AgentState) -> AgentState:
        """
        Finalize: Prepare final response and calculate confidence
        """
        # Use verified response if available, otherwise use initial
        final_response = state.get("verified_response") or state.get("initial_response", "No response generated")
        
        # Calculate confidence based on verification status
        if state.get("verified_response"):
            confidence = 0.95  # High confidence after verification
        elif state.get("initial_response"):
            confidence = 0.75  # Medium confidence without verification
        else:
            confidence = 0.50  # Low confidence if something went wrong
        
        state["confidence_score"] = confidence
        
        logger.info(f"✅ Finalized response (confidence: {confidence:.2f})")
        return state
    
    def _validate_response(self, query: str, response: str, context: str) -> Dict[str, Any]:
        """
        Validate response quality using LLM-based checks
        
        Returns dict with: passed (bool), issues (list), notes (str)
        """
        try:
            if not self.llm:
                return {"passed": True, "issues": [], "notes": "Validation skipped (no LLM)"}
            
            # Build validation prompt
            validation_prompt = ChatPromptTemplate.from_messages([
                ("system", """You are a Quality Validation Agent for the NEO Warehouse Management System chatbot.

**Your Task**: Validate if the response meets quality standards.

**Validation Criteria** (ALL must pass):
1. ✅ **No Hallucinations**: Every claim is supported by the provided context
2. ✅ **Accurate Citations**: Document references are correct
3. ✅ **Completeness**: Query is fully answered
4. ✅ **Specificity**: Uses actual technical details (not generic statements)
5. ✅ **No Contradictions**: Response doesn't contradict the context

**Output Format** (JSON only):
```json
{{
    "passed": true/false,
    "issues": ["issue 1", "issue 2", ...],
    "notes": "Overall assessment"
}}
```

Query: {query}

Context Available:
{context}

Response to Validate:
{response}

Validate and return JSON:"""),
                ("human", "Perform validation checks.")
            ])
            
            chain = validation_prompt | self.llm | StrOutputParser()
            
            validation_json = chain.invoke({
                "query": query,
                "context": context[:2000],  # Truncate long context
                "response": response
            })
            
            # Parse validation result
            import json
            try:
                result = json.loads(validation_json)
                return {
                    "passed": result.get("passed", False),
                    "issues": result.get("issues", []),
                    "notes": result.get("notes", "Validation completed")
                }
            except:
                # Fallback: Check for obvious issues (more lenient)
                # Check for any document reference patterns (more flexible)
                has_doc_ref = any(pattern in response for pattern in ["Document", "📄", "File:", "Source:", "[", ".pdf", ".docx", "from the"])
                is_long_enough = len(response) > 30  # Reduced from 50
                # Removed generic check as it was too strict
                
                passed = has_doc_ref and is_long_enough
                issues = []
                if not has_doc_ref:
                    issues.append("Missing document citations")
                if not is_long_enough:
                    issues.append("Response too short")
                
                return {"passed": passed, "issues": issues, "notes": "Validation completed (fallback)"}
                
        except Exception as e:
            logger.error(f"❌ Validation error: {e}")
            return {"passed": True, "issues": [], "notes": f"Validation error: {str(e)}"}
    
    def _check_verification_result(self, state: AgentState) -> str:
        """
        Check if verification passed and determine next step
        
        Returns: "passed", "retry", or "max_iterations"
        """
        iteration_count = state.get("iteration_count", 0)
        max_iterations = state.get("max_iterations", 2)  # Allow 2 retries
        verification_passed = state.get("verification_passed", True)
        
        if verification_passed:
            logger.info("✅ Verification passed - proceeding to finalize")
            return "passed"
        
        if iteration_count >= max_iterations:
            logger.warning(f"⚠️ Max iterations ({max_iterations}) reached - using current response")
            return "max_iterations"
        
        # Increment iteration and retry
        state["iteration_count"] = iteration_count + 1
        logger.info(f"🔄 Verification failed - retry #{state['iteration_count']} (issues: {state.get('verification_issues', [])})")
        
        # Add feedback to messages for Response Agent to see
        issues_text = ", ".join(state.get("verification_issues", []))
        state["messages"].append(SystemMessage(content=f"""
[FEEDBACK FROM VERIFICATION]: Previous response had issues: {issues_text}

Please regenerate the response addressing these issues:
- Ensure all claims are from the provided context
- Add proper document citations
- Be specific with technical details
- Avoid generic statements
"""))
        
        return "retry"
    
    def _should_verify(self, state: AgentState) -> str:
        """
        Decide whether verification is needed
        
        Returns:
            "verify" or "skip_verify"
        """
        if state.get("needs_verification", True):
            logger.info("➡️ Routing to verification agent")
            return "verify"
        else:
            logger.info("➡️ Skipping verification (simple query)")
            return "skip_verify"
    
    def _determine_verification_need(self, query: str, response: str) -> bool:
        """
        Determine if a query needs verification based on complexity
        
        Simple queries (greetings, confirmations) skip verification
        Complex queries (technical, multi-part) get verified
        """
        # Simple queries that don't need verification
        simple_patterns = [
            "hello", "hi", "hey", "thanks", "thank you",
            "ok", "okay", "yes", "no", "bye", "goodbye"
        ]
        
        query_lower = query.lower().strip()
        
        # Skip verification for very simple queries
        if any(pattern in query_lower for pattern in simple_patterns) and len(query.split()) <= 3:
            return False
        
        # Skip verification for very short responses
        if len(response) < 100:
            return False
        
        # All other queries need verification
        return True
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process user query using multi-agent workflow
        
        Args:
            chat_request: User's chat request
            
        Returns:
            Chat response with verified answer
        """
        try:
            logger.info(f"🚀 Agentic AI processing query: {chat_request.message[:50]}...")
            
            # Step 1: Retrieve context from RAG with improved strategy
            # 1a. Expand query with domain-specific terms
            expanded_query = self._expand_query_terms(chat_request.message)
            logger.info(f"🔍 Query expanded: {expanded_query[:100]}...")
            
            # 1b. Generate embedding and retrieve top-k candidates
            query_embedding = self.llm_service.generate_embedding(expanded_query)
            
            search_results = self.vector_store.search(
                query_embedding=query_embedding,
                top_k=20,  # Retrieve more candidates for ranking
                min_similarity=0.28  # Lower threshold for ranking phase
            )
            
            logger.info(f"📚 Retrieved {len(search_results)} document candidates")
            
            # 1c. RANKING: Use LLM to rank and select most relevant documents
            if self.llm and len(search_results) > 10:
                ranked_results = self._rank_documents_with_llm(
                    query=chat_request.message,
                    search_results=search_results,
                    top_k=10
                )
                logger.info(f"📊 Ranked to top {len(ranked_results)} most relevant documents")
            else:
                ranked_results = search_results[:10]
            
            # Build context and extract sources from ranked results
            rag_context = self._build_context(ranked_results)
            source_documents = self._extract_source_documents(ranked_results)
            
            # Step 2: Initialize agent state with feedback loop tracking
            initial_state: AgentState = {
                "messages": [HumanMessage(content=chat_request.message)],
                "query": chat_request.message,
                "rag_context": rag_context,
                "source_documents": source_documents,
                "format_decision": "",
                "format_instructions": "",
                "user_constraints": {},
                "initial_response": "",
                "verified_response": "",
                "verification_notes": "",
                "verification_passed": True,
                "verification_issues": [],
                "confidence_score": 0.0,
                "needs_verification": True,
                "iteration_count": 0,
                "max_iterations": 2  # Allow up to 2 retries
            }
            
            # Step 3: Run the agent workflow
            if not self.graph:
                logger.error("❌ Agent graph not available - falling back to error response")
                return ChatResponse(
                    response="Agentic AI system is not properly initialized. Please check that LangChain and LangGraph are installed.",
                    session_id=chat_request.session_id or "default-session",
                    chatbot_type=chat_request.chatbot_type,
                    confidence_score=0.0,
                    source_documents=[],
                    metadata={"error": "Graph not initialized", "agent_workflow": "unavailable"}
                )
            
            final_state = self.graph.invoke(initial_state)
            
            # Step 4: Extract final response
            final_response = final_state.get("verified_response") or final_state.get("initial_response", "No response generated")
            confidence = final_state.get("confidence_score", 0.5)
            
            # Step 5: Build chat response with enhanced metadata
            response = ChatResponse(
                response=final_response,
                session_id=chat_request.session_id or "default-session",
                chatbot_type=chat_request.chatbot_type,
                confidence_score=confidence,
                source_documents=source_documents,
                metadata={
                    "agent_workflow": "3-agent-system-with-ranking-and-feedback",
                    "documents_retrieved": len(search_results),
                    "documents_ranked": len(ranked_results),
                    "format_decision": final_state.get("format_decision", "structured_paragraphs"),
                    "format_instructions": final_state.get("format_instructions", ""),
                    "user_constraints": final_state.get("user_constraints", {}),
                    "verification_performed": bool(final_state.get("verified_response")),
                    "verification_passed": final_state.get("verification_passed", True),
                    "verification_issues": final_state.get("verification_issues", []),
                    "verification_notes": final_state.get("verification_notes", ""),
                    "iterations_used": final_state.get("iteration_count", 0),
                    "initial_response_length": len(final_state.get("initial_response", "")),
                    "final_response_length": len(final_response)
                }
            )
            
            logger.info(f"✅ Agentic AI completed (confidence: {confidence:.2f})")
            return response
            
        except Exception as e:
            logger.error(f"❌ Agentic AI error: {e}", exc_info=True)
            
            # Fallback to simple response
            return ChatResponse(
                response=f"I encountered an error processing your request: {str(e)}",
                session_id=chat_request.session_id or "error-session",
                chatbot_type=chat_request.chatbot_type,
                confidence_score=0.0,
                source_documents=[],
                metadata={"error": str(e), "agent_workflow": "failed"}
            )
    
    def _rank_documents_with_llm(self, query: str, search_results: List[Dict[str, Any]], top_k: int = 10) -> List[Dict[str, Any]]:
        """
        Use LLM to intelligently rank documents by relevance to query
        This provides better ranking than just cosine similarity
        """
        try:
            if not self.llm or len(search_results) <= top_k:
                return search_results[:top_k]
            
            logger.info(f"🎯 LLM ranking {len(search_results)} documents for relevance...")
            
            # Build ranking prompt with document summaries
            doc_summaries = []
            for i, result in enumerate(search_results[:20], 1):  # Rank top 20 candidates
                doc = result["document"]
                content_preview = doc.get('content', '')[:200]
                doc_summaries.append(f"""
Document {i}:
Source: {doc.get('source_file', 'Unknown')}
Similarity: {result['similarity']:.2f}
Preview: {content_preview}...
""")
            
            ranking_prompt = ChatPromptTemplate.from_messages([
                ("system", """You are a document ranking expert for the NEO Warehouse Management System.

Your task: Rank documents by relevance to the user's query.

**Ranking Criteria**:
1. **Direct Relevance**: Does the document directly answer the query?
2. **Technical Depth**: Does it contain specific technical details needed?
3. **Completeness**: Does it provide comprehensive information?
4. **Specificity**: Does it mention exact components/features asked about?

**Instructions**:
- Analyze each document preview
- Consider the query context
- Rank by actual usefulness, not just keyword matching
- Return ONLY the document numbers in order of relevance (comma-separated)
- Example output: "5,2,8,1,3,7,4,6,9,10"

Query: {query}

Documents to rank:
{documents}

Output the top {top_k} document numbers (most relevant first):"""),
                ("human", "Rank these documents by relevance.")
            ])
            
            chain = ranking_prompt | self.llm | StrOutputParser()
            
            ranking_response = chain.invoke({
                "query": query,
                "documents": "\n".join(doc_summaries),
                "top_k": top_k
            })
            
            # Parse ranking (expect comma-separated numbers like "5,2,8,1,3")
            try:
                ranked_indices = [int(x.strip()) - 1 for x in ranking_response.strip().split(",") if x.strip().isdigit()]
                ranked_results = [search_results[i] for i in ranked_indices if 0 <= i < len(search_results)]
                
                # Add remaining docs if not enough ranked
                if len(ranked_results) < top_k:
                    remaining = [doc for i, doc in enumerate(search_results) if i not in ranked_indices]
                    ranked_results.extend(remaining[:top_k - len(ranked_results)])
                
                logger.info(f"✅ LLM ranking complete: {len(ranked_results)} documents reordered")
                return ranked_results[:top_k]
                
            except Exception as parse_error:
                logger.warning(f"⚠️ Ranking parse error, using similarity order: {parse_error}")
                return search_results[:top_k]
                
        except Exception as e:
            logger.error(f"❌ LLM ranking failed: {e}, falling back to similarity ranking")
            return search_results[:top_k]
    
    def _expand_query_terms(self, query: str) -> str:
        """Expand query with domain-specific synonyms and related terms"""
        query_lower = query.lower()
        
        # Domain-specific term expansions for NEO system
        expansions = {
            "sorter": "sorter sortation cross-belt sorting chute destination",
            "conveyor": "conveyor conveyer belt roller powered accumulation telescopic",
            "sensor": "sensor scanner barcode 1D 2D RFID detection PLC",
            "induct": "induct induction GTC goods-to-conveyor put-away",
            "gtc": "GTC goods-to-conveyor station workstation pick",
            "robot": "robot bot NEO automated ASRS storage retrieval",
            "wcs": "WCS warehouse control system falcon software",
            "plc": "PLC programmable logic controller siemens omron",
            "picking": "picking pick-to-light PTL order consolidation fulfillment",
            "storage": "storage ASRS automated bin tote grid rack",
            "telescopic": "telescopic extendable retractable conveyor loading unloading",
            "components": "components parts modules equipment devices hardware system architecture",
            "types": "types categories models configurations variants specifications"
        }
        
        # Add relevant expansions
        expanded_terms = [query]
        for term, expansion in expansions.items():
            if term in query_lower:
                expanded_terms.append(expansion)
        
        return " ".join(expanded_terms)
    
    def _build_context(self, search_results: List[Dict[str, Any]]) -> str:
        """Build context string from search results with enhanced details"""
        if not search_results:
            return "No relevant context found."
        
        context_parts = []
        # Increased from 5 to 10 for more comprehensive context
        for i, result in enumerate(search_results[:10], 1):
            doc = result["document"]
            similarity = result["similarity"]
            
            # Include more content (800 chars instead of 500) for better context
            content = doc.get('content', '')[:800]
            source_file = doc.get('source_file', 'Unknown')
            page_num = doc.get('page_number', 'N/A')
            doc_type = doc.get('document_type', 'document')
            
            context_parts.append(f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Document {i} - Relevance: {similarity:.2f}
Source: {source_file}
Type: {doc_type}
Page: {page_num}
Content: {content}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        
        return "\n".join(context_parts)
    
    def _extract_source_documents(self, search_results: List[Dict[str, Any]]) -> List[SourceDocument]:
        """Extract source documents for citation"""
        sources = []
        
        for result in search_results[:5]:
            doc = result["document"]
            sources.append(SourceDocument(
                document_name=doc.get("source_file", "Unknown"),
                content_snippet=doc.get("content", "")[:200],
                relevance_score=result["similarity"],
                page_number=doc.get("page_number"),
                document_type=doc.get("type", "unknown")
            ))
        
        return sources


# Singleton instance
_agentic_service = None

def get_agentic_service() -> AgenticService:
    """Get or create singleton AgenticService instance"""
    global _agentic_service
    if _agentic_service is None:
        _agentic_service = AgenticService()
    return _agentic_service

