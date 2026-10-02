"""Seed QA extras for desktop/web testing (idempotent — safe to re-run).

Creates (if missing):
  - kind QA user  qa.kind1@example.com / KidPass123!  with COMMON_ENTRANCE CBT access
  - a published Common Entrance practice paper (6 questions)

Run:  PYTHONUTF8=1 .venv/Scripts/python.exe scripts/seed_qa_kind.py
Requires the local server running on :8000 (kind user goes through the real API);
the practice paper is inserted directly into local_dev.db like the demo seeders.
"""
import sqlite3
import sys
import uuid
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import httpx  # noqa: E402

BASE = "http://127.0.0.1:8000/api/v1"
DB = Path(__file__).resolve().parent.parent / "local_dev.db"

QUESTIONS = [
    ("What is 25% of 200?", "25", "50", "75", "100", "B", "Mathematics"),
    ("Which of these is a mammal?", "Crocodile", "Eagle", "Dolphin", "Snake", "C", "Science"),
    ("Choose the correct spelling.", "Recieve", "Receive", "Receeve", "Receve", "B", "English"),
    ("The capital of Nigeria is ___", "Lagos", "Kano", "Abuja", "Ibadan", "C", "Social Studies"),
    ("Water boils at ___ degrees Celsius.", "50", "80", "100", "120", "C", "Science"),
    ("How many sides does a hexagon have?", "5", "6", "7", "8", "B", "Mathematics"),
]


def ensure_kind_user() -> str:
    """Create the QA kind user via the API (idempotent) and return its id."""
    r = httpx.post(
        BASE + "/auth/kind/signup",
        json={
            "email": "qa.kind1@example.com",
            "password": "KidPass123!",
            "full_name": "QA Kid Tester",
            "age_group": "6-8",
        },
        timeout=30,
    )
    if r.status_code == 201:
        print("kind QA user created")
    elif r.status_code == 400 and "already registered" in r.text:
        print("kind QA user already exists")
    else:
        print("kind signup response:", r.status_code, r.text[:120])

    db = sqlite3.connect(DB)
    row = db.execute("SELECT id FROM users WHERE email='qa.kind1@example.com'").fetchone()
    if not row:
        print("ERROR: kind user not found in DB")
        sys.exit(1)
    uid = row[0]

    has = db.execute(
        "SELECT 1 FROM student_entitlements WHERE student_id=? AND entitlement_key='common_entrance'",
        (uid,),
    ).fetchone()
    if not has:
        db.execute(
            "INSERT INTO student_entitlements (id, student_id, entitlement_type, entitlement_key, granted_at, expires_at, details)"
            " VALUES (?,?,?,?,?,?,?)",
            (
                str(uuid.uuid4()),
                uid,
                "cbt_package",
                "common_entrance",
                datetime.utcnow().isoformat(),
                (datetime.utcnow() + timedelta(days=365)).isoformat(),
                "{}",
            ),
        )
        db.commit()
        print("COMMON_ENTRANCE entitlement granted")
    else:
        print("entitlement already present")
    db.close()
    return uid


def ensure_ce_exam() -> None:
    db = sqlite3.connect(DB)
    row = db.execute(
        "SELECT id FROM cbt_exams WHERE title='Common Entrance Practice Paper 1'"
    ).fetchone()
    if row:
        print("Common Entrance paper already present")
        db.close()
        return
    eid = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()
    db.execute(
        "INSERT INTO cbt_exams (id, title, subject, exam_type, paper_kind, year, duration_minutes,"
        " total_questions, is_published, created_at, is_school_exam, ai_locked, camera_required, block_minimize)"
        " VALUES (?,?,?,?,?,?,?,?,1,?,0,0,0,0)",
        (eid, "Common Entrance Practice Paper 1", "General Paper", "COMMON_ENTRANCE",
         "cbt_practice", 2024, 30, len(QUESTIONS), now),
    )
    for text, a, b, c, d, correct, topic in QUESTIONS:
        db.execute(
            "INSERT INTO cbt_questions (id, exam_id, question_text, option_a, option_b, option_c,"
            " option_d, correct_option, topic) VALUES (?,?,?,?,?,?,?,?,?)",
            (str(uuid.uuid4()), eid, text, a, b, c, d, correct, topic),
        )
    db.commit()
    db.close()
    print("Common Entrance paper seeded (6 questions)")


if __name__ == "__main__":
    ensure_kind_user()
    ensure_ce_exam()
    print("QA seed done.")
