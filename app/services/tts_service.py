"""
Text-to-Speech — Sia / Teacher AI / Kind voice
------------------------------------------------
Order:
  1. ElevenLabs (if ELEVENLABS_API_KEY is set)
  2. Microsoft Edge TTS — free, high quality, no API key (edge-tts)
  3. Google gTTS fallback

Returns MP3 bytes for /speak endpoints.
"""

from __future__ import annotations

import asyncio
import io
import logging
import re

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

ELEVENLABS_TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"

ELEVENLABS_SUPPORTED_LANGUAGES = {
    "english", "french", "spanish", "portuguese", "german", "italian",
    "polish", "dutch", "russian", "arabic", "hindi", "turkish", "swedish",
    "norwegian", "danish", "finnish", "romanian", "hungarian", "czech",
    "slovak", "ukrainian", "greek", "indonesian", "malay", "tagalog",
    "vietnamese", "thai", "chinese", "japanese", "korean",
}

# Clear female neural voices (Edge TTS — no key required).
_EDGE_VOICE_BY_LANG = {
    "english": "en-US-JennyNeural",
    "french": "fr-FR-DeniseNeural",
    "spanish": "es-ES-ElviraNeural",
    "portuguese": "pt-BR-FranciscaNeural",
    "german": "de-DE-KatjaNeural",
    "italian": "it-IT-ElsaNeural",
    "arabic": "ar-SA-ZariyahNeural",
    "hindi": "hi-IN-SwaraNeural",
    "chinese": "zh-CN-XiaoxiaoNeural",
    "japanese": "ja-JP-NanamiNeural",
    "korean": "ko-KR-SunHiNeural",
    "turkish": "tr-TR-EmelNeural",
    "russian": "ru-RU-SvetlanaNeural",
    "dutch": "nl-NL-ColetteNeural",
    "polish": "pl-PL-ZofiaNeural",
    "swedish": "sv-SE-SofieNeural",
    "norwegian": "nb-NO-PernilleNeural",
    "danish": "da-DK-ChristelNeural",
    "finnish": "fi-FI-NooraNeural",
    "romanian": "ro-RO-AlinaNeural",
    "hungarian": "hu-HU-NoemiNeural",
    "czech": "cs-CZ-VlastaNeural",
    "slovak": "sk-SK-ViktoriaNeural",
    "ukrainian": "uk-UA-PolinaNeural",
    "greek": "el-GR-AthinaNeural",
    "indonesian": "id-ID-GadisNeural",
    "malay": "ms-MY-YasminNeural",
    "vietnamese": "vi-VN-HoaiMyNeural",
    "thai": "th-TH-PremwadeeNeural",
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
    """Convert text to MP3 bytes. Tries ElevenLabs → Edge → gTTS."""
    clean = prepare_speech_text(text)
    if not clean:
        return b""

    lang = (language or "english").lower().strip()

    if settings.ELEVENLABS_API_KEY and lang in ELEVENLABS_SUPPORTED_LANGUAGES:
        try:
            audio = await _elevenlabs_tts(clean)
            if audio:
                return audio
        except Exception as e:
            logger.warning("ElevenLabs TTS failed, falling back: %s", e)

    try:
        audio = await _edge_tts(clean, lang)
        if audio:
            return audio
    except Exception as e:
        logger.warning("Edge TTS failed, falling back to gTTS: %s", e)

    try:
        return await _gtts_fallback(clean, lang)
    except Exception as e:
        logger.error("All TTS backends failed: %s", e)
        return b""


async def _elevenlabs_tts(text: str) -> bytes:
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
    async with httpx.AsyncClient(timeout=45.0) as client:
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


async def _edge_tts(text: str, language: str) -> bytes:
    """Microsoft Edge neural TTS — free, no API key."""
    import edge_tts

    voice = _EDGE_VOICE_BY_LANG.get(language, "en-US-JennyNeural")
    communicate = edge_tts.Communicate(text, voice)
    chunks: list[bytes] = []

    async for item in communicate.stream():
        if item["type"] == "audio":
            chunks.append(item["data"])

    return b"".join(chunks)


async def _gtts_fallback(text: str, language: str) -> bytes:
    from gtts import gTTS

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
    buffer = io.BytesIO()

    def _generate():
        tts = gTTS(text=text, lang=gtts_lang, slow=False)
        tts.write_to_fp(buffer)
        buffer.seek(0)

    await asyncio.get_event_loop().run_in_executor(None, _generate)
    return buffer.read()
