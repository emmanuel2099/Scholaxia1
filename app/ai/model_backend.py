"""
Scholaxia AI Model Backend — Sia
----------------------------------
Supports multiple backends via AI_BACKEND env var:
  "gemini"   — Google Gemini (1,500 req/day free) ← primary
  "openai"   — OpenAI GPT-4o (paid, highest quality)
  "deepseek" — DeepSeek (smart + cheap)
  "groq"     — Groq (fallback)
  "hosted"   — Self-hosted (Ollama, vLLM)
  "local"    — HuggingFace in-process
"""

import asyncio
import httpx
from app.core.config import settings
from app.ai.prompt_builder import SIA_SYSTEM_PROMPT


# ── Gemini ────────────────────────────────────────────────────────────────────

async def _infer_gemini(prompt: str, conversation_history: list = None,
                        image_base64: str = None, system_prompt: str = None,
                        max_tokens: int = None, temperature: float = None) -> str:
    """Google Gemini — uses X-goog-api-key header, gemini-flash-latest model."""
    model = settings.GEMINI_MODEL  # default: gemini-flash-latest
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

    contents = []

    # Gemini uses systemInstruction for the system prompt
    system_instruction = {"parts": [{"text": system_prompt or SIA_SYSTEM_PROMPT}]}

    if conversation_history:
        for msg in conversation_history[-10:]:
            role = "user" if msg.get("role") == "user" else "model"
            contents.append({"role": role, "parts": [{"text": msg.get("content", "")}]})

    if image_base64:
        contents.append({
            "role": "user",
            "parts": [
                {"inline_data": {"mime_type": "image/jpeg", "data": image_base64}},
                {"text": prompt}
            ]
        })
    else:
        contents.append({"role": "user", "parts": [{"text": prompt}]})

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            url,
            headers={
                "X-goog-api-key": settings.GEMINI_API_KEY,
                "Content-Type": "application/json",
            },
            json={
                "contents": contents,
                "systemInstruction": system_instruction,
                "generationConfig": {
                    "maxOutputTokens": max_tokens or settings.AI_MAX_TOKENS,
                    "temperature": temperature if temperature is not None else settings.AI_TEMPERATURE,
                },
            },
        )
        response.raise_for_status()
        data = response.json()
        return data["candidates"][0]["content"]["parts"][0]["text"].strip()


# ── OpenAI ────────────────────────────────────────────────────────────────────

async def _infer_openai(prompt: str, conversation_history: list = None,
                        image_base64: str = None, system_prompt: str = None,
                        max_tokens: int = None, temperature: float = None) -> str:
    """OpenAI GPT-4o — highest quality, paid."""
    messages = [{"role": "system", "content": system_prompt or SIA_SYSTEM_PROMPT}]

    if conversation_history:
        for msg in conversation_history[-10:]:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})

    if image_base64:
        messages.append({
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}},
                {"type": "text", "text": prompt}
            ]
        })
    else:
        messages.append({"role": "user", "content": prompt})

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.OPENAI_MODEL,
                "messages": messages,
                "max_tokens": max_tokens or settings.AI_MAX_TOKENS,
                "temperature": temperature if temperature is not None else settings.AI_TEMPERATURE,
            },
        )
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"].strip()


# ── DeepSeek ──────────────────────────────────────────────────────────────────

async def _infer_deepseek(prompt: str, conversation_history: list = None,
                          system_prompt: str = None, max_tokens: int = None,
                          temperature: float = None) -> str:
    """DeepSeek — very smart, cheap."""
    messages = [{"role": "system", "content": system_prompt or SIA_SYSTEM_PROMPT}]

    if conversation_history:
        for msg in conversation_history[-10:]:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})

    messages.append({"role": "user", "content": prompt})

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.deepseek.com/chat/completions",
            headers={
                "Authorization": f"Bearer {settings.DEEPSEEK_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.DEEPSEEK_MODEL,
                "messages": messages,
                "max_tokens": max_tokens or settings.AI_MAX_TOKENS,
                "temperature": temperature if temperature is not None else settings.AI_TEMPERATURE,
            },
        )
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"].strip()


# ── Groq ──────────────────────────────────────────────────────────────────────

async def _infer_groq(prompt: str, conversation_history: list = None,
                      image_base64: str = None, system_prompt: str = None,
                      max_tokens: int = None, temperature: float = None) -> str:
    """Groq — fast free tier, 30 req/min limit."""
    messages = [{"role": "system", "content": system_prompt or SIA_SYSTEM_PROMPT}]

    if conversation_history:
        for msg in conversation_history[-10:]:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})

    if image_base64:
        model = "meta-llama/llama-4-scout-17b-16e-instruct"
        messages.append({
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}},
                {"type": "text", "text": prompt}
            ]
        })
    else:
        model = settings.GROQ_MODEL
        messages.append({"role": "user", "content": prompt})

    for attempt in range(3):
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model,
                    "messages": messages,
                    "max_tokens": max_tokens or settings.AI_MAX_TOKENS,
                    "temperature": temperature if temperature is not None else settings.AI_TEMPERATURE,
                },
            )
            if response.status_code == 429:
                retry_after = int(response.headers.get("retry-after", 10))
                await asyncio.sleep(min(retry_after, 30))
                continue
            response.raise_for_status()
            return response.json()["choices"][0]["message"]["content"].strip()

    raise Exception("Groq rate limit exceeded.")


# ── Hosted ────────────────────────────────────────────────────────────────────

async def _infer_hosted(prompt: str) -> str:
    async with httpx.AsyncClient(timeout=60.0) as client:
        if settings.AI_HOSTED_ENDPOINT_TYPE == "ollama":
            response = await client.post(
                f"{settings.AI_HOSTED_BASE_URL}/api/generate",
                json={
                    "model": settings.AI_HOSTED_MODEL_NAME,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"num_predict": settings.AI_MAX_TOKENS, "temperature": settings.AI_TEMPERATURE},
                },
            )
            response.raise_for_status()
            return response.json()["response"].strip()
        else:
            response = await client.post(
                f"{settings.AI_HOSTED_BASE_URL}/v1/chat/completions",
                headers={"Authorization": f"Bearer {settings.AI_HOSTED_API_KEY}"},
                json={
                    "model": settings.AI_HOSTED_MODEL_NAME,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": settings.AI_MAX_TOKENS,
                    "temperature": settings.AI_TEMPERATURE,
                },
            )
            response.raise_for_status()
            return response.json()["choices"][0]["message"]["content"].strip()


# ── Local ─────────────────────────────────────────────────────────────────────

_local_pipeline = None


def _load_local_pipeline():
    global _local_pipeline
    if _local_pipeline is None:
        from transformers import pipeline
        _local_pipeline = pipeline(
            "text-generation",
            model=settings.AI_LOCAL_MODEL_NAME,
            device=settings.AI_LOCAL_DEVICE,
            max_new_tokens=settings.AI_MAX_TOKENS,
            do_sample=True,
            temperature=settings.AI_TEMPERATURE,
        )
    return _local_pipeline


async def _infer_local(prompt: str) -> str:
    pipe = await asyncio.get_event_loop().run_in_executor(None, _load_local_pipeline)
    result = await asyncio.get_event_loop().run_in_executor(None, lambda: pipe(prompt))
    return result[0]["generated_text"][len(prompt):].strip()


# ── Public interface ──────────────────────────────────────────────────────────

async def run_inference(prompt: str, conversation_history: list = None,
                        image_base64: str = None, system_prompt: str = None,
                        max_tokens: int = None, temperature: float = None) -> str:
    """
    Run inference with automatic fallback chain.

    Priority order (primary → fallbacks):
      gemini → openai → deepseek → groq

    Any backend can be set as primary via AI_BACKEND env var.
    All others with valid API keys are tried automatically on failure.
    """
    backend = settings.AI_BACKEND.lower()

    # ── Primary backend ───────────────────────────────────────────────────────
    try:
        if backend == "gemini":
            return await _infer_gemini(prompt, conversation_history, image_base64,
                                       system_prompt, max_tokens, temperature)
        elif backend == "openai":
            return await _infer_openai(prompt, conversation_history, image_base64,
                                       system_prompt, max_tokens, temperature)
        elif backend == "deepseek":
            return await _infer_deepseek(prompt, conversation_history,
                                         system_prompt, max_tokens, temperature)
        elif backend == "groq":
            return await _infer_groq(prompt, conversation_history, image_base64,
                                     system_prompt, max_tokens, temperature)
        elif backend == "hosted":
            return await _infer_hosted(prompt)
        elif backend == "local":
            return await _infer_local(prompt)
        else:
            raise ValueError(f"Unknown AI_BACKEND: '{backend}'")

    except Exception as primary_error:
        # ── Fallback chain — priority order: gemini → openai → deepseek → groq ─
        # Each backend is only tried if it has an API key and isn't the primary
        fallback_chain = [
            ("gemini",   settings.GEMINI_API_KEY,   lambda: _infer_gemini(prompt, conversation_history, image_base64, system_prompt, max_tokens, temperature)),
            ("openai",   settings.OPENAI_API_KEY,   lambda: _infer_openai(prompt, conversation_history, image_base64, system_prompt, max_tokens, temperature)),
            ("deepseek", settings.DEEPSEEK_API_KEY, lambda: _infer_deepseek(prompt, conversation_history, system_prompt, max_tokens, temperature)),
            ("groq",     settings.GROQ_API_KEY,     lambda: _infer_groq(prompt, conversation_history, image_base64, system_prompt, max_tokens, temperature)),
        ]

        for name, api_key, fn in fallback_chain:
            if name == backend or not api_key:
                continue  # skip primary and unconfigured backends
            try:
                return await fn()
            except Exception:
                continue  # try next fallback

        # All backends failed — raise original error
        raise primary_error
