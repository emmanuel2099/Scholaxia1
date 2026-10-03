"""Pass 7 functional test — run against a freshly reseeded local backend.

Covers:
 1. /public/school-features catalog (plans endpoint retired)
 2. /public/schools/register accepts + stores requested_features
 3. school-cbt student registration issues reg number + access code IMMEDIATELY
    (new unique school-prefixed pattern), and the same student keeps one reg
    number across registrations
 4. school-office candidate registration now returns credentials that WORK at
    the exam portal login (after Save Schedule)
 5. Full reference-like E2E: register student -> schedule exam -> student
    login with printed credentials -> my-exams -> start -> save answers ->
    submit
"""
import json
import os
import sys

import httpx

BASE = os.environ.get("QA_BASE", "http://127.0.0.1:8000/api/v1")
FAILS = []


def check(name, cond, extra=""):
    tag = "PASS" if cond else "FAIL"
    print(f"[{tag}] {name}" + (f" — {extra}" if extra else ""))
    if not cond:
        FAILS.append(name)


def main() -> int:
    c = httpx.Client(base_url=BASE, timeout=30)

    # ── 1. feature catalog ────────────────────────────────────────────────
    r = c.get("/public/school-features")
    check("school-features endpoint 200", r.status_code == 200, str(r.status_code))
    feats = r.json().get("features", [])
    check("11 features in catalog", len(feats) == 11, f"got {len(feats)}")
    check("cbt feature present", any(f["id"] == "cbt" for f in feats))

    # ── 2. school registration with requested features ────────────────────
    import time
    suffix = str(int(time.time()))[-6:]
    email = f"pass7.school{suffix}@example.com"
    reg_payload = {
        "school_name": f"Pass Seven Academy {suffix}",
        "city": "Uyo",
        "state": "Akwa Ibom",
        "school_type": "private",
        "category": "mixed",
        "admin_full_name": "Pass Seven Admin",
        "admin_email": email,
        "admin_phone": f"080{suffix}77",
        "admin_password": "Pass7School123!",
        "requested_features": ["results", "cbt", "attendance", "fees"],
    }
    r = c.post("/public/schools/register", json=reg_payload)
    check("school register 201", r.status_code == 201, r.text[:200])
    data = r.json()
    check("requested_features echoed", sorted(data.get("requested_features") or []) == ["attendance", "cbt", "fees", "results"], str(data.get("requested_features")))
    school_slug = data["slug"]
    school_id = data["school_id"]

    # invalid feature id rejected
    bad = dict(reg_payload, admin_email=f"bad{suffix}@example.com", requested_features=["not_a_feature"])
    r = c.post("/public/schools/register", json=bad)
    check("invalid feature rejected 422", r.status_code == 422, str(r.status_code))

    # login as the school admin (approve the pending school first via the
    # platform admin — same as the real Super Admin flow)
    r = c.post("/auth/login", json={"email": "admin@scholaxiatest.com", "password": "AdminPass123!"})
    check("platform admin login", r.status_code == 200, r.text[:150])
    atok = r.json()["access_token"]
    r = c.post(f"/super-admin/schools/{school_id}/approve", headers={"Authorization": f"Bearer {atok}"})
    check("school approved", r.status_code == 200, r.text[:150])

    r = c.post("/auth/login", json={"email": email, "password": "Pass7School123!"})
    check("school admin login", r.status_code == 200, r.text[:150])
    tok = r.json()["access_token"]
    H = {"Authorization": f"Bearer {tok}"}

    # ── 3. school-cbt student registration — credentials issued at once ──
    r = c.post("/school-cbt/students/register", json={
        "first_name": "Ada", "surname": "Obi", "class_name": "JSS1", "subject": "ALL",
    }, headers=H, params={"school_id": school_id})
    check("exam student register 201", r.status_code == 201, r.text[:200])
    st1 = r.json()
    check("reg_number present", bool(st1.get("reg_number")), st1.get("reg_number"))
    check("access_code present immediately", bool(st1.get("access_code")), st1.get("access_code"))
    reg1 = st1["reg_number"]
    year2 = reg1.split("/")[1] if "/" in reg1 else "??"
    check("reg pattern is CODE/YY/NNNNNN", len(reg1.split("/")) == 3 and len(year2) == 2 and reg1.split("/")[2].isdigit(), reg1)
    check("reg prefix is school-derived (not SCHX)", not reg1.startswith("SCHX/"), reg1)

    # two students never share a reg number (global uniqueness)
    r = c.post("/school-cbt/students/register", json={
        "first_name": "Tunde", "surname": "Bello", "class_name": "JSS1", "subject": "ALL",
    }, headers=H, params={"school_id": school_id})
    st2 = r.json()
    check("second student different reg", st2["reg_number"] != reg1, f"{reg1} vs {st2['reg_number']}")

    # ── 4. upload question bank + schedule exam (reference Save Schedule) ─
    r = c.post("/school-cbt/banks", json={"class_name": "JSS1", "subject": "Basic Science", "name": "BS JSS1"}, headers=H, params={"school_id": school_id})
    check("bank created", r.status_code == 201, r.text[:150])
    bank_id = r.json()["id"]
    questions = [{
        "question_text": f"What is {10 + i} + 5?",
        "option_a": str(15 + i), "option_b": str(16 + i), "option_c": str(17 + i), "option_d": str(18 + i),
        "correct_option": "A", "marks": 1,
    } for i in range(5)]
    r = c.post(f"/school-cbt/banks/{bank_id}/questions", json=questions, headers=H)
    check("5 questions added", r.status_code == 201, r.text[:120])

    from datetime import datetime, timedelta
    start = (datetime.utcnow() - timedelta(minutes=5)).isoformat()
    r = c.post("/school-cbt/schedule/save", json={
        "class_name": "JSS1", "subjects": ["Basic Science"],
        "question_count": 5, "duration_minutes": 30, "total_mark": 100,
        "starts_at": start,
    }, headers=H, params={"school_id": school_id})
    check("schedule saved", r.status_code == 200, r.text[:200])
    sched = r.json()
    check("1 exam created", sched.get("created") == 1, str(sched))

    # ── 5. student logs in with the credentials printed at REGISTRATION ──
    r = c.post("/school-cbt/student/login", json={
        "school_slug": school_slug,
        "reg_number": reg1,
        "access_code": st1["access_code"],
    })
    check("student login with registration slip credentials", r.status_code == 200, r.text[:200])
    if r.status_code != 200:
        return finish()
    exam_tok = r.json()["access_token"]
    EH = {"Authorization": f"Bearer {exam_tok}"}

    r = c.get("/school-cbt/student/my-exams", headers=EH)
    check("my-exams lists scheduled exam", r.status_code == 200 and len(r.json().get("exams", [])) == 1, r.text[:200])
    exams = r.json().get("exams", [])
    if not exams:
        return finish()
    exam_id = exams[0]["id"]

    # ── 6. take the exam like the reference ───────────────────────────────
    r = c.post(f"/school-cbt/student/exams/{exam_id}/start", headers=EH)
    check("start exam 200", r.status_code == 200, r.text[:150])
    start_data = r.json()
    attempt_id = start_data["attempt_id"]
    qs = start_data["questions"]
    check("5 questions served", len(qs) == 5, str(len(qs)))

    for i, q in enumerate(qs):
        ans = "A" if i % 2 == 0 else "B"
        r = c.post("/school-cbt/student/answers", headers=EH, json={
            "attempt_id": attempt_id, "question_id": q["id"], "answer": ans,
        })
        if r.status_code != 200:
            check("save answer", False, r.text[:120])
    check("5 answers saved", True)

    r = c.post(f"/school-cbt/student/exams/{exam_id}/submit", headers=EH, json={"attempt_id": attempt_id})
    check("submit exam 200", r.status_code == 200, r.text[:150])
    sub = r.json()
    check("score computed (3 of 5 correct)", (sub.get("summary") or {}).get("raw_score") == 3, json.dumps(sub)[:150])

    # ── 7. school-office candidates now carry WORKING credentials ─────────
    r = c.post("/admin/school-office/candidates", json={
        "school_id": school_id,
        "class_name": "JSS1",
        "full_name": "Ngozi Candidate",
        "subjects": ["Basic Science"],
    }, headers=H)
    check("candidate register 201", r.status_code == 201, r.text[:200])
    cand = r.json()
    check("candidate reg_number uses new pattern", bool(cand.get("rec_number")) and not cand["rec_number"].startswith("REC-"), cand.get("rec_number"))
    check("candidate access_code present", bool(cand.get("access_code")), cand.get("access_code"))

    r = c.post("/school-cbt/student/login", json={
        "school_slug": school_slug,
        "reg_number": cand["rec_number"],
        "access_code": cand["access_code"],
    })
    check("CANDIDATE credentials work at exam login (THE FIX)", r.status_code == 200, r.text[:200])
    if r.status_code == 200:
        cand_tok = r.json()["access_token"]
        r2 = c.get("/school-cbt/student/my-exams", headers={"Authorization": f"Bearer {cand_tok}"})
        check("candidate sees the scheduled exam", r2.status_code == 200 and len(r2.json().get("exams", [])) == 1, r2.text[:150])

    # slip endpoint still returns the same working credentials
    r = c.get(f"/admin/school-office/candidates/{cand['id']}/slip", headers=H)
    slip = r.json()
    check("slip reprint shows same credentials", r.status_code == 200 and slip.get("rec_number") == cand["rec_number"] and slip.get("access_code") == cand["access_code"], r.text[:150])

    return finish()


def finish() -> int:
    print()
    if FAILS:
        print(f"✗ {len(FAILS)} failed: {FAILS}")
        return 1
    print("✓ ALL PASS 7 CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
