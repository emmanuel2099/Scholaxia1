"""In-memory per-room classroom state (Layer 2 — authoritative for WS peers).

Stable participant identity = user_id (authenticated JWT sub).
Reconnects upsert; they do not create duplicate participants.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set
import uuid

whiteboard_access: Dict[str, Set[str]] = {}
mic_access: Dict[str, Set[str]] = {}
camera_access: Dict[str, Set[str]] = {}
room_board_state: Dict[str, dict] = {}

# room_id -> { user_id_lower -> participant dict }
room_participants: Dict[str, Dict[str, dict]] = {}
# room_id -> presentation / class meta
room_meta: Dict[str, dict] = {}
# room_id -> ordered list of user_ids with hand raised
room_raised_hands: Dict[str, List[str]] = {}


def _uid(user_id: str) -> str:
    return str(user_id or "").strip().lower()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_event_id() -> str:
    return uuid.uuid4().hex


# ── Session status (derived — no DB migration required) ───────────────────────

def derive_session_status(
    *,
    is_live: bool,
    start_time: Optional[datetime],
    end_time: Optional[datetime],
    now: Optional[datetime] = None,
) -> str:
    """
    SCHEDULED | LOBBY | LIVE | ENDED
    Maps onto existing LiveClass.is_live / start_time / end_time.
    """
    now = now or datetime.utcnow()
    if end_time is not None and end_time <= now:
        return "ENDED"
    if is_live:
        return "LIVE"
    if start_time is not None and start_time > now:
        return "SCHEDULED"
    # Window open but teacher has not flipped is_live yet
    if start_time is not None and start_time <= now:
        return "LOBBY"
    return "SCHEDULED"


# ── Board state ───────────────────────────────────────────────────────────────

def record_board_event(room_id: str, action: str, data: dict | None) -> None:
    if not room_id:
        return
    state = room_board_state.setdefault(room_id, {"open": False, "events": []})
    action = str(action or "")
    data = dict(data or {})
    if action == "image":
        url = str(data.get("url") or "")
        if url.startswith("blob:") or url.startswith("data:"):
            return
    if action == "board_open":
        state["open"] = bool(data.get("open"))
        if not state["open"]:
            state["events"] = []
        return
    if action == "clear":
        state["events"] = []
        return
    if action == "text_stream":
        state["events"] = [e for e in state["events"] if e.get("action") != "text_stream"]
        state["events"].append({"action": action, "data": data})
        return
    state["events"].append({"action": action, "data": data})
    if action in ("draw", "text", "image", "erase"):
        state["events"] = [e for e in state["events"] if e.get("action") != "text_stream"]
    if len(state["events"]) > 800:
        state["events"] = state["events"][-800:]


def get_board_replay_messages(room_id: str) -> List[dict]:
    state = room_board_state.get(room_id)
    if not state:
        return []
    out: List[dict] = [
        {
            "event": "whiteboard",
            "action": "board_open",
            "data": {"open": bool(state.get("open"))},
        }
    ]
    if state.get("open"):
        for ev in state.get("events") or []:
            out.append(
                {
                    "event": "whiteboard",
                    "action": ev.get("action"),
                    "data": ev.get("data") or {},
                }
            )
    return out


# ── Permission sets ───────────────────────────────────────────────────────────

def grant_whiteboard(room_id: str, user_id: str) -> None:
    whiteboard_access.setdefault(room_id, set()).add(_uid(user_id))
    upsert_participant_flags(room_id, user_id, whiteboard_enabled=True)


def revoke_whiteboard(room_id: str, user_id: str) -> None:
    whiteboard_access.get(room_id, set()).discard(_uid(user_id))
    upsert_participant_flags(room_id, user_id, whiteboard_enabled=False)


def has_whiteboard_access(room_id: str, user_id: str) -> bool:
    return _uid(user_id) in whiteboard_access.get(room_id, set())


def grant_mic(room_id: str, user_id: str) -> None:
    mic_access.setdefault(room_id, set()).add(_uid(user_id))
    upsert_participant_flags(room_id, user_id, microphone_enabled=True, mic_allowed=True)


def revoke_mic(room_id: str, user_id: str) -> None:
    mic_access.get(room_id, set()).discard(_uid(user_id))
    upsert_participant_flags(room_id, user_id, microphone_enabled=False, mic_allowed=False)


def has_mic_access(room_id: str, user_id: str) -> bool:
    return _uid(user_id) in mic_access.get(room_id, set())


def grant_camera(room_id: str, user_id: str) -> None:
    camera_access.setdefault(room_id, set()).add(_uid(user_id))
    upsert_participant_flags(room_id, user_id, camera_allowed=True)


def revoke_camera(room_id: str, user_id: str) -> None:
    camera_access.get(room_id, set()).discard(_uid(user_id))
    upsert_participant_flags(room_id, user_id, camera_allowed=False, camera_enabled=False)


def has_camera_access(room_id: str, user_id: str) -> bool:
    return _uid(user_id) in camera_access.get(room_id, set())


def has_publish_access(room_id: str, user_id: str) -> bool:
    return has_mic_access(room_id, user_id) or has_camera_access(room_id, user_id)


# ── Participants ──────────────────────────────────────────────────────────────

def _empty_participant(user_id: str, role: str, name: str) -> dict:
    rid = str(role or "student").strip().lower().replace("userrole.", "")
    is_teacher = rid in ("teacher", "admin", "host")
    return {
        "participantId": _uid(user_id),
        "userId": str(user_id),
        "name": name or ("Teacher" if is_teacher else "Student"),
        "role": "TEACHER" if is_teacher else "STUDENT",
        "cameraEnabled": False,
        "cameraAllowed": False,
        "microphoneEnabled": False,
        "micAllowed": False,
        "whiteboardEnabled": False,
        "isSpeaking": False,
        "isHandRaised": False,
        "handRaisedAt": None,
        "currentReaction": None,
        "connectionState": "CONNECTING",
        "isScreenSharing": False,
        "joinedAt": _now_iso(),
    }


def upsert_participant(
    room_id: str,
    user_id: str,
    *,
    role: str = "student",
    name: str = "",
    reconnect: bool = False,
) -> dict:
    """Create or update participant by stable user_id. Prevents duplicates."""
    if not room_id or not user_id:
        return {}
    key = _uid(user_id)
    bucket = room_participants.setdefault(room_id, {})
    existing = bucket.get(key)
    if existing:
        existing["name"] = name or existing.get("name") or "Student"
        if role:
            rid = str(role).strip().lower().replace("userrole.", "")
            existing["role"] = "TEACHER" if rid in ("teacher", "admin", "host") else existing.get("role") or "STUDENT"
        existing["connectionState"] = "CONNECTED"
        existing["micAllowed"] = has_mic_access(room_id, user_id) or bool(existing.get("micAllowed"))
        existing["cameraAllowed"] = has_camera_access(room_id, user_id) or bool(existing.get("cameraAllowed"))
        existing["whiteboardEnabled"] = has_whiteboard_access(room_id, user_id)
        if reconnect:
            existing["reconnectedAt"] = _now_iso()
        bucket[key] = existing
        return existing

    p = _empty_participant(user_id, role, name)
    p["connectionState"] = "CONNECTED"
    p["micAllowed"] = has_mic_access(room_id, user_id)
    p["cameraAllowed"] = has_camera_access(room_id, user_id)
    p["whiteboardEnabled"] = has_whiteboard_access(room_id, user_id)
    # Teachers always allowed
    if p["role"] == "TEACHER":
        p["micAllowed"] = True
        p["cameraAllowed"] = True
        p["whiteboardEnabled"] = True
    bucket[key] = p
    return p


def upsert_participant_flags(room_id: str, user_id: str, **flags: Any) -> Optional[dict]:
    key = _uid(user_id)
    bucket = room_participants.get(room_id) or {}
    p = bucket.get(key)
    if not p:
        return None
    mapping = {
        "camera_enabled": "cameraEnabled",
        "cameraEnabled": "cameraEnabled",
        "camera_allowed": "cameraAllowed",
        "cameraAllowed": "cameraAllowed",
        "microphone_enabled": "microphoneEnabled",
        "microphoneEnabled": "microphoneEnabled",
        "mic_allowed": "micAllowed",
        "micAllowed": "micAllowed",
        "whiteboard_enabled": "whiteboardEnabled",
        "whiteboardEnabled": "whiteboardEnabled",
        "is_speaking": "isSpeaking",
        "isSpeaking": "isSpeaking",
        "is_screen_sharing": "isScreenSharing",
        "isScreenSharing": "isScreenSharing",
        "connection_state": "connectionState",
        "connectionState": "connectionState",
        "current_reaction": "currentReaction",
        "currentReaction": "currentReaction",
    }
    for k, v in flags.items():
        field = mapping.get(k)
        if field:
            p[field] = v
    bucket[key] = p
    room_participants[room_id] = bucket
    return p


def mark_participant_disconnected(room_id: str, user_id: str) -> Optional[dict]:
    key = _uid(user_id)
    bucket = room_participants.get(room_id) or {}
    p = bucket.get(key)
    if not p:
        return None
    p["connectionState"] = "DISCONNECTED"
    p["cameraEnabled"] = False
    p["microphoneEnabled"] = False
    p["isScreenSharing"] = False
    p["leftAt"] = _now_iso()
    bucket[key] = p
    return p


def mark_participant_reconnecting(room_id: str, user_id: str) -> Optional[dict]:
    key = _uid(user_id)
    bucket = room_participants.get(room_id) or {}
    p = bucket.get(key)
    if not p:
        return None
    p["connectionState"] = "RECONNECTING"
    bucket[key] = p
    return p


def remove_participant(room_id: str, user_id: str) -> None:
    key = _uid(user_id)
    bucket = room_participants.get(room_id)
    if bucket:
        bucket.pop(key, None)
    hands = room_raised_hands.get(room_id) or []
    room_raised_hands[room_id] = [h for h in hands if h != key]


def list_participants(room_id: str) -> List[dict]:
    bucket = room_participants.get(room_id) or {}
    # Prefer connected first, then by join time
    items = list(bucket.values())

    def sort_key(p: dict):
        state = p.get("connectionState") or ""
        order = 0 if state == "CONNECTED" else 1 if state == "RECONNECTING" else 2
        return (order, p.get("joinedAt") or "")

    items.sort(key=sort_key)
    return items


def raise_hand(room_id: str, user_id: str, name: str = "") -> dict:
    key = _uid(user_id)
    p = upsert_participant(room_id, user_id, name=name or "Student")
    p["isHandRaised"] = True
    p["handRaisedAt"] = _now_iso()
    if name:
        p["name"] = name
    hands = room_raised_hands.setdefault(room_id, [])
    if key not in hands:
        hands.append(key)
    return p


def lower_hand(room_id: str, user_id: str) -> Optional[dict]:
    key = _uid(user_id)
    bucket = room_participants.get(room_id) or {}
    p = bucket.get(key)
    if p:
        p["isHandRaised"] = False
        p["handRaisedAt"] = None
    hands = room_raised_hands.get(room_id) or []
    room_raised_hands[room_id] = [h for h in hands if h != key]
    return p


def raised_hand_queue(room_id: str) -> List[dict]:
    hands = room_raised_hands.get(room_id) or []
    bucket = room_participants.get(room_id) or {}
    out = []
    for key in hands:
        p = bucket.get(key)
        if p and p.get("isHandRaised"):
            out.append(
                {
                    "userId": p.get("userId"),
                    "name": p.get("name"),
                    "handRaisedAt": p.get("handRaisedAt"),
                }
            )
    return out


def set_room_meta(room_id: str, **kwargs: Any) -> dict:
    meta = room_meta.setdefault(room_id, {})
    meta.update({k: v for k, v in kwargs.items() if v is not None})
    return meta


def get_room_snapshot(room_id: str) -> dict:
    """Full classroom state for a late joiner / reconnect."""
    meta = room_meta.get(room_id) or {}
    board = room_board_state.get(room_id) or {"open": False, "events": []}
    return {
        "event": "room_snapshot",
        "eventId": new_event_id(),
        "roomId": room_id,
        "sessionStatus": meta.get("sessionStatus") or "LIVE",
        "classId": meta.get("classId"),
        "presentation": meta.get("presentation") or "teacher",
        "screenShareActive": bool(meta.get("screenShareActive")),
        "participants": list_participants(room_id),
        "raisedHands": raised_hand_queue(room_id),
        "boardOpen": bool(board.get("open")),
        "permissions": meta.get("permissions")
        or {
            "studentsCanUseCamera": True,
            "studentsCanUseMicrophone": True,
            "studentsCanChat": True,
            "studentsCanReact": True,
            "studentsCanRaiseHand": True,
            "studentsCanShareScreen": False,
            "studentsCanWriteBoard": False,
        },
    }


def cleanup_room(room_id: str) -> None:
    whiteboard_access.pop(room_id, None)
    mic_access.pop(room_id, None)
    camera_access.pop(room_id, None)
    room_board_state.pop(room_id, None)
    room_participants.pop(room_id, None)
    room_meta.pop(room_id, None)
    room_raised_hands.pop(room_id, None)
