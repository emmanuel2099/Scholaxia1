"""In-memory per-room state for live class WebSocket sessions."""
from typing import Dict, Set, List

whiteboard_access: Dict[str, Set[str]] = {}
mic_access: Dict[str, Set[str]] = {}
camera_access: Dict[str, Set[str]] = {}
# Server-side whiteboard replay so students always catch up even if teacher sync hiccups.
room_board_state: Dict[str, dict] = {}


def _uid(user_id: str) -> str:
    return str(user_id or "").strip().lower()


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


def grant_whiteboard(room_id: str, user_id: str) -> None:
    whiteboard_access.setdefault(room_id, set()).add(_uid(user_id))


def revoke_whiteboard(room_id: str, user_id: str) -> None:
    whiteboard_access.get(room_id, set()).discard(_uid(user_id))


def has_whiteboard_access(room_id: str, user_id: str) -> bool:
    return _uid(user_id) in whiteboard_access.get(room_id, set())


def grant_mic(room_id: str, user_id: str) -> None:
    mic_access.setdefault(room_id, set()).add(_uid(user_id))


def revoke_mic(room_id: str, user_id: str) -> None:
    mic_access.get(room_id, set()).discard(_uid(user_id))


def has_mic_access(room_id: str, user_id: str) -> bool:
    return _uid(user_id) in mic_access.get(room_id, set())


def grant_camera(room_id: str, user_id: str) -> None:
    camera_access.setdefault(room_id, set()).add(_uid(user_id))


def revoke_camera(room_id: str, user_id: str) -> None:
    camera_access.get(room_id, set()).discard(_uid(user_id))


def has_camera_access(room_id: str, user_id: str) -> bool:
    return _uid(user_id) in camera_access.get(room_id, set())


def has_publish_access(room_id: str, user_id: str) -> bool:
    return has_mic_access(room_id, user_id) or has_camera_access(room_id, user_id)


def cleanup_room(room_id: str) -> None:
    whiteboard_access.pop(room_id, None)
    mic_access.pop(room_id, None)
    camera_access.pop(room_id, None)
    room_board_state.pop(room_id, None)
