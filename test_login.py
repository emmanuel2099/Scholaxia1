import urllib.request, json, urllib.error

BASE = "https://scholaxia1.onrender.com"

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

print("=" * 60)
print("  LOGIN DIAGNOSTIC — " + BASE)
print("=" * 60)

# 1. Health check
s, r = get("/health")
print(f"\n[{'OK' if s==200 else 'FAIL'}] Health -> HTTP {s} | {r}")

# 2. Try existing student
print("\n--- Existing student (chidi@test.com) ---")
s, r = post("/api/v1/auth/login", {"email": "chidi@test.com", "password": "Student123!"})
print(f"  HTTP {s}")
print(f"  Response: {json.dumps(r, indent=2)}")
student_token = r.get("access_token", "") if isinstance(r, dict) else ""

# 3. Signup a fresh student
import time
ts = int(time.time())
fresh_email = f"fresh_{ts}@test.com"
print(f"\n--- Fresh signup ({fresh_email}) ---")
s, r = post("/api/v1/auth/student/signup", {
    "email": fresh_email,
    "password": "FreshPass123!",
    "full_name": "Fresh Student"
})
print(f"  HTTP {s}")
print(f"  Response: {json.dumps(r, indent=2)}")
fresh_token = r.get("access_token", "") if isinstance(r, dict) else ""

# 4. Login with fresh account
if fresh_token:
    print(f"\n--- Login with fresh account ---")
    s, r = post("/api/v1/auth/login", {"email": fresh_email, "password": "FreshPass123!"})
    print(f"  HTTP {s}")
    print(f"  Response: {json.dumps(r, indent=2)}")

# 5. Test token works - get profile
token_to_use = fresh_token or student_token
if token_to_use:
    print(f"\n--- GET /students/me with token ---")
    s, r = get("/api/v1/students/me", token=token_to_use)
    print(f"  HTTP {s}")
    print(f"  Response: {json.dumps(r, indent=2)}")
else:
    print("\n  No token available — login is broken")

# 6. Wrong password test
print("\n--- Wrong password (should be 401) ---")
s, r = post("/api/v1/auth/login", {"email": "chidi@test.com", "password": "wrongpassword"})
print(f"  HTTP {s} | detail: {r.get('detail', r) if isinstance(r, dict) else r}")

print("\n" + "=" * 60)
print("  SUMMARY")
print("  Student token:    " + ("OK" if student_token else "FAILED"))
print("  Fresh signup:     " + ("OK" if fresh_token else "FAILED"))
print("=" * 60)
