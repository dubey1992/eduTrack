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
WEAK_TOPIC = "weak_topic"
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

        found.extend(weak_chapters(subject, weak_below))
        found.extend(moved(subject, previous_term))

    found.extend(missed(performance, subjects))
    found.extend(may_explain(weak, attendance))

    return found


def weak_chapters(subject: dict, weak_below) -> list[dict]:
    """A chapter under the school's mark, whatever the subject averages.

    This is the whole point of reading the topic a test was about. A
    subject at 70% looks like a child who is fine; if the trigonometry half
    of it is at 30%, that is a weak area the average was hiding, and saying
    only "Mathematics is 70%" would be the page keeping it hidden.
    """
    if weak_below is None:
        return []

    found = []

    for topic in weak_topics_of(subject, weak_below):
        average = number(topic.get("average_percentage"))

        found.append(
            insight(
                WEAK_TOPIC,
                f"{topic['topic_name']} in {subject['subject_name']} is at {plain(average)}%, "
                f"below the school's {plain(weak_below)}% mark.",
                {
                    "average": plain(average),
                    "threshold": plain(weak_below),
                    "topic_id": topic.get("topic_id"),
                    "topic_name": topic.get("topic_name"),
                    "subject_average": plain(number(subject.get("average_percentage"))),
                },
                subject,
            )
        )

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


# -- what to do about it ------------------------------------------------------
#
# A finding says what the numbers are; a recommendation says what somebody
# could do next. Both are rules, both carry the figures they came from, and
# both live here so that "what the page says" has one home.
#
# The line this does not cross: it suggests an action a teacher was always
# free to take - revise a chapter, arrange a re-sit, speak to a guardian -
# and never advises how to teach. The product knows what the marks say. It
# does not know the child, and it should not pretend to.

REVISE_TOPICS = "revise_topics"
PRACTISE_SUBJECT = "practise_subject"
CHECK_WHAT_CHANGED = "check_what_changed"
ARRANGE_RESIT = "arrange_resit"
ATTENDANCE_FIRST = "attendance_first"


def recommendation(code: str, message: str, numbers: dict, subject: dict | None = None) -> dict:
    return {
        "code": code,
        "message": message,
        "subject_id": None if subject is None else subject.get("subject_id"),
        "subject_name": None if subject is None else subject.get("subject_name"),
        "numbers": numbers,
    }


def recommendations_for(performance: dict) -> list[dict]:
    """One next step per finding, drawn from figures the page already shows.

    Ordered the way somebody would act on them: the thing that is weak, the
    thing that moved, and then what might be behind both.

    Nothing is suggested from fewer than two published results, for the same
    reason nothing is said from fewer: one test is not a trend, and an
    instruction drawn from a single mark is worse than silence.
    """
    subjects = performance.get("subjects") or []
    weak_below = number(performance.get("weak_below_percentage"))
    previous_term = performance.get("previous_term") or {}
    attendance = performance.get("attendance") or {}

    found = []
    weak = []

    for subject in subjects:
        if (subject.get("assessments") or 0) < ENOUGH:
            continue

        average = number(subject.get("average_percentage"))

        # A weak chapter earns revision whatever the subject averages; the
        # subject itself earns practice only when it is weak as a whole.
        is_weak = weak_below is not None and average is not None and average < weak_below

        if is_weak:
            weak.append(subject)

        found.extend(what_to_revise(subject, average, weak_below, is_weak))
        found.extend(what_changed(subject, previous_term))

    found.extend(resit(performance, subjects))
    found.extend(attendance_first(weak, attendance))

    return found


def weak_topics_of(subject: dict, weak_below) -> list[dict]:
    """The chapters inside a weak subject that are themselves weak.

    A topic nobody has measured is not weak - the student was absent for
    every test on it, and there is nothing to revise *because of*.
    """
    topics = subject.get("topics") or []
    found = []

    for topic in topics:
        average = number(topic.get("average_percentage"))

        if average is not None and average < weak_below:
            found.append(topic)

    return found


def what_to_revise(subject: dict, average, weak_below, is_weak: bool) -> list[dict]:
    """Which chapters to go back over, or - where no test named one - that
    the subject as a whole needs practice.

    One or the other, never both: naming the chapters is strictly better
    advice than naming the subject, and a page that said both would be
    telling somebody the same thing twice.

    The chapters are checked whatever the subject averages. A subject at
    70% with a chapter at 30% is exactly the case the topic breakdown
    exists for, and requiring the subject to be weak first would hide it
    again.
    """
    if weak_below is None:
        return []

    topics = weak_topics_of(subject, weak_below)

    if topics:
        names = [topic["topic_name"] for topic in topics]

        return [
            recommendation(
                REVISE_TOPICS,
                f"Revise {and_list(names)} in {subject['subject_name']} "
                f"before the next test.",
                {
                    "topics": names,
                    "averages": [plain(number(topic.get("average_percentage"))) for topic in topics],
                    "threshold": plain(weak_below),
                },
                subject,
            )
        ]

    if not is_weak:
        return []

    against = number(subject.get("class_average_percentage"))
    gap = (
        ""
        if against is None
        else f" The class averaged {plain(against)}%."
    )

    return [
        recommendation(
            PRACTISE_SUBJECT,
            f"Set extra practice in {subject['subject_name']} - it is at {plain(average)}%.{gap}",
            {
                "average": plain(average),
                "class_average": plain(against),
                "threshold": plain(weak_below),
            },
            subject,
        )
    ]


def what_changed(subject: dict, previous_term: dict) -> list[dict]:
    """A subject that has fallen is worth asking about before it falls
    further. A subject that has risen needs nothing done to it."""
    change = number(subject.get("change"))

    if change is None or change > -MOVED:
        return []

    since = previous_term.get("name")
    when = "" if since is None else f" since {since}"

    return [
        recommendation(
            CHECK_WHAT_CHANGED,
            f"Find out what changed in {subject['subject_name']} - it is down "
            f"{plain(abs(change))} points{when}.",
            {
                "change": plain(change),
                "average": plain(number(subject.get("average_percentage"))),
                "previous": plain(number(subject.get("previous_average_percentage"))),
            },
            subject,
        )
    ]


def resit(performance: dict, subjects: list) -> list[dict]:
    """Tests missed are marks nobody has. Offering them again is the only
    way the term's figures come to describe the student rather than their
    attendance."""
    overall = performance.get("overall") or {}
    total = overall.get("assessments") or sum((subject.get("assessments") or 0) for subject in subjects)
    absent = overall.get("absent") or sum((subject.get("absent") or 0) for subject in subjects)

    if total < ENOUGH or not absent:
        return []

    if decimal.Decimal(absent) / decimal.Decimal(total) < MISSED_SHARE:
        return []

    return [
        recommendation(
            ARRANGE_RESIT,
            f"Offer a re-sit for the {absent} test{'s' if absent != 1 else ''} missed, "
            f"of {total} this term.",
            {"absent": absent, "tests": total},
        )
    ]


def attendance_first(weak: list, attendance: dict) -> list[dict]:
    """Where a child is both behind and often away, the attendance is the
    thing to take up first - and with the guardian, because it is not
    something a teacher can fix inside a lesson.

    Only beside a weak subject, and never from a register nobody took: the
    same two guards may_explain() keeps, for the same reasons.
    """
    if not weak:
        return []

    rate = number(attendance.get("attendance_rate"))

    if rate is None or rate >= ATTENDANCE_MAY_EXPLAIN:
        return []

    marked = sum(attendance.get(key) or 0 for key in ("present", "absent", "leave"))

    if marked == 0:
        return []

    return [
        recommendation(
            ATTENDANCE_FIRST,
            f"Take attendance up with the guardian before the next test - it is "
            f"{plain(rate)}% this term.",
            {
                "attendance_rate": plain(rate),
                "weak_subjects": [subject["subject_name"] for subject in weak],
            },
        )
    ]


def and_list(names: list) -> str:
    """"Vectors", "Vectors and Waves", "Vectors, Waves and Optics"."""
    if len(names) == 1:
        return names[0]

    return f"{', '.join(names[:-1])} and {names[-1]}"
