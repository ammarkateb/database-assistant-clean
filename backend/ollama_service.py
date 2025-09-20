#!/usr/bin/env python3
"""
Ollama Service for Neural Pulse AI Assistant
Handles LLM interactions with Phi-3 Mini model
"""

import json
import logging
import requests
import time
from typing import Dict, Any, List, Optional
import asyncio
import aiohttp

logger = logging.getLogger(__name__)

class OllamaService:
    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url
        self.model = "phi3:mini"
        self.session = None

    async def initialize(self):
        """Initialize the service and ensure model is available"""
        try:
            # Wait for Ollama to be ready
            await self._wait_for_ollama()

            # Pull phi3:mini if not already available
            await self._ensure_model_available()

            logger.info("✅ Ollama service initialized successfully")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to initialize Ollama service: {e}")
            return False

    async def _wait_for_ollama(self, max_retries: int = 30):
        """Wait for Ollama service to be ready"""
        for i in range(max_retries):
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(f"{self.base_url}/api/tags") as response:
                        if response.status == 200:
                            logger.info("✅ Ollama service is ready")
                            return
            except Exception as e:
                logger.info(f"⏳ Waiting for Ollama... ({i+1}/{max_retries})")
                await asyncio.sleep(2)

        raise Exception("Ollama service did not become ready in time")

    async def _ensure_model_available(self):
        """Ensure phi3:mini model is available"""
        try:
            # Check if model exists
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.base_url}/api/tags") as response:
                    if response.status == 200:
                        data = await response.json()
                        models = [model['name'] for model in data.get('models', [])]

                        if self.model not in models:
                            logger.info(f"📥 Pulling {self.model} model...")
                            await self._pull_model()
                        else:
                            logger.info(f"✅ Model {self.model} is available")
        except Exception as e:
            logger.error(f"❌ Error checking model availability: {e}")
            raise

    async def _pull_model(self):
        """Pull the phi3:mini model"""
        try:
            async with aiohttp.ClientSession() as session:
                payload = {"name": self.model}
                async with session.post(
                    f"{self.base_url}/api/pull",
                    json=payload
                ) as response:
                    if response.status == 200:
                        logger.info(f"✅ Successfully pulled {self.model}")
                    else:
                        raise Exception(f"Failed to pull model: {response.status}")
        except Exception as e:
            logger.error(f"❌ Error pulling model: {e}")
            raise

    async def generate_response(
        self,
        prompt: str,
        context: Optional[Dict] = None,
        system_prompt: Optional[str] = None
    ) -> Dict[str, Any]:
        """Generate a response using phi3:mini"""
        try:
            # Build the full prompt
            full_prompt = self._build_prompt(prompt, context, system_prompt)

            async with aiohttp.ClientSession() as session:
                payload = {
                    "model": self.model,
                    "prompt": full_prompt,
                    "stream": False,
                    "options": {
                        "temperature": 0.7,
                        "top_p": 0.9,
                        "max_tokens": 2048,
                        "stop": ["Human:", "Assistant:", "User:"]
                    }
                }

                async with session.post(
                    f"{self.base_url}/api/generate",
                    json=payload
                ) as response:

                    if response.status == 200:
                        data = await response.json()
                        return {
                            "success": True,
                            "message": data.get("response", "").strip(),
                            "model": self.model,
                            "tokens": data.get("eval_count", 0)
                        }
                    else:
                        error_text = await response.text()
                        raise Exception(f"Ollama API error: {response.status} - {error_text}")

        except Exception as e:
            logger.error(f"❌ Error generating response: {e}")
            return {
                "success": False,
                "message": f"Error generating response: {str(e)}",
                "model": self.model
            }

    def _build_prompt(
        self,
        user_query: str,
        context: Optional[Dict] = None,
        system_prompt: Optional[str] = None
    ) -> str:
        """Build a comprehensive prompt for the LLM"""

        # Default system prompt for business intelligence
        default_system = """You are a bilingual AI assistant for Neural Pulse, a business intelligence app. You help analyze business data and answer questions in both English and Arabic.

Key capabilities:
- Answer business questions about customers, revenue, products
- Perform calculations and provide financial insights
- Generate chart recommendations
- Support both English and Arabic queries
- Provide accurate, data-driven responses

Always be helpful, accurate, and professional. If you don't have specific data, acknowledge this and provide general guidance."""

        prompt_parts = []

        # Add system prompt
        prompt_parts.append(f"System: {system_prompt or default_system}")

        # Add context if provided
        if context:
            prompt_parts.append(f"Context: {json.dumps(context, indent=2)}")

        # Add user query
        prompt_parts.append(f"Human: {user_query}")
        prompt_parts.append("Assistant:")

        return "\n\n".join(prompt_parts)

    def generate_business_prompt(self, query: str, business_data: Dict) -> str:
        """Generate a specialized prompt for business queries"""

        context = {
            "total_customers": len(business_data.get("customers", [])),
            "total_invoices": len(business_data.get("invoices", [])),
            "top_customers": business_data.get("top_customers", [])[:3],
            "recent_revenue": business_data.get("monthly_revenue", [])[-3:],
            "query_language": "Arabic" if self._is_arabic(query) else "English"
        }

        system_prompt = """You are analyzing real business data for Neural Pulse. Use the provided context to give specific, accurate answers about customers, revenue, and business metrics.

If asked about specific customers, use the actual names from the data.
If asked about revenue, use the actual numbers provided.
If asked for charts, recommend appropriate visualizations.
If the query is in Arabic, respond in Arabic. If in English, respond in English.

Be specific and use the real data provided in the context."""

        return self._build_prompt(query, context, system_prompt)

    def _is_arabic(self, text: str) -> bool:
        """Detect if text contains Arabic characters"""
        arabic_pattern = r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]'
        import re
        return bool(re.search(arabic_pattern, text))

# Global instance
ollama_service = OllamaService()

# Async initialization function
async def initialize_ollama():
    """Initialize the global Ollama service"""
    return await ollama_service.initialize()

# Sync wrapper for Flask compatibility
def generate_response_sync(prompt: str, context: Optional[Dict] = None) -> Dict[str, Any]:
    """Synchronous wrapper for generate_response"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        return loop.run_until_complete(
            ollama_service.generate_response(prompt, context)
        )
    finally:
        loop.close()