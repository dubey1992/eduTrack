"""Reads an uploaded CSV and turns it into records - or into a list of
everything wrong with it.

Port of BulkImportService. The rule that shapes it: **nothing is written until
every row has passed.** A file of two hundred students with a mistake on row
seven imports none of them and says so, because the alternative - a hundred
and ninety-nine rows in and one to chase - leaves the school reconciling a
half-finished import, and makes re-uploading the corrected file duplicate
everything that already landed.

Every problem is reported, not just the first, so one upload tells the school
everything it needs to fix.
"""

from __future__ import annotations

import csv
import io

from django.db import transaction

from ..errors import BulkImportFailed

# Enough for a large school's whole roll, small enough to stay in memory.
MAX_ROWS = 2000


def run(importer, upload, school_id: int, actor) -> dict:
    rows = read(upload, importer)
    errors = validate(rows, importer, school_id)

    if errors:
        raise BulkImportFailed(importer.label(), errors, len(rows))

    # Every row is known good by here, so the transaction is about atomicity
    # against a database failure rather than validation.
    with transaction.atomic():
        created = []

        for row in rows:
            result = importer.import_row(row["data"], school_id, actor)

            if result is not None:
                created.append(result)

    return {"imported": len(rows), "label": importer.label(), "details": created}


def read(upload, importer) -> list[dict]:
    """Parses the file into rows, each remembering the line it came from so an
    error can point at a line in the spreadsheet rather than an index.
    """
    try:
        raw = upload.read()
    except OSError:
        raise fail(importer, 0, "The file could not be read.")

    # A byte order mark is what a spreadsheet writes, and utf-8-sig eats it -
    # otherwise the first column name would never match.
    text = raw.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(text))

    try:
        headings = next(reader)
    except StopIteration:
        raise fail(importer, 0, "The file is empty. Download the template and fill it in.")

    expected = importer.headings()
    headings = [heading.strip() for heading in headings]

    if headings != expected:
        raise fail(
            importer,
            1,
            "The column headings do not match the template. Expected: " + ", ".join(expected) + ".",
        )

    rows = []
    line = 1

    for values in reader:
        line += 1

        # A trailing blank line is what every spreadsheet leaves behind; it is
        # not a row anybody meant to add.
        if is_blank(values):
            continue

        values = (values[: len(expected)] + [None] * len(expected))[: len(expected)]
        rows.append({"line": line, "data": dict(zip(expected, (clean(v) for v in values)))})

        if len(rows) > MAX_ROWS:
            raise fail(
                importer,
                line,
                f"A file can hold at most {MAX_ROWS} rows. Split it and upload again.",
            )

    if not rows:
        raise fail(importer, 1, "The file has headings but no rows.")

    return rows


def validate(rows: list[dict], importer, school_id: int) -> list[dict]:
    errors = []
    seen = {}

    for row in rows:
        messages = importer.check_fields(row["data"], school_id)

        # Cross-column checks only make sense once the columns themselves are
        # known good - otherwise a blank class produces both "the class is
        # required" and "that class has no such section".
        if not messages:
            messages = importer.check(row["data"], school_id)

        # Duplicates inside the file itself. The database catches a clash with
        # an existing record; nothing catches the same admission number typed
        # twice in the spreadsheet being uploaded.
        for column in importer.unique_columns():
            value = row["data"].get(column)

            if value is None or value == "":
                continue

            key = column + "|" + value.lower()

            if key in seen:
                messages.append(f'The {column} "{value}" is also on row {seen[key]}.')
            else:
                seen[key] = row["line"]

        if messages:
            errors.append({"row": row["line"], "messages": messages})

    return errors


def fail(importer, line: int, message: str) -> BulkImportFailed:
    return BulkImportFailed(importer.label(), [{"row": line, "messages": [message]}], 0)


def is_blank(values) -> bool:
    return all(str(value or "").strip() == "" for value in values)


def clean(value) -> str | None:
    """An empty cell is nothing, not an empty string - otherwise a nullable
    column would fail its own format rule on a blank."""
    value = str(value or "").strip()

    return value or None
