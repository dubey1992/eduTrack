"""Class tests as a spreadsheet (docs/assessments.md).

A term's worth of tests is a list somebody already has: the same unit test
set in eight sections, or a timetable of weekly quizzes. Typing them one
dialog at a time is the slow part, so they can be uploaded instead.

Like every other import this is an administrator's tool. A teacher sets
their own tests one at a time, where the timetable answers "is this your
class" per test; a spreadsheet that crossed classes would have to ask that
question per row, and the shared reader has no actor to ask about. Keeping
bulk creation with the people who may set tests for any class in the school
means there is no second set of rules to fall out of step.

People type names, not ids - a class called "Grade 8 A", a subject called
"Mathematics", a term called "Term 1" - so each is looked up per school,
case-blind, once per import.
"""

from __future__ import annotations

import datetime as dt
import decimal

from ..enums import AssessmentStatus, AssessmentType
from ..models import AcademicTerm, Assessment, ClassSection, GradeScale, Subject, SyllabusTopic
from ..services import AssessmentService
from ..validation import required, too_long
from .rules import to_iso

MAX_TOTAL_MARKS = decimal.Decimal("1000")


class AssessmentImporter:
    def __init__(self) -> None:
        # Worked out once per import: a file of two hundred rows should not
        # ask the database for the same section two hundred times.
        self._sections: dict[str, tuple[int, int, int]] | None = None
        self._subjects: dict[str, Subject] | None = None
        self._terms: dict[str, AcademicTerm] | None = None
        self._scales: dict[str, int] | None = None

    def label(self) -> str:
        return "Class Tests"

    def headings(self) -> list[str]:
        return [
            "class", "subject", "term", "type", "title",
            "max_marks", "pass_marks", "weightage", "date", "grade_scale", "topic",
        ]

    def sample(self) -> list[str]:
        return [
            "Grade 8 A", "Mathematics", "Term 1", "class_test", "Fractions - unit test",
            "20", "7", "25", "07/15/2026", "Secondary", "Fractions",
        ]

    def unique_columns(self) -> list[str]:
        # Two tests of the same name on one day for one class and subject is
        # far more likely to be a copy-paste slip than a real pair of tests.
        return []

    # -- per-column rules ---------------------------------------------------

    def check_fields(self, row: dict, school_id: int | None = None) -> list[str]:
        messages = []

        for field, limit in (("class", 60), ("subject", 100), ("term", 50), ("title", 150)):
            value = row.get(field)

            if value is None:
                messages.append(required(field))
            elif len(value) > limit:
                messages.append(too_long(field, limit))

        kind = (row.get("type") or "").lower()

        if not kind:
            messages.append(required("type"))
        elif kind not in AssessmentType.values:
            messages.append(
                'The type must be one of: ' + ", ".join(AssessmentType.values) + "."
            )

        messages += self._marks_messages(row)

        if row.get("date") is None:
            messages.append(required("date"))
        elif to_iso(row["date"]) is None:
            messages.append("The date is not a date. Use MM/DD/YYYY, as in 07/15/2026.")

        return messages

    def _marks_messages(self, row: dict) -> list[str]:
        messages = []
        maximum = self._number(row.get("max_marks"))

        if row.get("max_marks") is None:
            messages.append(required("max_marks"))
        elif maximum is None:
            messages.append("The max_marks is not a number.")
        elif maximum <= 0:
            messages.append("The max_marks must be greater than 0.")
        elif maximum > MAX_TOTAL_MARKS:
            messages.append(f"The max_marks must not be greater than {int(MAX_TOTAL_MARKS)}.")

        passing = self._number(row.get("pass_marks"))

        if row.get("pass_marks") is not None:
            if passing is None:
                messages.append("The pass_marks is not a number.")
            elif passing < 0:
                messages.append("The pass_marks must not be less than 0.")
            elif maximum is not None and passing > maximum:
                messages.append("The pass_marks must not be greater than max_marks.")

        weightage = self._number(row.get("weightage"))

        if row.get("weightage") is not None:
            if weightage is None:
                messages.append("The weightage is not a number.")
            elif weightage < 0 or weightage > 100:
                messages.append("The weightage must be between 0 and 100.")

        return messages

    # -- cross-column rules -------------------------------------------------

    def check(self, row: dict, school_id: int) -> list[str]:
        """Whether the pieces of this row belong together: the same questions
        the single-test form asks, in the same words where they are the
        same."""
        messages = []

        section = self._section(row, school_id)
        subject = self._subject(row, school_id)
        term = self._term(row, school_id)
        date = to_iso(row["date"])

        if section is None:
            messages.append(f'There is no class "{row["class"]}" in this school.')

        if subject is None:
            messages.append(f'There is no subject "{row["subject"]}" in this school.')

        if term is None:
            messages.append(f'There is no term "{row["term"]}" in this school.')

        if section is not None and subject is not None:
            _, _, level = section

            if not (subject.min_class_level <= level <= subject.max_class_level):
                messages.append(f'{subject.name} is not taught at "{row["class"]}".')

        if section is not None and term is not None:
            _, year_id, _ = section

            if term.academic_year_id != year_id:
                messages.append(f'{term.name} belongs to a different academic year than "{row["class"]}".')

        if term is not None and date is not None:
            marked = dt.date.fromisoformat(date)

            if not (term.start_date <= marked <= term.end_date):
                messages.append(
                    f"The date must fall inside {term.name} ({term.start_date} to {term.end_date})."
                )

        scale_name = row.get("grade_scale")

        if scale_name is not None and self._scale_id(scale_name, school_id) is None:
            messages.append(f'There is no grade scale "{scale_name}" in this school.')

        topic_title = row.get("topic")

        if topic_title is not None and subject is not None and self._topic_id(topic_title, subject) is None:
            messages.append(f'"{topic_title}" is not a topic of {subject.name}.')

        return messages

    # -- writing ------------------------------------------------------------

    def import_row(self, row: dict, school_id: int, actor) -> dict:
        section_id, year_id, _ = self._section(row, school_id)
        subject = self._subject(row, school_id)
        term = self._term(row, school_id)
        scale_name = row.get("grade_scale")
        topic_title = row.get("topic")

        # Through the same service the single-test form uses, so an imported
        # test is exactly what the dialog would have made - a draft, created
        # by whoever ran the import.
        assessment = AssessmentService.create(
            {
                "school_id": school_id,
                "academic_year_id": year_id,
                "academic_term_id": term.id,
                "class_section_id": section_id,
                "subject_id": subject.id,
                "syllabus_topic_id": self._topic_id(topic_title, subject) if topic_title else None,
                "grade_scale_id": self._scale_id(scale_name, school_id) if scale_name else None,
                "type": (row["type"] or "").lower(),
                "title": row["title"],
                "max_marks": self._number(row["max_marks"]),
                "pass_marks": self._number(row.get("pass_marks")),
                "weightage": self._number(row.get("weightage")),
                "assessment_date": to_iso(row["date"]),
            },
            actor,
        )

        return {"id": assessment.id, "title": assessment.title, "status": AssessmentStatus.DRAFT}

    # -- lookups ------------------------------------------------------------

    @staticmethod
    def _number(value):
        if value is None or value == "":
            return None

        try:
            return decimal.Decimal(str(value)).quantize(decimal.Decimal("0.01"))
        except (decimal.InvalidOperation, TypeError, ValueError):
            return None

    def _sections_of(self, school_id: int) -> dict[str, tuple[int, int, int]]:
        """"Grade 8 A" to the section, its year and its level - the three
        things a row is checked against."""
        if self._sections is None:
            self._sections = {
                f"{school_class_name} {name}".strip().lower(): (section_id, year_id, level)
                for section_id, name, school_class_name, year_id, level in ClassSection.objects.filter(
                    school_class__school_id=school_id
                ).values_list(
                    "id", "name", "school_class__name", "school_class__academic_year_id", "school_class__level"
                )
            }

        return self._sections

    def _section(self, row: dict, school_id: int):
        return self._sections_of(school_id).get((row.get("class") or "").strip().lower())

    def _subject(self, row: dict, school_id: int):
        if self._subjects is None:
            self._subjects = {
                subject.name.lower(): subject for subject in Subject.objects.filter(school_id=school_id)
            }

        return self._subjects.get((row.get("subject") or "").strip().lower())

    def _term(self, row: dict, school_id: int):
        if self._terms is None:
            self._terms = {term.name.lower(): term for term in AcademicTerm.objects.filter(school_id=school_id)}

        return self._terms.get((row.get("term") or "").strip().lower())

    def _scale_id(self, name: str, school_id: int):
        if self._scales is None:
            self._scales = {
                scale_name.lower(): scale_id
                for scale_id, scale_name in GradeScale.objects.filter(school_id=school_id).values_list("id", "name")
            }

        return self._scales.get((name or "").strip().lower())

    @staticmethod
    def _topic_id(title: str, subject):
        topic = SyllabusTopic.objects.filter(subject_id=subject.id, title__iexact=(title or "").strip()).first()

        return topic.id if topic is not None else None


class AssessmentImportPolicy:
    """The gate for the spreadsheet: may this person set tests for the school
    at all.

    Which class and which subject is a per-row question, and the answer for an
    administrator is "any in their school" - which is why bulk creation is
    theirs. A teacher's tests are set one at a time, where the timetable
    answers that question for each one.
    """

    @staticmethod
    def create(actor) -> bool:
        from ..policies import AssessmentPolicy

        return AssessmentPolicy.create_in_bulk(actor)
