"""
Test script for new community APIs:
  - POST /community/join (auto-create profile fix)
  - GET  /profiles/me
  - POST /community/posts (with is_anonymous, visibility, cbt_exam_id)
  - GET  /community/posts (visibility filtering)
  - POST /community/upload (skipped — requires binary file)
"""
import urllib.request, json, urllib.error, time

BASE = "https://scholaxia1.onrender.com"

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"


def post(path, data, token=None):
    body = json.dumps(data).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method="POST")
    try:
        r = urllib.request.urlopen(req, timeout=40)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        raw = e.read()
        try: return e.code, json.loads(raw)
        except: return e.code, {"raw": raw.decode()[:400]}


def get(path, token=None):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + path, headers=headers)
    try:
        r = urllib.request.urlopen(req, timeout=40)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        raw = e.read()
        try: return e.code, json.loads(raw)
        except: return e.code, {"raw": raw.decode()[:400]}


def check(label, condition, got=None):
    status = PASS if condition else FAIL
    print(f"  [{status}] {label}" + (f"  →  {got}" if got is not None else ""))


print("=" * 65)
print("  COMMUNITY API TEST — " + BASE)
print("=" * 65)

# ── 1. Health ──────────────────────────────────────────────────────────────
print("\n[1] Health check")
s, r = get("/health")
check("Server is up", s == 200, r)

# ── 2. Login (get a student token) ────────────────────────────────────────
print("\n[2] Login as existing student")
s, r = post("/api/v1/auth/login", {"email": "chidi@test.com", "password": "Student123!"})
check("Login OK", s == 200, f"HTTP {s}")
token = r.get("access_token", "") if isinstance(r, dict) else ""
user_id = r.get("user_id", "") if isinstance(r, dict) else ""
if not token:
    # Try signup a fresh user instead
    ts = int(time.time())
    email = f"comtest_{ts}@test.com"
    s, r = post("/api/v1/auth/student/signup", {"email": email, "password": "Test123!", "full_name": "Community Tester"})
    token = r.get("access_token", "") if isinstance(r, dict) else ""
    user_id = r.get("user_id", "") if isinstance(r, dict) else ""
    check(f"Fallback signup ({email})", bool(token), f"HTTP {s}")

if not token:
    print("\n  No token — cannot continue. Check server logs.")
    exit(1)

print(f"  Token: {token[:30]}...")

# ── 3. GET /profiles/me ───────────────────────────────────────────────────
print("\n[3] GET /api/v1/profiles/me")
s, r = get("/api/v1/profiles/me", token=token)
check("Status 200 or 404 (not 401)", s in (200, 404), f"HTTP {s}")
if s == 200:
    check("Has user_id field", "user_id" in r, r)
elif s == 404:
    check("404 = no profile yet (correct, not 401)", True, r.get("detail"))

# ── 4. Get channels ───────────────────────────────────────────────────────
print("\n[4] GET /api/v1/community/channels")
s, channels_r = get("/api/v1/community/channels", token=token)
check("Channels returned", s == 200, f"HTTP {s}")
channel_id = None
if isinstance(channels_r, list) and channels_r:
    # Pick the general (non-announcement) channel
    for ch in channels_r:
        if ch.get("type") != "teacher_announcement":
            channel_id = ch["id"]
            break
    check("Found a joinable channel", bool(channel_id), channel_id)
else:
    print(f"  No channels returned: {channels_r}")

# ── 5. POST /community/join ───────────────────────────────────────────────
print("\n[5] POST /api/v1/community/join (auto-profile creation)")
if channel_id:
    s, r = post("/api/v1/community/join", {"channel_id": channel_id}, token=token)
    check("Join succeeds (not 404 'Student profile not found')", s == 200, f"HTTP {s} | {r}")
else:
    print("  Skipped — no channel_id")

# ── 6. POST /community/posts — basic ─────────────────────────────────────
print("\n[6] POST /api/v1/community/posts — basic post")
if channel_id:
    s, r = post("/api/v1/community/posts", {
        "channel_id": channel_id,
        "content": "Hello from the automated test!",
    }, token=token)
    check("Post created or auth error", s in (200, 201, 403), f"HTTP {s}")
    post_id = r.get("id") if s in (200, 201) else None
    if post_id:
        check("Post has id", True, post_id)
else:
    print("  Skipped — no channel_id")
    post_id = None

# ── 7. POST /community/posts — anonymous ─────────────────────────────────
print("\n[7] POST /api/v1/community/posts — anonymous post")
if channel_id:
    s, r = post("/api/v1/community/posts", {
        "channel_id": channel_id,
        "content": "This post should be anonymous.",
        "is_anonymous": True,
        "visibility": "everyone",
    }, token=token)
    check("Anonymous post accepted", s in (200, 201, 403), f"HTTP {s}")
    if s in (200, 201):
        check("author_name is 'Anonymous'", r.get("author_name") == "Anonymous", r.get("author_name"))
        check("author_id is null", r.get("author_id") is None, r.get("author_id"))
        check("is_anonymous is true", r.get("is_anonymous") is True, r.get("is_anonymous"))
else:
    print("  Skipped — no channel_id")

# ── 8. POST /community/posts — visibility: class_only ────────────────────
print("\n[8] POST /api/v1/community/posts — visibility: class_only")
if channel_id:
    s, r = post("/api/v1/community/posts", {
        "channel_id": channel_id,
        "content": "Only classmates see this.",
        "visibility": "class_only",
    }, token=token)
    check("class_only post accepted", s in (200, 201, 403), f"HTTP {s}")
    if s in (200, 201):
        check("visibility is class_only", r.get("visibility") == "class_only", r.get("visibility"))
else:
    print("  Skipped — no channel_id")

# ── 9. POST /community/posts — with media_url ────────────────────────────
print("\n[9] POST /api/v1/community/posts — with media_url")
if channel_id:
    s, r = post("/api/v1/community/posts", {
        "channel_id": channel_id,
        "content": "Check this image.",
        "media_url": "https://res.cloudinary.com/demo/image/upload/sample.jpg",
        "media_type": "image",
    }, token=token)
    check("Post with media accepted", s in (200, 201, 403), f"HTTP {s}")
    if s in (200, 201):
        check("media_url present", bool(r.get("media_url")), r.get("media_url"))
        check("media_type is 'image'", r.get("media_type") == "image", r.get("media_type"))
else:
    print("  Skipped — no channel_id")

# ── 10. GET /community/posts — visibility filter ──────────────────────────
print("\n[10] GET /api/v1/community/posts — student sees only allowed posts")
if channel_id:
    s, r = get(f"/api/v1/community/posts?channel_id={channel_id}", token=token)
    check("Posts endpoint returns 200", s == 200, f"HTTP {s}")
    if s == 200 and isinstance(r, list):
        teachers_only_leak = [p for p in r if p.get("visibility") == "teachers_only"]
        check("No teachers_only posts visible to student", len(teachers_only_leak) == 0,
              f"{len(teachers_only_leak)} leaked")
        anon_posts = [p for p in r if p.get("is_anonymous")]
        if anon_posts:
            check("Anonymous posts hide author_id from student",
                  all(p.get("author_id") is None for p in anon_posts),
                  f"{len(anon_posts)} anon posts checked")
        print(f"  Total posts visible: {len(r)}")
else:
    print("  Skipped — no channel_id")

# ── 11. POST /community/upload — check endpoint exists (no file) ─────────
print("\n[11] POST /api/v1/community/upload — endpoint existence check")
# Send empty form to check if endpoint is registered (expect 422 not 404)
req = urllib.request.Request(
    BASE + "/api/v1/community/upload",
    data=b"",
    headers={"Authorization": "Bearer " + token},
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=15)
    check("Upload endpoint exists", True, "200")
except urllib.error.HTTPError as e:
    check("Upload endpoint exists (not 404)", e.code != 404, f"HTTP {e.code} — expected 422 for missing file")

print("\n" + "=" * 65)
print("  DONE")
print("=" * 65)
