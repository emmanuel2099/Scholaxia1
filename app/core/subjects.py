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
    "Literature",
    "Agricultural Science",
    "Commerce",
    "CRS",
    "IRS",
    "Further Mathematics",
    "Civic Education",
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
        "c.r.s": "crs",
        "c.r.s.": "crs",
        "i.r.s": "irs",
        "i.r.s.": "irs",
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
