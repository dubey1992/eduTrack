"""A roll of students, as a school keeps it.

Port of StudentImporter. The one thing worth knowing about it: the spreadsheet
names a class and a section, never the section id the API uses. Nobody filling
in a spreadsheet knows that a section is number 37.
"""

from __future__ import annotations

from ..enums import StudentStatus
from ..models import AcademicYear, ClassSection, Student
from ..services import StudentService
from ..validation import MOBILE_PATTERN, already_taken, bad_format, required, too_long


class StudentImporter:
    def __init__(self) -> None:
        # Class and section name to section id, worked out once per import.
        self._sections: dict[str, int] | None = None

    def label(self) -> str:
        return "Students"

    def headings(self) -> list[str]:
        return [
            "admission_number", "first_name", "last_name", "class", "section",
            "roll_number", "guardian_name", "guardian_mobile", "address",
        ]

    def sample(self) -> list[str]:
        """One example row, so nobody has to guess how a date or a phone
        number should look."""
        return [
            "ADM-2026-001", "Aarav", "Sharma", "Grade 5", "A",
            "12", "Meera Sharma", "+91 98765 43210", "14 Rose Lane, Pune",
        ]

    def unique_columns(self) -> list[str]:
        return ["admission_number"]

    def check_fields(self, row: dict, school_id: int | None = None) -> list[str]:
        """The per-column rules, in the same words the single-record form uses.

        Written out rather than run through a serializer because a row reports
        a list of sentences against a line number, not a map of field errors -
        the client renders them as "row 7: ..." beneath the upload.
        """
        messages = []

        for field, limit in (
            ("admission_number", 30),
            ("first_name", 100),
            ("last_name", 100),
            ("class", 50),
            ("section", 10),
            ("guardian_name", 150),
        ):
            value = row.get(field)

            if value is None:
                messages.append(required(field))
            elif len(value) > limit:
                messages.append(too_long(field, limit))

        for field, limit in (("roll_number", 20), ("address", 500)):
            value = row.get(field)

            if value is not None and len(value) > limit:
                messages.append(too_long(field, limit))

        mobile = row.get("guardian_mobile")

        if mobile is not None and not MOBILE_PATTERN.match(mobile):
            messages.append(bad_format("guardian_mobile"))

        return messages

    def check(self, row: dict, school_id: int) -> list[str]:
        """The cross-column checks: does this class and section exist, and is
        this admission number free?"""
        messages = []

        if self._section_id(row, school_id) is None:
            if not self._sections_of(school_id):
                messages.append(
                    "This school has no classes in its current academic year yet. "
                    "Set one up before importing students."
                )
            else:
                messages.append(
                    'There is no section "' + row["section"] + '" in class "' + row["class"] + '".'
                )

        if Student.objects.filter(
            school_id=school_id, admission_number=row["admission_number"]
        ).exists():
            messages.append(already_taken("admission_number"))

        return messages

    def import_row(self, row: dict, school_id: int, actor) -> dict:
        student = StudentService.create(
            {
                "school_id": school_id,
                "class_section_id": self._section_id(row, school_id),
                "admission_number": row["admission_number"],
                "first_name": row["first_name"],
                "last_name": row["last_name"],
                "roll_number": row.get("roll_number"),
                "guardian_name": row["guardian_name"],
                "guardian_mobile": row.get("guardian_mobile"),
                "address": row.get("address"),
                "status": StudentStatus.ACTIVE,
            },
            actor,
        )

        return {"id": student.id, "name": f"{student.first_name} {student.last_name}"}

    # -- resolving a class and section by name -----------------------------

    def _section_id(self, row: dict, school_id: int) -> int | None:
        return self._sections_of(school_id).get(key(row.get("class"), row.get("section")))

    def _sections_of(self, school_id: int) -> dict[str, int]:
        """The sections of the school's current academic year - the year
        students are being enrolled into.

        Class names repeat from one year to the next, so without that anchor
        "Grade 5 / A" would be ambiguous.
        """
        if self._sections is not None:
            return self._sections

        year_id = (
            AcademicYear.objects.filter(school_id=school_id, is_current=True)
            .values_list("id", flat=True)
            .first()
        )

        if year_id is None:
            self._sections = {}

            return self._sections

        self._sections = {
            key(section.school_class.name, section.name): section.id
            for section in ClassSection.objects.select_related("school_class").filter(
                school_class__academic_year_id=year_id
            )
        }

        return self._sections


def key(class_name, section_name) -> str:
    """Case and stray spaces should not decide whether a row imports."""
    return f"{str(class_name or '').strip().lower()}|{str(section_name or '').strip().lower()}"
