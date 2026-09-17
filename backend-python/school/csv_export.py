"""A CSV written the way PHP's fputcsv writes one.

Every CSV the API hands out - an import template, a report - is written here,
so the bytes match what Laravel sent. Python's csv module and PHP's fputcsv
both produce files a spreadsheet opens the same way, and differ in the bytes:

- fputcsv quotes a field containing a space, a tab or a backslash as well as a
  comma, a quote or a line break; the csv module quotes only what it must.
- fputcsv ends every line with "\\n"; the csv module defaults to "\\r\\n".

Nothing a person sees changes. A byte-for-byte comparison with the backend
this one replaces does, and so would any client that checksums a download.
"""

from __future__ import annotations

from django.http import HttpResponse

# The characters that make fputcsv enclose a field.
NEEDS_QUOTES = set(',"\\\n\r\t ')

# Excel reads a CSV as the system codepage unless the file opens with a byte
# order mark, which mangles any non-ASCII name.
BOM = "﻿"


def cell(value) -> str:
    """How a report cell reads in a spreadsheet: nothing is a dash, and a
    yes/no is a word."""
    if value is None:
        return "-"

    if isinstance(value, bool):
        return "Yes" if value else "No"

    return str(value)


def field(value: str) -> str:
    if any(character in NEEDS_QUOTES for character in value):
        return '"' + value.replace('"', '""') + '"'

    return value


def line(values) -> str:
    return ",".join(field(str(value)) for value in values) + "\n"


def response(file_name: str, headings, rows) -> HttpResponse:
    body = BOM + line(headings) + "".join(line(cell(value) for value in row) for row in rows)

    reply = HttpResponse(body.encode("utf-8"), content_type="text/csv; charset=UTF-8")
    reply["Content-Disposition"] = f'attachment; filename="{file_name}"'

    return reply
