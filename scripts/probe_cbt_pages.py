import re
import urllib.request

pages = ["practice-interface.html", "practice-login.html", "exam-interface.html"]
for page in pages:
    u = f"https://www.scholaxiacbtexam.blog/{page}"
    html = urllib.request.urlopen(
        urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=15
    ).read().decode("utf-8", "ignore")
    scripts = re.findall(r'src="([^"]+\.js[^"]*)"', html)
    print(page, scripts)
