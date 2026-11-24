"""How exams and admit cards read in the API (docs/examinations.md)."""

from __future__ import annotations

from ..clock import DATE, SchoolClock
from ..models import Examination, ExaminationPaper, ExaminationVersion
from ..resources import timestamp
from .service import PARENT_WORDS, STATE_WORDS, has_unpublished_changes, hhmm


def paper_resource(paper: ExaminationPaper) -> dict:
    return {
        "id": paper.id,
        "school_class_id": paper.school_class_id,
        "school_class_name": paper.school_class.name,
        "subject_id": paper.subject_id,
        "subject_name": paper.subject.name,
        "exam_date": paper.exam_date.isoformat(),
        "start_time": hhmm(paper.start_time),
        "end_time": hhmm(paper.end_time),
    }


def examination_resource(exam: Examination, *, detail: bool = False) -> dict:
    papers = list(
        ExaminationPaper.objects.filter(examination_id=exam.id)
        .select_related("school_class", "subject")
        .order_by("school_class__level", "school_class__name", "exam_date", "start_time", "subject__name")
    )
    body = {
        "id": exam.id,
        "school_id": exam.school_id,
        "academic_year_id": exam.academic_year_id,
        "academic_year_name": exam.academic_year.name,
        "academic_term_id": exam.academic_term_id,
        "academic_term_name": exam.academic_term.name if exam.academic_term_id else None,
        "name": exam.name,
        "centre": exam.centre,
        "reporting_time": hhmm(exam.reporting_time),
        "instructions": exam.instructions,
        "card_style": exam.card_style,
        "block_on_fee_dues": exam.block_on_fee_dues,
        "status": exam.status,
        "version": exam.version,
        "published_at": timestamp(exam.published_at),
        "has_unpublished_changes": exam.version > 0 and has_unpublished_changes(exam),
        "paper_count": len(papers),
        "class_count": len({paper.school_class_id for paper in papers}),
        "first_date": min((paper.exam_date for paper in papers), default=None),
        "last_date": max((paper.exam_date for paper in papers), default=None),
    }
    body["first_date"] = body["first_date"].isoformat() if body["first_date"] else None
    body["last_date"] = body["last_date"].isoformat() if body["last_date"] else None

    if detail:
        clock = SchoolClock.for_school(exam.school_id)
        body["papers"] = [paper_resource(paper) for paper in papers]
        body["versions"] = [
            {
                "version": version.version,
                "published_at": timestamp(version.published_at),
                "published_on": clock.format(version.published_at, DATE),
            }
            for version in ExaminationVersion.objects.filter(examination_id=exam.id).order_by("-version")
        ]

    return body


def candidate_resource(enrollment, state, *, exception=None) -> dict:
    student = enrollment.student

    return {
        "student_id": student.id,
        "name": student.name,
        "admission_number": student.admission_number,
        "school_class_id": enrollment.school_class_id,
        "school_class_name": enrollment.school_class.name,
        "class_section_id": enrollment.class_section_id,
        "class_section_name": enrollment.class_section.name if enrollment.class_section_id else None,
        "roll_number": enrollment.roll_number or student.roll_number,
        "state": state.code,
        "state_label": STATE_WORDS[state.code],
        # Staff only: the reason a card was withheld, or what is overdue.
        "reason": state.reason,
        "overdue": None if state.overdue is None else f"{state.overdue:.2f}",
        "exception": None if exception is None else exception.kind,
        # What a reader would have to fix before the card is right.
        "missing": [label for label, value in (("roll number", enrollment.roll_number or student.roll_number),)
                    if not value],
    }


def family_card_resource(exam: Examination, state, version: ExaminationVersion | None, class_id=None) -> dict:
    """What a parent sees of one exam: never the reason a card is withheld,
    and no figures. With [class_id], the published date sheet's papers for
    the child's class - what "Add to calendar" reads (M8, 6.3). A withheld
    card still shows them: the date sheet is the class's, not the card's."""
    clock = SchoolClock.for_school(exam.school_id)
    papers = []
    if version is not None and class_id is not None:
        papers = (version.snapshot.get("classes") or {}).get(str(class_id), {}).get("papers", [])

    return {
        "examination_id": exam.id,
        "name": exam.name,
        "academic_year_name": exam.academic_year.name,
        "term_name": exam.academic_term.name if exam.academic_term_id else None,
        "available": state.ready,
        "state": state.code,
        "message": PARENT_WORDS[state.code],
        "version": version.version if version is not None else None,
        "issued_on": clock.format(version.published_at, DATE) if version is not None else None,
        "reporting_time": version.snapshot.get("reporting_time") if version is not None else None,
        "centre": version.snapshot.get("centre") if version is not None else None,
        "papers": papers,
    }
