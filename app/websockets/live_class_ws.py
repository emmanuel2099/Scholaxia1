"""
WebSocket handler for live class real-time features:
- Chat
- Whiteboard sync (teacher always has access; students need teacher grant)
- Raise hand + teacher grants mic
- Polls
"""
from fastapi import WebSocket, WebSocketDisconnect
from typing import Dict, List
import json

from app.services.live_class_room import (
    grant_whiteboard,
    revoke_whiteboard,
    has_whiteboard_access,
    grant_mic,
    revoke_mic,
    grant_camera,
    revoke_camera,
    cleanup_room,
    record_board_event,
    get_board_replay_messages,
)

# room_id -> list of connected websockets with metadata
rooms: Dict[str, List[dict]] = {}


async def connect(room_id: str, websocket: WebSocket, user_id: str, role: str, display_name: str = ""):
    await websocket.accept()
    if room_id not in rooms:
        rooms[room_id] = []
    rooms[room_id].append({
        "ws": websocket,
        "user_id": user_id,
        "role": role,
        "display_name": display_name or ("Teacher" if role in ("teacher", "admin") else "Student"),
    })


def disconnect(room_id: str, websocket: WebSocket):
    if room_id in rooms:
        rooms[room_id] = [c for c in rooms[room_id] if c["ws"] != websocket]
        if not rooms[room_id]:
            del rooms[room_id]
            cleanup_room(room_id)


async def broadcast(room_id: str, message: dict, exclude: WebSocket = None):
    if room_id not in rooms:
        return
    dead = []
    for conn in rooms[room_id]:
        if conn["ws"] == exclude:
            continue
        try:
            await conn["ws"].send_text(json.dumps(message))
        except Exception:
            dead.append(conn)
    for conn in dead:
        rooms[room_id].remove(conn)


async def replay_board_to_websocket(room_id: str, websocket: WebSocket) -> None:
    for msg in get_board_replay_messages(room_id):
        try:
            await websocket.send_text(json.dumps(msg))
        except Exception:
            break


async def send_to_user(room_id: str, target_user_id: str, message: dict):
    """Send a message to a specific user in the room."""
    if room_id not in rooms:
        return
    target = str(target_user_id or "").strip().lower()
    for conn in rooms[room_id]:
        if str(conn["user_id"] or "").strip().lower() == target:
            try:
                await conn["ws"].send_text(json.dumps(message))
            except Exception:
                pass


def _is_teacher_role(role: str) -> bool:
    r = str(role or "").strip().lower().replace("userrole.", "")
    return r in ("teacher", "admin", "host")


async def notify_mic_granted(room_id: str, student_id: str) -> None:
    sid = str(student_id or "").strip()
    grant_mic(room_id, sid)
    payload = {
        "event": "mic_access_granted",
        "user_id": sid,
        "target_user_id": sid,
        "message": "Your teacher let you speak. Your mic is turning on.",
    }
    await send_to_user(room_id, sid, payload)
    await broadcast(room_id, payload)
    await broadcast(room_id, {
        "event": "mic_access_update",
        "user_id": sid,
        "has_mic": True,
    })


async def notify_mic_revoked(room_id: str, student_id: str) -> None:
    sid = str(student_id or "").strip()
    revoke_mic(room_id, sid)
    payload = {
        "event": "mic_access_revoked",
        "user_id": sid,
        "target_user_id": sid,
        "message": "Your teacher muted you.",
    }
    await send_to_user(room_id, sid, payload)
    await broadcast(room_id, payload)
    await broadcast(room_id, {
        "event": "mic_access_update",
        "user_id": sid,
        "has_mic": False,
    })


async def notify_camera_granted(room_id: str, student_id: str) -> None:
    sid = str(student_id or "").strip()
    grant_camera(room_id, sid)
    await send_to_user(room_id, sid, {
        "event": "camera_access_granted",
        "user_id": sid,
        "target_user_id": sid,
        "message": "Your teacher let you turn on your camera.",
    })
    await broadcast(room_id, {
        "event": "camera_access_update",
        "user_id": sid,
        "has_camera": True,
    })


async def notify_camera_revoked(room_id: str, student_id: str) -> None:
    revoke_camera(room_id, student_id)
    await send_to_user(room_id, student_id, {
        "event": "camera_access_revoked",
        "message": "Your teacher turned off your camera access.",
    })
    await broadcast(room_id, {
        "event": "camera_access_update",
        "user_id": student_id,
        "has_camera": False,
    })


async def live_class_endpoint(websocket: WebSocket, room_id: str, user_id: str, role: str, display_name: str = ""):
    await connect(room_id, websocket, user_id, role, display_name)
    name = display_name or ("Teacher" if _is_teacher_role(role) else "Student")
    await broadcast(room_id, {
        "event": "user_joined",
        "user_id": user_id,
        "role": role,
        "name": name,
    }, exclude=websocket)
    if not _is_teacher_role(role):
        await replay_board_to_websocket(room_id, websocket)

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            event = message.get("event")

            if event == "chat":
                await broadcast(room_id, {
                    "event": "chat",
                    "user_id": user_id,
                    "role": role,
                    "text": message.get("text", ""),
                })

            elif event == "screen_share":
                # Relay so students force-subscribe / hide board under the share
                await broadcast(
                    room_id,
                    {
                        "event": "screen_share",
                        "user_id": user_id,
                        "role": role,
                        "active": bool(message.get("active")),
                    },
                    exclude=websocket,
                )

            elif event == "whiteboard":
                has_access = _is_teacher_role(role) or has_whiteboard_access(room_id, user_id)
                if not has_access:
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "You do not have whiteboard access. Ask your teacher.",
                    }))
                else:
                    action = message.get("action")
                    data = message.get("data") or {}
                    if _is_teacher_role(role):
                        record_board_event(room_id, action, data)
                    await broadcast(room_id, {
                        "event": "whiteboard",
                        "user_id": user_id,
                        "action": action,
                        "data": data,
                    }, exclude=websocket)

            elif event == "grant_whiteboard":
                if not _is_teacher_role(role):
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "Only teachers can grant whiteboard access.",
                    }))
                else:
                    target_id = message.get("target_user_id")
                    if target_id:
                        grant_whiteboard(room_id, target_id)
                        await send_to_user(room_id, target_id, {
                            "event": "whiteboard_access_granted",
                            "message": "Your teacher gave you whiteboard access.",
                        })
                        await broadcast(room_id, {
                            "event": "whiteboard_access_update",
                            "user_id": target_id,
                            "has_access": True,
                        })

            elif event == "revoke_whiteboard":
                if not _is_teacher_role(role):
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "Only teachers can revoke whiteboard access.",
                    }))
                else:
                    target_id = message.get("target_user_id")
                    if target_id:
                        revoke_whiteboard(room_id, target_id)
                        await send_to_user(room_id, target_id, {
                            "event": "whiteboard_access_revoked",
                            "message": "Your whiteboard access has been removed.",
                        })
                        await broadcast(room_id, {
                            "event": "whiteboard_access_update",
                            "user_id": target_id,
                            "has_access": False,
                        })

            elif event == "grant_mic":
                if not _is_teacher_role(role):
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "Only the teacher can allow students to speak.",
                    }))
                else:
                    target_id = message.get("target_user_id")
                    if target_id:
                        await notify_mic_granted(room_id, str(target_id))

            elif event == "revoke_mic":
                if not _is_teacher_role(role):
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "Only the teacher can mute students.",
                    }))
                else:
                    target_id = message.get("target_user_id")
                    if target_id:
                        await notify_mic_revoked(room_id, str(target_id))

            elif event == "request_board_sync":
                await replay_board_to_websocket(room_id, websocket)

            elif event == "raise_hand":
                await broadcast(room_id, {
                    "event": "raise_hand",
                    "user_id": user_id,
                    "name": message.get("name") or "Student",
                })

            elif event == "lower_hand":
                await broadcast(room_id, {
                    "event": "lower_hand",
                    "user_id": user_id,
                })

            elif event == "reaction":
                emoji = (message.get("emoji") or "👍").strip()[:8]
                await broadcast(room_id, {
                    "event": "reaction",
                    "user_id": user_id,
                    "name": message.get("name") or ("Teacher" if role == "teacher" else "Student"),
                    "emoji": emoji,
                    "role": role,
                })

            elif event == "poll_answer":
                await broadcast(room_id, {
                    "event": "poll_answer",
                    "user_id": user_id,
                    "answer": message.get("answer"),
                })

    except WebSocketDisconnect:
        disconnect(room_id, websocket)
        await broadcast(room_id, {"event": "user_left", "user_id": user_id, "role": role})
