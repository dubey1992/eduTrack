"""Homework for parents (docs/mobile-apps-review.md, M8, 8.1).

Every Homework box a teacher fills on a teaching report is shown to the
parents of that class, under the day it was set (decided 2026-11-24: all of
it, no "send to parents" tick). Nothing is copied: it is read from
`daily_teaching_reports.homework`, so a teacher who corrects a report
corrects what the parents see.

- `homework_for` - a child's homework over the last days, newest first.
- `send_digest`  - the evening push: once a day, after `DIGEST_AT` on the
                   school's clock, one Family-app message per child whose
                   class was set homework that day ("3 homework items for
                   today"). In the app only, never SMS. Run from cron with
                   the other quarter-hourly jobs.
"""

from __future__ import annotations

import datetime as dt

from . import dates, modules
from .clock import SchoolClock
from .enums import MessageEvent, SchoolStatus, StudentStatus
from .models import DailyTeachingReport, Message, School, Student

# The evening push goes after this, on the school's own clock - late enough
# for the day's reports to be in, early enough to be useful tonight.
DIGEST_AT = dt.time(18, 0)

# How far back the Homework screen looks.
DAYS_SHOWN = 14


def _reports(section_id: int, since: dt.date, until: dt.date):
    return (
        DailyTeachingReport.objects.filter(
            timetable_entry__class_section_id=section_id,
            report_date__gte=since,
            report_date__lte=until,
        )
        .exclude(homework__isnull=True)
        .exclude(homework="")
        .select_related("timetable_entry__subject", "timetable_entry__period")
        .order_by("-report_date", "timetable_entry__period__start_time", "id")
    )


def homework_for(student: Student, days: int = DAYS_SHOWN) -> dict:
    """The child's class's homework over the last [days] school days' worth
    of calendar, newest day first; each day's items in the order of the
    periods they were set in."""
    if student.class_section_id is None:
        return {"days": []}

    today = SchoolClock.for_school(student.school_id).now().date()
    grouped: dict[dt.date, list[dict]] = {}

    for report in _reports(student.class_section_id, today - dt.timedelta(days=days - 1), today):
        entry = report.timetable_entry
        subject = entry.subject
        grouped.setdefault(report.report_date, []).append({
            "id": report.id,
            "subject": subject.name if subject is not None else None,
            "homework": report.homework.strip(),
        })

    return {
        "days": [
            {"date": day.isoformat(), "date_label": dates.us(day), "today": day == today, "items": items}
            for day, items in grouped.items()
        ],
    }


def send_digest(at: dt.datetime | None = None, school_id: int | None = None) -> int:
    """The evening push for every school that has the Family app. Returns
    how many children's families were told. [at] is for tests."""
    schools = School.objects.filter(status=SchoolStatus.ACTIVE)
    if school_id is not None:
        schools = schools.filter(pk=school_id)

    told = 0
    for school in schools:
        if not modules.is_enabled(school.id, "family_app"):
            continue

        clock = SchoolClock.for_school(school.id)
        now = at.astimezone(clock.now().tzinfo) if at is not None else clock.now()
        if now.time() < DIGEST_AT:
            continue

        told += _digest_for(school, now.date(), clock)

    return told


def _digest_for(school: School, day: dt.date, clock: SchoolClock) -> int:
    from .notifications import copy_to_family_app

    by_section: dict[int, list[str]] = {}
    for report in (
        DailyTeachingReport.objects.filter(school_id=school.id, report_date=day)
        .exclude(homework__isnull=True)
        .exclude(homework="")
        .select_related("timetable_entry__subject")
    ):
        subject = report.timetable_entry.subject
        by_section.setdefault(report.timetable_entry.class_section_id, []).append(
            subject.name if subject is not None else "Homework"
        )

    if not by_section:
        return 0

    start = clock.start_of_day_utc(day)
    already = set(
        Message.objects.filter(
            school_id=school.id, event=MessageEvent.HOMEWORK_FOR_FAMILY, created_at__gte=start
        ).values_list("student_id", flat=True)
    )

    told = 0
    for section_id, subjects in by_section.items():
        count = len(subjects)
        for student in Student.objects.filter(class_section_id=section_id, status=StudentStatus.ACTIVE):
            if student.id in already:
                continue

            copies = copy_to_family_app(
                MessageEvent.HOMEWORK_FOR_FAMILY,
                student,
                {
                    "student_name": student.name,
                    "count": str(count),
                    "items": "homework item" if count == 1 else "homework items",
                    "subjects": ", ".join(dict.fromkeys(subjects)),
                    "date": dates.us(day),
                    "school_name": school.name,
                },
                subject="Homework for today",
            )
            if copies:
                told += 1

    return told
