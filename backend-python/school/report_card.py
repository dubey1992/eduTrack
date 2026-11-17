"""What the classic printed report card says (docs/document-styles.md, decided
2026-11-17): every term of the year side by side, each test's marks, the
totals, the grade by the school's own grading system, the result and - when
the school asks - the rank.

**The figures are raw marks added up**, as a printed marksheet adds them:
F.A.-I 19 + F.A.-II 19 + Notebook 8 + S.A.-I 41 = 87 out of 100. That is the
classic card's rule only. The screens and the standard progress report keep
their average of percentages (school/marks.py), and nothing here changes a
stored mark or grade.

Rules a sum needs that the average already had:

- **Only published results count**, as everywhere (school/performance.py).
- **Absent is not zero.** A test the student missed prints "AB" and leaves
  both the marks obtained and the marks possible, so the total is out of what
  the student sat.
- **A test is a column by its title.** Teachers name a term's tests -
  "F.A.-I", "Notebook", "S.A.-I" - and the card lays them out in the order
  they were first held. A subject that had no such test prints a dash.

How a total is graded follows the scale's kind (GradeScaleKind):

- `percentage`: the grade of the band the percentage reaches.
- `gpa`: the same band, and its grade points; a GPA is the mean of the
  subjects' points.
- `grades`: grades only - the card prints no marks and no percentages.

The result follows the school's `result_rule`, and the pass mark is the
Assessments module's `pass_percentage` - the line promotion already reads
(school/promotion.py). On a grades-only scale, where there is no percentage
to read against a pass mark, a failing band is what fails.

The computing (`summarize`) is pure, so its rules are tested without a
database; `load` reads the marks.
"""

from __future__ import annotations

import datetime as dt
import decimal
from dataclasses import dataclass, field

from . import modules
from .enums import AssessmentStatus, GradeScaleKind
from .models import AcademicTerm, AssessmentMark, GradeScale, StudentEnrollment
from .services import GradeScaleService

CENT = decimal.Decimal("0.01")
ZERO = decimal.Decimal("0")

MODULE = "assessments"


@dataclass(frozen=True)
class Mark:
    """One published mark, as the card reads it."""

    term_id: int
    subject: str
    title: str
    held_on: dt.date
    obtained: decimal.Decimal | None
    max_marks: decimal.Decimal
    absent: bool


@dataclass
class Total:
    obtained: decimal.Decimal = ZERO
    possible: decimal.Decimal = ZERO
    percentage: decimal.Decimal | None = None
    grade: str | None = None
    grade_point: decimal.Decimal | None = None
    failing: bool = False

    def add(self, obtained, possible) -> None:
        self.obtained += obtained
        self.possible += possible


@dataclass
class SubjectRow:
    name: str
    # term id -> {title: Mark}
    marks: dict = field(default_factory=dict)
    # term id -> Total
    terms: dict = field(default_factory=dict)
    overall: Total = field(default_factory=Total)


@dataclass
class Column:
    title: str
    # The marks the test is out of, when every subject's is the same.
    out_of: decimal.Decimal | None


@dataclass
class Card:
    kind: str
    terms: list
    columns: dict  # term id -> [Column]
    subjects: list
    term_totals: dict  # term id -> Total
    overall: Total
    gpa_by_term: dict  # term id -> GPA or None
    gpa: decimal.Decimal | None
    passed: bool | None
    has_marks: bool
    # A GPA scale's top points (10, 4) and the school's GPA-to-percentage
    # multiplier, for the card to print beside the GPA.
    max_point: decimal.Decimal | None = None
    multiplier: decimal.Decimal | None = None


def grade_of(scale: GradeScale | None, total: Total) -> None:
    """Grades a total in place by the scale's band for its percentage."""
    if total.possible > 0:
        total.percentage = (total.obtained / total.possible * 100).quantize(CENT)

    if scale is None or total.percentage is None:
        return

    band = GradeScaleService.grade_for(scale, total.percentage)

    if band is not None:
        total.grade = band.label
        total.grade_point = band.grade_point
        total.failing = band.is_failing


def mean(values: list) -> decimal.Decimal | None:
    kept = [value for value in values if value is not None]

    return (sum(kept) / len(kept)).quantize(CENT) if kept else None


def summarize(terms: list, marks: list[Mark], scale: GradeScale | None, *, pass_percentage: int,
              result_rule: str) -> Card:
    """The card's figures from its marks. `terms` are the terms printed, in
    order; marks of any other term are ignored."""
    kind = scale.kind if scale is not None else GradeScaleKind.PERCENTAGE
    term_ids = [term.id for term in terms]
    rows: dict[str, SubjectRow] = {}
    first_held: dict[int, dict[str, dt.date]] = {term_id: {} for term_id in term_ids}
    out_of: dict[int, dict[str, set]] = {term_id: {} for term_id in term_ids}

    for mark in marks:
        if mark.term_id not in first_held:
            continue

        row = rows.setdefault(mark.subject, SubjectRow(name=mark.subject))
        row.marks.setdefault(mark.term_id, {})[mark.title] = mark
        held = first_held[mark.term_id]
        held[mark.title] = min(held.get(mark.title, mark.held_on), mark.held_on)
        out_of[mark.term_id].setdefault(mark.title, set()).add(mark.max_marks)

    columns = {
        term_id: [
            Column(title, next(iter(out_of[term_id][title])) if len(out_of[term_id][title]) == 1 else None)
            for title in sorted(first_held[term_id], key=lambda title: (first_held[term_id][title], title))
        ]
        for term_id in term_ids
    }

    term_totals = {term_id: Total() for term_id in term_ids}
    overall = Total()
    subjects = sorted(rows.values(), key=lambda row: row.name.lower())

    for row in subjects:
        for term_id in term_ids:
            total = Total()

            for mark in row.marks.get(term_id, {}).values():
                # Absent is not zero: out of the total altogether.
                if mark.absent or mark.obtained is None:
                    continue

                total.add(mark.obtained, mark.max_marks)

            grade_of(scale, total)
            row.terms[term_id] = total
            row.overall.add(total.obtained, total.possible)
            term_totals[term_id].add(total.obtained, total.possible)

        grade_of(scale, row.overall)
        overall.add(row.overall.obtained, row.overall.possible)

    for total in term_totals.values():
        grade_of(scale, total)

    grade_of(scale, overall)

    gpa_by_term = {
        term_id: mean([row.terms[term_id].grade_point for row in subjects if row.terms[term_id].possible > 0])
        for term_id in term_ids
    } if kind == GradeScaleKind.GPA else {term_id: None for term_id in term_ids}
    gpa = mean([row.overall.grade_point for row in subjects if row.overall.possible > 0]) \
        if kind == GradeScaleKind.GPA else None

    has_marks = overall.possible > 0

    points = [band.grade_point for band in scale.bands.all() if band.grade_point is not None] if scale else []

    return Card(
        kind=kind, terms=terms, columns=columns, subjects=subjects, term_totals=term_totals, overall=overall,
        gpa_by_term=gpa_by_term, gpa=gpa,
        passed=result_of(kind, subjects, overall, pass_percentage, result_rule) if has_marks else None,
        has_marks=has_marks,
        max_point=max(points) if points else None,
        multiplier=scale.gpa_multiplier if scale is not None else None,
    )


def result_of(kind: str, subjects: list, overall: Total, pass_percentage: int, rule: str) -> bool | None:
    """Passed, not passed, or None when the school prints no result."""
    if rule == "none":
        return None

    line = decimal.Decimal(pass_percentage)

    def passes(total: Total) -> bool:
        if kind == GradeScaleKind.GRADES:
            return not total.failing

        return total.percentage is not None and total.percentage >= line

    if rule == "overall":
        return passes(overall)

    return all(passes(row.overall) for row in subjects if row.overall.possible > 0)


def rank_of(scores: dict[int, decimal.Decimal], student_id: int) -> int | None:
    """The student's place among `scores` (student id -> score), highest
    first. Equal scores share a place and the next one is skipped - 1, 2,
    2, 4 - as a class list is read out."""
    mine = scores.get(student_id)

    if mine is None:
        return None

    return 1 + sum(1 for score in scores.values() if score > mine)


# -- reading the database ------------------------------------------------------------


def terms_through(term: AcademicTerm) -> list:
    """The year's terms up to the one asked for: a card printed at the end
    of Term I shows Term I; one printed at the year's end shows them all."""
    return list(
        AcademicTerm.objects.filter(
            academic_year_id=term.academic_year_id, sequence_number__lte=term.sequence_number
        ).order_by("sequence_number", "start_date")
    )


def marks_of(student_ids, terms: list):
    """Published marks of these students in these terms, as the card reads
    them, grouped by student."""
    rows = (
        AssessmentMark.objects.filter(
            student_id__in=list(student_ids),
            assessment__academic_term_id__in=[term.id for term in terms],
            assessment__status=AssessmentStatus.PUBLISHED,
        )
        .select_related("assessment__subject")
        .order_by("assessment__assessment_date", "assessment_id")
    )
    found: dict[int, list[Mark]] = {}

    for row in rows:
        assessment = row.assessment
        found.setdefault(row.student_id, []).append(Mark(
            term_id=assessment.academic_term_id,
            subject=assessment.subject.name,
            title=assessment.title.strip(),
            held_on=assessment.assessment_date,
            obtained=row.marks_obtained,
            max_marks=assessment.max_marks,
            absent=row.is_absent,
        ))

    return found


def scale_for(school_id: int, terms: list) -> GradeScale | None:
    """The scale the year's tests were graded on, else the school's
    default - the same choice the progress report makes."""
    used = (
        AssessmentMark.objects.filter(
            assessment__academic_term_id__in=[term.id for term in terms],
            assessment__school_id=school_id,
            assessment__grade_scale__isnull=False,
        )
        .values_list("assessment__grade_scale_id", flat=True)
        .first()
    )
    scales = GradeScale.objects.prefetch_related("bands")

    if used is not None:
        return scales.filter(pk=used).first()

    return scales.filter(school_id=school_id, is_default=True).first()


def load(student, through: AcademicTerm) -> tuple[Card, dict]:
    """The student's card through `through`, and what the school set for it."""
    settings = modules.settings_for(student.school_id, MODULE)
    terms = terms_through(through)
    scale = scale_for(student.school_id, terms)
    marks = marks_of([student.id], terms).get(student.id, [])
    card = summarize(
        terms, marks, scale, pass_percentage=int(settings["pass_percentage"]), result_rule=settings["result_rule"]
    )

    return card, {"settings": settings, "scale": scale, "rank": rank_for(student, terms, scale, card, settings)}


def rank_for(student, terms: list, scale: GradeScale | None, card: Card, settings: dict) -> int | None:
    """The class rank, when the school prints one: among the students of
    the same section that year, by the year's percentage - or by GPA on a
    grade-point scale. A grades-only card has no score to rank by."""
    if not settings.get("print_rank") or not card.has_marks:
        return None

    kind = scale.kind if scale is not None else GradeScaleKind.PERCENTAGE

    if kind == GradeScaleKind.GRADES:
        return None

    enrollment = StudentEnrollment.objects.filter(
        student_id=student.id, academic_year_id=terms[0].academic_year_id
    ).first()
    section_id = enrollment.class_section_id if enrollment is not None else student.class_section_id

    if section_id is None:
        return None

    classmates = StudentEnrollment.objects.filter(
        academic_year_id=terms[0].academic_year_id, class_section_id=section_id
    ).values_list("student_id", flat=True)
    scores: dict[int, decimal.Decimal] = {}

    for student_id, marks in marks_of(classmates, terms).items():
        theirs = summarize(terms, marks, scale, pass_percentage=0, result_rule="none")
        score = theirs.gpa if kind == GradeScaleKind.GPA else theirs.overall.percentage

        if score is not None:
            scores[student_id] = score

    return rank_of(scores, student.id)
