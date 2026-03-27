"""
LLM Service - Integration with Large Language Models (OpenAI/Anthropic/Local)
Handles AI interactions for the chatbot with fallback to local LLM
"""

import os
import logging
from typing import List, Dict, Any, Optional
from .ai_config_service import get_ai_config_service

logger = logging.getLogger(__name__)


class LLMService:
    """
    Service for interacting with Large Language Models
    Supports Groq, OpenAI, Anthropic with automatic fallback to local LLM
    """
    
    def __init__(self):
        """Initialize LLM service with API keys from environment"""
        self.ai_config = get_ai_config_service().get_config()
        self.configured_provider = self.ai_config.get("active_provider", "openai")
        configured_chat_model = self.ai_config.get("chat_model", "gpt-5.2")
        self.openai_chat_model = configured_chat_model if self.configured_provider == "openai" else "gpt-5.2"
        self.groq_chat_model = configured_chat_model if self.configured_provider == "groq" else "llama-3.3-70b-versatile"
        self.embedding_model = self.ai_config.get("embedding_model", "text-embedding-3-small")

        self.groq_api_key = os.getenv("GROQ_API_KEY") or os.getenv("GROK_API_KEY")  # Groq (fast inference) - Priority 1
        self.openai_api_key = os.getenv("OPENAI_API_KEY")
        self.anthropic_api_key = os.getenv("ANTHROPIC_API_KEY")
        self.huggingface_api_key = os.getenv("HUGGINGFACE_API_KEY") or os.getenv("HF_TOKEN")  # HuggingFace for FREE embeddings
        
        # Local LLM fallback settings
        from app.core.config import settings
        self.local_llm_enabled = settings.LOCAL_LLM_ENABLED
        self.local_llm_model = settings.LOCAL_LLM_MODEL
        self.local_llm_service = None
        
        # HuggingFace client for embeddings
        self.hf_client = None
        if self.huggingface_api_key:
            try:
                from huggingface_hub import InferenceClient
                # Add timeout to prevent hanging
                self.hf_client = InferenceClient(
                    token=self.huggingface_api_key,
                    timeout=30  # 30 second timeout
                )
                logger.info("✅ HuggingFace API initialized for FREE embeddings")
            except ImportError:
                logger.warning("⚠️ huggingface_hub not installed. Run: pip install huggingface_hub")
            except Exception as e:
                logger.warning(f"⚠️ HuggingFace initialization failed: {e}")
        
        # Determine which provider to use (Groq has priority)
        self.provider = None
        self.groq_client = None
        self.openai_client = None
        self.anthropic_client = None
        
        # Initialize ALL available clients (for fallback support)
        # Try OpenAI client
        if self.openai_api_key:
            try:
                from openai import OpenAI
                self.openai_client = OpenAI(api_key=self.openai_api_key)
                logger.info("✅ OpenAI client initialized")
            except ImportError:
                logger.warning("⚠️ OpenAI package not installed. Run: pip install openai")
            except Exception as e:
                logger.warning(f"⚠️ OpenAI initialization failed: {e}")
        
        # Initialize Groq client
        if self.groq_api_key:
            try:
                from groq import Groq
                self.groq_client = Groq(api_key=self.groq_api_key)
                logger.info("✅ Groq (Fast Inference) client initialized")
            except ImportError:
                logger.warning("⚠️ Groq package not installed. Run: pip install groq")
            except Exception as e:
                logger.warning(f"⚠️ Groq initialization failed: {e}")
        
        # Initialize Anthropic client (not part of admin AI config, fallback only)
        if self.anthropic_api_key:
            try:
                import anthropic
                self.anthropic_client = anthropic.Anthropic(api_key=self.anthropic_api_key)
                logger.info("✅ Anthropic client initialized")
            except ImportError:
                logger.warning("⚠️ Anthropic package not installed. Run: pip install anthropic")
            except Exception as e:
                logger.warning(f"⚠️ Anthropic initialization failed: {e}")
        
        # Pick primary provider based on admin config, then available fallbacks.
        if self.configured_provider == "groq" and self.groq_client:
            self.provider = "groq"
        elif self.configured_provider == "openai" and self.openai_client:
            self.provider = "openai"
        elif self.openai_client:
            self.provider = "openai"
        elif self.groq_client:
            self.provider = "groq"
        elif self.anthropic_client:
            self.provider = "anthropic"

        if self.provider:
            logger.info(
                "🎯 Primary LLM provider: %s (configured=%s)",
                self.provider.upper(),
                self.configured_provider.upper(),
            )
        
        # Initialize local LLM if enabled and no cloud API available
        if not self.provider and self.local_llm_enabled:
            try:
                from .local_llm_service import get_local_llm
                self.local_llm_service = get_local_llm(model_name=self.local_llm_model)
                self.provider = "local_llm"
                logger.info(f"✅ Local LLM initialized ({self.local_llm_model})")
            except Exception as e:
                logger.warning(f"⚠️ Local LLM initialization failed: {e}")
        
        if not self.provider:
            logger.warning("⚠️ No LLM available - using mock responses")
            logger.warning("   Add GROQ_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY to .env")
            logger.warning("   Or enable LOCAL_LLM_ENABLED=true in config")
            self.provider = "mock"

    def _refresh_runtime_config(self) -> None:
        """Reload AI config so long-lived instances pick up admin changes."""
        cfg = get_ai_config_service().get_config()
        configured_provider = cfg.get("active_provider", "openai")
        configured_chat_model = cfg.get("chat_model", "gpt-5.2")

        self.configured_provider = configured_provider
        self.openai_chat_model = configured_chat_model if configured_provider == "openai" else "gpt-5.2"
        self.groq_chat_model = configured_chat_model if configured_provider == "groq" else "llama-3.3-70b-versatile"
        self.embedding_model = cfg.get("embedding_model", "text-embedding-3-small")

        if configured_provider == "groq" and self.groq_client:
            self.provider = "groq"
        elif configured_provider == "openai" and self.openai_client:
            self.provider = "openai"
        elif self.openai_client:
            self.provider = "openai"
        elif self.groq_client:
            self.provider = "groq"
        elif self.anthropic_client:
            self.provider = "anthropic"
        elif self.local_llm_enabled:
            self.provider = "local_llm"
        else:
            self.provider = "mock"
    
    def generate_response(
        self, 
        messages: List[Dict[str, str]], 
        system_prompt: Optional[str] = None,
        max_tokens: int = 1000,
        temperature: float = 0.1
    ) -> str:
        """
        Generate response from LLM
        
        Args:
            messages: Conversation messages [{"role": "user", "content": "..."}]
            system_prompt: System instructions for the LLM
            max_tokens: Maximum response length
            temperature: Creativity (0.0 = deterministic, 1.0 = creative)
            
        Returns:
            Generated response text
        """
        try:
            self._refresh_runtime_config()
            if self.provider == "groq":
                return self._generate_groq(messages, system_prompt, max_tokens, temperature)
            elif self.provider == "openai":
                return self._generate_openai(messages, system_prompt, max_tokens, temperature)
            elif self.provider == "anthropic":
                return self._generate_anthropic(messages, system_prompt, max_tokens, temperature)
            elif self.provider == "local_llm":
                return self._generate_local_llm(messages, system_prompt, max_tokens, temperature)
            else:
                return self._generate_mock(messages)
                
        except Exception as e:
            logger.error(f"❌ Error with {self.provider} LLM: {e}")
            
            # Try fallback chain: Groq → Anthropic → Local LLM (OpenAI is primary, so fallback to others)
            fallback_tried = []
            
            # Try Groq if available and not already using it
            if self.groq_api_key and self.groq_client and self.provider != "groq":
                try:
                    fallback_tried.append("Groq")
                    logger.info("🔄 Attempting fallback to Groq...")
                    return self._generate_groq(messages, system_prompt, max_tokens, temperature)
                except Exception as groq_error:
                    logger.error(f"❌ Groq fallback failed: {groq_error}")
            
            # Try Anthropic if available and not already using it
            if self.anthropic_api_key and self.provider != "anthropic":
                try:
                    fallback_tried.append("Anthropic")
                    logger.info("🔄 Attempting fallback to Anthropic...")
                    return self._generate_anthropic(messages, system_prompt, max_tokens, temperature)
                except Exception as anthropic_error:
                    logger.error(f"❌ Anthropic fallback failed: {anthropic_error}")
            
            # Try local LLM if enabled and not already using it
            if self.local_llm_enabled and self.provider != "local_llm":
                try:
                    fallback_tried.append("Local LLM")
                    logger.info("🔄 Attempting fallback to local LLM...")
                    return self._generate_local_llm(messages, system_prompt, max_tokens, temperature)
                except Exception as fallback_error:
                    logger.error(f"❌ Local LLM fallback also failed: {fallback_error}")
            
            logger.error(f"❌ All fallbacks exhausted. Tried: {', '.join(fallback_tried) if fallback_tried else 'none available'}")
            return "I apologize, but I encountered an error processing your request. Please try again."
    
    def _generate_groq(
        self, 
        messages: List[Dict[str, str]], 
        system_prompt: Optional[str],
        max_tokens: int,
        temperature: float
    ) -> str:
        """Generate response using Groq (Fast Inference API)"""
        try:
            full_messages = []
            if system_prompt:
                full_messages.append({"role": "system", "content": system_prompt})
            full_messages.extend(messages)
            
            response = self.groq_client.chat.completions.create(
                model=self.groq_chat_model,
                #model = "llama-3.1-8b-instant",  # Too small, produces templated responses
                #model = "mixtral-8x7b",
                #model = "qwen2-72b-instruct",
                messages=full_messages,
                max_tokens=max_tokens,
                temperature=temperature
            )
            
            return response.choices[0].message.content
        except Exception as e:
            # Check if it's a rate limit error
            error_str = str(e)
            if "rate_limit" in error_str.lower() or "429" in error_str:
                logger.warning(f"⚠️ Groq rate limit hit: {error_str[:200]}")
                raise  # Re-raise to trigger fallback
            else:
                logger.error(f"❌ Groq error: {e}")
                raise
    
    def _generate_openai(
        self, 
        messages: List[Dict[str, str]], 
        system_prompt: Optional[str],
        max_tokens: int,
        temperature: float
    ) -> str:
        """Generate response using OpenAI GPT"""
        full_messages = []
        if system_prompt:
            full_messages.append({"role": "system", "content": system_prompt})
        full_messages.extend(messages)
        
        response = self.openai_client.chat.completions.create(
            model=self.openai_chat_model,
            messages=full_messages,
            max_tokens=max_tokens,
            stream=True,
            temperature=temperature
        )
        
        return response.choices[0].message.content
    
    def _generate_anthropic(
        self, 
        messages: List[Dict[str, str]], 
        system_prompt: Optional[str],
        max_tokens: int,
        temperature: float
    ) -> str:
        """Generate response using Anthropic Claude"""
        response = self.anthropic_client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=max_tokens,
            temperature=temperature,
            system=system_prompt or "You are NEO, an intelligent assistant for warehouse management.",
            messages=messages
        )
        
        return response.content[0].text
    
    def _generate_local_llm(
        self,
        messages: List[Dict[str, str]],
        system_prompt: Optional[str],
        max_tokens: int,
        temperature: float
    ) -> str:
        """Generate response using local LLM (fallback)"""
        # Initialize local LLM if not already done
        if self.local_llm_service is None:
            from .local_llm_service import get_local_llm
            self.local_llm_service = get_local_llm(model_name=self.local_llm_model)
        
        # Prepare messages with system prompt
        full_messages = []
        if system_prompt:
            full_messages.append({"role": "system", "content": system_prompt})
        full_messages.extend(messages)
        
        # Generate using local LLM
        logger.info(f"💾 Using local LLM: {self.local_llm_model}")
        response = self.local_llm_service.chat(
            messages=full_messages,
            max_tokens=max_tokens,
            temperature=temperature
        )
        
        return response
    
    def _generate_mock(self, messages: List[Dict[str, str]]) -> str:
        """Generate mock response when no API key is available"""
        user_message = messages[-1]["content"].lower()
        
        # Simple keyword-based responses
        if "database" in user_message or "sql" in user_message:
            return """To use the SQL assistant feature, I need access to an AI model. 
            
Please configure either:
- OpenAI API key: Add OPENAI_API_KEY to your .env file
- Anthropic API key: Add ANTHROPIC_API_KEY to your .env file

For database queries, I can help you:
- Generate SQL queries from natural language
- Explain database structure
- Show data insights

Once configured, just ask me questions like "Show me top 10 SKUs" and I'll generate the SQL for you!"""
        
        elif "scheduler" in user_message or "mining" in user_message:
            return """I can help with scheduler and mining issues!

Common issues I can diagnose:
- Scheduler not running
- Mining jobs not executing
- Custom parameters not working
- Database connection issues

Please describe your issue in detail, and I'll guide you through troubleshooting steps.

Note: For full AI capabilities, please add OPENAI_API_KEY or ANTHROPIC_API_KEY to your .env file."""
        
        elif "help" in user_message:
            return """Hi! I'm NEO Assistant. I can help you with:

**📚 Documentation Q&A**
- Answer questions about NEO system
- Explain features and configurations
- Provide examples and best practices

**💾 Database Assistant**  
- Convert questions to SQL queries
- Show data insights
- Explain database structure

**🔧 Diagnostic Support**
- Troubleshoot system issues
- Guide through problem resolution
- Provide solutions and prevention tips

**⚠️ Note**: Currently running in mock mode. For full AI capabilities:
1. Get an API key from OpenAI or Anthropic
2. Add to .env file: OPENAI_API_KEY=your_key
3. Restart the application

What would you like help with?"""
        
        else:
            return f"""I understand you're asking about: "{messages[-1]['content']}"

This is a mock response since no AI API key is configured.

To enable full chatbot functionality:
1. Obtain API key from OpenAI (https://platform.openai.com) or Anthropic
2. Add to .env file: OPENAI_API_KEY=sk-your-key-here
3. Restart the application

Currently available (with limited functionality):
- Issue diagnostics based on support knowledge base
- Database schema information
- System status checks

How can I help you today?"""
    
    def generate_embedding(self, text: str) -> List[float]:
        """
        Generate embedding vector for text (for vector search)
        
        Priority (UPDATED FOR RELIABILITY):
        1. OpenAI (paid but MOST RELIABLE, excellent quality)
        2. HuggingFace (FREE but may timeout due to network issues)
        3. Mock embeddings (fallback for testing only)
        
        Args:
            text: Text to embed
            
        Returns:
            Embedding vector (1536 or 384 dimensions)
        """
        try:
            self._refresh_runtime_config()
            # Priority 1: OpenAI Embeddings (MOST RELIABLE!)
            if self.openai_client:
                try:
                    response = self.openai_client.embeddings.create(
                        model=self.embedding_model,
                        input=text
                    )
                    embedding = response.data[0].embedding
                    logger.debug(f"✅ Generated OpenAI embedding ({len(embedding)} dims)")
                    return embedding
                except Exception as openai_error:
                    logger.warning(f"⚠️ OpenAI embedding failed: {openai_error}, trying HuggingFace...")
            
            # Priority 2: HuggingFace FREE Embeddings (with retry logic)
            if self.hf_client:
                # Try HuggingFace with retry logic (3 attempts with increasing timeout)
                for attempt in range(3):
                    try:
                        logger.debug(f"Attempting HuggingFace embedding (attempt {attempt + 1}/3)...")
                        response = self.hf_client.feature_extraction(
                            text,
                            model="BAAI/bge-small-en-v1.5"  # High-quality free embeddings
                        )
                        
                        # HuggingFace returns nested list, flatten it
                        if isinstance(response, list):
                            if isinstance(response[0], list):
                                embedding = response[0]
                            else:
                                embedding = response
                        else:
                            embedding = list(response)
                        
                        logger.debug(f"✅ Generated HuggingFace embedding ({len(embedding)} dims)")
                        return embedding
                        
                    except Exception as hf_error:
                        if attempt < 2:  # Not last attempt
                            logger.debug(f"⚠️ Attempt {attempt + 1} failed: {hf_error}, retrying...")
                            import time
                            time.sleep(2 ** attempt)  # Exponential backoff: 1s, 2s
                        else:  # Last attempt failed
                            logger.warning(f"⚠️ HuggingFace embedding failed after 3 attempts: {hf_error}")
                            logger.warning(f"   Using mock fallback (search quality will be reduced)")
            
            # Fallback: Mock embeddings (POOR QUALITY - for testing only!)
            logger.warning("⚠️ Using MOCK embeddings - search quality will be SIGNIFICANTLY REDUCED!")
            logger.warning("   Configure OPENAI_API_KEY for reliable, high-quality embeddings")
            logger.warning("   OR fix HuggingFace network connectivity for free embeddings")
            
            # Simple sentence-transformer-like mock
            import hashlib
            import numpy as np
            
            # Create deterministic embedding from text
            hash_val = int(hashlib.md5(text.encode()).hexdigest(), 16)
            np.random.seed(hash_val % (2**32))
            
            # Generate 384 dimensions (same as bge-small-en-v1.5)
            embedding = np.random.randn(384).tolist()
            
            # Normalize to unit length (like real embeddings)
            norm = np.linalg.norm(embedding)
            embedding = (np.array(embedding) / norm).tolist()
            
            return embedding
            
        except Exception as e:
            logger.error(f"❌ Error generating embedding: {e}", exc_info=True)
            # Return zero vector as last resort
            return [0.0] * 384
    
    def is_available(self) -> bool:
        """Check if LLM service is available with real API"""
        return self.provider in ["openai", "anthropic"]
    
    def get_provider_info(self) -> Dict[str, Any]:
        """Get information about current LLM provider"""
        return {
            "provider": self.provider,
            "is_mock": self.provider == "mock",
            "has_openai": self.openai_api_key is not None,
            "has_anthropic": self.anthropic_api_key is not None,
            "model": self.openai_chat_model if self.provider == "openai" else self.groq_chat_model if self.provider == "groq" else "claude-3-5-sonnet" if self.provider == "anthropic" else "mock"
        }

