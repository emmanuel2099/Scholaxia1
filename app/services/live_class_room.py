"""In-memory per-room state for live class WebSocket sessions."""
from typing import Dict, Set

whiteboard_access: Dict[str, Set[str]] = {}
mic_access: Dict[str, Set[str]] = {}


def grant_whiteboard(room_id: str, user_id: str) -> None:
    whiteboard_access.setdefault(room_id, set()).add(user_id)


def revoke_whiteboard(room_id: str, user_id: str) -> None:
    whiteboard_access.get(room_id, set()).discard(user_id)


def has_whiteboard_access(room_id: str, user_id: str) -> bool:
    return user_id in whiteboard_access.get(room_id, set())


def grant_mic(room_id: str, user_id: str) -> None:
    mic_access.setdefault(room_id, set()).add(user_id)


def revoke_mic(room_id: str, user_id: str) -> None:
    mic_access.get(room_id, set()).discard(user_id)


def has_mic_access(room_id: str, user_id: str) -> bool:
    return user_id in mic_access.get(room_id, set())


def cleanup_room(room_id: str) -> None:
    whiteboard_access.pop(room_id, None)
    mic_access.pop(room_id, None)
