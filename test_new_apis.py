"""
Tests for new APIs:
  - CBT: list exams, get exam, download for offline, my-sessions, result, review
  - Profiles: student profile, teacher profile, list teachers, teachers/me, PATCH teachers/me
"""
import urllib.request, json, time

BASE = "https://scholaxia1.onrender.com"
PASS = 0; FAIL = 0


def post(path, data, token=None):
    body = json.dumps(data).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method="POST")
    try:
        r = urllib.request.urlopen(req, timeout=60)
        raw = r.read()
        return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:    return e.code, json.loads(raw)
        except: return e.code, raw.decode()[:300]

def get(path, token=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, headers=headers)
    try:
        r = urllib.request.urlopen(req, timeout=60)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:    return e.code, json.loads(raw)
        except: return e.code, raw.decode()[:300]

def patch(path, data, token=None):
    body = json.dumps(data).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method="PATCH")
    try:
        r = urllib.request.urlopen(req, timeout=60)
        raw = r.read()
        return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:    return e.code, json.loads(raw)
        except: return e.code, raw.decode()[:300]

def check(label, status, body, expected=(200, 201)):
    global PASS, FAIL
    ok = status in expected
    icon = "PASS" if ok else "FAIL"
    if ok: PASS += 1
    else:  FAIL += 1
    detail = ""
    if isinstance(body, dict):
        detail = body.get("detail", "")
    print(f"  [{icon}] {label} → HTTP {status}  {detail}")
    return ok


print("=" * 55)
print("  SCHOLAXIA — New API Tests")
print(f"  Target: {BASE}")
print("=" * 55)

# ── Wake up server ────────────────────────────────────────
print("\n  Waking server (Render cold start may take ~60s)...")
for attempt in range(6):
    try:
        req = urllib.request.Request(BASE + "/health")
        r = urllib.request.urlopen(req, timeout=60)
        data = json.loads(r.read())
        print(f"  Server online: {data}")
        break
    except Exception as e:
        print(f"  Attempt {attempt+1}/6 — waiting... ({e.__class__.__name__})")
        time.sleep(10)

# ── 0. Setup tokens ───────────────────────────────────────
print("\n── Setup ──")

# Admin
s, r = post("/api/v1/admin/register", {
    "email": "admin@scholaxia.com", "password": "ScholaxiaAdmin2026",
    "full_name": "Test Admin", "invite_code": "SCHOLAXIA_ADMIN_2026"
})
admin_token = r.get("access_token", "") if isinstance(r, dict) else ""
if not admin_token:
    s, r = post("/api/v1/auth/login", {"email": "admin@scholaxia.com", "password": "ScholaxiaAdmin2026"})
    admin_token = r.get("access_token", "") if isinstance(r, dict) else ""
print(f"  Admin token: {'OK' if admin_token else 'MISSING — some tests will skip'}")

# Create teacher
if admin_token:
    ts = int(time.time())
    teacher_email = f"teacher_{ts}@scholaxia.com"
    s, r = post("/api/v1/admin/teachers", {
        "email": teacher_email, "password": "Teacher123!",
        "full_name": "Mrs Ada Nwosu",
        "subjects": ["Biology", "Chemistry"], "bio": "10 years teaching experience"
    }, token=admin_token)
    teacher_id = r.get("id", "") if isinstance(r, dict) else ""
    # Login as teacher
    s, r = post("/api/v1/auth/login", {"email": teacher_email, "password": "Teacher123!"})
    teacher_token = r.get("access_token", "") if isinstance(r, dict) else ""
    print(f"  Teacher token: {'OK' if teacher_token else 'MISSING'}")
else:
    teacher_token = ""; teacher_id = ""

# Student signup
ts = int(time.time())
student_email = f"student_{ts}@test.com"
s, r = post("/api/v1/auth/student/signup", {
    "email": student_email, "password": "Student123!",
    "full_name": "Amaka Obi"
})
student_token = r.get("access_token", "") if isinstance(r, dict) else ""
student_id = ""
if student_token:
    s2, r2 = get("/api/v1/students/me", token=student_token)
    student_id = r2.get("user_id", "") if isinstance(r2, dict) else ""
print(f"  Student token: {'OK' if student_token else 'MISSING'}")
print(f"  Student ID: {student_id or 'unknown'}")


# ── 1. CBT: List Exams (no auth) ──────────────────────────
print("\n── CBT Endpoints ──")

s, r = get("/api/v1/cbt/exams")
ok = check("GET /cbt/exams (no auth)", s, r)
exams = r if isinstance(r, list) else []
print(f"         Exams returned: {len(exams)}")
for e in exams[:4]:
    print(f"         · {e.get('exam_type')} | {e.get('subject')} | {e.get('title')} | {e.get('total_questions')}Q")

exam_id = exams[0]["id"] if exams else None


# ── 2. CBT: Filter by exam_type ───────────────────────────
s, r = get("/api/v1/cbt/exams?exam_type=WAEC")
ok = check("GET /cbt/exams?exam_type=WAEC", s, r)
waec = r if isinstance(r, list) else []
all_waec = all(e.get("exam_type") == "WAEC" for e in waec)
print(f"         WAEC exams: {len(waec)}, all filtered correctly: {all_waec}")

s, r = get("/api/v1/cbt/exams?exam_type=NECO")
check("GET /cbt/exams?exam_type=NECO", s, r)
neco = r if isinstance(r, list) else []
print(f"         NECO exams: {len(neco)}")


# ── 3. CBT: Get exam info ─────────────────────────────────
if exam_id:
    s, r = get(f"/api/v1/cbt/exams/{exam_id}")
    check("GET /cbt/exams/{id}", s, r)
    print(f"         Title: {r.get('title')}, Questions: {r.get('total_questions')}")
else:
    print("  [SKIP] GET /cbt/exams/{id} — no exam_id available (server may need restart to seed)")


# ── 4. CBT: Download exam for offline (auth required) ─────
if exam_id and student_token:
    s, r = get(f"/api/v1/cbt/exams/{exam_id}/download", token=student_token)
    check("GET /cbt/exams/{id}/download (auth)", s, r)
    questions = r.get("questions", []) if isinstance(r, dict) else []
    has_answers = any("correct_option" in q for q in questions)
    print(f"         Questions in payload: {len(questions)}")
    print(f"         Correct answers exposed: {has_answers} (should be False)")
elif not exam_id:
    print("  [SKIP] Download exam — no exam_id")
else:
    print("  [SKIP] Download exam — no student token")

# No auth should be rejected
if exam_id:
    s, r = get(f"/api/v1/cbt/exams/{exam_id}/download")
    check("GET /cbt/exams/{id}/download (no auth → 403)", s, r, expected=(401, 403))


# ── 5. CBT: my-sessions (empty for new student) ───────────
if student_token:
    s, r = get("/api/v1/cbt/my-sessions", token=student_token)
    check("GET /cbt/my-sessions", s, r)
    sessions = r if isinstance(r, list) else []
    print(f"         Sessions: {len(sessions)}")
else:
    print("  [SKIP] my-sessions — no student token")


# ── 6. CBT: Start + submit a session end-to-end ───────────
session_id = None
if exam_id and student_token:
    # Start
    s, r = post(f"/api/v1/cbt/sessions/{exam_id}/start", {}, token=student_token)
    ok = check("POST /cbt/sessions/{id}/start", s, r)
    session_id = r.get("session_id") if isinstance(r, dict) else None
    print(f"         Session ID: {session_id}")

    if session_id:
        # Need questions to build answer dict
        s2, r2 = get(f"/api/v1/cbt/exams/{exam_id}/download", token=student_token)
        qs = r2.get("questions", []) if isinstance(r2, dict) else []
        # Answer all A
        answers = {q["id"]: "A" for q in qs}

        # Submit
        s, r = post("/api/v1/cbt/sessions/submit", {
            "session_id": session_id,
            "answers": answers,
            "is_auto_submit": False
        }, token=student_token)
        check("POST /cbt/sessions/submit", s, r)
        print(f"         Score: {r.get('percentage')}% | Correct: {r.get('total_correct')} | Wrong: {r.get('total_wrong')}")
        print(f"         Weak topics: {r.get('weak_topics', [])[:3]}")

        # Result
        s, r = get(f"/api/v1/cbt/sessions/{session_id}/result", token=student_token)
        check("GET /cbt/sessions/{id}/result", s, r)

        # Review
        s, r = get(f"/api/v1/cbt/sessions/{session_id}/review", token=student_token)
        check("GET /cbt/sessions/{id}/review", s, r)
        review_qs = r.get("questions", []) if isinstance(r, dict) else []
        has_correct = any("correct_option" in q for q in review_qs)
        has_explanations = any(q.get("explanation") for q in review_qs)
        print(f"         Review questions: {len(review_qs)}, has correct answers: {has_correct}, has explanations: {has_explanations}")

        # my-sessions again — should now show 1
        s, r = get("/api/v1/cbt/my-sessions", token=student_token)
        check("GET /cbt/my-sessions (after submit)", s, r)
        sessions = r if isinstance(r, list) else []
        print(f"         Sessions after submit: {len(sessions)}")
else:
    print("  [SKIP] Session start/submit — missing exam_id or student token")


# ── 7. Profiles: Student ──────────────────────────────────
print("\n── Profile Endpoints ──")

if student_id:
    s, r = get(f"/api/v1/profiles/student/{student_id}")
    check("GET /profiles/student/{id}", s, r)
    print(f"         Name: {r.get('full_name')}, Level: {r.get('education_level')}, Joined: {r.get('joined')}")
else:
    print("  [SKIP] Student profile — no student_id")

# 404 for fake ID
s, r = get("/api/v1/profiles/student/00000000-0000-0000-0000-000000000000")
check("GET /profiles/student/fake-id → 404", s, r, expected=(404,))


# ── 8. Profiles: List teachers (public) ───────────────────
s, r = get("/api/v1/profiles/teachers")
check("GET /profiles/teachers (public)", s, r)
teachers = r if isinstance(r, list) else []
print(f"         Approved teachers: {len(teachers)}")
if teachers:
    t = teachers[0]
    print(f"         First: {t.get('full_name')} | subjects: {t.get('subjects')}")
    teacher_user_id = t.get("user_id")
else:
    teacher_user_id = None


# ── 9. Profiles: Single teacher (public) ──────────────────
if teacher_user_id:
    s, r = get(f"/api/v1/profiles/teacher/{teacher_user_id}")
    check("GET /profiles/teacher/{id}", s, r)
    print(f"         Name: {r.get('full_name')}, Bio: {r.get('bio')}, Approved: {r.get('is_approved')}")
elif teacher_id:
    s, r = get(f"/api/v1/profiles/teacher/{teacher_id}")
    check("GET /profiles/teacher/{id}", s, r)
    print(f"         Name: {r.get('full_name')}, Bio: {r.get('bio')}")
else:
    print("  [SKIP] Teacher profile — no teacher_user_id")


# ── 10. Teachers/me (teacher auth) ────────────────────────
if teacher_token:
    s, r = get("/api/v1/teachers/me", token=teacher_token)
    check("GET /teachers/me (teacher auth)", s, r)
    print(f"         Name: {r.get('full_name')}, Email: {r.get('email')}, Subjects: {r.get('subjects')}")

    # PATCH bio
    s, r = patch("/api/v1/teachers/me", {
        "bio": "Updated via test — 10 years experience in Sciences",
        "subjects": ["Biology", "Chemistry", "Physics"]
    }, token=teacher_token)
    check("PATCH /teachers/me", s, r)
    print(f"         Updated bio: {r.get('bio')}")
    print(f"         Updated subjects: {r.get('subjects')}")
else:
    print("  [SKIP] teachers/me — no teacher token")

# teachers/me requires auth
s, r = get("/api/v1/teachers/me")
check("GET /teachers/me (no auth → 403)", s, r, expected=(401, 403))

# student cannot access teachers/me
if student_token:
    s, r = get("/api/v1/teachers/me", token=student_token)
    check("GET /teachers/me (student → 403)", s, r, expected=(403,))


# ── Summary ───────────────────────────────────────────────
print()
print("=" * 55)
total = PASS + FAIL
print(f"  RESULTS: {PASS}/{total} passed   ({FAIL} failed)")
if FAIL == 0:
    print("  All new APIs working correctly.")
else:
    print("  Some tests failed — check output above.")
print("=" * 55)
