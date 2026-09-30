"""Seed the LOCAL demo school (run_local.py) with a ready-to-take OFFLINE exam.

Run:  .venv/Scripts/python.exe scripts/seed_local_demo.py
Creates: JSS1 Mathematics bank (5 questions) + published OFFLINE exam assigned
to JSS1 with access codes. Students: stu1@divine-light.example.com (DLC/26/1001).
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import asyncio  # noqa: E402

import httpx  # noqa: E402

BASE = "http://127.0.0.1:8000/api/v1"
QUESTIONS = [
    ("2 + 2 = ?", "3", "4", "5", "6", "B"),
    ("5 × 3 = ?", "15", "10", "8", "53", "A"),
    ("10 − 4 = ?", "5", "7", "6", "14", "C"),
    ("9 ÷ 3 = ?", "6", "2", "27", "3", "D"),
    ("7 + 1 = ?", "8", "6", "9", "17", "A"),
]
EXAM_TITLE = "JSS1 Mathematics — First Term Exam"


async def main():
    async with httpx.AsyncClient(base_url=BASE, timeout=60) as c:
        r = await c.post("/auth/login", json={"email": "admin@divine-light.example.com", "password": "Admin1234!"})
        r.raise_for_status()
        h = {"Authorization": f"Bearer {r.json()['access_token']}"}
        print("admin token ok")

        # Reuse the demo bank if this script already ran (idempotent).
        banks = (await c.get("/school-cbt/banks", headers=h)).json().get("banks", [])
        existing = next((b for b in banks if b.get("name") == "JSS1 Maths Bank" and b.get("question_count", 0) > 0), None)
        if existing:
            bid = existing["id"]
        else:
            bank = (await c.post("/school-cbt/banks", headers=h, json={
                "name": "JSS1 Maths Bank", "subject": "Mathematics", "class_name": "JSS1",
            })).json()
            bid = bank["id"]
            await c.post(f"/school-cbt/banks/{bid}/questions", headers=h, json=[
                {"question_text": q, "option_a": a, "option_b": b, "option_c": cc, "option_d": d,
                 "correct_option": k, "marks": 1}
                for q, a, b, cc, d, k in QUESTIONS
            ])

        # Reuse the demo exam too.
        exams = (await c.get("/school-cbt/exams", headers=h)).json().get("exams", [])
        exam = next((e for e in exams if e.get("title") == EXAM_TITLE), None)
        if not exam:
            exam = (await c.post("/school-cbt/exams", headers=h, json={
                "title": EXAM_TITLE,
                "subject": "Mathematics",
                "class_name": "JSS1",
                "session": "2026/2027",
                "term": "First Term",
                "instructions": "Answer all questions. Works offline once downloaded.",
                "exam_mode": "OFFLINE",
                "duration_minutes": 60,
                "total_mark": 100,
                "questions_to_display": 5,
                "assigned_class_names": ["JSS1"],
                "bank_ids": [bid],
                "auto_pick_count": 5,
                "generate_codes": True,
                "publish": True,
            })).json()
        print(json.dumps({
            "exam_id": exam.get("id"),
            "questions": exam.get("question_count"),
            "assigned": exam.get("students_assigned"),
            "codes": exam.get("access_codes_created"),
        }, indent=2))

        codes = (await c.get(f"/school-cbt/exams/{exam['id']}/codes", headers=h)).json()
        print("ACCESS CODES (reg -> code):")
        for row in codes.get("codes", [])[:5]:
            print(" ", row.get("reg_number"), "->", row.get("access_code"))


asyncio.run(main())
