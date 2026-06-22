"""Purge all student and teacher emails from the live Scholaxia database."""
import json
import urllib.error
import urllib.request

BASE = "https://scholaxia1.onrender.com"
ADMIN_EMAIL = "admin@scholaxia.com"
ADMIN_PASS = "ScholaxiaAdmin2026"


def api(method, path, data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=120)
        raw = resp.read()
        return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"detail": raw.decode()[:300]}


def main():
    print("Logging in as admin...")
    status, data = api("POST", "/api/v1/auth/login", {"email": ADMIN_EMAIL, "password": ADMIN_PASS})
    token = data.get("access_token")
    if not token:
        print("Login failed:", status, data)
        return 1

    print("Removing all students...")
    status, data = api("POST", "/api/v1/admin/students/remove-all", token=token)
    print("  students:", status, data)

    print("Removing all teachers...")
    status, data = api("POST", "/api/v1/admin/teachers/remove-all", token=token)
    print("  teachers:", status, data)

    # New endpoint after deploy — try anyway
    print("Purging all user accounts (students + teachers + kind)...")
    status, data = api("POST", "/api/v1/admin/users/purge-all", token=token)
    if status == 404:
        print("  purge-all not deployed yet — students/teachers remove-all used above.")
    else:
        print("  purge:", status, data)

    print("Removing all live classes...")
    status, data = api("DELETE", "/api/v1/admin/live-classes/remove-all", token=token)
    print("  live classes:", status, data)

    print("Checking remaining students...")
    status, students = api("GET", "/api/v1/admin/students", token=token)
    count = len(students) if isinstance(students, list) else "?"
    print("  students left:", count)

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
