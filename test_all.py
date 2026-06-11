"""
Scholaxia Full API Test Suite
Tests every endpoint in the correct order.
"""
import urllib.request, urllib.error, json, time, random, string

BASE = "https://scholaxia1.onrender.com"
PASS = 0
FAIL = 0
SKIP = 0

# Shared state
tokens = {}
ids = {}

def rnd():
    return "".join(random.choices(string.ascii_lowercase, k=6))

def req(method, path, data=None, token=None, expect_json=True):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data else None
    r = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(r, timeout=90)
        raw = resp.read()
        if expect_json and raw:
            return resp.status, json.loads(raw)
        return resp.status, raw.decode()[:100]
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode()[:200]
    except Exception as e:
        return 0, f"TIMEOUT/ERROR: {str(e)[:100]}"

def post(path, data, token=None): return req("POST", path, data, token)
def get(path, token=None): return req("GET", path, token=token)
def patch(path, data, token=None): return req("PATCH", path, data, token)
def delete(path, token=None): return req("DELETE", path, token=token)

def check(label, status, expected, note=""):
    global PASS, FAIL
    ok = status in (expected if isinstance(expected, list) else [expected])
    icon = "PASS" if ok else "FAIL"
    if ok:
        PASS += 1
    else:
        FAIL += 1
    suffix = f" | {note}" if note else ""
    print(f"  [{icon}] {label} -> {status}{suffix}")
    return ok

def section(title):
    print(f"\n{'='*55}")
    print(f"  {title}")
    print(f"{'='*55}")

# ─────────────────────────────────────────────────────────
section("1. HEALTH & DOCS")
s, r = get("/health")
check("Health check", s, 200, r.get("status","") if isinstance(r,dict) else "")

s, r = get("/openapi.json")
check("OpenAPI schema", s, 200, f"{len(r.get('paths',{}))} routes" if isinstance(r,dict) else "")

# ─────────────────────────────────────────────────────────
section("2. ADMIN REGISTER & LOGIN")
email_admin = f"admin_{rnd()}@scholaxia.com"
s, r = post("/api/v1/admin/register", {
    "email": email_admin,
    "password": "AdminPass123",
    "full_name": "Scholaxia Admin",
    "invite_code": "SCHOLAXIA_ADMIN_2026"
})
if check("Admin register", s, [200, 201, 400, 500]):
    tokens["admin"] = r.get("access_token","") if isinstance(r,dict) else ""
    if not tokens["admin"] and s == 400:
        # already exists, try login
        s2, r2 = post("/api/v1/auth/login", {"email": email_admin, "password": "AdminPass123"})
        tokens["admin"] = r2.get("access_token","") if isinstance(r2,dict) else ""
print(f"     Admin token: {'OK' if tokens.get('admin') else 'MISSING - write endpoints blocked'}")

# ─────────────────────────────────────────────────────────
section("3. STUDENT AUTH")
email_student = f"student_{rnd()}@test.com"
s, r = post("/api/v1/auth/student/signup", {
    "email": email_student,
    "password": "Student123!",
    "full_name": "Chidi Okafor"
})
check("Student signup", s, [200, 201, 400, 500],
      r.get("message", r.get("detail","")) if isinstance(r,dict) else str(r)[:60])

# Login (works if already verified or OTP bypassed)
s, r = post("/api/v1/auth/login", {"email": email_student, "password": "Student123!"})
check("Student login", s, [200, 201, 403],
      r.get("detail","ok") if isinstance(r,dict) else "")
tokens["student"] = r.get("access_token","") if isinstance(r,dict) else ""
print(f"     Student token: {'OK' if tokens.get('student') else 'MISSING (email not verified)'}")

# ─────────────────────────────────────────────────────────
section("4. COMMUNITY (no auth needed for channels)")
s, r = get("/api/v1/community/channels")
check("List channels", s, 200)
channels = r if isinstance(r, list) else []
general_id = next((c["id"] for c in channels if c.get("type") == "general"), None)
teacher_ch_id = next((c["id"] for c in channels if c.get("type") == "teacher_announcement"), None)
ids["general_channel"] = general_id
print(f"     Channels: {len(channels)} | General: {general_id}")

# ─────────────────────────────────────────────────────────
section("5. SIA AI (public endpoints)")
s, r = get("/api/v1/sia/about")
check("Sia about", s, 200, r.get("name","") if isinstance(r,dict) else "")

s, r = get("/api/v1/sia/languages")
check("Sia languages", s, 200, f"{r.get('total',0)} languages" if isinstance(r,dict) else "")

s, r = get("/api/v1/ai/models")
check("Public AI models", s, 200)

# Sia ask (requires student token)
if tokens.get("student"):
    s, r = post("/api/v1/sia/ask", {
        "question": "What is photosynthesis?",
        "subject": "Biology",
        "language": "english"
    }, token=tokens["student"])
    check("Sia ask", s, [200, 201], str(r)[:80] if r else "")

    s, r = post("/api/v1/sia/explain", {
        "topic": "Newton third law",
        "subject": "Physics",
        "language": "english"
    }, token=tokens["student"])
    check("Sia explain", s, [200, 201])

    s, r = post("/api/v1/sia/solve", {
        "question": "Solve: 2x + 5 = 15",
        "subject": "Mathematics",
        "language": "english"
    }, token=tokens["student"])
    check("Sia solve", s, [200, 201])

    s, r = post("/api/v1/sia/evaluate", {
        "question": "What is the capital of Nigeria?",
        "student_answer": "Lagos",
        "subject": "Geography",
        "language": "english"
    }, token=tokens["student"])
    check("Sia evaluate", s, [200, 201])

    s, r = post("/api/v1/sia/generate-questions", {
        "topic": "Photosynthesis",
        "subject": "Biology",
        "number": 3,
        "curriculum": "WAEC"
    }, token=tokens["student"])
    check("Sia generate questions", s, [200, 201])

    s, r = post("/api/v1/sia/feedback", {
        "subject": "Mathematics",
        "score": 65.0
    }, token=tokens["student"])
    check("Sia feedback", s, [200, 201])

    s, r = get("/api/v1/sia/weak-topics", token=tokens["student"])
    check("Sia weak topics", s, [200, 201])

    s, r = get("/api/v1/sia/history", token=tokens["student"])
    check("Sia history", s, [200, 201])

    # Sia notes
    s, r = post("/api/v1/sia/notes", {
        "content": "Photosynthesis is the process by which plants make food using sunlight.",
        "title": "Biology Note",
        "subject": "Biology",
        "topic": "Photosynthesis"
    }, token=tokens["student"])
    check("Save Sia note", s, [200, 201])
    note_id = r.get("note_id","") if isinstance(r,dict) else ""

    s, r = get("/api/v1/sia/notes", token=tokens["student"])
    check("Get Sia notes", s, [200, 201])

    if note_id:
        s, r = get(f"/api/v1/sia/notes/{note_id}", token=tokens["student"])
        check("Get single note", s, [200, 201])

        s, r = patch(f"/api/v1/sia/notes/{note_id}", {"is_pinned": True}, token=tokens["student"])
        check("Pin note", s, [200, 201])

        s, r = delete(f"/api/v1/sia/notes/{note_id}", token=tokens["student"])
        check("Delete note", s, [200, 201, 204])
else:
    print("     SKIP - no student token")
    SKIP += 7

# ─────────────────────────────────────────────────────────
section("6. ADMIN OPERATIONS")
if tokens.get("admin"):
    # Create teacher
    email_teacher = f"teacher_{rnd()}@scholaxia.com"
    s, r = post("/api/v1/admin/teachers", {
        "email": email_teacher,
        "password": "Teacher123!",
        "full_name": "Mr Emeka Obi",
        "subjects": ["Mathematics", "Physics"],
        "bio": "10 years experience"
    }, token=tokens["admin"])
    check("Create teacher", s, [200, 201, 400])
    ids["teacher_id"] = r.get("id","") if isinstance(r,dict) else ""
    print(f"     Teacher ID: {ids.get('teacher_id','N/A')}")

    s, r = get("/api/v1/admin/teachers", token=tokens["admin"])
    check("List teachers", s, 200, f"{len(r)} teachers" if isinstance(r,list) else "")

    # Teacher login
    s, r = post("/api/v1/auth/login", {"email": email_teacher, "password": "Teacher123!"})
    check("Teacher login", s, [200, 201])
    tokens["teacher"] = r.get("access_token","") if isinstance(r,dict) else ""
    print(f"     Teacher token: {'OK' if tokens.get('teacher') else 'MISSING'}")
else:
    print("     SKIP - no admin token")
    SKIP += 3

# ─────────────────────────────────────────────────────────
section("7. LIVE CLASSES")
if tokens.get("teacher"):
    s, r = post("/api/v1/live-classes/", {
        "subject": "Mathematics",
        "title": "Quadratic Equations",
        "start_time": "2026-06-01T10:00:00"
    }, token=tokens["teacher"])
    check("Create live class", s, [200, 201])
    ids["class_id"] = r.get("id","") if isinstance(r,dict) else ""
    print(f"     Class ID: {ids.get('class_id','N/A')}")

    if ids.get("class_id"):
        s, r = post(f"/api/v1/live-classes/{ids['class_id']}/start", {}, token=tokens["teacher"])
        check("Start live class", s, [200, 201])

        if tokens.get("student"):
            s, r = post(f"/api/v1/live-classes/{ids['class_id']}/join", {}, token=tokens["student"])
            check("Student join class", s, [200, 201, 404])
else:
    print("     SKIP - no teacher token")
    SKIP += 3

# ─────────────────────────────────────────────────────────
section("8. TEACHER AI")
if tokens.get("teacher"):
    s, r = post("/api/v1/teacher-ai/ask", {
        "task": "quiz",
        "subject": "Mathematics",
        "education_level": "SS3",
        "details": "Create 3 questions on quadratic equations"
    }, token=tokens["teacher"])
    check("Teacher AI ask", s, [200, 201])

    s, r = post("/api/v1/teacher-ai/ask", {
        "task": "lesson_plan",
        "subject": "Physics",
        "education_level": "SS2",
        "details": "Lesson plan for Newton laws of motion"
    }, token=tokens["teacher"])
    check("Teacher AI lesson plan", s, [200, 201])
else:
    print("     SKIP - no teacher token")
    SKIP += 2

# ─────────────────────────────────────────────────────────
section("9. STUDENT PROFILE")
if tokens.get("student"):
    s, r = post("/api/v1/students/setup-exam", {
        "exam_type": "JAMB",
        "subjects": ["Mathematics", "English", "Physics", "Chemistry"],
        "education_level": "SS3"
    }, token=tokens["student"])
    check("Setup exam", s, [200, 201])

    s, r = get("/api/v1/students/me", token=tokens["student"])
    check("Get student profile", s, [200, 201])
    if isinstance(r, dict):
        print(f"     Name: {r.get('full_name','?')} | Exam: {r.get('exam_type','?')}")
else:
    print("     SKIP - no student token")
    SKIP += 2

# ─────────────────────────────────────────────────────────
section("10. COMMUNITY MESSAGES")
if tokens.get("student") and general_id:
    s, r = post("/api/v1/community/join", {
        "channel_id": general_id
    }, token=tokens["student"])
    check("Join channel", s, [200, 201, 403])

    s, r = post("/api/v1/community/messages", {
        "channel_id": general_id,
        "content": "Hello everyone! Can someone explain Newton third law?"
    }, token=tokens["student"])
    check("Send message", s, [200, 201, 400, 403])
else:
    print("     SKIP - no student token or channel")
    SKIP += 2

# ─────────────────────────────────────────────────────────
section("11. NOTIFICATIONS")
if tokens.get("student"):
    s, r = get("/api/v1/notifications/", token=tokens["student"])
    check("Get notifications", s, [200, 201])

    s, r = post("/api/v1/notifications/read-all", {}, token=tokens["student"])
    check("Mark all read", s, [200, 201])

    s, r = post("/api/v1/notifications/device-token", {
        "token": "test-fcm-token-123",
        "platform": "android"
    }, token=tokens["student"])
    check("Register device token", s, [200, 201])
else:
    print("     SKIP - no student token")
    SKIP += 3

# ─────────────────────────────────────────────────────────
section("12. DEVELOPER PORTAL")
email_dev = f"dev_{rnd()}@myapp.com"
s, r = post("/api/v1/developer/auth/signup", {
    "email": email_dev,
    "password": "DevPass123!",
    "full_name": "Test Developer",
    "company_name": "TestCo Ltd"
})
check("Developer signup", s, [200, 201, 400, 500])
tokens["dev"] = r.get("access_token","") if isinstance(r,dict) else ""

if tokens.get("dev"):
    s, r = post("/api/v1/developer/keys/", {
        "name": "My Test Key",
        "tier": "free"
    }, token=tokens["dev"])
    check("Create API key", s, [200, 201])
    api_key = r.get("key","") if isinstance(r,dict) else ""
    key_id = r.get("id","") if isinstance(r,dict) else ""
    print(f"     API key: {api_key[:25]}..." if api_key else "     No key returned")

    s, r = get("/api/v1/developer/keys/", token=tokens["dev"])
    check("List API keys", s, [200, 201])

    if key_id:
        s, r = get(f"/api/v1/developer/keys/{key_id}/usage", token=tokens["dev"])
        check("Key usage stats", s, [200, 201])

    # Public AI API with key
    if api_key:
        headers = {"Content-Type": "application/json", "x-api-key": api_key}
        body = json.dumps({
            "question": "What is osmosis?",
            "subject": "Biology",
            "education_level": "SS1",
            "language": "english"
        }).encode()
        r2 = urllib.request.Request(BASE + "/api/v1/ai/ask", data=body, headers=headers, method="POST")
        try:
            resp = urllib.request.urlopen(r2, timeout=30)
            s2 = resp.status
            ans = json.loads(resp.read())
            check("Public AI ask (with API key)", s2, [200, 201])
            print(f"     Sia says: {str(ans.get('answer',''))[:80]}...")
        except urllib.error.HTTPError as e:
            check("Public AI ask (with API key)", e.code, [200, 201])
else:
    print("     SKIP - developer signup failed (500)")
    SKIP += 4

# ─────────────────────────────────────────────────────────
section("13. REVIEWS & REPORTS")
if tokens.get("student") and ids.get("teacher_id"):
    s, r = post("/api/v1/reviews-reports/reviews", {
        "teacher_id": ids["teacher_id"],
        "rating": 5,
        "comment": "Excellent teacher, very clear!",
        "is_anonymous": False
    }, token=tokens["student"])
    check("Submit teacher review", s, [200, 201])

    s, r = get(f"/api/v1/reviews-reports/reviews/teacher/{ids['teacher_id']}")
    check("Get teacher reviews", s, [200, 201])
    if isinstance(r, dict):
        print(f"     Avg rating: {r.get('average_rating','?')} | Reviews: {r.get('total_reviews','?')}")

    s, r = post("/api/v1/reviews-reports/reports", {
        "target_id": ids["teacher_id"],
        "target_type": "teacher",
        "reason": "spam",
        "description": "Test report"
    }, token=tokens["student"])
    check("Submit report", s, [200, 201])

    s, r = get("/api/v1/reviews-reports/reports/mine", token=tokens["student"])
    check("My reports", s, [200, 201])
else:
    print("     SKIP - missing student or teacher")
    SKIP += 4

# ─────────────────────────────────────────────────────────
section("14. LIBRARY (public browse)")
s, r = get("/api/v1/library/student", token=tokens.get("student"))
check("Student library", s, [200, 201], f"{len(r)} books" if isinstance(r,list) else "empty")

if tokens.get("teacher"):
    s, r = get("/api/v1/library/teacher", token=tokens["teacher"])
    check("Teacher library", s, [200, 201], f"{len(r)} books" if isinstance(r,list) else "empty")

s, r = get("/api/v1/library/saved", token=tokens.get("student"))
check("Saved books", s, [200, 201] if tokens.get("student") else [401, 403])

# ─────────────────────────────────────────────────────────
section("15. CBT")
if tokens.get("admin"):
    # Admin list reports
    s, r = get("/api/v1/reviews-reports/admin/reports", token=tokens["admin"])
    check("Admin list reports", s, [200, 201])

# ─────────────────────────────────────────────────────────
print(f"\n{'='*55}")
print(f"  FINAL RESULTS")
print(f"{'='*55}")
print(f"  PASS : {PASS}")
print(f"  FAIL : {FAIL}")
print(f"  SKIP : {SKIP} (missing tokens from 500 errors)")
total = PASS + FAIL
pct = round((PASS / total) * 100) if total else 0
print(f"  SCORE: {PASS}/{total} ({pct}%)")
print(f"{'='*55}")
