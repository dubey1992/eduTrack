"""Roll numbers within a section (docs/onboarding.md, slice O2).

A roll number is what a teacher calls out, so a section's students are listed
by it, a new student left without one gets the next free number, and two
students in a section never share one.

Only active students hold a number. A child who left keeps the number on their
record, but it is free for the next admission - otherwise a section would run
out of low numbers over the years.

Roll numbers are text (some schools write "12A"), so the order is numeric
where the numbers are numbers: 9 before 10, by length first, then by value.
Uniqueness is checked here, not by the database: older data may already hold
duplicates, and a constraint would refuse to be added over them.
"""

from __future__ import annotations

from django.db.models import Q
from django.db.models.functions import Length

from .enums import StudentStatus
from .models import Student

# A student list read by roll number: numbered students first, 9 before 10,
# those without a number last and by name.
ORDER = (
    Length("roll_number").asc(nulls_last=True),
    "roll_number",
    "first_name",
    "last_name",
    "id",
)


def normalise(roll_number) -> str | None:
    """" 07 " and "7" are the same roll number; a blank is none."""
    text = str(roll_number or "").strip()

    if not text:
        return None

    return str(int(text)) if text.isdigit() else text


def holders(class_section_id: int):
    """The students who hold a number in this section: the active ones."""
    return Student.objects.filter(class_section_id=class_section_id, status=StudentStatus.ACTIVE).exclude(
        Q(roll_number__isnull=True) | Q(roll_number="")
    )


def holder_of(class_section_id: int, roll_number, ignoring: int | None = None) -> Student | None:
    """The active student in the section who already has this number."""
    wanted = normalise(roll_number)

    if wanted is None:
        return None

    students = holders(class_section_id)

    if ignoring is not None:
        students = students.exclude(pk=ignoring)

    for student in students.only("id", "first_name", "last_name", "roll_number"):
        if normalise(student.roll_number).lower() == wanted.lower():
            return student

    return None


def taken_message(student: Student, roll_number) -> str:
    return (
        f"Roll number {normalise(roll_number)} is already {student.first_name} {student.last_name}'s in this "
        "section. Leave it blank to get the next free number."
    )


def highest(class_section_id: int) -> int:
    """The highest plain number held in the section, or 0."""
    numbers = [
        int(value)
        for value in holders(class_section_id).values_list("roll_number", flat=True)
        if value and value.strip().isdigit()
    ]

    return max(numbers, default=0)


def next_free(class_section_id: int) -> str:
    """One past the highest number held, so a new student joins the end of
    the roll - never a gap in the middle, which would reorder the register
    the teacher has already written down."""
    return str(highest(class_section_id) + 1)
