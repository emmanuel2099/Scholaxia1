"""
One-time script: pushes JAMB exams to the live server via admin API.
Run: python seed_jamb.py
"""
import urllib.request, json, sys

BASE = "https://scholaxia1.onrender.com"
ADMIN_EMAIL = "admin@scholaxia.com"
ADMIN_PASS  = "ScholaxiaAdmin2026"


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
        return e.code, json.loads(e.read())


def get(path, token=None):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + path, headers=headers)
    try:
        r = urllib.request.urlopen(req, timeout=40)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


# ── Login ─────────────────────────────────────────────────────────────────────
print("Logging in as admin...")
s, r = post("/api/v1/auth/login", {"email": ADMIN_EMAIL, "password": ADMIN_PASS})
token = r.get("access_token", "")
if not token:
    print(f"Login failed: {r}")
    sys.exit(1)
print("Admin authenticated.\n")


# ── Check existing exams ──────────────────────────────────────────────────────
s, r = get("/api/v1/cbt/exams")
existing = [e["title"] for e in r] if isinstance(r, list) else []
print(f"Existing exams ({len(existing)}):")
for t in existing:
    print(f"  · {t}")
print()


# ── JAMB exam definitions ─────────────────────────────────────────────────────
JAMB_EXAMS = [
    {
        "title": "JAMB Mathematics 2023",
        "subject": "Mathematics",
        "exam_type": "JAMB",
        "duration_minutes": 30,
        "is_published": True,
        "questions": [
            {
                "question_text": "If log₂ 8 = x, find x.",
                "option_a": "2", "option_b": "3", "option_c": "4", "option_d": "8",
                "correct_option": "B",
                "explanation": "2^x = 8 = 2^3, so x = 3",
                "topic": "Logarithms"
            },
            {
                "question_text": "Find x if 2x + 3 = 4x - 5.",
                "option_a": "2", "option_b": "3", "option_c": "4", "option_d": "5",
                "correct_option": "C",
                "explanation": "2x + 3 = 4x - 5 → 8 = 2x → x = 4",
                "topic": "Algebra"
            },
            {
                "question_text": "A circle has circumference 44cm. Its radius (π = 22/7) is:",
                "option_a": "5 cm", "option_b": "6 cm", "option_c": "7 cm", "option_d": "8 cm",
                "correct_option": "C",
                "explanation": "C = 2πr → r = 44 / (2 × 22/7) = 44 × 7/44 = 7 cm",
                "topic": "Mensuration"
            },
            {
                "question_text": "Sum of interior angles of a hexagon:",
                "option_a": "540°", "option_b": "720°", "option_c": "900°", "option_d": "1080°",
                "correct_option": "B",
                "explanation": "(n-2) × 180 = (6-2) × 180 = 720°",
                "topic": "Geometry"
            },
            {
                "question_text": "If P = {1,2,3,4} and Q = {3,4,5,6}, find P∩Q.",
                "option_a": "{1,2,5,6}", "option_b": "{3,4}", "option_c": "{1,2,3,4,5,6}", "option_d": "{}",
                "correct_option": "B",
                "explanation": "Intersection = elements common to both sets: {3, 4}",
                "topic": "Set Theory"
            },
            {
                "question_text": "The derivative of f(x) = 3x² + 2x is:",
                "option_a": "3x + 2", "option_b": "6x + 2", "option_c": "6x", "option_d": "3x",
                "correct_option": "B",
                "explanation": "f'(x) = 6x + 2 by the power rule",
                "topic": "Calculus"
            },
            {
                "question_text": "How many ways can 4 people sit in a row of 4 chairs?",
                "option_a": "4", "option_b": "12", "option_c": "16", "option_d": "24",
                "correct_option": "D",
                "explanation": "4! = 4 × 3 × 2 × 1 = 24",
                "topic": "Permutation and Combination"
            },
            {
                "question_text": "Simplify: (√3 + 1)(√3 - 1)",
                "option_a": "2", "option_b": "3", "option_c": "4", "option_d": "√3",
                "correct_option": "A",
                "explanation": "(a+b)(a-b) = a² - b² = 3 - 1 = 2",
                "topic": "Surds"
            },
            {
                "question_text": "Range of: 4, 7, 2, 9, 1, 5",
                "option_a": "6", "option_b": "7", "option_c": "8", "option_d": "9",
                "correct_option": "C",
                "explanation": "Range = max - min = 9 - 1 = 8",
                "topic": "Statistics"
            },
            {
                "question_text": "If sin θ = 0.5, then θ =",
                "option_a": "30°", "option_b": "45°", "option_c": "60°", "option_d": "90°",
                "correct_option": "A",
                "explanation": "sin 30° = 0.5",
                "topic": "Trigonometry"
            },
            {
                "question_text": "Evaluate: ∫(2x + 3)dx",
                "option_a": "2x² + 3x", "option_b": "x² + 3x + C",
                "option_c": "2 + C", "option_d": "x² + C",
                "correct_option": "B",
                "explanation": "∫(2x + 3)dx = x² + 3x + C",
                "topic": "Calculus"
            },
            {
                "question_text": "The nth term of an AP with first term 3 and common difference 4 is:",
                "option_a": "4n - 1", "option_b": "3n + 4", "option_c": "4n + 3", "option_d": "3 + 4n",
                "correct_option": "A",
                "explanation": "Tn = a + (n-1)d = 3 + (n-1)4 = 3 + 4n - 4 = 4n - 1",
                "topic": "Sequences and Series"
            },
            {
                "question_text": "Solve the inequality: 2x - 5 > 9",
                "option_a": "x > 2", "option_b": "x > 7", "option_c": "x < 7", "option_d": "x > 14",
                "correct_option": "B",
                "explanation": "2x > 14 → x > 7",
                "topic": "Inequalities"
            },
            {
                "question_text": "The LCM of 12 and 18 is:",
                "option_a": "6", "option_b": "18", "option_c": "36", "option_d": "72",
                "correct_option": "C",
                "explanation": "12 = 2²×3, 18 = 2×3². LCM = 2²×3² = 36",
                "topic": "Number Theory"
            },
            {
                "question_text": "If 3^(2x) = 81, find x.",
                "option_a": "1", "option_b": "2", "option_c": "3", "option_d": "4",
                "correct_option": "B",
                "explanation": "81 = 3^4, so 3^(2x) = 3^4 → 2x = 4 → x = 2",
                "topic": "Indices"
            },
        ],
    },
    {
        "title": "JAMB English Language 2023",
        "subject": "English Language",
        "exam_type": "JAMB",
        "duration_minutes": 30,
        "is_published": True,
        "questions": [
            {
                "question_text": "Correct plural of 'phenomenon':",
                "option_a": "Phenomenons", "option_b": "Phenomenon",
                "option_c": "Phenomena", "option_d": "Phenomenas",
                "correct_option": "C",
                "explanation": "Greek-origin word; plural is 'phenomena'.",
                "topic": "Grammar"
            },
            {
                "question_text": "'AMELIORATE' means:",
                "option_a": "Worsen", "option_b": "Improve", "option_c": "Ignore", "option_d": "Repeat",
                "correct_option": "B",
                "explanation": "Ameliorate = make something bad better; improve.",
                "topic": "Vocabulary"
            },
            {
                "question_text": "Identify the gerund in: 'Swimming is my hobby.'",
                "option_a": "is", "option_b": "my", "option_c": "Swimming", "option_d": "hobby",
                "correct_option": "C",
                "explanation": "A gerund is a verb used as a noun. 'Swimming' is the subject here.",
                "topic": "Parts of Speech"
            },
            {
                "question_text": "Correct spelling:",
                "option_a": "Recieve", "option_b": "Receive", "option_c": "Receeve", "option_d": "Recive",
                "correct_option": "B",
                "explanation": "'i before e except after c' → Receive.",
                "topic": "Spelling"
            },
            {
                "question_text": "Correct indirect speech for: 'I am tired.'",
                "option_a": "She said she is tired.",
                "option_b": "She said she was tired.",
                "option_c": "She said she were tired.",
                "option_d": "She said she be tired.",
                "correct_option": "B",
                "explanation": "Backshift tense in reported speech: 'am' → 'was'.",
                "topic": "Reported Speech"
            },
            {
                "question_text": "Rhyme scheme ABAB CDCD EFEF GG is a:",
                "option_a": "Sonnet", "option_b": "Haiku", "option_c": "Ballad", "option_d": "Ode",
                "correct_option": "A",
                "explanation": "Shakespearean sonnet: three quatrains + a couplet.",
                "topic": "Poetry"
            },
            {
                "question_text": "'PROLIFIC' means:",
                "option_a": "Lazy", "option_b": "Producing much output", "option_c": "Dangerous", "option_d": "Expensive",
                "correct_option": "B",
                "explanation": "Prolific = producing many works, results, or offspring.",
                "topic": "Vocabulary"
            },
            {
                "question_text": "Correct punctuation:",
                "option_a": 'He said, I will come.',
                "option_b": 'He said; "I will come."',
                "option_c": 'He said, "I will come."',
                "option_d": 'He said: I will come.',
                "correct_option": "C",
                "explanation": "Direct speech: comma before quote, quote marks around spoken words.",
                "topic": "Punctuation"
            },
            {
                "question_text": "'LACONIC' means:",
                "option_a": "Very talkative", "option_b": "Using few words",
                "option_c": "Unclear", "option_d": "Angry",
                "correct_option": "B",
                "explanation": "Laconic = brief and concise in speech or expression.",
                "topic": "Vocabulary"
            },
            {
                "question_text": "Choose the sentence with correct subject-verb agreement:",
                "option_a": "The committee have made their decision.",
                "option_b": "The committee has made its decision.",
                "option_c": "The committee are making their decision.",
                "option_d": "The committee were making its decision.",
                "correct_option": "B",
                "explanation": "Collective noun 'committee' takes singular verb 'has' when acting as one body.",
                "topic": "Grammar"
            },
            {
                "question_text": "A word that imitates a sound is called:",
                "option_a": "Alliteration", "option_b": "Onomatopoeia", "option_c": "Assonance", "option_d": "Metaphor",
                "correct_option": "B",
                "explanation": "Onomatopoeia = words that phonetically imitate the sound they describe (e.g. buzz, hiss).",
                "topic": "Figures of Speech"
            },
            {
                "question_text": "Choose the antonym of 'DILIGENT':",
                "option_a": "Hardworking", "option_b": "Careful", "option_c": "Lazy", "option_d": "Honest",
                "correct_option": "C",
                "explanation": "Diligent means hardworking. Antonym: lazy.",
                "topic": "Antonyms"
            },
        ],
    },
    {
        "title": "JAMB Biology 2023",
        "subject": "Biology",
        "exam_type": "JAMB",
        "duration_minutes": 30,
        "is_published": True,
        "questions": [
            {
                "question_text": "Organelle responsible for protein synthesis:",
                "option_a": "Mitochondria", "option_b": "Ribosome",
                "option_c": "Nucleus", "option_d": "Vacuole",
                "correct_option": "B",
                "explanation": "Ribosomes translate mRNA into proteins.",
                "topic": "Cell Biology"
            },
            {
                "question_text": "Hormone that regulates blood glucose:",
                "option_a": "Adrenaline", "option_b": "Thyroxine",
                "option_c": "Insulin", "option_d": "Oestrogen",
                "correct_option": "C",
                "explanation": "Insulin (from pancreas) lowers blood glucose by promoting cellular uptake.",
                "topic": "Hormones"
            },
            {
                "question_text": "Vitamin that prevents scurvy:",
                "option_a": "Vitamin A", "option_b": "Vitamin B",
                "option_c": "Vitamin C", "option_d": "Vitamin D",
                "correct_option": "C",
                "explanation": "Vitamin C (ascorbic acid) deficiency causes scurvy.",
                "topic": "Nutrition"
            },
            {
                "question_text": "Breaking down glucose to release energy is called:",
                "option_a": "Photosynthesis", "option_b": "Fermentation",
                "option_c": "Respiration", "option_d": "Digestion",
                "correct_option": "C",
                "explanation": "Cellular respiration: C₆H₁₂O₆ + O₂ → CO₂ + H₂O + ATP",
                "topic": "Respiration"
            },
            {
                "question_text": "Male reproductive cell:",
                "option_a": "Ovum", "option_b": "Zygote", "option_c": "Sperm", "option_d": "Embryo",
                "correct_option": "C",
                "explanation": "Sperm is the male gamete; ovum is the female gamete.",
                "topic": "Reproduction"
            },
            {
                "question_text": "Mushrooms belong to kingdom:",
                "option_a": "Plantae", "option_b": "Animalia", "option_c": "Fungi", "option_d": "Protista",
                "correct_option": "C",
                "explanation": "Mushrooms are fungi — absorb nutrients from decomposing matter.",
                "topic": "Classification"
            },
            {
                "question_text": "Malaria is caused by:",
                "option_a": "Bacteria", "option_b": "Virus", "option_c": "Plasmodium", "option_d": "Fungus",
                "correct_option": "C",
                "explanation": "Plasmodium parasite, transmitted via Anopheles mosquito bite.",
                "topic": "Diseases"
            },
            {
                "question_text": "Fluid that transports food in plants:",
                "option_a": "Blood", "option_b": "Xylem sap", "option_c": "Phloem sap", "option_d": "Lymph",
                "correct_option": "C",
                "explanation": "Phloem transports sugars from leaves to other plant parts.",
                "topic": "Transport in Plants"
            },
            {
                "question_text": "The process by which cells divide to form gametes:",
                "option_a": "Mitosis", "option_b": "Meiosis", "option_c": "Budding", "option_d": "Fission",
                "correct_option": "B",
                "explanation": "Meiosis reduces chromosome number by half to produce gametes (sperm/eggs).",
                "topic": "Cell Division"
            },
            {
                "question_text": "The largest organ in the human body is:",
                "option_a": "Liver", "option_b": "Brain", "option_c": "Skin", "option_d": "Lungs",
                "correct_option": "C",
                "explanation": "The skin (integumentary system) is the largest organ by surface area and weight.",
                "topic": "Human Body"
            },
            {
                "question_text": "Which of the following is NOT a greenhouse gas?",
                "option_a": "Carbon dioxide", "option_b": "Methane",
                "option_c": "Nitrogen", "option_d": "Water vapour",
                "correct_option": "C",
                "explanation": "Nitrogen (N₂) makes up ~78% of air but is NOT a greenhouse gas.",
                "topic": "Ecology"
            },
            {
                "question_text": "The part of the nephron that reabsorbs water:",
                "option_a": "Bowman's capsule", "option_b": "Loop of Henle",
                "option_c": "Glomerulus", "option_d": "Collecting duct",
                "correct_option": "D",
                "explanation": "The collecting duct reabsorbs water under the influence of ADH (antidiuretic hormone).",
                "topic": "Excretion"
            },
        ],
    },
    {
        "title": "JAMB Chemistry 2023",
        "subject": "Chemistry",
        "exam_type": "JAMB",
        "duration_minutes": 30,
        "is_published": True,
        "questions": [
            {
                "question_text": "Atomic number of Carbon:",
                "option_a": "4", "option_b": "6", "option_c": "8", "option_d": "12",
                "correct_option": "B",
                "explanation": "Carbon has 6 protons — atomic number 6.",
                "topic": "Atomic Structure"
            },
            {
                "question_text": "Noble gas in Group 18:",
                "option_a": "Nitrogen", "option_b": "Chlorine", "option_c": "Argon", "option_d": "Oxygen",
                "correct_option": "C",
                "explanation": "Argon (Ar) is in Group 18 — the noble/inert gases.",
                "topic": "Periodic Table"
            },
            {
                "question_text": "pH of a neutral solution:",
                "option_a": "0", "option_b": "5", "option_c": "7", "option_d": "14",
                "correct_option": "C",
                "explanation": "Pure water is neutral with pH 7.",
                "topic": "Acids and Bases"
            },
            {
                "question_text": "Bond formed by sharing electrons:",
                "option_a": "Ionic bond", "option_b": "Metallic bond",
                "option_c": "Covalent bond", "option_d": "Hydrogen bond",
                "correct_option": "C",
                "explanation": "Covalent bonds form by sharing electron pairs between atoms.",
                "topic": "Chemical Bonding"
            },
            {
                "question_text": "Chemical formula of water:",
                "option_a": "HO", "option_b": "H₂O", "option_c": "H₂O₂", "option_d": "OH",
                "correct_option": "B",
                "explanation": "Water = H₂O: two hydrogen atoms bonded to one oxygen.",
                "topic": "Chemical Formulae"
            },
            {
                "question_text": "Burning of fuel is a _____ reaction.",
                "option_a": "Endothermic", "option_b": "Photosynthetic",
                "option_c": "Exothermic", "option_d": "Decomposition",
                "correct_option": "C",
                "explanation": "Combustion releases heat energy — it is exothermic.",
                "topic": "Energy Changes"
            },
            {
                "question_text": "Which is a mixture?",
                "option_a": "Water", "option_b": "Salt", "option_c": "Air", "option_d": "Copper",
                "correct_option": "C",
                "explanation": "Air is a mixture of N₂ (~78%), O₂ (~21%), and other gases.",
                "topic": "Mixtures"
            },
            {
                "question_text": "Number of moles in 44g of CO₂ (M = 44 g/mol):",
                "option_a": "0.5", "option_b": "1", "option_c": "2", "option_d": "44",
                "correct_option": "B",
                "explanation": "Moles = mass/M = 44/44 = 1 mol",
                "topic": "Mole Concept"
            },
            {
                "question_text": "The most reactive metal in the reactivity series:",
                "option_a": "Gold", "option_b": "Iron", "option_c": "Potassium", "option_d": "Zinc",
                "correct_option": "C",
                "explanation": "Potassium (K) is at the top of the reactivity series — extremely reactive.",
                "topic": "Reactivity Series"
            },
            {
                "question_text": "Electrolysis of brine produces at the cathode:",
                "option_a": "Chlorine gas", "option_b": "Hydrogen gas",
                "option_c": "Oxygen gas", "option_d": "Sodium metal",
                "correct_option": "B",
                "explanation": "At cathode: 2H⁺ + 2e⁻ → H₂. Chlorine is produced at the anode.",
                "topic": "Electrolysis"
            },
            {
                "question_text": "Type of isomerism shown by CH₃CH₂OH and CH₃OCH₃:",
                "option_a": "Chain isomerism", "option_b": "Position isomerism",
                "option_c": "Functional group isomerism", "option_d": "Geometric isomerism",
                "correct_option": "C",
                "explanation": "Same molecular formula (C₂H₆O) but different functional groups (alcohol vs ether).",
                "topic": "Organic Chemistry"
            },
            {
                "question_text": "Rusting of iron is an example of:",
                "option_a": "Reduction", "option_b": "Oxidation", "option_c": "Neutralisation", "option_d": "Sublimation",
                "correct_option": "B",
                "explanation": "Iron gains oxygen to form iron oxide (rust) — this is oxidation.",
                "topic": "Oxidation and Reduction"
            },
        ],
    },
    {
        "title": "JAMB Physics 2023",
        "subject": "Physics",
        "exam_type": "JAMB",
        "duration_minutes": 30,
        "is_published": True,
        "questions": [
            {
                "question_text": "The SI unit of force is:",
                "option_a": "Joule", "option_b": "Watt", "option_c": "Newton", "option_d": "Pascal",
                "correct_option": "C",
                "explanation": "Force is measured in Newtons (N). F = ma.",
                "topic": "Mechanics"
            },
            {
                "question_text": "Speed of light in a vacuum:",
                "option_a": "3 × 10⁶ m/s", "option_b": "3 × 10⁸ m/s",
                "option_c": "3 × 10¹⁰ m/s", "option_d": "3 × 10⁴ m/s",
                "correct_option": "B",
                "explanation": "c ≈ 3 × 10⁸ m/s",
                "topic": "Waves and Light"
            },
            {
                "question_text": "Work done = Force × ___",
                "option_a": "Time", "option_b": "Mass", "option_c": "Distance", "option_d": "Velocity",
                "correct_option": "C",
                "explanation": "W = F × d (force times displacement in direction of force)",
                "topic": "Work and Energy"
            },
            {
                "question_text": "Ohm's Law states that V =",
                "option_a": "I/R", "option_b": "IR", "option_c": "I + R", "option_d": "R/I",
                "correct_option": "B",
                "explanation": "V = IR (Voltage = Current × Resistance)",
                "topic": "Electricity"
            },
            {
                "question_text": "The unit of electrical resistance is:",
                "option_a": "Volt", "option_b": "Ampere", "option_c": "Ohm", "option_d": "Watt",
                "correct_option": "C",
                "explanation": "Resistance is measured in Ohms (Ω).",
                "topic": "Electricity"
            },
            {
                "question_text": "A body of mass 2kg moving at 5m/s has kinetic energy of:",
                "option_a": "5 J", "option_b": "10 J", "option_c": "25 J", "option_d": "50 J",
                "correct_option": "C",
                "explanation": "KE = ½mv² = ½ × 2 × 5² = ½ × 2 × 25 = 25 J",
                "topic": "Work and Energy"
            },
            {
                "question_text": "The frequency of a wave with period 0.02s is:",
                "option_a": "2 Hz", "option_b": "20 Hz", "option_c": "50 Hz", "option_d": "100 Hz",
                "correct_option": "C",
                "explanation": "f = 1/T = 1/0.02 = 50 Hz",
                "topic": "Waves"
            },
            {
                "question_text": "Boyle's Law states that pressure is _____ proportional to volume at constant temperature.",
                "option_a": "Directly", "option_b": "Inversely",
                "option_c": "Not", "option_d": "Equally",
                "correct_option": "B",
                "explanation": "P₁V₁ = P₂V₂ — pressure and volume are inversely proportional.",
                "topic": "Gas Laws"
            },
            {
                "question_text": "Which type of mirror is used in car headlights?",
                "option_a": "Plane", "option_b": "Concave", "option_c": "Convex", "option_d": "Parabolic",
                "correct_option": "D",
                "explanation": "Parabolic (concave) mirrors focus light into a parallel beam in headlights.",
                "topic": "Optics"
            },
            {
                "question_text": "The half-life of a radioactive substance is the time for half the nuclei to:",
                "option_a": "Double", "option_b": "Decay",
                "option_c": "Split", "option_d": "Form",
                "correct_option": "B",
                "explanation": "Half-life = time for half the radioactive nuclei to decay.",
                "topic": "Radioactivity"
            },
        ],
    },
]


# ── Push each exam ────────────────────────────────────────────────────────────
created = 0
skipped = 0

for exam in JAMB_EXAMS:
    if exam["title"] in existing:
        print(f"  [SKIP] {exam['title']} — already exists")
        skipped += 1
        continue

    s, r = post("/api/v1/admin/cbt/exams", exam, token=token)
    if s in (200, 201):
        print(f"  [OK]   {exam['title']} — {r.get('total_questions')}Q created (id: {r.get('id', '')[:8]}...)")
        created += 1
    else:
        print(f"  [FAIL] {exam['title']} — HTTP {s}: {r.get('detail', r)}")

print(f"\nDone. Created: {created}  Skipped: {skipped}")

# ── Verify final state ────────────────────────────────────────────────────────
print("\nAll exams now on server:")
s, r = get("/api/v1/cbt/exams")
for e in sorted(r, key=lambda x: x["exam_type"]):
    print(f"  {e['exam_type']:6} | {e['subject']:20} | {e['title']:40} | {e['total_questions']}Q")
