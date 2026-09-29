"""End-to-end test of the SCHOLAXIA school CBT engine (in-memory SQLite).

Covers: exam bank → exam create → access codes → student exam login →
assigned-exams → download gate → start attempt → save answers → submit
(auto-marking raw→total mark) → results publish → grant retake → re-attempt.
Tenant isolation checks included (§30).

Run:  .venv/Scripts/python.exe scripts/test_school_cbt.py
"""
import asyncio
import json
import os
import sys
import uuid as uuidmod
from datetime import datetime

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///:memory:"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

import app.core.database as database  # noqa: E402
from app.core.database import Base  # noqa: E402

# ── swap the app's engine for an in-memory SQLite one ────────────────────
engine = create_async_engine(
    "sqlite+aiosqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSession = async_sessionmaker(engine, expire_on_commit=False)
database.engine = engine
database.AsyncSessionLocal = TestingSession


async def _stub_db():
    yield None


# Route registration needs get_db to be a real dependency function; the
# endpoints are called directly in this test, so a stub generator is enough.
database.get_db = _stub_db

import app.models  # noqa: E402,F401  — register every model
from app.models.school_campus import SchoolCampus  # noqa: E402
from app.models.user import User, UserRole, StudentProfile  # noqa: E402
from app.models.school_cbt import SchoolExamAccessCode, SchoolExamQuestion  # noqa: E402
from app.core.security import hash_password  # noqa: E402

# SQLite test shims: PG ARRAY → JSON, PG UUID → CHAR(36) that accepts both
# str and uuid.UUID on bind. Applied to metadata BEFORE tables are created.
from sqlalchemy.dialects.postgresql import ARRAY  # noqa: E402
from sqlalchemy.dialects.postgresql import UUID as PG_UUID  # noqa: E402
from sqlalchemy import JSON as _JSON  # noqa: E402
from sqlalchemy.types import TypeDecorator, CHAR  # noqa: E402


class _GuidAny(TypeDecorator):
    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, str) else str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, uuidmod.UUID) else uuidmod.UUID(str(value))


for _t in Base.metadata.tables.values():
    for _c in _t.columns:
        if isinstance(_c.type, ARRAY):
            _c.type = _JSON()
        elif isinstance(_c.type, PG_UUID):
            _c.type = _GuidAny()

from fastapi import HTTPException  # noqa: E402
from fastapi.security import HTTPAuthorizationCredentials  # noqa: E402

import app.routers.school_cbt as scbt  # noqa: E402

PASS = []
FAIL = []


def check(name, cond, extra=""):
    (PASS if cond else FAIL).append(name + (f"  [{extra}]" if extra and not cond else ""))
    print(("  ✓ " if cond else "  ✗ ") + name + (f"  → {extra}" if extra and not cond else ""))


def creds(token):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


TABLES = [
    "school_campuses", "users", "student_profiles",
    "school_ex_question_banks", "school_ex_questions",
    "school_exams", "school_exam_questions", "school_exam_assignments",
    "school_exam_access_codes", "school_exam_attempts", "school_exam_answers",
    "school_exam_downloads", "school_exam_sync_logs", "school_exam_results",
]


async def seed():
    async with TestingSession() as db:
        campus = SchoolCampus(name="Test College", code="TST", city="Lagos", state="LA", is_active=True)
        db.add(campus)
        await db.flush()
        admin = User(email="admin@test.sch", hashed_password=hash_password("password123"),
                     full_name="Test Admin", role=UserRole.school_admin, is_verified=True, is_active=True,
                     school_id=campus.id)
        db.add(admin)
        await db.flush()
        students = []
        for i in (1, 2):
            u = User(email=f"stu{i}@test.sch", hashed_password=hash_password("password123"),
                     full_name=f"Student {i}", role=UserRole.student, is_verified=True, is_active=True,
                     school_id=campus.id)
            db.add(u)
            await db.flush()
            db.add(StudentProfile(user_id=u.id, education_level="SS2", school_student_id=f"SCHX/26/1000{i}"))
            students.append(u)
        other = SchoolCampus(name="Other College", code="OTH", is_active=True)
        db.add(other)
        await db.flush()
        outsider = User(email="out@test.sch", hashed_password=hash_password("password123"),
                        full_name="Outsider", role=UserRole.student, is_verified=True, is_active=True,
                        school_id=other.id)
        db.add(outsider)
        await db.commit()
        return campus, admin, students, outsider


async def main():
    # Create ONLY the tables this flow touches (skip PG-ARRAY models).
    wanted = {t for t in TABLES}
    todo = [t for t in Base.metadata.sorted_tables if t.name in wanted]
    async with engine.begin() as conn:
        await conn.run_sync(lambda sync: Base.metadata.create_all(sync, tables=todo))

    campus, admin, students, outsider = await seed()
    # UUID object for `sub` (SQLite UUID bind needs .hex; Postgres coerces str).
    admin_user = {"sub": admin.id, "role": "school_admin", "school_id": str(campus.id)}
    staff_school = str(campus.id)

    async with TestingSession() as db:
        print("\n── 1. Exam bank ──")
        bank = await scbt.create_bank(scbt.BankIn(name="Maths SS2 Bank", subject="Mathematics", class_name="SS2"),
                                      admin_user, db)
        check("bank created", bool(bank["id"]))
        added = await scbt.add_bank_questions(bank["id"], [
            scbt.BankQuestionIn(question_text="2x + 6 = 14, x = ?", option_a="2", option_b="3", option_c="4",
                                option_d="5", correct_option="C", topic="Algebra", marks=1),
            scbt.BankQuestionIn(question_text="5 × 6 = ?", option_a="30", option_b="11", option_c="56",
                                option_d="35", correct_option="A", topic="Arithmetic", marks=1),
            scbt.BankQuestionIn(question_text="√81 = ?", option_a="7", option_b="8", option_c="9", option_d="11",
                                correct_option="C", topic="Algebra", marks=1),
            scbt.BankQuestionIn(question_text="10% of 200 = ?", option_a="10", option_b="20", option_c="2",
                                option_d="100", correct_option="B", topic="Arithmetic", marks=1),
        ], admin_user, db)
        check("bank questions added", added["added"] == 4, str(added))

        print("\n── 2. Create exam (OFFLINE, display 3, total_mark 50, randomized) ──")
        exam = await scbt.create_exam(scbt.ExamCreateIn(
            title="First Term Mathematics Examination", subject="Mathematics", class_name="SS2",
            session="2026/2027", term="First Term", instructions="Read each question carefully.",
            exam_mode="OFFLINE", total_mark=50, duration_minutes=90,
            questions_to_display=3, questions_to_answer=2,
            randomize_questions=True, randomize_options=True,
            bank_ids=[bank["id"]], auto_pick_count=3,
            assigned_class_names=["SS2"],
            generate_codes=True, publish=True,
        ), admin_user, db)
        check("exam created published", exam["status"] == "published", str(exam))
        check("3 questions picked from bank", exam["question_count"] == 3, str(exam))
        check("students assigned via class", exam["students_assigned"] == 2, str(exam))
        check("access codes generated", exam["access_codes_created"] == 2, str(exam))
        exam_id = exam["id"]

        detail = await scbt.exam_detail(exam_id, staff_school, admin_user, db)
        reg1 = detail["assigned"][0]["reg_number"]
        code1 = detail["assigned"][0]["access_code"]
        reg2 = detail["assigned"][1]["reg_number"]
        code2 = detail["assigned"][1]["access_code"]
        check("reg number format", reg1.startswith("SCHX/26/"), reg1)
        check("access code format SCH-XXXX-XXXX",
              len(code1) == 13 and code1.startswith("SCH-") and code1[8] == "-",
              code1)

        print("\n── 3. Student exam login (§14) + brute-force protection ──")
        login = await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg1, access_code=code1), db)
        tok = creds(login["access_token"])
        check("login returns student name", login["student"]["full_name"] == "Student 1")
        for i in range(5):
            try:
                await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg1, access_code="SCH-WRONG-01"), db)
                check(f"wrong code rejected (try {i + 1})", False, "no exception")
            except HTTPException as e:
                check(f"wrong code rejected (try {i + 1})", e.status_code == 401, str(e.status_code))
        # 5 failures → code locked server-side; even the CORRECT code is blocked
        try:
            await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg1, access_code=code1), db)
            check("correct code blocked while locked", False, "no exception")
        except HTTPException as e:
            check("correct code blocked while locked", e.status_code == 429, str(e.status_code))
        # unlock to continue
        row = (await db.execute(select(SchoolExamAccessCode).where(
            SchoolExamAccessCode.exam_id == uuidmod.UUID(exam_id),
            SchoolExamAccessCode.student_id == students[0].id))).scalar_one()
        row.locked_until = None
        row.failed_attempts = 0
        await db.commit()
        login1b = await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg1, access_code=code1), db)
        tok = creds(login1b["access_token"])
        check("login works again after unlock", bool(tok.credentials))

        print("\n── 4. Assigned exams (§15) ──")
        mine = await scbt.student_my_exams(credentials=tok, db=db)
        check("sees exactly 1 exam", len(mine["exams"]) == 1, str(len(mine["exams"])))
        ex = mine["exams"][0]
        check("needs_download flagged for OFFLINE", ex["needs_download"] is True)
        check("meta fields present", ex["questions"] == 3 and ex["duration_minutes"] == 90 and ex["total_mark"] == 50)

        print("\n── 5. Download (§16/§17) — OFFLINE gate + no answers leaked ──")
        try:
            await scbt.start_attempt(exam_id, credentials=tok, db=db)
            check("start blocked before download", False, "no exception")
        except HTTPException as e:
            check("start blocked before download", e.status_code == 400 and "Download" in str(e.detail))
        pkg = await scbt.download_exam(exam_id, credentials=tok, db=db)
        check("download returns 3 questions", len(pkg["questions"]) == 3)
        blob = json.dumps(pkg).lower()
        check("no correct answers in package", "correct" not in blob and '"answer_key"' not in blob)
        ver = await scbt.verify_download(exam_id, credentials=tok, db=db)
        check("download verified", ver["verified"] is True)

        print("\n── 6. Start attempt — server-side timer + randomization mapping ──")
        started = await scbt.start_attempt(exam_id, credentials=tok, db=db)
        att_id = started["attempt_id"]
        check("seconds_remaining ≈ duration", 5390 <= started["seconds_remaining"] <= 5400,
              str(started["seconds_remaining"]))
        check("questions shown = 3 (display)", len(started["questions"]) == 3)
        # Randomization shuffles CONTENT under fixed positional labels A–D.
        nat = {}
        for q in (await db.execute(select(SchoolExamQuestion).where(
                SchoolExamQuestion.exam_id == uuidmod.UUID(exam_id)))).scalars().all():
            nat[str(q.id)] = [q.option_a, q.option_b, q.option_c, q.option_d]
        content_orders = {q["id"]: [o["text"] for o in q["options"]] for q in started["questions"]}
        labels_ok = all([o["label"] for o in q["options"]] == ["A", "B", "C", "D"] for q in started["questions"])
        check("labels stay positional A–D", labels_ok)
        check("option content shuffled (download mapping)",
              any(content_orders[qid] != nat[qid] for qid in content_orders), str(content_orders))

        print("\n── 7. Save answers (labels mapped back server-side, §10/§21) ──")
        qs = started["questions"]

        def q_with(needle):
            for q in qs:
                if needle in q["question_text"]:
                    return q
            raise AssertionError(f"question not found: {needle}")

        def label_with(q, text):
            for o in q["options"]:
                if o["text"].strip() == text:
                    return o["label"]
            raise AssertionError(f"option {text} not found for: {q['question_text']}")

        TRUTH = {"2x + 6": "4", "5 × 6": "30", "√81": "9", "10% of 200": "20"}
        answered_pairs = []
        for q in qs:
            key = next((k for k in TRUTH if k in q["question_text"]), None)
            check("question matched to truth key", key is not None, q["question_text"][:40])
            lbl = label_with(q, TRUTH[key])
            await scbt.save_answer(scbt.AnswerIn(attempt_id=att_id, question_id=q["id"], answer=lbl),
                                   credentials=tok, db=db)
            answered_pairs.append((q["id"], TRUTH[key]))
        check("3 answers saved via auto-save", len(answered_pairs) == 3)

        print("\n── 8. Offline batch sync + submit (§21/§23) ──")
        # Wipe one answer locally-style: resubmit all via the offline batch,
        # which must be idempotent and validate question ids server-side.
        res = await scbt.offline_sync(scbt.OfflineBatchIn(
            attempt_id=att_id,
            answers=[{"question_id": qid, "answer": "A"} for qid, _ in answered_pairs]
                     + [{"question_id": "00000000-0000-0000-0000-00000000dead", "answer": "B"}],  # forged id
            submit=False, offline_sync=True, client="test-offline",
        ), credentials=tok, db=db)
        check("forged question id dropped, valid synced", res["answers_synced"] == 3, str(res))
        # Re-answer correctly (batch overwrote with "A" above), then submit.
        for qid, truth_text in []:
            pass
        for q in qs:
            key = next((k for k in TRUTH if k in q["question_text"]), None)
            lbl = label_with(q, TRUTH[key])
            await scbt.save_answer(scbt.AnswerIn(attempt_id=att_id, question_id=q["id"], answer=lbl),
                                   credentials=tok, db=db)
        res = await scbt.offline_sync(scbt.OfflineBatchIn(
            attempt_id=att_id, answers=[], submit=True, offline_sync=True, client="test-offline",
        ), credentials=tok, db=db)
        check("offline submit ok", res["ok"] is True)
        s = res["result"]["summary"]
        check("correct=3 marked", s["correct"] == 3, str(s))
        # §22 — score stays HIDDEN from the student until the school publishes.
        check("student submit hides score pre-publish", s["final_score"] is None and s["grade"] is None, str(s))

        print("\n── 9. Duplicate submit is idempotent ──")
        dup = await scbt.submit_attempt(exam_id, scbt.SubmitIn(attempt_id=att_id), credentials=tok, db=db)
        check("duplicate flagged", dup["already_submitted"] is True)

        print("\n── 9b. Access-code management (dedicated tab endpoints) ──")
        listing = await scbt.list_codes(exam_id, staff_school, admin_user, db)
        check("list_codes returns 2 slips", len(listing["codes"]) == 2, str(len(listing["codes"])))
        c0 = listing["codes"][0]
        check("slip fields present", all(k in c0 for k in ("reg_number", "access_code", "is_used", "locked", "full_name")), str(c0)[:120])
        reset = await scbt.reset_code(exam_id, str(students[0].id), staff_school, admin_user, db)
        check("reset issues fresh code", reset["access_code"] != code1 and reset["reg_number"] == reg1, reset["access_code"])
        fresh_login = await scbt.student_exam_login(
            scbt.StudentLoginIn(reg_number=reg1, access_code=reset["access_code"]), db)
        check("fresh code logs in", bool(fresh_login["access_token"]))
        try:
            await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg1, access_code=code1), db)
            check("old code dead after reset", False, "no exception")
        except HTTPException as e:
            check("old code dead after reset", e.status_code == 401, str(e.status_code))
        dir_all = await scbt.codes_student_directory(school_id=None, current_user=admin_user, db=db)
        check("directory is tenant-scoped",
              {s["id"] for s in dir_all["students"]} == {str(su.id) for su in students},
              str(dir_all)[:150])

        print("\n── 10. Result hidden until publish (§22) ──")
        mine2 = await scbt.student_my_exams(credentials=tok, db=db)
        check("student sees no result before publish", mine2["exams"][0]["result"] is None)
        sr = await scbt.student_results(credentials=tok, db=db)
        check("student results endpoint empty pre-publish", len(sr["results"]) == 0)

        print("\n── 11. Staff results + publish (§29) ──")
        staff_results = await scbt.exam_results(exam_id, staff_school, admin_user, db)
        check("staff sees 1 result", len(staff_results["results"]) == 1, str(staff_results)[:200])
        r0 = staff_results["results"][0]
        check("staff sees raw numbers", r0["correct_answers"] == 3, str(r0))
        # §29 — AUTO MARKING: raw 3/3 → configured total mark 50/50, A1.
        check("raw→total_mark mapping: 3/3 → 50/50",
              r0["final_score"] == 50 and r0["total_mark"] == 50, str(r0))
        check("percentage 100 + grade A1", r0["percentage"] == 100.0 and r0["grade"] == "A1", str(r0))
        await scbt.publish_results(exam_id, True, staff_school, admin_user, db)
        sr2 = await scbt.student_results(credentials=tok, db=db)
        check("student sees published result", len(sr2["results"]) == 1 and sr2["results"][0]["final_score"] == 50,
              str(sr2)[:200])

        print("\n── 12. Grant retake → student can start again ──")
        await scbt.grant_retake(exam_id, scbt.RetakeIn(student_ids=[str(students[0].id)]), staff_school, admin_user, db)
        started2 = await scbt.start_attempt(exam_id, credentials=tok, db=db)
        check("retake attempt started", started2["attempt_id"] != att_id)

        print("\n── 13. Tenant isolation (§30) ──")
        try:
            await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg2, access_code=code1), db)
            check("cross-student code rejected", False, "no exception")
        except HTTPException as e:
            check("cross-student code rejected", e.status_code == 401, str(e.status_code))
        login2 = await scbt.student_exam_login(scbt.StudentLoginIn(reg_number=reg2, access_code=code2), db)
        tok2 = creds(login2["access_token"])
        mine3 = await scbt.student_my_exams(credentials=tok2, db=db)
        check("student 2 sees the same exam", len(mine3["exams"]) == 1)
        try:
            await scbt.save_answer(scbt.AnswerIn(attempt_id=att_id, question_id=qs[0]["id"], answer="A"),
                                   credentials=tok2, db=db)
            check("foreign attempt blocked", False, "no exception")
        except HTTPException as e:
            check("foreign attempt blocked", e.status_code == 404, str(e.status_code))
        try:
            await scbt.exam_details("00000000-0000-0000-0000-000000000000", credentials=tok2, db=db)
            check("unknown exam 404", False, "no exception")
        except HTTPException as e:
            check("unknown exam 404", e.status_code == 404, str(e.status_code))

    print(f"\n════ RESULT: {len(PASS)} passed, {len(FAIL)} failed ════")
    if FAIL:
        for f in FAIL:
            print("  ✗ " + f)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
