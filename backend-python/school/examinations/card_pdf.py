"""The printed admit card (docs/examinations.md), after the prototype
`school365ai_exam_admit_card_prototype.html`: A4 portrait.

- **Header.** The school's logo, name, address and the academic session.
- **Title.** "EXAMINATION ADMIT CARD", then the exam, the term, and when this version was issued.
- **Student block.** Name, admission no, class and section that year, roll no, guardian (a father or mother where a Family-app link names one), centre, reporting time, and the student's photo in its box (docs/student-photos.md), or the empty box where there is none.
- **The date sheet.** The papers the student's class sits, with the table header repeated on a new page.
- **The rest.** The school's instructions, and the signature lines.

Two looks: `classic` (light-blue bands) and `mono` (black on white, for a
school's own printer). No QR code, seat number or signature image: the
product has no verification service, seating plan or signature store, and a
card that pretended otherwise would be a forgery waiting to happen.

Every exam fact is read from a frozen version (service.py) - never from the
live tables - so a reprint says what was issued. A school previewing a draft
gets the live sheet under a DRAFT banner, which no parent can download.
"""

from __future__ import annotations

from dataclasses import dataclass

from .. import pdf_design, student_photos
from ..models import StudentEnrollment
from ..parent_names import parent_names
from ..receipts import e
from .service import date_label, time_label

INK = "#171717"


@dataclass(frozen=True)
class Card:
    student: object
    snapshot: dict
    class_id: int
    version: int | None  # None for a draft preview
    issued_on: str | None  # school-local date of the version, already formatted


def styles(mono: bool) -> str:
    band = "#ffffff" if mono else "#c9dfef"
    band_line = "#333333" if mono else "#6e91a9"
    band_ink = "#111111" if mono else "#183d5e"
    head_line = "#333333" if mono else "#31597f"
    name_ink = "#111111" if mono else "#1d4168"
    table_head = "#ffffff" if mono else "#e2eff9"

    return f"""
@page {{ size: a4 portrait; margin: 1.1cm 1.3cm 1.1cm 1.3cm; }}
body {{ font-family: Helvetica, sans-serif; font-size: 9.5pt; color: {INK}; }}
table {{ width: 100%; border-collapse: collapse; }}
td, th {{ vertical-align: top; }}
.head td {{ border-bottom: 2px solid {head_line}; padding-bottom: 7px; vertical-align: middle; }}
.head .side {{ width: 64px; }}
.head .middle {{ text-align: center; }}
.school {{ font-size: 17pt; font-weight: bold; color: {name_ink}; }}
.addr {{ font-size: 8.5pt; font-weight: bold; padding-top: 3px; }}
.title td {{ background-color: {band}; border: 1px solid {band_line}; color: {band_ink}; text-align: center;
    font-size: 13pt; font-weight: bold; letter-spacing: 1px; padding: 6px; }}
.meta td {{ font-size: 9pt; padding: 7px 0 9px 0; }}
.meta .right {{ text-align: right; }}
.block td.b-left {{ border-top: 1px solid #777777; border-bottom: 1px solid #777777;
    border-left: 1px solid #777777; padding: 7px 4px 7px 8px; }}
.block td.b-mid {{ border-top: 1px solid #777777; border-bottom: 1px solid #777777; padding: 7px 4px; }}
.block td.b-right {{ border-top: 1px solid #777777; border-bottom: 1px solid #777777;
    border-right: 1px solid #777777; padding: 7px 8px 7px 4px; }}
.pairs td {{ padding: 3px 0; font-size: 9pt; }}
.pairs .k {{ width: 98px; font-weight: bold; }}
.pairs .colon {{ width: 8px; font-weight: bold; }}
.photo td {{ border: 1px solid #777777; background-color: #eef2f5; color: #57616c; text-align: center;
    vertical-align: middle; font-size: 7.5pt; height: 96px; }}
.sheet th {{ background-color: {table_head}; border: 1px solid #606060; padding: 6px 6px; text-align: left;
    font-size: 9pt; }}
.sheet td {{ border: 1px solid #606060; padding: 6px 6px; font-size: 9pt; }}
.sheet .no {{ text-align: center; }}
.box td {{ border: 1px solid #858585; padding: 7px 10px; font-size: 9pt; }}
.box-title {{ font-weight: bold; font-size: 9pt; padding-bottom: 4px; }}
.sign td {{ border-top: 1px solid #333333; text-align: center; font-weight: bold; font-size: 9pt; padding-top: 5px; }}
.foot {{ font-size: 7.5pt; color: #555555; text-align: center; padding-top: 10px; }}
.draft td {{ border: 2px solid #b91c1c; color: #b91c1c; text-align: center; font-weight: bold; font-size: 11pt;
    padding: 5px; }}
"""


def spacer(height: int) -> str:
    return f'<table><tr><td style="height: {height}px; font-size: 1pt;">&nbsp;</td></tr></table>'


def header(school, logo: str | None, session: str) -> str:
    size = pdf_design.logo_size(logo) if logo else None
    image = ""

    if size:
        width = min(size[0], 56)
        image = f'<img src="{logo}" width="{width}" height="{round(size[1] * width / size[0])}">'

    address = pdf_design.joined(school.address, school.city, school.state)

    return f"""
    <table class="head"><tr>
        <td class="side">{image}</td>
        <td class="middle">
            <div class="school">{e(school.name.upper())}</div>
            {f'<div class="addr">{e(address)}</div>' if address else ""}
            {f'<div class="addr">Phone: {e(school.phone)}</div>' if school.phone else ""}
            <div class="addr">Academic Session: {e(session)}</div>
        </td>
        <td class="side"></td>
    </tr></table>"""


def pair(key: str, value) -> str:
    shown = "-" if value in (None, "") else e(value)
    return f'<tr><td class="k">{e(key)}</td><td class="colon">:</td><td>{shown}</td></tr>'


def student_rows(card: Card, year_id: int) -> tuple[list, list]:
    student = card.student
    enrollment = (
        StudentEnrollment.objects.select_related("class_section")
        .filter(student_id=student.id, academic_year_id=year_id).first()
    )
    section = enrollment.class_section.name if enrollment is not None and enrollment.class_section_id else None
    class_name = card.snapshot["classes"][str(card.class_id)]["name"]
    roll = (enrollment.roll_number if enrollment is not None else None) or student.roll_number
    parent_label, parent = parent_names(student).first_line()
    reporting = card.snapshot.get("reporting_time")

    left = [
        ("Student Name", student.name),
        ("Class / Section", " - ".join(part for part in (class_name, section) if part)),
        (parent_label, parent),
        ("Exam Centre", card.snapshot.get("centre")),
    ]
    right = [
        ("Admission No.", student.admission_number),
        ("Roll Number", roll),
        ("Reporting Time", time_label(reporting) if reporting else None),
        ("Session", card.snapshot.get("year")),
    ]

    return left, right


def one_card(card: Card, school, logo: str | None, year_id: int, *, mono: bool = False) -> str:
    snap = card.snapshot
    papers = snap["classes"][str(card.class_id)]["papers"]
    left, right = student_rows(card, year_id)
    title = pdf_design.joined(snap["name"], snap.get("term"), separator=" - ")
    issued = (
        f"Version {card.version} - issued {e(card.issued_on)}" if card.version is not None
        else "Draft - not issued"
    )

    rows = "".join(
        f'<tr><td class="no">{index}</td><td>{e(date_label(paper["date"]))}</td><td>{e(paper["subject"])}</td>'
        f'<td>{e(time_label(paper["start"]))} - {e(time_label(paper["end"]))}</td></tr>'
        for index, paper in enumerate(papers, start=1)
    )
    instructions = "".join(f"<li>{e(line)}</li>" for line in snap.get("instructions") or [])
    # The student's photo (docs/student-photos.md, P3), grey on a
    # black-and-white card; the empty box as before when there is none.
    photo = student_photos.photo_cell(card.student, placeholder="Student<br/>photo", width=72, grey=mono)
    draft = (
        f'{spacer(4)}<table class="draft"><tr><td>DRAFT - NOT ISSUED. Publish the exam before handing out admit '
        f"cards.</td></tr></table>" if card.version is None else ""
    )

    return f"""
    {header(school, logo, snap.get("year") or "")}
    {spacer(10)}
    <table class="title"><tr><td>EXAMINATION ADMIT CARD</td></tr></table>
    {draft}
    <table class="meta"><tr><td><b>{e(title)}</b></td><td class="right">{issued}</td></tr></table>
    <table class="block"><tr>
        <td class="b-left" width="45%"><table class="pairs">{"".join(pair(k, v) for k, v in left)}</table></td>
        <td class="b-mid" width="39%"><table class="pairs">{"".join(pair(k, v) for k, v in right)}</table></td>
        <td class="b-right" width="16%"><table class="photo"><tr><td>{photo}</td></tr></table></td>
    </tr></table>
    {spacer(10)}
    <table class="sheet" repeat="1">
        <tr><th class="no" width="8%">No.</th><th width="24%">Date</th><th width="40%">Subject / Paper</th>
            <th width="28%">Time</th></tr>
        {rows}
    </table>
    {spacer(10) + '<table class="box"><tr><td><div class="box-title">Instructions to Students</div><ol>' + instructions + '</ol></td></tr></table>' if instructions else ""}
    {spacer(56)}
    <table><tr>
        <td style="width: 34%"><table class="sign"><tr><td>Class Teacher</td></tr></table></td>
        <td style="width: 32%"></td>
        <td style="width: 34%"><table class="sign"><tr><td>Principal / Exam Controller</td></tr></table></td>
    </tr></table>
    <div class="foot">{e(school.name)} - {e(snap["name"])} - admit card for {e(card.student.name)}. Not valid without the school's signature.</div>"""


def document(cards: list[Card], *, school, year_id: int) -> str:
    """One or many cards, each starting on its own sheet."""
    logo = pdf_design.stored_logo_data_uri(school) or pdf_design.logo_data_uri(school.logo_url)
    mono = bool(cards) and cards[0].snapshot.get("card_style") == "mono"
    body = "<pdf:nextpage />".join(one_card(card, school, logo, year_id, mono=mono) for card in cards)

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Admit card</title><style>{styles(mono)}</style></head>
<body>{body}</body></html>"""


def render(cards: list[Card], *, school, year_id: int) -> bytes:
    return pdf_design.render(document(cards, school=school, year_id=year_id), "admit-cards.pdf")


def file_name(exam_name: str, who: str) -> str:
    def slug(value) -> str:
        kept = [c if str(c).isalnum() else "-" for c in str(value)]
        return "-".join(part for part in "".join(kept).lower().split("-") if part) or "card"

    return f"admit-card-{slug(exam_name)}-{slug(who)}.pdf"

