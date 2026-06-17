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
    """Flexible match: 'English' matches 'English Language'."""
    if not selected_subjects:
        return True
    exam_s = (exam_subject or "").lower().strip()
    for s in selected_subjects:
        sl = (s or "").lower().strip()
        if exam_s == sl or exam_s in sl or sl in exam_s:
            return True
    return False
