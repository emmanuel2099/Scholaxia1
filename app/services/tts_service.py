"""
Text-to-Speech Service — ElevenLabs
-------------------------------------
Converts Sia's text responses to audio so students can hear Sia speak.

Voice style:
- Friendly and calm
- Medium pace with warmth
- Clear pronunciation
- Conversational, not robotic

ElevenLabs multilingual_v2 model supports 29 languages natively.
For languages not supported by ElevenLabs, we fall back to gTTS (Google TTS).
"""

import httpx
import io
import re
from app.core.config import settings

ELEVENLABS_TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"

# Languages natively supported by ElevenLabs multilingual_v2
ELEVENLABS_SUPPORTED_LANGUAGES = {
    "english", "french", "spanish", "portuguese", "german", "italian",
    "polish", "dutch", "russian", "arabic", "hindi", "turkish", "swedish",
    "norwegian", "danish", "finnish", "romanian", "hungarian", "czech",
    "slovak", "ukrainian", "greek", "indonesian", "malay", "tagalog",
    "vietnamese", "thai", "chinese", "japanese", "korean",
}


def prepare_speech_text(text: str, max_len: int = 3500) -> str:
    """Strip markdown and trim for natural TTS."""
    if not text:
        return ""
    t = re.sub(r"```[\s\S]*?```", " ", text)
    t = re.sub(r"`([^`]+)`", r"\1", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"\1", t)
    t = re.sub(r"\*([^*]+)\*", r"\1", t)
    t = re.sub(r"^#+\s*", "", t, flags=re.MULTILINE)
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) > max_len:
        cut = t[:max_len].rsplit(" ", 1)[0]
        t = f"{cut}..."
    return t


async def text_to_speech(text: str, language: str = "english") -> bytes:
    """
    Convert text to audio bytes (MP3).
    Returns raw MP3 bytes — the API endpoint streams this directly to the client.

    Uses ElevenLabs for supported languages, falls back to gTTS for others.
    """
    clean = prepare_speech_text(text)
    if not clean:
        return b""

    if not settings.ELEVENLABS_API_KEY:
        return await _gtts_fallback(clean, language)

    lang = language.lower()

    if lang in ELEVENLABS_SUPPORTED_LANGUAGES:
        return await _elevenlabs_tts(clean)
    else:
        return await _gtts_fallback(clean, language)


async def _elevenlabs_tts(text: str) -> bytes:
    """Call ElevenLabs API and return MP3 bytes."""
    url = ELEVENLABS_TTS_URL.format(voice_id=settings.ELEVENLABS_VOICE_ID)

    payload = {
        "text": text,
        "model_id": settings.ELEVENLABS_MODEL_ID,
        "voice_settings": {
            "stability": 0.55,
            "similarity_boost": 0.80,
            "style": 0.25,
            "use_speaker_boost": True,
        },
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            json=payload,
            headers={
                "xi-api-key": settings.ELEVENLABS_API_KEY,
                "Content-Type": "application/json",
                "Accept": "audio/mpeg",
            },
        )
        response.raise_for_status()
        return response.content


async def _gtts_fallback(text: str, language: str) -> bytes:
    """
    Fallback TTS using gTTS (Google Text-to-Speech).
    Works for most world languages. Requires 'gtts' package.
    Returns MP3 bytes.
    """
    try:
        from gtts import gTTS
        from gtts.lang import tts_langs

        # Map our language names to gTTS language codes
        lang_map = {
            "english": "en", "igbo": "ig", "yoruba": "yo", "hausa": "ha",
            "french": "fr", "arabic": "ar", "spanish": "es", "portuguese": "pt",
            "german": "de", "italian": "it", "dutch": "nl", "russian": "ru",
            "polish": "pl", "ukrainian": "uk", "turkish": "tr", "greek": "el",
            "hindi": "hi", "bengali": "bn", "tamil": "ta", "telugu": "te",
            "gujarati": "gu", "marathi": "mr", "punjabi": "pa", "urdu": "ur",
            "chinese": "zh-CN", "japanese": "ja", "korean": "ko",
            "vietnamese": "vi", "thai": "th", "indonesian": "id", "malay": "ms",
            "tagalog": "tl", "swahili": "sw", "afrikaans": "af",
            "catalan": "ca", "czech": "cs", "danish": "da", "finnish": "fi",
            "hungarian": "hu", "romanian": "ro", "slovak": "sk", "swedish": "sv",
            "norwegian": "no", "icelandic": "is", "latvian": "lv",
            "lithuanian": "lt", "estonian": "et", "bulgarian": "bg",
            "serbian": "sr", "croatian": "hr", "slovenian": "sl",
            "albanian": "sq", "macedonian": "mk", "georgian": "ka",
            "armenian": "hy", "azerbaijani": "az", "kazakh": "kk",
            "uzbek": "uz", "mongolian": "mn", "nepali": "ne", "sinhala": "si",
            "khmer": "km", "lao": "lo", "burmese": "my", "amharic": "am",
            "somali": "so", "haitian_creole": "ht", "welsh": "cy",
            "irish": "ga", "maltese": "mt", "maori": "mi",
        }

        gtts_lang = lang_map.get(language.lower(), "en")

        # Run gTTS in thread (it's synchronous)
        import asyncio
        buffer = io.BytesIO()

        def _generate():
            tts = gTTS(text=text, lang=gtts_lang, slow=False)
            tts.write_to_fp(buffer)
            buffer.seek(0)

        await asyncio.get_event_loop().run_in_executor(None, _generate)
        return buffer.read()

    except Exception:
        # If gTTS also fails, return empty bytes — frontend handles gracefully
        return b""
