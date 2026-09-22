"""Report-card PDF: photo, school name, QR verification code.

Built with reportlab + qrcode (added to requirements). Renders one A4
portrait sheet per student-term: header with school name, student photo,
subject table (CA/exam/total/grade/position) and a summary.
"""
from __future__ import annotations

import io

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.school_campus import SchoolCampus
from app.models.school_results import SchoolResult
from app.models.user import User


async def _student_photo_bytes(user: User) -> bytes | None:
    """Inline the student photo if profile_picture is a local URL we served."""
    import httpx

    url = (getattr(user, "profile_picture", None) or "").strip()
    if not url:
        return None
    try:
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            resp = await client.get(url)
            if resp.status_code == 200 and resp.headers.get("content-type", "").startswith("image"):
                return resp.content
    except Exception:
        pass
    return None


def _qr_png(data: str) -> bytes:
    import qrcode

    img = qrcode.make(data)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


async def build_report_card_pdf(
    db: AsyncSession,
    *,
    school: SchoolCampus,
    student: User,
    term_label: str,
    results: list[SchoolResult],
) -> tuple[bytes, str]:
    """Return (pdf_bytes, suggested_filename)."""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        Image,
        PageBreak,
        Paragraph,
        SimpleDocTemplate,
        Spacer,
        Table,
        TableStyle,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("schoolday", parent=styles["Title"], fontSize=18, spaceAfter=2)
    sub_style = ParagraphStyle("sub", parent=styles["Normal"], fontSize=11, textColor=colors.HexColor("#444444"))

    grand_total = sum(float(r.total) for r in results)
    average = grand_total / len(results) if results else 0

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        title=f"Report card — {student.full_name}",
        author=school.name,
    )

    story: list = []
    # Header: school name + term, logo placeholder box
    story.append(Paragraph(school.name or "School", title_style))
    meta_line = f"{term_label}"
    if results and results[0].class_name:
        meta_line = f"{results[0].class_name} &nbsp;|&nbsp; {meta_line}"
    if school.city or school.state:
        meta_line += f" &nbsp;|&nbsp; {school.city or ''} {school.state or ''}".rstrip()
    story.append(Paragraph(meta_line, sub_style))
    story.append(Spacer(1, 6 * mm))

    # Student info table: photo left, details right
    photo_bytes = await _student_photo_bytes(student)
    photo_cell = ""
    if photo_bytes:
        try:
            photo_cell = Image(io.BytesIO(photo_bytes), width=28 * mm, height=28 * mm)
        except Exception:
            photo_cell = ""
    info_rows = [
        [photo_cell, Paragraph(f"<b>{student.full_name}</b>", styles["Heading3"])],
        ["", Paragraph(f"Term: {term_label}", styles["Normal"])],
    ]
    info_table = Table(info_rows, colWidths=[32 * mm, 120 * mm])
    info_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#CCCCCC")),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 6 * mm))

    # Subjects table
    header = ["Subject", "CA", "Exam", "Total", "Grade", "Position", "Remark"]
    data = [header]
    for r in sorted(results, key=lambda x: x.subject):
        data.append([
            r.subject,
            f"{float(r.ca_score):g}",
            f"{float(r.exam_score):g}",
            f"{float(r.total):g}",
            r.grade or "",
            r.position or "",
            (r.remark or "")[:40],
        ])
    table = Table(data, colWidths=[45 * mm, 18 * mm, 22 * mm, 22 * mm, 20 * mm, 22 * mm, 24 * mm])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1F4E79")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ALIGN", (1, 0), (-1, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F2F6FA")]),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
        ("TOPPADDING", (0, 0), (-1, 0), 6),
    ]))
    story.append(table)
    story.append(Spacer(1, 6 * mm))

    # Summary + QR verification
    verify_code = f"SCHOLAXIA-VERIFY|{school.slug or school.id}|{student.id}|{term_label}"
    qr_cell = ""
    try:
        qr_cell = Image(io.BytesIO(_qr_png(verify_code)), width=22 * mm, height=22 * mm)
    except Exception:
        qr_cell = ""
    summary = Paragraph(
        f"<b>Subjects:</b> {len(results)} &nbsp;&nbsp; "
        f"<b>Grand total:</b> {grand_total:.1f} &nbsp;&nbsp; "
        f"<b>Average:</b> {average:.1f}%<br/><br/>"
        f"Scan to verify this result.<br/>"
        f"<font size='7' color='#777777'>{verify_code}</font>",
        styles["Normal"],
    )
    summary_table = Table([[summary, qr_cell]], colWidths=[135 * mm, 32 * mm])
    summary_table.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
    story.append(summary_table)

    doc.build(story)
    pdf_bytes = buffer.getvalue()
    safe_name = "".join(c for c in (student.full_name or "student") if c.isalnum() or c in "-_ ").strip() or "student"
    filename = f"report-{safe_name.replace(' ', '-')}-{term_label.replace('/', '-')}.pdf"
    return pdf_bytes, filename
