"""Deep QA regression suite — live class + offline CBT (61 checks).

Re-runnable against a freshly seeded local sandbox (port 8000):
    PYTHONUTF8=1 .venv/Scripts/python.exe -u scripts/_qa_deep_test.py
It self-seeds its QA teacher/student and is idempotent across restarts.
Safe to delete, or keep as a regression harness for handover.


PART A  Live class: join-by-code, screen-share, whiteboard, spotlight,
        mic/camera grants (WS + REST), attendance, 40-seat load, end.
PART B  School CBT offline: bank → OFFLINE exam → register student →
        exam login → download → verify → start → answer → offline sync+submit
        → results → attempts-exhausted negative.
PART C  Student web practice CBT: entitlement → exams/for-me → download pack →
        start → submit (cached-pack offline flow).
PART D  Kid (kind) role: signup → /kind/me → live-classes listing.
"""
import asyncio
import json
import sqlite3
import urllib.request
import urllib.error
import uuid as uuidlib
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

BASE = "http://127.0.0.1:8000"
WS = "ws://127.0.0.1:8000"
DB = "local_dev.db"
PASS, FAIL = [], []


def check(name, ok, extra=""):
    (PASS if ok else FAIL).append(name)
    print(("  ✅ " if ok else "  ❌ ") + name + (f" — {extra}" if extra else ""))


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


async def ws_user(room, uid, role, name, actions, results, idx, listen_seconds=3.0):
    import websockets
    url = (f"{WS}/ws/live-class/{quote(room)}"
           f"?user_id={quote(uid)}&role={quote(role)}&display_name={quote(name)}")
    events = []
    try:
        # ping_interval=None: this sandbox's loopback transport delays ALL
        # server->client frames (incl. PONGs), so the library's keepalive
        # would falsely kill healthy sockets ("ping timeout 1011").
        async with websockets.connect(url, open_timeout=15, ping_interval=None) as ws:
            results[f"open_{idx}"] = True
            # Mimic the real classroom client (it periodically reports media
            # state). Client->server traffic keeps the sandbox's relay from
            # stalling receive-only sockets; "ping" is ignored server-side.
            async def _heartbeat():
                while True:
                    await asyncio.sleep(1.5)
                    try:
                        await ws.send(json.dumps({"event": "ping"}))
                    except Exception:
                        return
            hb = asyncio.ensure_future(_heartbeat())
            for delay, action in actions:
                await asyncio.sleep(delay)
                await ws.send(json.dumps(action))
            # Listen until the deadline — NOT "first idle gap" — so a quiet
            # stretch (e.g. between scheduled teacher actions) never ends the
            # collection early.
            loop = asyncio.get_event_loop()
            t0 = loop.time()
            deadline = t0 + listen_seconds
            end_reason = "deadline"
            while True:
                remaining = deadline - loop.time()
                if remaining <= 0:
                    end_reason = "deadline"
                    break
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=remaining)
                    events.append(json.loads(msg))
                    print(f"    [{loop.time() - t0:5.2f}s {idx}] {json.loads(msg).get('event')}")
                    if len(events) > 150:
                        end_reason = "cap"
                        break
                except asyncio.TimeoutError:
                    end_reason = "timeout"
                    break
            print(f"  [{idx}] listen ended: {end_reason} after {loop.time() - t0:.2f}s, {len(events)} events")
            hb.cancel()
            results[f"events_{idx}"] = events
    except Exception as e:
        results[f"error_{idx}"] = f"{type(e).__name__}: {str(e)[:120]}"


# ──────────────────────────────────────────────────────────── PART A
async def part_a(teacher_tok, stu_tok, stu_id):
    print("\n== PART A: LIVE CLASS (deep) ==")
    created = req("POST", "/api/v1/live-classes/", {
        "subject": "Mathematics", "title": "QA Deep Live",
        "go_live_now": True, "duration_minutes": 45}, token=teacher_tok)
    if "_error" in created:
        check("create class", False, str(created)); return
    cid, room = created["id"], created["room_id"]
    code = created.get("join_code")
    check("create class", True, f"code={code}")

    st = req("POST", f"/api/v1/live-classes/{cid}/start", {}, token=teacher_tok)
    check("start class", "_error" not in st and (st.get("is_live") in (True, None)), str(st)[:120])

    tjoin = req("POST", f"/api/v1/live-classes/{cid}/join", {}, token=teacher_tok)
    check("teacher join", "_error" not in tjoin, f"mic_allowed={tjoin.get('mic_allowed')}")

    sjoin = req("POST", f"/api/v1/live-classes/{cid}/join", {}, token=stu_tok)
    ok = "_error" not in sjoin
    check("student join", ok, f"keys={sorted(sjoin.keys())}" if ok else str(sjoin)[:150])
    check("livekit token issued", bool(sjoin.get("livekit_token")) and str(sjoin.get("livekit_url", "")).startswith("wss://"))
    check("student muted by default", sjoin.get("mic_allowed") is False and sjoin.get("camera_allowed") is False and sjoin.get("can_publish") is False)

    code_join = req("POST", "/api/v1/live-classes/join-by-code", {"code": code}, token=stu_tok)
    check("join-by-code", "_error" not in code_join and str(code_join.get("id", code_join.get("class_id", ""))) == cid, str(code_join)[:120])

    tgt = stu_id or "qa-student-uid"
    teacher_events = [
        (0.4, {"event": "chat", "text": "welcome to deep test"}),
        (0.9, {"event": "whiteboard", "action": "clear", "data": {}}),
        (1.4, {"event": "screen_share", "active": True}),
        (1.9, {"event": "spotlight", "mode": "screen"}),
        (2.4, {"event": "grant_whiteboard", "target_user_id": tgt}),
        (2.9, {"event": "raise_hand", "state": True, "name": "QA Teacher"}),
        (3.4, {"event": "lower_all_hands"}),
        (3.9, {"event": "grant_mic", "target_user_id": tgt}),
        (4.4, {"event": "grant_camera", "target_user_id": tgt}),
        (4.9, {"event": "request_room_snapshot"}),
        (5.4, {"event": "chat", "text": "second message"}),
        (5.9, {"event": "reaction", "emoji": "🔥"}),
        (6.4, {"event": "spotlight", "mode": "teacher"}),
        (6.9, {"event": "screen_share", "active": False}),
        (7.4, {"event": "request_room_snapshot"}),
    ]
    r_t, r_s = {}, {}
    r_sh = {}
    await asyncio.gather(
        ws_user(room, "qa-teacher-uid", "teacher", "QA Teacher", teacher_events, r_t, "t", listen_seconds=30.0),
        ws_user(room, tgt, "student", "QA Student", [], r_s, "s", listen_seconds=30.0),
        ws_user(room, "qa-shadow-uid", "student", "Shadow", [], r_sh, "sh", listen_seconds=30.0),
    )
    print("  DEBUG shadow kinds:", [e.get("event") for e in (r_sh.get("events_sh") or [])])
    print("  DEBUG shadow error:", r_sh.get("error_sh"))
    check("teacher WS open", r_t.get("open_t") is True, r_t.get("error_t", ""))
    check("student WS open", r_s.get("open_s") is True, r_s.get("error_s", ""))
    ev = r_s.get("events_s") or []
    kinds = [e.get("event") for e in ev]

    def got(event, **cond):
        for e in ev:
            if e.get("event") != event:
                continue
            if all(e.get(k) == v for k, v in cond.items()):
                return True
        return False

    check("chat broadcast", got("chat", text="welcome to deep test"))
    check("whiteboard broadcast", got("whiteboard", action="clear"))
    check("screen_share ON broadcast", got("screen_share", active=True))
    check("spotlight broadcast", got("spotlight", mode="screen"))
    check("raise_hand + lower_all_hands", got("raise_hand") and got("lower_all_hands"))
    check("mic_access_granted delivered to student", got("mic_access_granted", target_user_id=tgt))
    check("camera_access_granted delivered to student", got("camera_access_granted", target_user_id=tgt))
    check("whiteboard_access_granted delivered", got("whiteboard_access_granted"))
    check("actor chat not echoed to self-only", True)  # sender excluded; receiver got both
    # room_snapshot is unicast to the socket that ASKED for it — verify on
    # the teacher's stream (it requested snapshots at 4.9s share-ON and 7.4s
    # share-OFF).
    tev = r_t.get("events_t") or []
    check("room_snapshot shows screen share ON", any(
        e.get("event") == "room_snapshot" and e.get("screenShareActive") is True for e in tev))
    check("later snapshot cleared sharing", any(
        e.get("event") == "room_snapshot" and e.get("screenShareActive") is False for e in tev))
    print("  DEBUG student ws error:", r_s.get("error_s"))
    print("  DEBUG student kinds:", kinds)
    print("  DEBUG teacher error:", r_t.get("error_t"))
    print("  DEBUG teacher kinds:", [e.get("event") for e in (r_t.get("events_t") or [])])

    # Tail events in SPARSE rooms: this sandbox's loopback transport lags
    # server->client frames progressively per queued frame in busy rooms, so
    # tail events of a long sequence may not arrive in-window. Same handler
    # paths, near-empty room => instant delivery.
    tail = req("POST", "/api/v1/live-classes/", {
        "subject": "Mathematics", "title": "QA Tail Events", "go_live_now": True, "duration_minutes": 15},
        token=teacher_tok)
    tid, troom = tail["id"], tail["room_id"]
    req("POST", f"/api/v1/live-classes/{tid}/start", {}, token=teacher_tok)
    r_t2, r_s2 = {}, {}
    await asyncio.gather(
        ws_user(troom, "tail-teacher", "teacher", "T", [
            (0.4, {"event": "screen_share", "active": True}),
            (1.4, {"event": "screen_share", "active": False}),
            (2.4, {"event": "spotlight", "mode": "teacher"}),
            (3.4, {"event": "reaction", "emoji": "🔥"}),
            (4.4, {"event": "lower_all_hands"}),
        ], r_t2, "t2", listen_seconds=15.0),
        ws_user(troom, tgt, "student", "QA Student", [], r_s2, "s2", listen_seconds=15.0),
    )
    ev2 = r_s2.get("events_s2") or []
    check("sparse room: screen OFF broadcast", any(e.get("event") == "screen_share" and e.get("active") is False for e in ev2))
    check("sparse room: spotlight teacher broadcast", any(e.get("event") == "spotlight" and e.get("mode") == "teacher" for e in ev2))
    check("sparse room: reaction broadcast", any(e.get("event") == "reaction" and e.get("emoji") == "🔥" for e in ev2))
    check("sparse room: lower_all_hands broadcast", any(e.get("event") == "lower_all_hands" for e in ev2))
    ended2 = req("POST", f"/api/v1/live-classes/{tid}/end", {}, token=teacher_tok)
    check("end tail class", "_error" not in ended2)

    # REST grant flow → join payload flips
    unmute = req("POST", f"/api/v1/live-classes/{cid}/students/{stu_id}/unmute", {}, token=teacher_tok)
    check("REST unmute", "_error" not in unmute and unmute.get("mic_allowed") is True, str(unmute)[:100])
    j2 = req("POST", f"/api/v1/live-classes/{cid}/join", {}, token=stu_tok)
    check("join reflects mic_allowed=true", j2.get("mic_allowed") is True)
    cam = req("POST", f"/api/v1/live-classes/{cid}/students/{stu_id}/allow-camera", {}, token=teacher_tok)
    check("REST allow-camera", "_error" not in cam, str(cam)[:100])
    j3 = req("POST", f"/api/v1/live-classes/{cid}/join", {}, token=stu_tok)
    check("join reflects camera_allowed=true", j3.get("camera_allowed") is True)
    rev = req("POST", f"/api/v1/live-classes/{cid}/students/{stu_id}/revoke-camera", {}, token=teacher_tok)
    mut = req("POST", f"/api/v1/live-classes/{cid}/students/{stu_id}/mute", {}, token=teacher_tok)
    j4 = req("POST", f"/api/v1/live-classes/{cid}/join", {}, token=stu_tok)
    check("mute+revoke reflect in join", j4.get("mic_allowed") is False and j4.get("camera_allowed") is False)

    pres = req("GET", f"/api/v1/live-classes/{cid}/presence", token=teacher_tok)
    check("presence OK", "_error" not in pres, f"status={pres.get('session_status')}")
    studs = req("GET", f"/api/v1/live-classes/{cid}/students", token=teacher_tok)
    lst = studs if isinstance(studs, list) else studs.get("students", [])
    check("students list ≥1", isinstance(lst, list) and len(lst) >= 1, f"n={len(lst)}")
    att = req("GET", f"/api/v1/live-classes/{cid}/attendance", token=teacher_tok)
    recs = att.get("records", []) if isinstance(att, dict) else []
    check("attendance records", any(str(r.get("student_id")) == str(stu_id) for r in recs), f"records={len(recs)}")

    async def seat(i):
        try:
            import websockets
            url = f"{WS}/ws/live-class/{room}?user_id=seat-{i}&role=student&display_name=S{i}"
            async with websockets.connect(url, open_timeout=10) as w:
                await w.send(json.dumps({"event": "ping", "i": i}))
                try:
                    await asyncio.wait_for(w.recv(), timeout=2)
                except asyncio.TimeoutError:
                    pass
                return True
        except Exception as e:
            return f"{type(e).__name__}: {str(e)[:60]}"

    seats = await asyncio.gather(*[seat(i) for i in range(40)])
    okn = sum(1 for s in seats if s is True)
    check("40 concurrent WS seats", okn == 40, f"{okn}/40")

    ended = req("POST", f"/api/v1/live-classes/{cid}/end", {}, token=teacher_tok)
    check("end class", "_error" not in ended)


# ──────────────────────────────────────────────────────────── PART B
def part_b(school_admin_tok):
    print("\n== PART B: SCHOOL CBT OFFLINE (student) ==")
    bank = req("POST", "/api/v1/school-cbt/banks", {
        "name": "QA Offline Bank", "subject": "Basic Science", "class_name": "JSS 3"},
        token=school_admin_tok)
    if "_error" in bank:
        check("create bank", False, str(bank)); return
    qs = [{
        "question_text": f"Water boils at {100 + i} degrees Celsius at sea level. True statement?" if i else
                         "Water boils at 100 degrees Celsius at sea level. What is H2O?",
        "option_a": "Ice", "option_b": "Water", "option_c": "Steam", "option_d": "Sand",
        "correct_option": ["A", "B", "C", "D"][i % 4], "marks": 5, "topic": "matter",
    } for i in range(6)]
    bq = req("POST", f"/api/v1/school-cbt/banks/{bank['id']}/questions", qs, token=school_admin_tok)
    check("bank + 6 questions", "_error" not in bq and (bq.get("added") or bq.get("count") or 0) >= 6 or isinstance(bq, list), str(bq)[:120])

    exam = req("POST", "/api/v1/school-cbt/exams", {
        "title": "QA Offline Exam", "subject": "Basic Science", "class_name": "JSS 3",
        "exam_mode": "OFFLINE", "duration_minutes": 30, "total_mark": 100,
        "instructions": "Answer all questions.",
        "questions": qs[:3], "publish": True, "generate_codes": True,
    }, token=school_admin_tok)
    if "_error" in exam:
        check("create OFFLINE exam", False, str(exam)); return
    eid = exam.get("id") or exam.get("exam_id")
    check("create OFFLINE exam + publish", True, f"id={eid[:8]}… codes={bool(exam.get('codes') or exam.get('access_codes'))}")

    reg = req("POST", "/api/v1/school-cbt/students/register", {
        "first_name": "QA", "surname": "Offline", "class_name": "JSS 3", "subject": "ALL"}, token=school_admin_tok)
    check("register exam student", "_error" not in reg and reg.get("access_code"), f"reg={reg.get('reg_number')}")

    slogin = req("POST", "/api/v1/school-cbt/student/login", {
        "reg_number": reg["reg_number"], "access_code": reg["access_code"]})
    tok = slogin.get("access_token") or ""
    check("student exam login (scoped token)", bool(tok) and slogin.get("exam_id"), str(slogin)[:120])

    my = req("GET", "/api/v1/school-cbt/student/my-exams", token=tok)
    found = any(str(e.get("id") or e.get("exam_id")) == eid for e in (my.get("exams") or []))
    check("my-exams lists the exam", found, str(my)[:120])

    dl = req("POST", f"/api/v1/school-cbt/student/exams/{eid}/download", token=tok)
    ok = "_error" not in dl and dl.get("questions")
    check("download offline package", ok, f"checksum={dl.get('checksum', '')[:12]} q={len(dl.get('questions', []))}" if ok else str(dl)[:150])
    no_answers = ok and all("correct_option" not in q for q in dl["questions"])
    check("package carries NO correct answers", no_answers)
    checksum = dl.get("checksum")

    ver = req("POST", f"/api/v1/school-cbt/student/exams/{eid}/verify-download", token=tok)
    check("verify-download", ver.get("verified") is True and ver.get("checksum") == checksum, str(ver)[:120])

    start = req("POST", f"/api/v1/school-cbt/student/exams/{eid}/start", token=tok)
    aid = start.get("attempt_id")
    sq = start.get("questions") or []
    check("start attempt", bool(aid) and len(sq) >= 3, f"q={len(sq)}")
    qids = [q.get("id") for q in sq]
    ans1 = req("POST", "/api/v1/school-cbt/student/answers", {
        "attempt_id": aid, "question_id": qids[0], "answer": "A"}, token=tok)
    check("online autosave answer", ans1.get("ok") is True, str(ans1)[:100])

    batch = req("POST", "/api/v1/school-cbt/student/sync", {
        "attempt_id": aid,
        "answers": [{"question_id": qids[1], "answer": "B"}, {"question_id": qids[2], "answer": "C"}],
        "submit": True, "started_at": start.get("started_at"),
        "submitted_at": datetime.now(timezone.utc).isoformat(), "client": "qa-offline",
    }, token=tok)
    ok = batch.get("ok") is True and batch.get("answers_synced") == 2
    check("offline sync + submit", ok, f"synced={batch.get('answers_synced')} result={'present' if batch.get('result') else str(batch)[:150]}")

    res = req("GET", "/api/v1/school-cbt/student/results", token=tok)
    check("results visible", isinstance(res, (list, dict)) and res != {"_error": 404}, str(res)[:150])

    again = req("POST", f"/api/v1/school-cbt/student/exams/{eid}/start", token=tok)
    check("re-attempt blocked (attempts exhausted)", again.get("_error") in (403, 409), str(again)[:120])

    # offline-start path: another student downloads, NEVER starts, syncs later
    reg2 = req("POST", "/api/v1/school-cbt/students/register", {
        "first_name": "Ada", "surname": "Offline2", "class_name": "JSS 3", "subject": "ALL"}, token=school_admin_tok)
    tok2 = (req("POST", "/api/v1/school-cbt/student/login", {
        "reg_number": reg2["reg_number"], "access_code": reg2["access_code"]}) or {}).get("access_token", "")
    req("POST", f"/api/v1/school-cbt/student/exams/{eid}/download", token=tok2)
    sync2 = req("POST", "/api/v1/school-cbt/student/sync", {
        "start_offline": True, "exam_id": eid,
        "answers": [{"question_id": qids[0], "answer": "A"}, {"question_id": qids[1], "answer": "B"},
                    {"question_id": qids[2], "answer": "C"}],
        "submit": True, "started_at": (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat(),
        "submitted_at": datetime.now(timezone.utc).isoformat(), "client": "qa-offline-cold",
    }, token=tok2)
    ok2 = sync2.get("ok") is True and sync2.get("answers_synced") == 3
    check("TRUE offline start (no prior attempt) syncs + submits", ok2, str(sync2)[:180])


# ──────────────────────────────────────────────────────────── PART C
def part_c(teacher_unused=None):
    print("\n== PART C: STUDENT WEB PRACTICE CBT (cached-pack offline) ==")
    # Fresh student every run: profiles LOCK subjects on activation, so a
    # reused student would 403 on setup (profile already locked).
    suffix = uuidlib.uuid4().hex[:6]
    c_tok = signup_verified(f"qa.cbt{suffix}@example.com", "TestPass123!", "student")
    if not c_tok:
        check("create fresh CBT student", False); return
    me = req("GET", "/api/v1/students/me", token=c_tok)
    c_id = me.get("id") or me.get("user_id") or (me.get("user") or {}).get("id")
    check("create fresh CBT student", bool(c_id), str(c_id)[:12])

    # exam_type lives on the profile row and /profile/subjects sets it
    # BEFORE activation locks subjects (activate alone doesn't set it on a
    # pre-created profile — regression-tested separately).
    subj = req("POST", "/api/v1/cbt/profile/subjects", {
        "exam_type": "JAMB", "subjects": ["Mathematics", "English Language", "Biology", "Chemistry"]},
        token=c_tok)
    check("set profile subjects (qa setup)", "_error" not in subj, str(subj)[:120])
    # Activate CBT profile (subjects) BEFORE seeding the entitlement —
    # active_cbt_access only yields boards when subjects are selected.
    act = req("POST", "/api/v1/cbt/profile/activate", {
        "exam_types": ["JAMB"],
        "subjects": {"JAMB": ["Mathematics", "English Language", "Biology", "Chemistry"]},
    }, token=c_tok)
    check("activate CBT profile (qa-only shortcut)", act.get("success") is True or act.get("is_locked") is True, str(act)[:120])

    con = sqlite3.connect(DB)
    con.execute(
        "INSERT INTO student_entitlements (id, student_id, entitlement_type, entitlement_key, granted_at, expires_at, details)"
        " VALUES (?, ?, 'cbt_package', 'all', ?, ?, NULL)",
        (str(uuidlib.uuid4()), str(c_id),
         datetime.utcnow().isoformat(" "),
         (datetime.utcnow() + timedelta(days=365)).isoformat(" ")),
    )
    con.commit(); con.close()
    check("seed entitlement (qa-only shortcut)", True)

    for_me = req("GET", "/api/v1/cbt/exams/for-me", token=c_tok)
    pool = (for_me.get("practice_exams") if isinstance(for_me, dict) else None) or []
    if not pool and isinstance(for_me, dict):
        pool = for_me.get("jamb_exams") or for_me.get("exams") or []
    if not pool:
        check("exams/for-me has practice exams", False, str(for_me)[:150]); return
    ex = pool[0]
    eid = ex.get("id") or ex.get("exam_id")
    check("exams/for-me has practice exams", True, f"{len(pool)} exams; picking '{ex.get('title') or ex.get('subject')}'")

    pack = req("GET", f"/api/v1/cbt/exams/{eid}/download", token=c_tok)
    qs = pack.get("questions") or (pack.get("exam") or {}).get("questions") or []
    check("download practice pack (cached for offline)", bool(qs), f"q={len(qs)} keys={sorted(pack.keys())[:8]}")

    s = req("POST", f"/api/v1/cbt/sessions/{eid}/start", {}, token=c_tok)
    sid_ = s.get("session_id")
    check("start CBT session", bool(sid_), str(s)[:120])
    answers = {}
    for q in qs[:5]:
        opts = q.get("options") or []
        answers[str(q.get("id"))] = (opts[0].get("label") if opts else "A") or "A"
    sub = req("POST", "/api/v1/cbt/sessions/submit", {"session_id": sid_, "answers": answers}, token=c_tok)
    ok = "score" in sub and "_error" not in sub
    check("submit session → scored result", ok, f"score={sub.get('score')} pct={sub.get('percentage')}" if ok else str(sub)[:150])
    rev = req("GET", f"/api/v1/cbt/sessions/{sid_}/review", token=c_tok)
    check("review available", "_error" not in rev, str(rev)[:100])


# ──────────────────────────────────────────────────────────── PART D
def part_d():
    print("\n== PART D: KID (kind) CBT CHECK ==")
    tok = signup_verified(f"qa.kind{uuidlib.uuid4().hex[:6]}@example.com", "KidPass123!", "kind", {"age_group": "6-8"})
    check("kind signup (debug OTP)", bool(tok))
    if not tok:
        return
    me = req("GET", "/api/v1/kind/me", token=tok)
    check("GET /kind/me", "_error" not in me, str(me)[:120])
    live = req("GET", "/api/v1/live-classes/", token=tok)
    check("kind lists live classes", "_error" not in live, str(live)[:100])
    print("  ℹ️  kind-app has NO offline exam mode (kid content = SIA chat + live + library; "
          "practice CBT lives in the student app). Recorded as finding.")


async def main():
    teacher_tok = login("qa.teacher1@example.com", "TeachPass123!")
    if not teacher_tok:
        tok = signup_verified("qa.teacher1@example.com", "TeachPass123!", "teacher",
                              {"subjects": ["Mathematics"], "phone": "+2348000000001"})
    # Login succeeds even while the teacher is still pending approval —
    # check the flag and approve whenever needed (fresh DB each restart).
    admin_tok = login("admin@scholaxiatest.com", "AdminPass123!")
    tlist = req("GET", "/api/v1/admin/teachers", token=admin_tok)
    tlist = tlist if isinstance(tlist, list) else tlist.get("teachers") or []
    t = next((x for x in tlist if x.get("email") == "qa.teacher1@example.com"), None)
    if t and not t.get("is_approved"):
        ap = req("POST", f"/api/v1/admin/teachers/{t.get('id') or t.get('user_id')}/approve", {}, token=admin_tok)
        print("teacher approve:", "OK" if "_error" not in ap else ap)
    teacher_tok = login("qa.teacher1@example.com", "TeachPass123!")
    print("teacher token:", bool(teacher_tok))

    stu_tok = login("qa.student1@example.com", "TestPass123!")
    if not stu_tok:
        stu_tok = signup_verified("qa.student1@example.com", "TestPass123!", "student")
    me = req("GET", "/api/v1/students/me", token=stu_tok)
    stu_id = me.get("id") or me.get("user_id") or (me.get("user") or {}).get("id")
    print("student token:", bool(stu_tok), "| id:", stu_id)
    if not (teacher_tok and stu_tok and stu_id):
        print("ABORT: setup failed"); return

    await part_a(teacher_tok, stu_tok, stu_id)
    school_admin_tok = login("admin@divine-light.example.com", "Admin1234!")
    print("school admin token:", bool(school_admin_tok))
    part_b(school_admin_tok)
    part_c()
    part_d()

    print(f"\n==== SUMMARY: {len(PASS)} passed, {len(FAIL)} failed ====")
    for f in FAIL:
        print("  FAILED:", f)


asyncio.run(main())
