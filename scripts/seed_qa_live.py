"""Seed the QA live-class fixtures: an approved teacher + two LIVE classes.

Run against the local sandbox (port 8000) after any backend restart:
    PYTHONUTF8=1 .venv/Scripts/python.exe -u scripts/seed_qa_live.py

Idempotent — reuses existing accounts/classes when present.
Creates:
  - teacher qa.teacher1@example.com / TeachPass123! (approved)
  - LIVE public class  "QA Live Algebra Sprint desktop"   (student join test)
  - LIVE public class  "QA Kids Circle Story Time"        (kid join test)
"""
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8000"
TEACHER_EMAIL = "qa.teacher1@example.com"
TEACHER_PW = "TeachPass123!"
MAIN_ADMIN = ("admin@scholaxiatest.com", "AdminPass123!")

CLASSES = [
    {"title": "QA Live Algebra Sprint desktop", "subject": "Mathematics"},
    {"title": "QA Kids Circle Story Time", "subject": "English"},
]


def req(method, path, body=None, token=None):
    r = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Content-Type": "application/json",
            **({"Authorization": "Bearer " + token} if token else {}),
        },
        method=method,
    )
    try:
        raw = urllib.request.urlopen(r, timeout=40).read().decode()
        try:
            return json.loads(raw)
        except Exception:
            return {"_raw": raw[:200]}
    except urllib.error.HTTPError as e:
        try:
            return {"_error": e.code, "detail": e.read().decode()[:300]}
        except Exception:
            return {"_error": e.code, "detail": "?"}


def login(email, pw):
    d = req("POST", "/api/v1/auth/login", {"email": email, "password": pw})
    return d.get("access_token") or ""


def signup_verified(email, pw, role, extra=None):
    st = req("POST", "/api/v1/auth/signup/start", {
        "email": email, "full_name": email.split("@")[0].title(),
        "password": pw, "role": role, **(extra or {})})
    otp = st.get("debug_otp")
    if not otp:
        return ""
    ver = req("POST", "/api/v1/auth/signup/verify", {"email": email, "otp": otp})
    return ver.get("access_token") or ""


def main():
    tok = login(TEACHER_EMAIL, TEACHER_PW)
    if not tok:
        print("seeding teacher account...")
        tok = signup_verified(TEACHER_EMAIL, TEACHER_PW, "teacher",
                              {"subjects": ["Mathematics"], "phone": "+2348000000001"})
    if not tok:
        print("FAIL: could not create teacher"); sys.exit(1)

    # Approve via the main admin if still pending.
    admin_tok = login(*MAIN_ADMIN)
    if admin_tok:
        tlist = req("GET", "/api/v1/admin/teachers", token=admin_tok)
        tlist = tlist if isinstance(tlist, list) else tlist.get("teachers") or []
        t = next((x for x in tlist if x.get("email") == TEACHER_EMAIL), None)
        if t and not t.get("is_approved"):
            tid = t.get("id") or t.get("user_id")
            ap = req("POST", f"/api/v1/admin/teachers/{tid}/approve", {}, token=admin_tok)
            print("teacher approve:", "OK" if "_error" not in ap else ap)
            tok = login(TEACHER_EMAIL, TEACHER_PW)

    # Existing live classes from earlier runs?
    mine = req("GET", "/api/v1/live-classes/?status=live&limit=50", token=tok)
    have = {c.get("title") for c in (mine if isinstance(mine, list) else []) if isinstance(c, dict)}

    for spec in CLASSES:
        if spec["title"] in have:
            print(f"live class already running: {spec['title']}")
            continue
        body = {**spec, "go_live_now": True, "duration_minutes": 60, "visibility": "public"}
        r = req("POST", "/api/v1/live-classes/", body, token=tok)
        if "_error" in r:
            print(f"FAIL create '{spec['title']}':", r.get("detail"))
        else:
            print(f"LIVE: {r.get('title')}  id={r.get('id')}  code={r.get('join_code')}")

    live = req("GET", "/api/v1/live-classes/?status=live&limit=50", token=tok)
    rows = live if isinstance(live, list) else []
    print(f"\n== {len(rows)} live class(es) now ==")
    for c in rows:
        print(f"  id={c.get('id')}  {c.get('title')}  room={c.get('room_id')}  code={c.get('join_code')}")


if __name__ == "__main__":
    main()
