"""
Local LLM Service - Fallback when Groq API is unavailable
Uses small quantized models (Phi-2, TinyLlama) via llama-cpp-python
"""

import logging
import os
from pathlib import Path
from typing import Optional, Dict, Any
import requests
from threading import Lock

logger = logging.getLogger(__name__)


class LocalLLMService:
    """
    Manages local LLM inference as fallback for Groq API
    
    Features:
    - Downloads and caches small quantized models (GGUF format)
    - Efficient CPU inference with llama-cpp-python
    - Thread-safe model loading
    - Automatic model selection based on available memory
    """
    
    # Recommended small models (GGUF quantized for CPU efficiency)
    AVAILABLE_MODELS = {
        "tinyllama-1.1b": {
            "url": "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            "filename": "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            "size_mb": 669,
            "description": "TinyLlama 1.1B - Fast, good for simple queries"
        },
        "phi-2-2.7b": {
            "url": "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf",
            "filename": "phi-2.Q4_K_M.gguf",
            "size_mb": 1560,
            "description": "Phi-2 2.7B - Better quality, moderate speed"
        },
        "mistral-7b-instruct": {
            "url": "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf",
            "filename": "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
            "size_mb": 4370,
            "description": "Mistral 7B - High quality, slower (recommended if you have good hardware)"
        }
    }
    
    def __init__(self, model_name: str = "phi-2-2.7b", models_dir: Optional[Path] = None):
        """
        Initialize Local LLM Service
        
        Args:
            model_name: Name of model to use (from AVAILABLE_MODELS)
            models_dir: Directory to store downloaded models
        """
        self.model_name = model_name
        self.models_dir = models_dir or Path(__file__).parent.parent / "data" / "models"
        self.models_dir.mkdir(parents=True, exist_ok=True)
        
        self.llm = None
        self.model_loaded = False
        self.load_lock = Lock()
        
        logger.info(f"💾 Local LLM Service initialized with model: {model_name}")
    
    def download_model(self, model_name: Optional[str] = None) -> Path:
        """
        Download model if not already cached
        
        Args:
            model_name: Model to download (defaults to self.model_name)
        
        Returns:
            Path to downloaded model file
        """
        model_name = model_name or self.model_name
        
        if model_name not in self.AVAILABLE_MODELS:
            raise ValueError(f"Unknown model: {model_name}. Available: {list(self.AVAILABLE_MODELS.keys())}")
        
        model_info = self.AVAILABLE_MODELS[model_name]
        model_path = self.models_dir / model_info["filename"]
        
        # Check if already downloaded
        if model_path.exists():
            logger.info(f"✅ Model already cached: {model_path}")
            return model_path
        
        # Download model
        logger.info(f"📥 Downloading {model_name} ({model_info['size_mb']} MB)...")
        logger.info(f"   URL: {model_info['url']}")
        logger.info(f"   This may take a few minutes...")
        
        try:
            response = requests.get(model_info["url"], stream=True)
            response.raise_for_status()
            
            total_size = int(response.headers.get('content-length', 0))
            downloaded = 0
            
            with open(model_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        
                        # Progress indicator every 100MB
                        if downloaded % (100 * 1024 * 1024) < 8192:
                            progress = (downloaded / total_size * 100) if total_size > 0 else 0
                            logger.info(f"   Downloaded: {downloaded // (1024*1024)} MB ({progress:.1f}%)")
            
            logger.info(f"✅ Model downloaded successfully: {model_path}")
            return model_path
            
        except Exception as e:
            logger.error(f"❌ Failed to download model: {e}")
            if model_path.exists():
                model_path.unlink()  # Clean up partial download
            raise
    
    def load_model(self, force_reload: bool = False) -> bool:
        """
        Load the model into memory
        
        Args:
            force_reload: Force reload even if already loaded
        
        Returns:
            True if model loaded successfully
        """
        with self.load_lock:
            if self.model_loaded and not force_reload:
                return True
            
            try:
                # Import here to avoid dependency if not used
                from llama_cpp import Llama
                
                # Ensure model is downloaded
                model_path = self.download_model()
                
                logger.info(f"🔄 Loading model into memory: {model_path}")
                
                # Load model with CPU-optimized settings
                self.llm = Llama(
                    model_path=str(model_path),
                    n_ctx=2048,  # Context window
                    n_threads=4,  # CPU threads
                    n_gpu_layers=0,  # CPU only (set to >0 if you have GPU)
                    verbose=False
                )
                
                self.model_loaded = True
                logger.info(f"✅ Model loaded successfully: {self.model_name}")
                return True
                
            except ImportError:
                logger.error("❌ llama-cpp-python not installed. Run: pip install llama-cpp-python")
                return False
            except Exception as e:
                logger.error(f"❌ Failed to load model: {e}")
                self.model_loaded = False
                return False
    
    def generate(
        self,
        prompt: str,
        max_tokens: int = 500,
        temperature: float = 0.3,
        stop: Optional[list] = None
    ) -> str:
        """
        Generate text using local LLM
        
        Args:
            prompt: Input prompt
            max_tokens: Maximum tokens to generate
            temperature: Sampling temperature (0.0-1.0)
            stop: Stop sequences
        
        Returns:
            Generated text
        """
        # Load model if not already loaded
        if not self.model_loaded:
            if not self.load_model():
                raise RuntimeError("Failed to load local LLM model")
        
        try:
            logger.info(f"💭 Generating with local LLM (max_tokens={max_tokens})...")
            
            # Generate response
            response = self.llm(
                prompt,
                max_tokens=max_tokens,
                temperature=temperature,
                stop=stop or ["</s>", "<|im_end|>", "\n\nUser:", "\n\nHuman:"],
                echo=False
            )
            
            generated_text = response["choices"][0]["text"].strip()
            
            logger.info(f"✅ Generated {len(generated_text)} characters")
            return generated_text
            
        except Exception as e:
            logger.error(f"❌ Local LLM generation failed: {e}")
            raise
    
    def chat(
        self,
        messages: list[Dict[str, str]],
        max_tokens: int = 500,
        temperature: float = 0.3
    ) -> str:
        """
        Chat completion with conversation history
        
        Args:
            messages: List of message dicts with 'role' and 'content'
            max_tokens: Maximum tokens to generate
            temperature: Sampling temperature
        
        Returns:
            Generated response
        """
        # Convert messages to prompt format
        prompt = self._format_chat_prompt(messages)
        
        # Generate response
        return self.generate(prompt, max_tokens=max_tokens, temperature=temperature)
    
    def _format_chat_prompt(self, messages: list[Dict[str, str]]) -> str:
        """
        Format chat messages into prompt string
        
        Args:
            messages: List of message dicts
        
        Returns:
            Formatted prompt
        """
        # Use ChatML format (common for instruction-tuned models)
        prompt_parts = []
        
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            
            if role == "system":
                prompt_parts.append(f"<|im_start|>system\n{content}<|im_end|>")
            elif role == "user":
                prompt_parts.append(f"<|im_start|>user\n{content}<|im_end|>")
            elif role == "assistant":
                prompt_parts.append(f"<|im_start|>assistant\n{content}<|im_end|>")
        
        # Add assistant prompt to trigger response
        prompt_parts.append("<|im_start|>assistant\n")
        
        return "\n".join(prompt_parts)
    
    def is_available(self) -> bool:
        """Check if local LLM is available and working"""
        try:
            if not self.model_loaded:
                return self.load_model()
            return True
        except:
            return False
    
    def get_model_info(self) -> Dict[str, Any]:
        """Get information about current model"""
        if self.model_name in self.AVAILABLE_MODELS:
            info = self.AVAILABLE_MODELS[self.model_name].copy()
            info["loaded"] = self.model_loaded
            info["model_path"] = str(self.models_dir / info["filename"])
            return info
        return {"model_name": self.model_name, "loaded": self.model_loaded}
    
    @classmethod
    def list_available_models(cls) -> Dict[str, Dict[str, Any]]:
        """List all available models with their info"""
        return cls.AVAILABLE_MODELS.copy()
    
    def unload_model(self):
        """Unload model from memory"""
        with self.load_lock:
            if self.llm is not None:
                del self.llm
                self.llm = None
                self.model_loaded = False
                logger.info("🗑️  Model unloaded from memory")


# Singleton instance
_local_llm_instance: Optional[LocalLLMService] = None


def get_local_llm(model_name: str = "phi-2-2.7b") -> LocalLLMService:
    """
    Get or create singleton LocalLLMService instance
    
    Args:
        model_name: Model to use
    
    Returns:
        LocalLLMService instance
    """
    global _local_llm_instance
    
    if _local_llm_instance is None or _local_llm_instance.model_name != model_name:
        _local_llm_instance = LocalLLMService(model_name=model_name)
    
    return _local_llm_instance

