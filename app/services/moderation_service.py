import re
from typing import Tuple

# Prohibited words — spam, abuse, insults (extend as needed)
BAD_WORDS = [
    "spam", "scam", "whatsapp", "telegram", "instagram", "facebook", "tiktok", "snapchat",
    "follow me", "dm me", "call me", "my number", "phone number", "my whatsapp",
    "click here", "free money", "send me", "wire me", "bank details",
    "stupid", "idiot", "dumb", "moron", "retard", "bastard", "bitch", "fuck", "shit",
    "asshole", "slut", "whore", "kill yourself", "kys", "hate you", "ugly fool",
    "nonsense teacher", "useless", "shut up",
]

# Patterns that indicate sharing personal/social info
PERSONAL_INFO_PATTERNS = [
    r"(?:\+?\d{1,3}[\s.-]?)?(?:0\d{2,3}[\s.-]?)?\d{3}[\s.-]?\d{4,5}",  # phone (incl. 080…)
    r"\b\d{10,11}\b",
    r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
    r"(wa\.me|t\.me|ig\.com|fb\.com|chat\.whatsapp\.com)",
    r"https?://(?!scholaxia\.com)\S+",
]


async def check_message_content(content: str) -> Tuple[bool, str]:
    """
    Returns (is_flagged, reason).
    Checks for bad words, personal info, social media links.
    """
    lower = content.lower()

    for word in BAD_WORDS:
        if word in lower:
            return True, "This post was blocked: abusive language or prohibited content is not allowed."

    for pattern in PERSONAL_INFO_PATTERNS:
        if re.search(pattern, content, re.IGNORECASE):
            return True, "This post was blocked: phone numbers, emails, and external links are not allowed."

    return False, ""
