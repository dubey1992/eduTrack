"""What the numbers seem to be saying (docs/assessments.md).

Rules, not a model. Each one reads the figures another module already
worked out and, when it fires, produces three things: a **code** a client
can act on, a **sentence** a teacher reads, and the **numbers** it was drawn
from - so nothing on the screen is a claim somebody has to take on trust.

Pure on purpose. Nothing here touches the database or the clock: it is
given a performance payload and returns a list. That is what lets the
thresholds be tested at their boundaries without a term, a school or a
single row of marks.

**Nothing is said from fewer than two published results.** One test is not
a trend, and a confident sentence drawn from a single mark is worse than
silence - which is why every rule below checks the count first.
"""

from __future__ import annotations

import decimal

# A subject needs at least this many published tests before anything is said
# about it. The same floor applies to the term as a whole.
ENOUGH = 2

# Ten points either way is the change worth mentioning: smaller than that is
# the ordinary movement of one hard paper.
MOVED = decimal.Decimal("10")

# A third of the term's tests missed is worth saying out loud.
MISSED_SHARE = decimal.Decimal("1") / decimal.Decimal("3")

# Below this, attendance is offered as something that may explain a weak
# subject. It is not a claim that it does.
ATTENDANCE_MAY_EXPLAIN = decimal.Decimal("75")

WEAK_SUBJECT = "weak_subject"
SLIPPING = "slipping"
IMPROVING = "improving"
MISSED_TESTS = "missed_tests"
ATTENDANCE = "attendance_may_explain"


def plain(value) -> str:
    """A percentage as a person would write it: 34 rather than 34.00, and
    12.5 rather than 12.50."""
    if value is None:
        return ""

    number = decimal.Decimal(str(value)).normalize()

    return f"{number:f}"


def number(value):
    """A figure from the payload, as a Decimal - or None where there is
    nothing to read."""
    if value is None or value == "":
        return None

    try:
        return decimal.Decimal(str(value))
    except decimal.InvalidOperation:
        return None


def insight(code: str, message: str, numbers: dict, subject: dict | None = None) -> dict:
    return {
        "code": code,
        "message": message,
        "subject_id": None if subject is None else subject.get("subject_id"),
        "subject_name": None if subject is None else subject.get("subject_name"),
        "numbers": numbers,
    }


def for_performance(performance: dict) -> list[dict]:
    """Everything worth saying about one student's term.

    Ordered the way a teacher reads them: what is weak, what moved, and then
    what might explain it.
    """
    subjects = performance.get("subjects") or []
    weak_below = number(performance.get("weak_below_percentage"))
    previous_term = performance.get("previous_term") or {}
    attendance = performance.get("attendance") or {}

    found = []
    weak = []

    for subject in subjects:
        # One test is not a trend, whatever it says.
        if (subject.get("assessments") or 0) < ENOUGH:
            continue

        average = number(subject.get("average_percentage"))

        if weak_below is not None and average is not None and average < weak_below:
            weak.append(subject)
            found.append(
                insight(
                    WEAK_SUBJECT,
                    f"{subject['subject_name']} is at {plain(average)}%, "
                    f"below the school's {plain(weak_below)}% mark.",
                    {"average": plain(average), "threshold": plain(weak_below)},
                    subject,
                )
            )

        found.extend(moved(subject, previous_term))

    found.extend(missed(performance, subjects))
    found.extend(may_explain(weak, attendance))

    return found


def moved(subject: dict, previous_term: dict) -> list[dict]:
    """Ten points or more, either way, against the previous term."""
    change = number(subject.get("change"))

    if change is None:
        return []

    since = previous_term.get("name")
    when = "" if since is None else f" since {since}"

    if change <= -MOVED:
        return [
            insight(
                SLIPPING,
                f"{subject['subject_name']} has fallen {plain(abs(change))} points{when}.",
                {
                    "change": plain(change),
                    "average": plain(number(subject.get("average_percentage"))),
                    "previous": plain(number(subject.get("previous_average_percentage"))),
                },
                subject,
            )
        ]

    if change >= MOVED:
        return [
            insight(
                IMPROVING,
                f"{subject['subject_name']} is up {plain(change)} points{when}.",
                {
                    "change": plain(change),
                    "average": plain(number(subject.get("average_percentage"))),
                    "previous": plain(number(subject.get("previous_average_percentage"))),
                },
                subject,
            )
        ]

    return []


def missed(performance: dict, subjects: list) -> list[dict]:
    """A third of the term's tests or more, missed.

    Counted across the term rather than per subject: three missed tests
    spread over three subjects is the same fortnight away from school, and
    saying it once is the useful way to say it.
    """
    overall = performance.get("overall") or {}
    total = overall.get("assessments") or sum((subject.get("assessments") or 0) for subject in subjects)
    absent = overall.get("absent") or sum((subject.get("absent") or 0) for subject in subjects)

    if total < ENOUGH or not absent:
        return []

    if decimal.Decimal(absent) / decimal.Decimal(total) < MISSED_SHARE:
        return []

    return [
        insight(
            MISSED_TESTS,
            f"Absent for {absent} of {total} tests this term.",
            {"absent": absent, "tests": total},
        )
    ]


def may_explain(weak: list, attendance: dict) -> list[dict]:
    """Attendance, offered beside a weak subject.

    Only where something is weak: "attendance is 68%" on a page of good
    marks is a fact about the register, not an insight about the child. And
    only ever offered - the sentence says what attendance is, and stops
    short of saying it is the reason.

    Nothing is said about a term whose register was never taken: 0% there is
    a fact about the school's paperwork.
    """
    if not weak:
        return []

    rate = number(attendance.get("attendance_rate"))

    if rate is None or rate >= ATTENDANCE_MAY_EXPLAIN:
        return []

    # A term nobody took the register for reads as 0%, which is the truth
    # about the register and says nothing about the child. The product
    # counts unmarked days as unmarked everywhere else; a sentence drawn
    # from them would be the one place it accused somebody.
    marked = sum(attendance.get(key) or 0 for key in ("present", "absent", "leave"))

    if marked == 0:
        return []

    return [
        insight(
            ATTENDANCE,
            f"Attendance is {plain(rate)}% this term.",
            {
                "attendance_rate": plain(rate),
                "weak_subjects": [subject["subject_name"] for subject in weak],
            },
        )
    ]
