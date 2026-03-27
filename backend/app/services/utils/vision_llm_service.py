"""
Vision-Enhanced LLM Service
Adds image understanding capability to chatbot using Claude 3 Sonnet or GPT-4 Vision
"""

import os
import base64
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
from app.services.ai_config_service import get_ai_config_service

logger = logging.getLogger(__name__)


class VisionLLMService:
    """
    Service for vision-enhanced LLM queries
    Supports Claude 3 Sonnet and GPT-4 Vision for image understanding
    """
    
    def __init__(self):
        """Initialize vision LLM service"""
        ai_cfg = get_ai_config_service().get_config()
        self.vision_model = ai_cfg.get("vision_model", "gpt-5.2")

        self.anthropic_api_key = os.getenv("ANTHROPIC_API_KEY")
        self.openai_api_key = os.getenv("OPENAI_API_KEY")
        
        self.anthropic_client = None
        self.openai_client = None
        
        # Initialize Anthropic Claude (preferred for vision + cost)
        if self.anthropic_api_key:
            try:
                from anthropic import Anthropic
                self.anthropic_client = Anthropic(api_key=self.anthropic_api_key)
                logger.info("✅ Claude 3 Sonnet initialized for vision queries")
            except Exception as e:
                logger.warning(f"⚠️ Failed to initialize Anthropic: {e}")
        
        # Initialize OpenAI (fallback for vision)
        if self.openai_api_key:
            try:
                from openai import OpenAI
                self.openai_client = OpenAI(api_key=self.openai_api_key)
                logger.info("✅ GPT-4 Vision initialized as fallback")
            except Exception as e:
                logger.warning(f"⚠️ Failed to initialize OpenAI: {e}")
    
    def is_vision_enabled(self) -> bool:
        """Check if vision capability is available"""
        return self.anthropic_client is not None or self.openai_client is not None
    
    def is_vision_query(self, query: str) -> bool:
        """
        Detect if query requires vision/image understanding
        
        Keywords: diagram, flowchart, image, picture, show, visual, graph, chart
        """
        vision_keywords = [
            "diagram", "flowchart", "flow chart", "image", "picture", "photo",
            "show me", "visual", "graph", "chart", "illustration", "figure",
            "screenshot", "architecture", "workflow", "process flow"
        ]
        
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in vision_keywords)
    
    def encode_image_to_base64(self, image_path: str) -> str:
        """Convert image file to base64 string"""
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode("utf-8")
    
    def analyze_image_with_claude(
        self,
        image_data: str,
        prompt: str,
        image_type: str = "image/png",
        max_tokens: int = 1024
    ) -> str:
        """
        Analyze image using Claude 3 Sonnet Vision
        
        Args:
            image_data: Base64-encoded image or image bytes
            prompt: Question/instruction about the image
            image_type: MIME type (image/png, image/jpeg, etc.)
            max_tokens: Maximum response length
        
        Returns:
            Detailed description/analysis of the image
        """
        if not self.anthropic_client:
            raise ValueError("Anthropic API key not configured")
        
        try:
            # Prepare image content
            if not image_data.startswith("data:"):
                # Add data URL prefix if not present
                image_source = {
                    "type": "base64",
                    "media_type": image_type,
                    "data": image_data
                }
            else:
                # Extract base64 data from data URL
                image_source = {
                    "type": "base64",
                    "media_type": image_type,
                    "data": image_data.split(",")[1] if "," in image_data else image_data
                }
            
            # Create vision message
            message = self.anthropic_client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=max_tokens,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image",
                                "source": image_source
                            },
                            {
                                "type": "text",
                                "text": prompt
                            }
                        ]
                    }
                ]
            )
            
            return message.content[0].text
        
        except Exception as e:
            logger.error(f"❌ Claude vision analysis failed: {e}")
            raise
    
    def analyze_image_with_gpt4(
        self,
        image_data: str,
        prompt: str,
        max_tokens: int = 1024
    ) -> str:
        """
        Analyze image using GPT-4 Vision
        
        Args:
            image_data: Base64-encoded image
            prompt: Question/instruction about the image
            max_tokens: Maximum response length
        
        Returns:
            Detailed description/analysis of the image
        """
        if not self.openai_client:
            raise ValueError("OpenAI API key not configured")
        
        try:
            # Format image for GPT-4V
            if not image_data.startswith("data:"):
                image_url = f"data:image/png;base64,{image_data}"
            else:
                image_url = image_data
            
            response = self.openai_client.chat.completions.create(
                model=self.vision_model,
                max_tokens=max_tokens,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": prompt
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": image_url,
                                    "detail": "high"  # High detail for technical diagrams
                                }
                            }
                        ]
                    }
                ]
            )
            
            return response.choices[0].message.content
        
        except Exception as e:
            logger.error(f"❌ GPT-4 vision analysis failed: {e}")
            raise
    
    def analyze_image(
        self,
        image_data: str,
        prompt: str,
        image_type: str = "image/png",
        max_tokens: int = 1024,
        prefer_claude: bool = True
    ) -> str:
        """
        Analyze image using available vision LLM
        
        Tries Claude first (better cost/quality), falls back to GPT-4V
        
        Args:
            image_data: Base64-encoded image
            prompt: Question/instruction about the image
            image_type: MIME type for Claude
            max_tokens: Maximum response length
            prefer_claude: Try Claude before GPT-4
        
        Returns:
            Detailed description/analysis of the image
        """
        if prefer_claude and self.anthropic_client:
            try:
                logger.info("🖼️ Analyzing image with Claude 3 Sonnet...")
                return self.analyze_image_with_claude(image_data, prompt, image_type, max_tokens)
            except Exception as e:
                logger.warning(f"⚠️ Claude vision failed, trying GPT-4: {e}")
                if self.openai_client:
                    logger.info("🖼️ Analyzing image with GPT-4 Vision...")
                    return self.analyze_image_with_gpt4(image_data, prompt, max_tokens)
                else:
                    raise
        
        elif self.openai_client:
            logger.info("🖼️ Analyzing image with GPT-4 Vision...")
            return self.analyze_image_with_gpt4(image_data, prompt, max_tokens)
        
        else:
            raise ValueError("No vision-enabled LLM available. Configure ANTHROPIC_API_KEY or OPENAI_API_KEY")
    
    def describe_technical_diagram(
        self,
        image_data: str,
        diagram_type: str = "flowchart",
        max_tokens: int = 1500
    ) -> str:
        """
        Specialized method for technical diagrams (flowcharts, architecture, etc.)
        
        Args:
            image_data: Base64-encoded image
            diagram_type: Type hint (flowchart, architecture, sequence, etc.)
            max_tokens: Maximum response length
        
        Returns:
            Detailed technical description
        """
        prompt = f"""Analyze this technical {diagram_type} in detail:

1. **Purpose**: What process or system does it represent?
2. **Components**: List all main components, boxes, or steps
3. **Flow**: Describe the sequence of operations or data flow
4. **Relationships**: Explain connections, dependencies, or interactions
5. **Key Details**: Any important labels, conditions, or annotations
6. **Technical Notes**: Specific implementation details or constraints

Be precise and technical. This will be used for documentation search and support."""
        
        return self.analyze_image(image_data, prompt, max_tokens=max_tokens)


# Singleton instance
_vision_service = None

def get_vision_service() -> VisionLLMService:
    """Get or create vision LLM service singleton"""
    global _vision_service
    if _vision_service is None:
        _vision_service = VisionLLMService()
    return _vision_service

