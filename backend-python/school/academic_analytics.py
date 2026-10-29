"""Academic analytics, A4 (docs/analytics.md): how each subject and each
class did, term by term, through one academic year.

The rule A1 set holds here too: nothing is worked out afresh. Each term is
the Class Performance report run over that term's dates, so every figure
on the screen is one a school can print. This module only lines the terms
up side by side and adds them up two ways - by subject across the classes
that take it, and by class across its subjects.

Both of those are weighted by the marks counted, the way the report's own
total is: a subject with forty marks in a term weighs more than one with
four. A term with no published result has no figure, never 0%.
"""

from __future__ import annotations

from .clock import SchoolClock
from .models import AcademicTerm, AcademicYear
from .reports import ClassPerformanceReport
from .reports.performance import percent
from .reports.range import ReportRange


def academic(school_id: int, year_id: int | None, filters: dict) -> dict:
    """The school's year, term by term. [filters] narrows as the report
    does - a head of department's `department_ids` among them."""
    today = SchoolClock.for_school(school_id).now().date()
    years = list(AcademicYear.objects.filter(school_id=school_id).order_by("-start_date", "-id"))

    year = next((y for y in years if y.id == year_id), None) if year_id else None
    if year is None:
        # The current year, or failing that the latest that has begun.
        year = next((y for y in years if y.is_current), None) or next(
            (y for y in years if y.start_date <= today), None
        )

    summary = {
        "years": [
            {"id": y.id, "name": y.name, "is_current": bool(y.is_current)} for y in years
        ],
        "year": None if year is None else {"id": year.id, "name": year.name},
    }

    # Only the terms that have begun: a term still to come has nothing to say.
    terms = (
        []
        if year is None
        else list(
            AcademicTerm.objects.filter(academic_year_id=year.id, start_date__lte=today).order_by(
                "sequence_number", "start_date", "id"
            )
        )
    )

    built = [
        ClassPerformanceReport().build(ReportRange(school_id, term.start_date, min(term.end_date, today), []), filters)
        for term in terms
    ]

    cells: dict[tuple, dict] = {}
    for index, report in enumerate(built):
        for row in report["rows"]:
            key = (row["class_section_id"], row["subject_id"])
            cell = cells.setdefault(key, {
                "class_section_id": row["class_section_id"],
                "class_section": row["class_section"],
                "subject_id": row["subject_id"],
                "subject": row["subject"],
                "department": row["department"],
                "terms": [None] * len(terms),
            })
            cell["terms"][index] = {
                "average_percentage": row["average_percentage"],
                "marks_counted": row["marks_counted"],
                "students": row["students"],
                "students_below_the_mark": row["students_below_the_mark"],
            }

    cell_list = sorted(cells.values(), key=lambda c: (c["class_section"] or "", c["subject"] or ""))

    return {
        **summary,
        # How many terms the year has at all, begun or not - so "no term has
        # begun" can be told apart from "nobody has set the terms up".
        "terms_set_up": 0 if year is None else AcademicTerm.objects.filter(academic_year_id=year.id).count(),
        "terms": [
            {
                "id": term.id,
                "name": term.name,
                "from": term.start_date.isoformat(),
                "to": min(term.end_date, today).isoformat(),
                "in_progress": term.end_date >= today,
            }
            for term in terms
        ],
        "subjects": _rolled_up(cell_list, ("subject_id", "subject", "department"), len(terms)),
        "classes": _rolled_up(cell_list, ("class_section_id", "class_section"), len(terms)),
        "cells": cell_list,
    }


def _rolled_up(cells: list[dict], keys: tuple, term_count: int) -> list[dict]:
    """Cells added up by [keys] - a subject across its classes, or a class
    across its subjects - each term weighted by the marks it counted."""
    groups: dict = {}

    for cell in cells:
        group = groups.setdefault(cell[keys[0]], {
            **{key: cell[key] for key in keys},
            "weighted": [0.0] * term_count,
            "counted": [0] * term_count,
        })
        for index, term in enumerate(cell["terms"]):
            if term is None or term["average_percentage"] is None or not term["marks_counted"]:
                continue
            group["weighted"][index] += float(term["average_percentage"]) * term["marks_counted"]
            group["counted"][index] += term["marks_counted"]

    rows = []
    for group in groups.values():
        rows.append({
            **{key: group[key] for key in keys},
            "terms": [
                None if counted == 0 else {"average_percentage": percent(weighted / counted), "marks_counted": counted}
                for weighted, counted in zip(group["weighted"], group["counted"])
            ],
        })

    return sorted(rows, key=lambda row: str(row[keys[1]] or ""))
