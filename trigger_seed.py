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
        try:    return e.code, json.loads(raw)
        except: return e.code, {"error": raw.decode()[:500]}

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
        try:    return e.code, json.loads(raw)
        except: return e.code, {"error": raw.decode()[:500]}

print("Step 1: Admin login...")
s, r = post("/api/v1/auth/login", {"email": "admin@scholaxia.com", "password": "ScholaxiaAdmin2026"})
print("  HTTP", s, r.get("role", ""))
token = r.get("access_token", "")

if not token:
    raise SystemExit("No admin token: " + str(r))

print("\nStep 2: Trigger CBT seed...")
s, r = post("/api/v1/admin/seed-cbt", {}, token=token)
print("  HTTP", s)
print("  Response:", json.dumps(r, indent=2))

print("\nStep 3: Verify exams in DB...")
s, r = get("/api/v1/cbt/exams")
exams = r if isinstance(r, list) else []
print("  Exams count:", len(exams))
for e in exams:
    print(f"  [{e.get('exam_type')}] {e.get('title')} | {e.get('total_questions')} questions")
