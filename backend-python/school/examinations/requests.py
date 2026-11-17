"""What an exam form may say (docs/examinations.md).

The school is never read from the request: an exam's is its academic year's,
and that year has to be in the caller's scope. A paper's class has to be a
class of the exam's year, and its subject one of the school's.

Errors are keyed the way the screens need them: `papers.3.end_time`.
"""

from __future__ import annotations

import datetime as dt
import re

from rest_framework import serializers

from ..models import AcademicTerm, AcademicYear, SchoolClass, Student, Subject
from ..policies import in_scope
from ..validation import does_not_exist, required, too_long
from .service import ALLOW, STYLES, WITHHOLD

MAX_PAPERS = 400
TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def parse_time(value, field: str, errors: dict) -> dt.time | None:
    if value in (None, ""):
        errors[field] = [required(field.rsplit(".", 1)[-1].replace("_", " "))]
        return None

    found = TIME.match(str(value).strip()[:5]) if isinstance(value, str) else None

    if found is None:
        errors[field] = ["Use a 24-hour time such as 09:00."]
        return None

    return dt.time(int(found.group(1)), int(found.group(2)))


def parse_date(value, field: str, errors: dict) -> dt.date | None:
    if value in (None, ""):
        errors[field] = ["The exam date is required."]
        return None

    try:
        return dt.date.fromisoformat(str(value))
    except ValueError:
        errors[field] = ["The exam date must be a date written as YYYY-MM-DD."]
        return None


def text_of(data: dict, key: str, limit: int, errors: dict, *, required_field: bool = False) -> str | None:
    value = data.get(key)

    if value is None or (isinstance(value, str) and not value.strip()):
        if required_field:
            errors[key] = [required(key)]
        return None

    if not isinstance(value, str):
        errors[key] = [f"The {key.replace('_', ' ')} field must be text."]
        return None

    value = value.strip()

    if len(value) > limit:
        errors[key] = [too_long(key.replace("_", " "), limit)]
        return None

    return value


class ExamFields:
    """The exam's own details, for create and update alike."""

    def __init__(self, data, *, actor, exam=None) -> None:
        self.data = data if isinstance(data, dict) else {}
        self.actor = actor
        self.exam = exam
        self.validated_data: dict = {}

    def is_valid(self, raise_exception: bool = True) -> bool:
        data, errors, out = self.data, {}, {}
        creating = self.exam is None

        if creating:
            year = None
            year_id = data.get("academic_year_id")

            if year_id in (None, ""):
                errors["academic_year_id"] = [required("academic year id")]
            else:
                year = AcademicYear.objects.filter(pk=year_id).first() if str(year_id).isdigit() else None

                if year is None or not in_scope(self.actor, year.school_id):
                    errors["academic_year_id"] = [does_not_exist("academic year id")]
                else:
                    out["academic_year"] = year
        else:
            year = self.exam.academic_year

        if creating or "name" in data:
            name = text_of(data, "name", 100, errors, required_field=True)
            if name is not None:
                out["name"] = name

        if "academic_term_id" in data:
            term_id = data.get("academic_term_id")

            if term_id in (None, ""):
                out["academic_term"] = None
            else:
                term = AcademicTerm.objects.filter(pk=term_id).first() if str(term_id).isdigit() else None

                if term is None or year is None or term.academic_year_id != year.id:
                    errors["academic_term_id"] = ["Choose a term of the exam's academic year."]
                else:
                    out["academic_term"] = term

        for key, limit in (("centre", 150), ("instructions", 2000)):
            if key in data:
                out[key] = text_of(data, key, limit, errors)

        if "reporting_time" in data:
            raw = data.get("reporting_time")
            out["reporting_time"] = None if raw in (None, "") else parse_time(raw, "reporting_time", errors)

        if "card_style" in data:
            if data.get("card_style") not in STYLES:
                errors["card_style"] = ["The card style must be classic or mono."]
            else:
                out["card_style"] = data["card_style"]

        if "block_on_fee_dues" in data:
            if not isinstance(data.get("block_on_fee_dues"), bool):
                errors["block_on_fee_dues"] = ["The block on fee dues field must be true or false."]
            else:
                out["block_on_fee_dues"] = data["block_on_fee_dues"]

        if errors:
            if raise_exception:
                raise serializers.ValidationError(errors)
            return False

        self.validated_data = out
        return True


class PapersRequest:
    """The whole date sheet, replacing what was there."""

    def __init__(self, data, *, exam) -> None:
        self.data = data if isinstance(data, dict) else {}
        self.exam = exam
        self.validated_data: dict = {}

    def is_valid(self, raise_exception: bool = True) -> bool:
        raw = self.data.get("papers")
        errors: dict = {}

        if not isinstance(raw, list):
            raise serializers.ValidationError({"papers": ["The papers must be a list."]})

        if len(raw) > MAX_PAPERS:
            raise serializers.ValidationError({"papers": [f"A date sheet can have at most {MAX_PAPERS} papers."]})

        exam = self.exam
        year = exam.academic_year
        classes = {c.id: c for c in SchoolClass.objects.filter(academic_year_id=year.id, school_id=exam.school_id)}
        subjects = {s.id: s for s in Subject.objects.filter(school_id=exam.school_id)}
        papers, seen = [], {}

        for index, item in enumerate(raw):
            prefix = f"papers.{index}"
            item = item if isinstance(item, dict) else {}
            school_class = classes.get(int(item["school_class_id"])) if str(item.get("school_class_id", "")).isdigit() else None
            subject = subjects.get(int(item["subject_id"])) if str(item.get("subject_id", "")).isdigit() else None

            if school_class is None:
                errors[f"{prefix}.school_class_id"] = ["Choose a class of the exam's academic year."]

            if subject is None:
                errors[f"{prefix}.subject_id"] = ["Choose one of the school's subjects."]

            day = parse_date(item.get("exam_date"), f"{prefix}.exam_date", errors)
            start = parse_time(item.get("start_time"), f"{prefix}.start_time", errors)
            end = parse_time(item.get("end_time"), f"{prefix}.end_time", errors)

            if day is not None and not (year.start_date <= day <= year.end_date):
                errors[f"{prefix}.exam_date"] = [
                    f"The exam date must fall within the academic year {year.name}."
                ]

            if start is not None and end is not None and end <= start:
                errors[f"{prefix}.end_time"] = ["The end time must be after the start time."]

            if school_class is not None and subject is not None:
                key = (school_class.id, subject.id)

                if key in seen:
                    errors[f"{prefix}.subject_id"] = [
                        f"{subject.name} already has a paper for {school_class.name}."
                    ]
                seen[key] = index

            papers.append({
                "school_class": school_class, "subject": subject, "exam_date": day, "start_time": start,
                "end_time": end, "index": index,
            })

        if not errors:
            self.check_clashes(papers, errors)

        if errors:
            if raise_exception:
                raise serializers.ValidationError(errors)
            return False

        self.validated_data = {"papers": papers}
        return True

    @staticmethod
    def check_clashes(papers: list[dict], errors: dict) -> None:
        """One class cannot sit two papers at once."""
        by_day: dict[tuple, list[dict]] = {}

        for paper in papers:
            by_day.setdefault((paper["school_class"].id, paper["exam_date"]), []).append(paper)

        for rows in by_day.values():
            rows.sort(key=lambda row: row["start_time"])

            for before, after in zip(rows, rows[1:]):
                if after["start_time"] < before["end_time"]:
                    errors[f"papers.{after['index']}.start_time"] = [
                        f"This overlaps {before['subject'].name} for {before['school_class'].name} on the same day."
                    ]


class ExceptionRequest:
    """Withhold a card, let one through a fee hold, or clear either."""

    def __init__(self, data, *, exam) -> None:
        self.data = data if isinstance(data, dict) else {}
        self.exam = exam
        self.validated_data: dict = {}

    def is_valid(self, raise_exception: bool = True) -> bool:
        data, errors = self.data, {}
        kind = data.get("kind")

        if kind not in (WITHHOLD, ALLOW, None, "none"):
            errors["kind"] = ["The kind must be withhold, allow or none."]

        student_id = data.get("student_id")
        student = Student.objects.filter(pk=student_id, school_id=self.exam.school_id).first() \
            if str(student_id or "").isdigit() else None

        if student is None:
            errors["student_id"] = [does_not_exist("student id")]

        reason = text_of(data, "reason", 255, errors)

        if kind == WITHHOLD and not reason and "reason" not in errors:
            errors["reason"] = ["Say why the card is withheld. Staff see the reason; parents do not."]

        if errors:
            if raise_exception:
                raise serializers.ValidationError(errors)
            return False

        self.validated_data = {"student": student, "kind": None if kind in (None, "none") else kind, "reason": reason}
        return True
