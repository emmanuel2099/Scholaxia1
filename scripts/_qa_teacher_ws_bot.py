"""QA helper: teacher WebSocket bot for a live-class room.

Joins as role=teacher, says hello in chat, prints every event it receives.
Usage:
    PYTHONUTF8=1 .venv/Scripts/python.exe -u scripts/_qa_teacher_ws_bot.py <room_id> <seconds>
"""
import asyncio
import json
import sys
import urllib.request
from urllib.parse import quote

import websockets

BASE = "http://127.0.0.1:8000"
WS = "ws://127.0.0.1:8000"


def teacher_identity():
    tok_req = urllib.request.Request(
        BASE + "/api/v1/auth/login",
        data=json.dumps({"email": "qa.teacher1@example.com", "password": "TeachPass123!"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    tok = json.loads(urllib.request.urlopen(tok_req, timeout=20).read())["access_token"]
    # JWT payload is base64url between the first two dots
    import base64
    payload = tok.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))["sub"], tok


async def main():
    room = sys.argv[1] if len(sys.argv) > 1 else "room-94037ed5043a"
    run_seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 25.0
    uid, tok = teacher_identity()
    url = f"{WS}/ws/live-class/{quote(room)}?user_id={quote(uid)}&role=teacher&display_name={quote('Qa.Teacher1')}"
    print(f"BOT connecting as {uid} to {room}")

    async with websockets.connect(url, open_timeout=15, ping_interval=None) as ws:
        print("BOT connected")

        async def heartbeat():
            while True:
                await asyncio.sleep(1.5)
                try:
                    await ws.send(json.dumps({"event": "ping"}))
                except Exception:
                    return

        hb = asyncio.ensure_future(heartbeat())

        async def say_hello():
            await asyncio.sleep(2.0)
            await ws.send(json.dumps({"event": "chat", "text": "QA-TEACHER-CHAT: hello class, welcome!"}))
            print("BOT chat sent")

        hello = asyncio.ensure_future(say_hello())

        loop = asyncio.get_event_loop()
        deadline = loop.time() + run_seconds
        seen = []
        while loop.time() < deadline:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=max(0.1, deadline - loop.time()))
                ev = json.loads(msg)
                seen.append(ev.get("event"))
                if ev.get("event") == "chat":
                    print(f"BOT chat from {ev.get('name')} ({ev.get('role')}): {ev.get('text')}")
            except asyncio.TimeoutError:
                break
        hb.cancel()
        hello.cancel()
        print("BOT events seen:", seen[-40:])


asyncio.run(main())
