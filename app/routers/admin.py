import os
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr
from typing import Optional
from app.core.database import get_db
from app.core.deps import require_admin
from app.core.security import hash_password, create_access_token, create_refresh_token
from app.models.user import User, UserRole, TeacherProfile
from app.models.content import Book, LibraryTarget
from app.services.media_service import generate_upload_signature

router = APIRouter(prefix="/admin", tags=["Admin"])


# ── Admin Self-Registration ───────────────────────────────────────────────────

class AdminRegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    invite_code: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def admin_register(payload: AdminRegisterRequest, db: AsyncSession = Depends(get_db)):
    """Admin creates their own account using a secret invite code."""
    invite_code = os.getenv("ADMIN_INVITE_CODE", "SCHOLAXIA_ADMIN_2026")

    if payload.invite_code != invite_code:
        raise HTTPException(status_code=403, detail="Invalid invite code")

    if len(payload.password) > 72:
        raise HTTPException(status_code=400, detail="Password must be 72 characters or less")

    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.admin,
        is_active=True,
        is_verified=True,
    )
    db.add(user)
    await db.flush()

    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
    )


# ── Teacher Management ────────────────────────────────────────────────────────

class CreateTeacherRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    subjects: list[str]
    bio: str = ""


class TeacherResponse(BaseModel):
    id: str
    email: str
    full_name: str
    subjects: list[str]


@router.post("/teachers", response_model=TeacherResponse, status_code=status.HTTP_201_CREATED)
async def create_teacher(
    payload: CreateTeacherRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates teacher accounts — teachers do NOT self-register."""
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already in use")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.teacher,
        is_verified=True,
    )
    db.add(user)
    await db.flush()

    profile = TeacherProfile(user_id=user.id, subjects=payload.subjects, bio=payload.bio)
    db.add(profile)
    await db.flush()

    return TeacherResponse(id=str(user.id), email=user.email, full_name=user.full_name, subjects=payload.subjects)


@router.get("/teachers", response_model=list[TeacherResponse])
async def list_teachers(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User, TeacherProfile)
        .join(TeacherProfile, TeacherProfile.user_id == User.id)
        .where(User.role == UserRole.teacher)
    )
    rows = result.all()
    return [
        TeacherResponse(id=str(u.id), email=u.email, full_name=u.full_name, subjects=p.subjects)
        for u, p in rows
    ]


@router.delete("/teachers/{teacher_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_teacher(
    teacher_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == teacher_id, User.role == UserRole.teacher))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Teacher not found")
    user.is_active = False


# ── Library Management ────────────────────────────────────────────────────────

class AddBookRequest(BaseModel):
    title: str
    author: Optional[str] = None
    subject: str
    exam_type: Optional[str] = None
    file_key: str
    cover_image_url: Optional[str] = None
    description: Optional[str] = None
    total_pages: Optional[int] = None
    library_target: LibraryTarget = LibraryTarget.student


class BookResponse(BaseModel):
    id: str
    title: str
    subject: str
    library_target: str
    is_downloadable: bool
    allow_copy: bool
    allow_screenshot: bool


@router.post("/library/upload-url")
async def get_book_upload_url(current_user: dict = Depends(require_admin)):
    return generate_upload_signature(folder="books")


@router.post("/library/books", response_model=BookResponse, status_code=201)
async def add_book(
    payload: AddBookRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    book = Book(
        title=payload.title,
        author=payload.author,
        subject=payload.subject,
        exam_type=payload.exam_type,
        file_key=payload.file_key,
        cover_image_url=payload.cover_image_url,
        description=payload.description,
        total_pages=payload.total_pages,
        library_target=payload.library_target,
        uploaded_by=current_user["sub"],
        is_downloadable=False,
        allow_copy=False,
        allow_screenshot=False,
        allow_print=False,
    )
    db.add(book)
    await db.flush()

    return BookResponse(
        id=str(book.id),
        title=book.title,
        subject=book.subject,
        library_target=book.library_target,
        is_downloadable=False,
        allow_copy=False,
        allow_screenshot=False,
    )


@router.get("/library/books")
async def list_all_books(
    library_target: Optional[LibraryTarget] = None,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    query = select(Book).where(Book.is_active == True)  # noqa: E712
    if library_target:
        query = query.where(Book.library_target == library_target)
    result = await db.execute(query.order_by(Book.created_at.desc()))
    books = result.scalars().all()
    return [
        {
            "id": str(b.id),
            "title": b.title,
            "subject": b.subject,
            "library_target": b.library_target,
            "exam_type": b.exam_type,
            "created_at": b.created_at,
        }
        for b in books
    ]


@router.post("/seed-cbt")
async def trigger_cbt_seed(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin triggers CBT seed manually."""
    import uuid as _uuid
    from app.models.cbt import CBTExam as _Exam, CBTQuestion as _Q
    from sqlalchemy import select as _sel

    exams_data = [
        {"title": "WAEC Mathematics Practice 2023", "subject": "Mathematics", "exam_type": "WAEC", "duration_minutes": 40,
         "questions": [
            {"question_text": "Simplify: (2x³y²) × (3xy⁴)", "option_a": "5x⁴y⁶", "option_b": "6x⁴y⁶", "option_c": "6x³y⁸", "option_d": "5x³y⁸", "correct_option": "B", "explanation": "2×3=6, x:3+1=4, y:2+4=6", "topic": "Algebra"},
            {"question_text": "Simple interest on ₦5,000 for 3 years at 8% p.a.:", "option_a": "₦1,000", "option_b": "₦1,200", "option_c": "₦1,500", "option_d": "₦2,000", "correct_option": "B", "explanation": "PRT/100=₦1,200", "topic": "Simple Interest"},
            {"question_text": "Gradient of line joining (2,3) and (4,7):", "option_a": "1", "option_b": "2", "option_c": "3", "option_d": "4", "correct_option": "B", "explanation": "(7-3)/(4-2)=2", "topic": "Coordinate Geometry"},
            {"question_text": "If 3x - 5 = 16, find x.", "option_a": "5", "option_b": "6", "option_c": "7", "option_d": "8", "correct_option": "C", "explanation": "3x=21, x=7", "topic": "Algebra"},
            {"question_text": "Bag: 4 red, 6 blue balls. P(red)?", "option_a": "2/5", "option_b": "3/5", "option_c": "1/4", "option_d": "2/3", "correct_option": "A", "explanation": "4/10=2/5", "topic": "Probability"},
            {"question_text": "Evaluate: log₁₀ 1000", "option_a": "2", "option_b": "3", "option_c": "4", "option_d": "10", "correct_option": "B", "explanation": "log₁₀ 10³=3", "topic": "Logarithms"},
            {"question_text": "Area of circle radius 7 cm (π=22/7):", "option_a": "44 cm²", "option_b": "154 cm²", "option_c": "22 cm²", "option_d": "308 cm²", "correct_option": "B", "explanation": "(22/7)×49=154 cm²", "topic": "Mensuration"},
            {"question_text": "What is 15% of 200?", "option_a": "25", "option_b": "30", "option_c": "35", "option_d": "40", "correct_option": "B", "explanation": "15/100×200=30", "topic": "Percentages"},
            {"question_text": "Mean of 3,5,7,x is 6. Find x.", "option_a": "7", "option_b": "8", "option_c": "9", "option_d": "10", "correct_option": "C", "explanation": "(15+x)/4=6→x=9", "topic": "Statistics"},
            {"question_text": "Solve: x² - 5x + 6 = 0", "option_a": "x=1 or 6", "option_b": "x=2 or 3", "option_c": "x=-2 or -3", "option_d": "x=2 or -3", "correct_option": "B", "explanation": "(x-2)(x-3)=0", "topic": "Quadratic Equations"},
         ]},
        {"title": "WAEC English Language Practice 2023", "subject": "English Language", "exam_type": "WAEC", "duration_minutes": 45,
         "questions": [
            {"question_text": "Word closest to BENEVOLENT:", "option_a": "Cruel", "option_b": "Kind", "option_c": "Greedy", "option_d": "Fearful", "correct_option": "B", "explanation": "Benevolent=kindly/generous", "topic": "Vocabulary"},
            {"question_text": "Correct sentence:", "option_a": "Each student have books.", "option_b": "Each has their books.", "option_c": "Each have his books.", "option_d": "Each of the students has his book.", "correct_option": "D", "explanation": "Each is singular", "topic": "Grammar"},
            {"question_text": "Opposite of LOQUACIOUS:", "option_a": "Talkative", "option_b": "Verbose", "option_c": "Taciturn", "option_d": "Garrulous", "correct_option": "C", "explanation": "Taciturn=reserved", "topic": "Antonyms"},
            {"question_text": "Figure of speech: The pen is mightier than the sword.", "option_a": "Simile", "option_b": "Personification", "option_c": "Metaphor", "option_d": "Synecdoche", "correct_option": "C", "explanation": "Metaphor compares without like/as", "topic": "Figures of Speech"},
            {"question_text": "She _____ to Lagos last week.", "option_a": "go", "option_b": "goes", "option_c": "gone", "option_d": "went", "correct_option": "D", "explanation": "Past tense=went", "topic": "Tenses"},
            {"question_text": "Correctly spelled:", "option_a": "Accomodation", "option_b": "Accommodation", "option_c": "Acomodation", "option_d": "Acommodation", "correct_option": "B", "explanation": "Double c and double m", "topic": "Spelling"},
            {"question_text": "UBIQUITOUS means:", "option_a": "Rare", "option_b": "Present everywhere", "option_c": "Hidden", "option_d": "Dangerous", "correct_option": "B", "explanation": "Present everywhere", "topic": "Vocabulary"},
            {"question_text": "Passive voice:", "option_a": "The boy kicked the ball.", "option_b": "They were eating.", "option_c": "The ball was kicked by the boy.", "option_d": "She sings.", "correct_option": "C", "explanation": "Subject receives action", "topic": "Active and Passive Voice"},
            {"question_text": "He is good _____ mathematics.", "option_a": "in", "option_b": "at", "option_c": "on", "option_d": "for", "correct_option": "B", "explanation": "Good at is correct", "topic": "Prepositions"},
            {"question_text": "Word meaning same as another:", "option_a": "Antonym", "option_b": "Homonym", "option_c": "Synonym", "option_d": "Acronym", "correct_option": "C", "explanation": "Synonym=same meaning", "topic": "Vocabulary"},
         ]},
        {"title": "NECO Biology Practice 2023", "subject": "Biology", "exam_type": "NECO", "duration_minutes": 40,
         "questions": [
            {"question_text": "Plants manufacture food via:", "option_a": "Respiration", "option_b": "Transpiration", "option_c": "Photosynthesis", "option_d": "Osmosis", "correct_option": "C", "explanation": "Photosynthesis uses sunlight CO2 water", "topic": "Photosynthesis"},
            {"question_text": "NOT a liver function:", "option_a": "Bile production", "option_b": "Detoxification", "option_c": "Insulin production", "option_d": "Glycogen storage", "correct_option": "C", "explanation": "Insulin made by pancreas", "topic": "Digestive System"},
            {"question_text": "Basic unit of life:", "option_a": "Atom", "option_b": "Tissue", "option_c": "Cell", "option_d": "Organ", "correct_option": "C", "explanation": "Cell is basic unit", "topic": "Cell Biology"},
            {"question_text": "DNA found mainly in:", "option_a": "Cytoplasm", "option_b": "Nucleus", "option_c": "Ribosome", "option_d": "Cell membrane", "correct_option": "B", "explanation": "DNA is in nucleus", "topic": "Genetics"},
            {"question_text": "Universal blood donor:", "option_a": "A", "option_b": "B", "option_c": "AB", "option_d": "O", "correct_option": "D", "explanation": "O negative no antigens", "topic": "Blood and Circulation"},
            {"question_text": "Brain part for balance:", "option_a": "Cerebrum", "option_b": "Medulla oblongata", "option_c": "Cerebellum", "option_d": "Hypothalamus", "correct_option": "C", "explanation": "Cerebellum coordinates movement", "topic": "Nervous System"},
            {"question_text": "Asexual reproduction example:", "option_a": "Fertilisation", "option_b": "Budding", "option_c": "Pollination", "option_d": "Meiosis", "correct_option": "B", "explanation": "Budding is asexual", "topic": "Reproduction"},
            {"question_text": "Powerhouse of the cell:", "option_a": "Nucleus", "option_b": "Ribosome", "option_c": "Mitochondria", "option_d": "Golgi apparatus", "correct_option": "C", "explanation": "Mitochondria produce ATP", "topic": "Cell Biology"},
            {"question_text": "Malaria caused by:", "option_a": "Bacteria", "option_b": "Virus", "option_c": "Plasmodium", "option_d": "Fungus", "correct_option": "C", "explanation": "Plasmodium parasite", "topic": "Diseases"},
            {"question_text": "Protein synthesis site:", "option_a": "Nucleus", "option_b": "Mitochondria", "option_c": "Ribosome", "option_d": "Vacuole", "correct_option": "C", "explanation": "Ribosomes translate mRNA", "topic": "Cell Biology"},
         ]},
        {"title": "NECO Chemistry Practice 2023", "subject": "Chemistry", "exam_type": "NECO", "duration_minutes": 40,
         "questions": [
            {"question_text": "Chemical formula of water:", "option_a": "HO", "option_b": "H2O", "option_c": "H2O2", "option_d": "OH", "correct_option": "B", "explanation": "2H + O = H2O", "topic": "Chemical Formulae"},
            {"question_text": "Atomic number of Carbon:", "option_a": "4", "option_b": "6", "option_c": "12", "option_d": "14", "correct_option": "B", "explanation": "Carbon has 6 protons", "topic": "Atomic Structure"},
            {"question_text": "Gas when acid reacts with metal:", "option_a": "Oxygen", "option_b": "Carbon dioxide", "option_c": "Hydrogen", "option_d": "Nitrogen", "correct_option": "C", "explanation": "Acid+Metal=Salt+Hydrogen", "topic": "Acid-Base Reactions"},
            {"question_text": "Which is a noble gas?", "option_a": "Nitrogen", "option_b": "Oxygen", "option_c": "Argon", "option_d": "Chlorine", "correct_option": "C", "explanation": "Argon Group 18", "topic": "Periodic Table"},
            {"question_text": "pH of neutral solution:", "option_a": "0", "option_b": "7", "option_c": "10", "option_d": "14", "correct_option": "B", "explanation": "Neutral=pH 7", "topic": "Acids and Bases"},
            {"question_text": "Bond by sharing electrons:", "option_a": "Ionic", "option_b": "Metallic", "option_c": "Covalent", "option_d": "Hydrogen", "correct_option": "C", "explanation": "Covalent shares electrons", "topic": "Chemical Bonding"},
            {"question_text": "Rusting of iron:", "option_a": "Physical change", "option_b": "Chemical change", "option_c": "Nuclear change", "option_d": "Reversible", "correct_option": "B", "explanation": "Fe2O3 is new substance", "topic": "Chemical Changes"},
            {"question_text": "Liquid to gas by heating:", "option_a": "Condensation", "option_b": "Sublimation", "option_c": "Evaporation", "option_d": "Distillation", "correct_option": "C", "explanation": "Evaporation", "topic": "States of Matter"},
            {"question_text": "Symbol Na stands for:", "option_a": "Nitrogen", "option_b": "Nickel", "option_c": "Sodium", "option_d": "Neon", "correct_option": "C", "explanation": "Natrium=Sodium", "topic": "Periodic Table"},
            {"question_text": "Electrolysis of brine: Cl2 at:", "option_a": "Cathode", "option_b": "Anode", "option_c": "Electrolyte", "option_d": "Both", "correct_option": "B", "explanation": "Cl- oxidised at anode", "topic": "Electrolysis"},
         ]},
    ]

    seeded = []
    skipped = []
    errors = []

    for ed in exams_data:
        try:
            res = await db.execute(_sel(_Exam).where(_Exam.title == ed["title"]))
            if res.scalar_one_or_none():
                skipped.append(ed["title"])
                continue

            exam = _Exam(
                title=ed["title"],
                subject=ed["subject"],
                exam_type=ed["exam_type"],
                duration_minutes=ed["duration_minutes"],
                total_questions=len(ed["questions"]),
                is_published=True,
                created_by=current_user["sub"],
            )
            db.add(exam)
            await db.flush()

            for q in ed["questions"]:
                db.add(_Q(exam_id=exam.id, **q))

            await db.commit()
            seeded.append(ed["title"])
        except Exception as e:
            await db.rollback()
            errors.append({"title": ed["title"], "error": str(e)})

    return {
        "status": "done",
        "seeded": seeded,
        "skipped": skipped,
        "errors": errors,
    }


@router.delete("/library/books/{book_id}", status_code=204)
async def remove_book(
    book_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Book).where(Book.id == book_id))
    book = result.scalar_one_or_none()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    book.is_active = False


# ── CBT Management ────────────────────────────────────────────────────────────

from app.models.cbt import CBTExam, CBTQuestion  # noqa: E402


class CBTQuestionCreate(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str   # A, B, C, or D
    explanation: Optional[str] = None
    topic: Optional[str] = None
    image_url: Optional[str] = None


class CBTExamCreate(BaseModel):
    title: str
    subject: str
    exam_type: str          # JAMB | WAEC | NECO | SCHOOL
    duration_minutes: int
    questions: list[CBTQuestionCreate]
    is_published: bool = True
    is_school_exam: bool = False
    ai_locked: bool = False
    camera_required: bool = False
    block_minimize: bool = False


@router.post("/cbt/exams", status_code=201)
async def create_cbt_exam(
    payload: CBTExamCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates a new CBT exam with questions."""
    exam = CBTExam(
        title=payload.title,
        subject=payload.subject,
        exam_type=payload.exam_type.upper(),
        duration_minutes=payload.duration_minutes,
        total_questions=len(payload.questions),
        created_by=current_user["sub"],
        is_published=payload.is_published,
        is_school_exam=payload.is_school_exam,
        ai_locked=payload.ai_locked,
        camera_required=payload.camera_required,
        block_minimize=payload.block_minimize,
    )
    db.add(exam)
    await db.flush()

    for q in payload.questions:
        db.add(CBTQuestion(
            exam_id=exam.id,
            question_text=q.question_text,
            option_a=q.option_a,
            option_b=q.option_b,
            option_c=q.option_c,
            option_d=q.option_d,
            correct_option=q.correct_option.upper(),
            explanation=q.explanation,
            topic=q.topic,
            image_url=q.image_url,
        ))

    return {
        "id": str(exam.id),
        "title": exam.title,
        "subject": exam.subject,
        "exam_type": exam.exam_type,
        "total_questions": exam.total_questions,
        "is_published": exam.is_published,
    }


@router.get("/cbt/exams")
async def admin_list_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin lists all exams (published and unpublished)."""
    result = await db.execute(select(CBTExam).order_by(CBTExam.created_at.desc()))
    exams = result.scalars().all()
    return [
        {
            "id": str(e.id),
            "title": e.title,
            "subject": e.subject,
            "exam_type": e.exam_type,
            "duration_minutes": e.duration_minutes,
            "total_questions": e.total_questions,
            "is_published": e.is_published,
            "is_school_exam": e.is_school_exam,
            "created_at": e.created_at,
        }
        for e in exams
    ]


@router.patch("/cbt/exams/{exam_id}/publish")
async def toggle_exam_publish(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin publishes or unpublishes an exam."""
    result = await db.execute(select(CBTExam).where(CBTExam.id == exam_id))
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.is_published = not exam.is_published
    return {"id": exam_id, "is_published": exam.is_published}


@router.delete("/cbt/exams/{exam_id}", status_code=204)
async def delete_cbt_exam(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin deletes an exam and all its questions."""
    result = await db.execute(select(CBTExam).where(CBTExam.id == exam_id))
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    # Delete questions first
    q_result = await db.execute(select(CBTQuestion).where(CBTQuestion.exam_id == exam_id))
    for q in q_result.scalars().all():
        await db.delete(q)
    await db.delete(exam)


# ── Admin: Create CBT Exam with Questions ─────────────────────────────────────

from app.models.cbt import CBTExam, CBTQuestion


class CBTQuestionCreate(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str  # A, B, C or D
    explanation: Optional[str] = None
    topic: Optional[str] = None
    image_url: Optional[str] = None


class CreateCBTExamRequest(BaseModel):
    title: str
    subject: str
    exam_type: str  # JAMB, WAEC, NECO, SCHOOL
    duration_minutes: int
    is_published: bool = True
    is_school_exam: bool = False
    ai_locked: bool = False
    camera_required: bool = False
    block_minimize: bool = False
    questions: list[CBTQuestionCreate]


class CBTExamResponse(BaseModel):
    id: str
    title: str
    subject: str
    exam_type: str
    duration_minutes: int
    total_questions: int
    is_published: bool


@router.post("/cbt/exams", response_model=CBTExamResponse, status_code=201)
async def admin_create_cbt_exam(
    payload: CreateCBTExamRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates a CBT exam with all questions in one request."""
    if not payload.questions:
        raise HTTPException(status_code=400, detail="At least one question required")

    exam = CBTExam(
        title=payload.title,
        subject=payload.subject,
        exam_type=payload.exam_type.upper(),
        duration_minutes=payload.duration_minutes,
        total_questions=len(payload.questions),
        is_published=payload.is_published,
        is_school_exam=payload.is_school_exam,
        ai_locked=payload.ai_locked,
        camera_required=payload.camera_required,
        block_minimize=payload.block_minimize,
        created_by=current_user["sub"],
    )
    db.add(exam)
    await db.flush()

    for q in payload.questions:
        if q.correct_option.upper() not in ("A", "B", "C", "D"):
            raise HTTPException(status_code=400, detail=f"correct_option must be A/B/C/D, got: {q.correct_option}")
        db.add(CBTQuestion(
            exam_id=exam.id,
            question_text=q.question_text,
            option_a=q.option_a,
            option_b=q.option_b,
            option_c=q.option_c,
            option_d=q.option_d,
            correct_option=q.correct_option.upper(),
            explanation=q.explanation,
            topic=q.topic,
            image_url=q.image_url,
        ))

    await db.flush()
    return CBTExamResponse(
        id=str(exam.id),
        title=exam.title,
        subject=exam.subject,
        exam_type=exam.exam_type,
        duration_minutes=exam.duration_minutes,
        total_questions=exam.total_questions,
        is_published=exam.is_published,
    )


@router.get("/cbt/exams", response_model=list[CBTExamResponse])
async def admin_list_cbt_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin lists all CBT exams (published and unpublished)."""
    result = await db.execute(select(CBTExam).order_by(CBTExam.exam_type, CBTExam.subject))
    exams = result.scalars().all()
    return [
        CBTExamResponse(
            id=str(e.id), title=e.title, subject=e.subject,
            exam_type=e.exam_type, duration_minutes=e.duration_minutes,
            total_questions=e.total_questions, is_published=e.is_published,
        )
        for e in exams
    ]


@router.patch("/cbt/exams/{exam_id}/publish")
async def admin_toggle_publish(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Toggle publish/unpublish an exam."""
    result = await db.execute(select(CBTExam).where(CBTExam.id == exam_id))
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.is_published = not exam.is_published
    await db.flush()
    return {"id": str(exam.id), "is_published": exam.is_published}
