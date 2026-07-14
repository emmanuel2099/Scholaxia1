"""
Database Seeder
---------------
Seeds community channels + WAEC/NECO CBT exam data on startup.
"""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.community import CommunityChannel, ChannelType
from app.models.cbt import CBTExam, CBTQuestion
from app.core.cbt_seed_data import JAMB_EXAMS


async def seed_database(db: AsyncSession):
    await _seed_channels(db)
    await _seed_cbt_exams(db)
    await db.commit()


async def _seed_channels(db: AsyncSession):
    channels = [
        {
            "name": "General Channel",
            "channel_type": ChannelType.general,
            "description": "Main channel for all students.",
            "is_readonly_for_students": False,
        },
        {
            "name": "Teacher Announcements",
            "channel_type": ChannelType.teacher_announcement,
            "description": "Official announcements. Students read only.",
            "is_readonly_for_students": True,
        },
    ]
    for ch in channels:
        res = await db.execute(
            select(CommunityChannel).where(CommunityChannel.channel_type == ch["channel_type"])
        )
        if res.scalar_one_or_none():
            continue
        db.add(CommunityChannel(**ch))
        print(f"[seed] Channel: {ch['name']}")


# ── Exam seed data ────────────────────────────────────────────────────────────

_EXAMS = [
    {
        "title": "WAEC Mathematics 2023",
        "subject": "Mathematics",
        "exam_type": "WAEC",
        "duration_minutes": 40,
        "questions": [
            {"question_text": "Simplify: (2x³y²) × (3xy⁴)", "option_a": "5x⁴y⁶", "option_b": "6x⁴y⁶", "option_c": "6x³y⁸", "option_d": "5x³y⁸", "correct_option": "B", "explanation": "Multiply coefficients 2×3=6, add x exponents 3+1=4, add y exponents 2+4=6.", "topic": "Algebra"},
            {"question_text": "Simple interest on ₦5,000 for 3 years at 8% p.a.", "option_a": "₦1,000", "option_b": "₦1,200", "option_c": "₦1,500", "option_d": "₦2,000", "correct_option": "B", "explanation": "SI = PRT/100 = 5000×8×3/100 = ₦1,200", "topic": "Simple Interest"},
            {"question_text": "Gradient of the line joining (2,3) and (4,7).", "option_a": "1", "option_b": "2", "option_c": "3", "option_d": "4", "correct_option": "B", "explanation": "(7-3)/(4-2) = 4/2 = 2", "topic": "Coordinate Geometry"},
            {"question_text": "If 3x - 5 = 16, find x.", "option_a": "5", "option_b": "6", "option_c": "7", "option_d": "8", "correct_option": "C", "explanation": "3x=21, x=7", "topic": "Algebra"},
            {"question_text": "Bag has 4 red, 6 blue balls. P(red) =", "option_a": "2/5", "option_b": "3/5", "option_c": "1/4", "option_d": "2/3", "correct_option": "A", "explanation": "P=4/10=2/5", "topic": "Probability"},
            {"question_text": "Evaluate: log₁₀ 1000", "option_a": "2", "option_b": "3", "option_c": "4", "option_d": "10", "correct_option": "B", "explanation": "10³=1000, log₁₀ 10³=3", "topic": "Logarithms"},
            {"question_text": "Area of circle with radius 7 cm (π=22/7):", "option_a": "44 cm²", "option_b": "154 cm²", "option_c": "22 cm²", "option_d": "308 cm²", "correct_option": "B", "explanation": "πr²=(22/7)×49=154", "topic": "Mensuration"},
            {"question_text": "What is 15% of 200?", "option_a": "25", "option_b": "30", "option_c": "35", "option_d": "40", "correct_option": "B", "explanation": "15/100×200=30", "topic": "Percentages"},
            {"question_text": "Mean of 3,5,7,x is 6. Find x.", "option_a": "7", "option_b": "8", "option_c": "9", "option_d": "10", "correct_option": "C", "explanation": "(3+5+7+x)/4=6 → x=9", "topic": "Statistics"},
            {"question_text": "Solve: x² - 5x + 6 = 0", "option_a": "x=1 or 6", "option_b": "x=2 or 3", "option_c": "x=-2 or -3", "option_d": "x=2 or -3", "correct_option": "B", "explanation": "(x-2)(x-3)=0", "topic": "Quadratic Equations"},
            {"question_text": "Convert 0.125 to lowest fraction.", "option_a": "1/4", "option_b": "1/6", "option_c": "1/8", "option_d": "1/10", "correct_option": "C", "explanation": "0.125=125/1000=1/8", "topic": "Fractions"},
            {"question_text": "Car travels 120 km in 2 hrs. Speed =", "option_a": "50 km/h", "option_b": "60 km/h", "option_c": "70 km/h", "option_d": "80 km/h", "correct_option": "B", "explanation": "120/2=60", "topic": "Speed Distance Time"},
            {"question_text": "Factorize: x² + 5x + 6", "option_a": "(x+1)(x+6)", "option_b": "(x+2)(x+3)", "option_c": "(x-2)(x-3)", "option_d": "(x+6)(x-1)", "correct_option": "B", "explanation": "(x+2)(x+3)=x²+5x+6", "topic": "Algebra"},
            {"question_text": "Value of 2⁵:", "option_a": "10", "option_b": "16", "option_c": "25", "option_d": "32", "correct_option": "D", "explanation": "2×2×2×2×2=32", "topic": "Indices"},
            {"question_text": "270° in standard position lies on:", "option_a": "Positive x-axis", "option_b": "Positive y-axis", "option_c": "Negative x-axis", "option_d": "Negative y-axis", "correct_option": "D", "explanation": "270° points straight down — negative y-axis", "topic": "Trigonometry"},
        ],
    },
    {
        "title": "WAEC English Language 2023",
        "subject": "English Language",
        "exam_type": "WAEC",
        "duration_minutes": 45,
        "questions": [
            {"question_text": "Word closest to 'BENEVOLENT':", "option_a": "Cruel", "option_b": "Kind", "option_c": "Greedy", "option_d": "Fearful", "correct_option": "B", "explanation": "Benevolent = well-meaning and kindly.", "topic": "Vocabulary"},
            {"question_text": "Select the correct sentence:", "option_a": "Each of the students have their books.", "option_b": "Each of the students has their books.", "option_c": "Each of the students have his books.", "option_d": "Each of the students has his book.", "correct_option": "D", "explanation": "'Each' is singular → 'has his book'.", "topic": "Grammar"},
            {"question_text": "Opposite of LOQUACIOUS:", "option_a": "Talkative", "option_b": "Verbose", "option_c": "Taciturn", "option_d": "Garrulous", "correct_option": "C", "explanation": "Loquacious=talkative; antonym=taciturn.", "topic": "Antonyms"},
            {"question_text": "Figure of speech: 'The pen is mightier than the sword.'", "option_a": "Simile", "option_b": "Personification", "option_c": "Metaphor", "option_d": "Synecdoche", "correct_option": "C", "explanation": "Metaphor without 'like' or 'as'.", "topic": "Figures of Speech"},
            {"question_text": "She _____ to Lagos last week.", "option_a": "go", "option_b": "goes", "option_c": "gone", "option_d": "went", "correct_option": "D", "explanation": "Past tense → 'went'.", "topic": "Tenses"},
            {"question_text": "Correctly spelled word:", "option_a": "Accomodation", "option_b": "Accommodation", "option_c": "Acomodation", "option_d": "Acommodation", "correct_option": "B", "explanation": "Double 'c' and double 'm'.", "topic": "Spelling"},
            {"question_text": "'UBIQUITOUS' means:", "option_a": "Rare", "option_b": "Present everywhere", "option_c": "Hidden", "option_d": "Dangerous", "correct_option": "B", "explanation": "Ubiquitous = found everywhere.", "topic": "Vocabulary"},
            {"question_text": "Identify the passive voice:", "option_a": "The boy kicked the ball.", "option_b": "They were eating dinner.", "option_c": "The ball was kicked by the boy.", "option_d": "She sings beautifully.", "correct_option": "C", "explanation": "Subject receives action.", "topic": "Active and Passive Voice"},
            {"question_text": "Word with same meaning = a:", "option_a": "Antonym", "option_b": "Homonym", "option_c": "Synonym", "option_d": "Acronym", "correct_option": "C", "explanation": "Synonym = same meaning.", "topic": "Vocabulary"},
            {"question_text": "He is good _____ mathematics.", "option_a": "in", "option_b": "at", "option_c": "on", "option_d": "for", "correct_option": "B", "explanation": "'Good at' a subject is the correct phrase.", "topic": "Prepositions"},
        ],
    },
    {
        "title": "NECO Biology 2023",
        "subject": "Biology",
        "exam_type": "NECO",
        "duration_minutes": 40,
        "questions": [
            {"question_text": "Green plants manufacture food using sunlight via:", "option_a": "Respiration", "option_b": "Transpiration", "option_c": "Photosynthesis", "option_d": "Osmosis", "correct_option": "C", "explanation": "Photosynthesis uses sunlight + CO₂ + water → glucose + O₂.", "topic": "Photosynthesis"},
            {"question_text": "Which is NOT a function of the liver?", "option_a": "Production of bile", "option_b": "Detoxification of blood", "option_c": "Production of insulin", "option_d": "Storage of glycogen", "correct_option": "C", "explanation": "Insulin is made by the pancreas, not the liver.", "topic": "Digestive System"},
            {"question_text": "Basic unit of life:", "option_a": "Atom", "option_b": "Tissue", "option_c": "Cell", "option_d": "Organ", "correct_option": "C", "explanation": "The cell is the basic structural and functional unit of life.", "topic": "Cell Biology"},
            {"question_text": "DNA is found mainly in the:", "option_a": "Cytoplasm", "option_b": "Nucleus", "option_c": "Ribosome", "option_d": "Cell membrane", "correct_option": "B", "explanation": "DNA is primarily in the nucleus of eukaryotic cells.", "topic": "Genetics"},
            {"question_text": "Universal blood donor group:", "option_a": "A", "option_b": "B", "option_c": "AB", "option_d": "O", "correct_option": "D", "explanation": "O negative has no A, B, or Rh antigens.", "topic": "Blood and Circulation"},
            {"question_text": "Brain part responsible for balance:", "option_a": "Cerebrum", "option_b": "Medulla oblongata", "option_c": "Cerebellum", "option_d": "Hypothalamus", "correct_option": "C", "explanation": "Cerebellum coordinates balance and posture.", "topic": "Nervous System"},
            {"question_text": "Example of asexual reproduction:", "option_a": "Fertilisation", "option_b": "Budding", "option_c": "Pollination", "option_d": "Meiosis", "correct_option": "B", "explanation": "Budding is asexual; offspring grows from parent body.", "topic": "Reproduction"},
            {"question_text": "Osmosis is movement of water from:", "option_a": "High to low concentration", "option_b": "Low to high concentration", "option_c": "High to high concentration", "option_d": "Low to low concentration", "correct_option": "B", "explanation": "Water moves from low solute (high water) to high solute (low water) through semi-permeable membrane.", "topic": "Transport"},
            {"question_text": "Which vitamin is produced by the skin in sunlight?", "option_a": "Vitamin A", "option_b": "Vitamin B", "option_c": "Vitamin C", "option_d": "Vitamin D", "correct_option": "D", "explanation": "Skin synthesises Vitamin D when exposed to UV light.", "topic": "Nutrition"},
            {"question_text": "The powerhouse of the cell:", "option_a": "Nucleus", "option_b": "Ribosome", "option_c": "Mitochondria", "option_d": "Golgi body", "correct_option": "C", "explanation": "Mitochondria produce ATP via cellular respiration.", "topic": "Cell Biology"},
        ],
    },
    {
        "title": "NECO Chemistry 2023",
        "subject": "Chemistry",
        "exam_type": "NECO",
        "duration_minutes": 40,
        "questions": [
            {"question_text": "Atomic number of Sodium:", "option_a": "10", "option_b": "11", "option_c": "12", "option_d": "23", "correct_option": "B", "explanation": "Sodium (Na) has 11 protons — atomic number 11.", "topic": "Atomic Structure"},
            {"question_text": "pH of a strong acid:", "option_a": "7", "option_b": "8-14", "option_c": "Below 7", "option_d": "Exactly 0", "correct_option": "C", "explanation": "Acids have pH below 7; strong acids like HCl have very low pH.", "topic": "Acids and Bases"},
            {"question_text": "Chemical formula of table salt:", "option_a": "NaOH", "option_b": "Na₂O", "option_c": "NaCl", "option_d": "NaHCO₃", "correct_option": "C", "explanation": "Table salt is sodium chloride, NaCl.", "topic": "Chemical Formulae"},
            {"question_text": "Type of bond in NaCl:", "option_a": "Covalent", "option_b": "Metallic", "option_c": "Ionic", "option_d": "Hydrogen", "correct_option": "C", "explanation": "NaCl forms ionic bond: Na⁺ and Cl⁻ held by electrostatic attraction.", "topic": "Chemical Bonding"},
            {"question_text": "Moles in 18g of water (M=18 g/mol):", "option_a": "0.5", "option_b": "1", "option_c": "2", "option_d": "18", "correct_option": "B", "explanation": "n = mass/M = 18/18 = 1 mol", "topic": "Mole Concept"},
            {"question_text": "Alloy of copper and zinc:", "option_a": "Bronze", "option_b": "Brass", "option_c": "Steel", "option_d": "Solder", "correct_option": "B", "explanation": "Brass = copper + zinc alloy.", "topic": "Metals and Alloys"},
            {"question_text": "Gas released when zinc reacts with HCl:", "option_a": "Oxygen", "option_b": "Carbon dioxide", "option_c": "Hydrogen", "option_d": "Nitrogen", "correct_option": "C", "explanation": "Zn + 2HCl → ZnCl₂ + H₂↑", "topic": "Reactions of Metals"},
            {"question_text": "Catalyst used in Haber process:", "option_a": "Platinum", "option_b": "Vanadium pentoxide", "option_c": "Iron", "option_d": "Nickel", "correct_option": "C", "explanation": "Iron catalyst at ~450°C in N₂ + H₂ → NH₃.", "topic": "Industrial Chemistry"},
            {"question_text": "Homologous series with general formula CₙH₂ₙ₊₂:", "option_a": "Alkenes", "option_b": "Alkynes", "option_c": "Alkanes", "option_d": "Arenes", "correct_option": "C", "explanation": "Alkanes: CₙH₂ₙ₊₂ (saturated hydrocarbons).", "topic": "Organic Chemistry"},
            {"question_text": "Indicator that turns red in acid:", "option_a": "Phenolphthalein", "option_b": "Methyl orange", "option_c": "Litmus", "option_d": "Universal indicator", "correct_option": "C", "explanation": "Litmus turns red in acid, blue in alkali.", "topic": "Indicators"},
        ],
    },
    {
        "title": "NECO Physics 2023",
        "subject": "Physics",
        "exam_type": "NECO",
        "duration_minutes": 40,
        "questions": [
            {"question_text": "Unit of electric current:", "option_a": "Volt", "option_b": "Ohm", "option_c": "Watt", "option_d": "Ampere", "correct_option": "D", "explanation": "Current is measured in Amperes (A).", "topic": "Electricity"},
            {"question_text": "Newton's first law is also called:", "option_a": "Law of Acceleration", "option_b": "Law of Inertia", "option_c": "Law of Action-Reaction", "option_d": "Law of Gravity", "correct_option": "B", "explanation": "First law: a body remains at rest or uniform motion unless acted upon by force — law of inertia.", "topic": "Mechanics"},
            {"question_text": "Pressure = Force ÷", "option_a": "Mass", "option_b": "Volume", "option_c": "Area", "option_d": "Density", "correct_option": "C", "explanation": "P = F/A (force per unit area)", "topic": "Pressure"},
            {"question_text": "Which wave does NOT need a medium?", "option_a": "Sound", "option_b": "Water waves", "option_c": "Electromagnetic", "option_d": "Seismic", "correct_option": "C", "explanation": "EM waves (light, radio) travel through vacuum; sound needs a medium.", "topic": "Waves"},
            {"question_text": "Power = Work ÷", "option_a": "Force", "option_b": "Distance", "option_c": "Mass", "option_d": "Time", "correct_option": "D", "explanation": "P = W/t (joules per second = Watts)", "topic": "Work and Energy"},
            {"question_text": "Convex lens is also called:", "option_a": "Diverging lens", "option_b": "Converging lens", "option_c": "Plane lens", "option_d": "Biconcave lens", "correct_option": "B", "explanation": "Convex (converging) lens brings parallel rays to a focus.", "topic": "Optics"},
            {"question_text": "A body in free fall has acceleration:", "option_a": "0 m/s²", "option_b": "5 m/s²", "option_c": "10 m/s²", "option_d": "Depends on mass", "correct_option": "C", "explanation": "g ≈ 10 m/s² (9.8 m/s²) near Earth's surface.", "topic": "Gravity"},
            {"question_text": "SI unit of temperature:", "option_a": "Celsius", "option_b": "Fahrenheit", "option_c": "Kelvin", "option_d": "Rankine", "correct_option": "C", "explanation": "SI unit is Kelvin (K); 0°C = 273 K.", "topic": "Thermal Physics"},
            {"question_text": "Transformer increases voltage by:", "option_a": "Increasing current", "option_b": "More turns on secondary coil", "option_c": "Less turns on secondary coil", "option_d": "Using DC current", "correct_option": "B", "explanation": "Step-up transformer: more turns on secondary → higher voltage.", "topic": "Electromagnetism"},
            {"question_text": "Alpha particles are:", "option_a": "High-energy electrons", "option_b": "Helium nuclei", "option_c": "Electromagnetic waves", "option_d": "Neutrons", "correct_option": "B", "explanation": "Alpha (α) particles = helium nuclei (2 protons, 2 neutrons).", "topic": "Radioactivity"},
        ],
    },
]

_ALL_CBT_EXAMS = _EXAMS + JAMB_EXAMS


async def seed_cbt_exams(db: AsyncSession) -> list[str]:
    """Seed WAEC, NECO, and JAMB exam data if not already present."""
    import re

    created = []
    for exam_data in _ALL_CBT_EXAMS:
        existing = await db.execute(
            select(CBTExam).where(CBTExam.title == exam_data["title"])
        )
        if existing.scalar_one_or_none():
            continue

        questions = exam_data["questions"]
        exam_fields = {k: v for k, v in exam_data.items() if k != "questions"}
        if exam_fields.get("year") is None:
            match = re.search(r"(20\d{2}|19\d{2})", str(exam_fields.get("title") or ""))
            if match:
                exam_fields["year"] = int(match.group(1))
        exam = CBTExam(
            **exam_fields,
            total_questions=len(questions),
            is_published=True,
        )
        db.add(exam)
        await db.flush()

        for q in questions:
            db.add(CBTQuestion(exam_id=exam.id, **q))

        created.append(exam.title)
        print(f"[seed] CBT Exam: {exam.title} ({len(questions)}Q)")
    return created


async def _seed_cbt_exams(db: AsyncSession):
    await seed_cbt_exams(db)
