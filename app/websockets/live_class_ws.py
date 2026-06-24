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
    cleanup_room,
)

# room_id -> list of connected websockets with metadata
rooms: Dict[str, List[dict]] = {}


async def connect(room_id: str, websocket: WebSocket, user_id: str, role: str):
    await websocket.accept()
    if room_id not in rooms:
        rooms[room_id] = []
    rooms[room_id].append({"ws": websocket, "user_id": user_id, "role": role})


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


async def send_to_user(room_id: str, target_user_id: str, message: dict):
    """Send a message to a specific user in the room."""
    if room_id not in rooms:
        return
    for conn in rooms[room_id]:
        if conn["user_id"] == target_user_id:
            try:
                await conn["ws"].send_text(json.dumps(message))
            except Exception:
                pass


def _is_teacher_role(role: str) -> bool:
    return role in ("teacher", "admin")


async def notify_mic_granted(room_id: str, student_id: str) -> None:
    grant_mic(room_id, student_id)
    await send_to_user(room_id, student_id, {
        "event": "mic_access_granted",
        "message": "Your teacher let you speak. Your mic is turning on.",
    })
    await broadcast(room_id, {
        "event": "mic_access_update",
        "user_id": student_id,
        "has_mic": True,
    })


async def notify_mic_revoked(room_id: str, student_id: str) -> None:
    revoke_mic(room_id, student_id)
    await send_to_user(room_id, student_id, {
        "event": "mic_access_revoked",
        "message": "Your teacher muted you.",
    })
    await broadcast(room_id, {
        "event": "mic_access_update",
        "user_id": student_id,
        "has_mic": False,
    })


async def live_class_endpoint(websocket: WebSocket, room_id: str, user_id: str, role: str):
    await connect(room_id, websocket, user_id, role)
    await broadcast(room_id, {"event": "user_joined", "user_id": user_id, "role": role}, exclude=websocket)

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

            elif event == "whiteboard":
                has_access = _is_teacher_role(role) or has_whiteboard_access(room_id, user_id)
                if not has_access:
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "You do not have whiteboard access. Ask your teacher.",
                    }))
                else:
                    await broadcast(room_id, {
                        "event": "whiteboard",
                        "user_id": user_id,
                        "action": message.get("action"),
                        "data": message.get("data"),
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
                        grant_mic(room_id, target_id)
                        await send_to_user(room_id, target_id, {
                            "event": "mic_access_granted",
                            "message": "Your teacher let you speak. Your mic is turning on.",
                        })
                        await broadcast(room_id, {
                            "event": "mic_access_update",
                            "user_id": target_id,
                            "has_mic": True,
                        })

            elif event == "revoke_mic":
                if not _is_teacher_role(role):
                    await websocket.send_text(json.dumps({
                        "event": "error",
                        "message": "Only the teacher can mute students.",
                    }))
                else:
                    target_id = message.get("target_user_id")
                    if target_id:
                        revoke_mic(room_id, target_id)
                        await send_to_user(room_id, target_id, {
                            "event": "mic_access_revoked",
                            "message": "Your teacher muted you.",
                        })
                        await broadcast(room_id, {
                            "event": "mic_access_update",
                            "user_id": target_id,
                            "has_mic": False,
                        })

            elif event == "request_board_sync":
                await broadcast(room_id, {
                    "event": "request_board_sync",
                    "user_id": user_id,
                }, exclude=websocket)

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

            elif event == "poll_answer":
                await broadcast(room_id, {
                    "event": "poll_answer",
                    "user_id": user_id,
                    "answer": message.get("answer"),
                })

    except WebSocketDisconnect:
        disconnect(room_id, websocket)
        await broadcast(room_id, {"event": "user_left", "user_id": user_id, "role": role})
