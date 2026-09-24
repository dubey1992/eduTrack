"""A class's marks as a spreadsheet (docs/assessments.md).

Marking forty children in a dialog is fine at a desk and slow everywhere
else, and a teacher often has the marks in a spreadsheet already. So a test's
sheet can be downloaded with the class already on it, filled in, and sent
back.

This does not go through the shared bulk importer, for one reason worth
stating: every other import creates records anywhere in a school, and is
therefore an administrator's tool. A marks file belongs to **one test**, and
the question "may you mark this class" already has an exact answer - the
timetable. Hanging the upload off the test keeps the teacher's own
permission, which is the whole point of it.

What the file holds, and what it does not:

- `admission_number` identifies the student, because that is what a school's
  own spreadsheets carry. A name would be ambiguous in any class with two
  Aaravs.
- `marks` is blank for somebody not marked yet, and `absent` is yes or no.
  Absent with a mark is refused rather than guessed at.
- Nothing is written unless every row passes, the same rule the other
  uploads keep.
"""

from __future__ import annotations

import csv
import decimal
import io

from ..enums import StudentStatus
from ..errors import BulkImportFailed
from ..models import Student

LABEL = "Marks"
HEADINGS = ["admission_number", "student_name", "marks", "absent", "remarks"]

# A class is a class. Far below the 2,000 rows the other uploads allow, and
# still more than any real section.
MAX_ROWS = 200

YES = {"y", "yes", "true", "1", "absent"}
NO = {"", "n", "no", "false", "0", "present"}


def roster_rows(sheet: dict) -> list[list[str]]:
    """The template: the class, already filled in, with the marks column
    blank. Nobody should have to type a roll of names to send marks back."""
    return [
        [
            student.admission_number,
            student.name,
            "" if row is None or row.marks_obtained is None else f"{row.marks_obtained:.2f}",
            "yes" if row is not None and row.is_absent else "",
            "" if row is None or row.remarks is None else row.remarks,
        ]
        for student, row in sheet["entries"]
    ]


def read(upload, assessment) -> list[dict]:
    """Parses the file into marks, or raises with every row that needs
    fixing."""
    try:
        raw = upload.read()
    except OSError:
        raise failure(0, "The file could not be read.")

    text = raw.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(text))

    try:
        headings = [heading.strip() for heading in next(reader)]
    except StopIteration:
        raise failure(0, "The file is empty. Download the template and fill it in.")

    if headings != HEADINGS:
        raise failure(1, "The column headings do not match the template. Expected: " + ", ".join(HEADINGS) + ".")

    roster = {
        admission_number.lower(): student_id
        for student_id, admission_number in Student.objects.filter(
            class_section_id=assessment.class_section_id, status=StudentStatus.ACTIVE
        ).values_list("id", "admission_number")
    }

    marks, errors, seen = [], [], {}
    line = 1

    for values in reader:
        line += 1

        if not any((value or "").strip() for value in values):
            continue

        values = (list(values) + [None] * len(HEADINGS))[: len(HEADINGS)]
        row = {heading: clean(value) for heading, value in zip(HEADINGS, values)}
        messages = []

        admission_number = (row["admission_number"] or "").lower()
        student_id = roster.get(admission_number)

        if not admission_number:
            messages.append("The admission_number is required.")
        elif student_id is None:
            messages.append(f'No student with admission number "{row["admission_number"]}" is in this class.')
        elif admission_number in seen:
            messages.append(f'"{row["admission_number"]}" is also on row {seen[admission_number]}.')

        seen.setdefault(admission_number, line)

        is_absent = False
        absent = (row["absent"] or "").strip().lower()

        if absent in YES:
            is_absent = True
        elif absent not in NO:
            messages.append('The absent column takes "yes" or "no".')

        obtained = None

        if row["marks"] is not None and row["marks"] != "":
            obtained = to_decimal(row["marks"])

            if obtained is None:
                messages.append("The marks is not a number.")
            elif obtained < 0 or obtained > assessment.max_marks:
                messages.append(f"The marks must be between 0 and {assessment.max_marks:.2f}.")
            elif is_absent:
                messages.append("An absent student has no marks.")

        if row["remarks"] is not None and len(row["remarks"]) > 255:
            messages.append("The remarks must not be greater than 255 characters.")

        if messages:
            errors.append({"row": line, "messages": messages})
            continue

        marks.append(
            {
                "student_id": student_id,
                "is_absent": is_absent,
                "marks_obtained": None if is_absent else obtained,
                "remarks": row["remarks"],
            }
        )

        if len(marks) + len(errors) > MAX_ROWS:
            raise failure(line, f"A marks file can hold at most {MAX_ROWS} rows.")

    if errors:
        raise BulkImportFailed(LABEL, errors, 0)

    if not marks:
        raise failure(1, "The file has headings but no rows.")

    return marks


def clean(value):
    if value is None:
        return None

    value = str(value).strip()

    return value or None


def to_decimal(value):
    try:
        return decimal.Decimal(str(value)).quantize(decimal.Decimal("0.01"))
    except (decimal.InvalidOperation, TypeError, ValueError):
        return None


def failure(line: int, message: str) -> BulkImportFailed:
    return BulkImportFailed(LABEL, [{"row": line, "messages": [message]}], 0)
