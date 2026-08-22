"""Shared subject list for exam setup and filtering."""

AVAILABLE_SUBJECTS = [
    "Mathematics",
    "English Language",
    "Biology",
    "Chemistry",
    "Physics",
    "Economics",
    "Government",
    "Geography",
    "Literature in English",
    "Agricultural Science",
    "Commerce",
    "Christian Religious Studies",
    "Islamic Religious Studies",
    "Further Mathematics",
    "Citizenship and Heritage Studies (Civic)",
]


def subject_matches(exam_subject: str, selected_subjects: list[str]) -> bool:
    """Flexible match: 'English' matches 'English Language', 'Maths' matches 'Mathematics'."""
    if not selected_subjects:
        return True
    exam_s = (exam_subject or "").lower().strip()
    aliases = {
        "math": "mathematics",
        "maths": "mathematics",
        "further math": "further mathematics",
        "further maths": "further mathematics",
        "english": "english language",
        "agric": "agricultural science",
        "agriculture": "agricultural science",
        "crs": "christian religious studies",
        "c.r.s": "christian religious studies",
        "c.r.s.": "christian religious studies",
        "christian religious studies": "christian religious studies",
        "irs": "islamic religious studies",
        "i.r.s": "islamic religious studies",
        "i.r.s.": "islamic religious studies",
        "islamic religious studies": "islamic religious studies",
        "literature": "literature in english",
        "lit": "literature in english",
        "literature-in-english": "literature in english",
        "civic": "citizenship and heritage studies (civic)",
        "civic education": "citizenship and heritage studies (civic)",
        "citizenship and heritage studies (civic)": "citizenship and heritage studies (civic)",
        "econs": "economics",
        "govt": "government",
        "geo": "geography",
    }
    exam_norm = aliases.get(exam_s, exam_s)
    for s in selected_subjects:
        sl = (s or "").lower().strip()
        sl_norm = aliases.get(sl, sl)
        if (
            exam_norm == sl_norm
            or exam_s == sl
            or exam_s in sl
            or sl in exam_s
            or exam_norm in sl_norm
            or sl_norm in exam_norm
        ):
            return True
    return False
