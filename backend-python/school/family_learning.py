"""What the Family app shows a parent about a child's learning
(docs/parent-student-app.md, F2). Read only, and like family_day.py, every
function takes a child the caller has already been checked against.

- `results_for`        - the term's published tests, subject by subject:
                         the mark, the grade frozen at publish, and the class
                         average when the school shows it.
- `progress_report_of` - the progress report PDF, once the term is over.
- `timetable_for`      - the class's week.
- `syllabus_for`       - each subject's topics covered so far.

Nothing unpublished ever leaves here: a draft test, its marks and its
grades stay with the teacher until they publish (Assessment.status).
"""

from __future__ import annotations

import datetime as dt

from . import modules, performance, progress_reports, syllabus_scope, week
from .clock import DATE_TIME, SchoolClock
from .marks import percentage_of
from .models import AcademicTerm, School, Student, SyllabusTopic, SyllabusTopicProgress
from .school_breaks import breaks_of
from .services import TimetableService, percent_of

MODULE = "family_app"


def text(value) -> str | None:
    """A mark or a percentage as the API sends them: a string, never a float."""
    return None if value is None else str(value)


def shows_class_average(school_id) -> bool:
    return bool(modules.setting(school_id, MODULE, "show_class_average"))


def school_today(student: Student) -> dt.date:
    return SchoolClock.for_school(student.school_id).now().date()


def term_of(student: Student, term_id: int | None) -> AcademicTerm | None:
    """The term asked for - only one of the child's own year - or the one
    being lived. A term of another year or school is no term at all."""
    if term_id is None:
        return performance.default_term(student, school_today(student))

    return performance.terms_of(student).filter(pk=term_id).first()


# -- results ------------------------------------------------------------------------


def results_for(student: Student, term_id: int | None = None) -> dict:
    term = term_of(student, term_id)
    today = school_today(student)
    averages_shown = shows_class_average(student.school_id)

    marks = list(performance.published_marks(student, term)) if term is not None else []
    averages = (
        performance.StudentPerformance.class_averages([mark.assessment_id for mark in marks]) if averages_shown else {}
    )
    summary = performance.StudentPerformance.subjects(student, term, None) if term is not None else []
    by_subject = {row["subject_id"]: row for row in summary}

    subjects: dict[int, dict] = {}
    for mark in marks:
        assessment = mark.assessment
        row = by_subject.get(assessment.subject_id, {})
        entry = subjects.setdefault(
            assessment.subject_id,
            {
                "subject": assessment.subject.name,
                "average_percentage": row.get("average_percentage"),
                "grade": row.get("grade"),
                "class_average_percentage": row.get("class_average_percentage") if averages_shown else None,
                "tests": [],
            },
        )
        entry["tests"].append(
            {
                "id": assessment.id,
                "title": assessment.title,
                "type": assessment.type,
                "date": assessment.assessment_date.isoformat() if assessment.assessment_date else None,
                "max_marks": text(assessment.max_marks),
                "marks_obtained": text(mark.marks_obtained),
                # Absent is not zero, here as everywhere.
                "is_absent": mark.is_absent,
                "percentage": text(percentage_of(mark)),
                "grade": mark.grade,
                "remarks": mark.remarks or None,
                "class_average_percentage": text(averages.get(assessment.id)) if averages_shown else None,
            }
        )

    return {
        "terms": [performance.StudentPerformance.term_resource(row) for row in performance.terms_of(student)],
        "term": performance.StudentPerformance.term_resource(term),
        "shows_class_average": averages_shown,
        "subjects": list(subjects.values()),
        "remark": remark_of(student, term),
        "progress_report": report_availability(term, today),
    }


def remark_of(student: Student, term: AcademicTerm | None) -> str | None:
    """The class teacher's remark for the term - the words only, not who."""
    found = performance.StudentPerformance.remark(student, term)
    return found["text"] if found else None


def report_availability(term: AcademicTerm | None, today: dt.date) -> dict:
    """A progress report is a report on a term, so it is ready when the term
    is over - before then it would be a report on half a term."""
    if term is None:
        return {"available": False, "from": None}

    return {"available": term.end_date < today, "from": (term.end_date + dt.timedelta(days=1)).isoformat()}


def progress_report_of(student: Student, term_id: int | None) -> tuple[bytes, str] | None:
    """The term's progress report as the office would print it, or None while
    the term is not over (or there is no such term for this child)."""
    term = term_of(student, term_id)
    if term is None or not report_availability(term, school_today(student))["available"]:
        return None

    payload = performance.for_student(student, term.id)
    clock = SchoolClock.for_school(student.school_id)
    document = progress_reports.render(
        payload, school=School.objects.get(pk=student.school_id), generated_at=clock.format(clock.now(), DATE_TIME)
    )

    return document, progress_reports.file_name(payload)


# -- the week's timetable ----------------------------------------------------------------


def timetable_for(student: Student) -> dict:
    """The class's week, Monday first, each school day with its periods and
    breaks in the order the bells ring - half days with their own bells."""
    school = School.objects.get(pk=student.school_id)
    working = week.WorkingWeek(school.working_days)
    today = school_today(student)

    entries = []
    if student.class_section_id is not None:
        entries = list(
            TimetableService.this_year(
                TimetableService.for_class_section(student.class_section_id), student.school_id
            ).order_by("period__start_time", "period__period_number")
        )

    days = []
    for day, shape in working.shapes.items():
        periods = [
            {
                "period_number": entry.period.period_number,
                "start_time": entry.period.start_time.strftime("%H:%M"),
                "end_time": entry.period.end_time.strftime("%H:%M"),
                "subject": entry.subject.name if entry.subject_id else None,
                "teacher": entry.teacher.name if entry.teacher_id else None,
            }
            for entry in entries
            if entry.day_of_week == day and entry.period.day_shape == shape
        ]
        breaks = [
            {"name": row.name, "start_time": row.start_time.strftime("%H:%M"),
             "end_time": row.end_time.strftime("%H:%M")}
            for row in breaks_of(student.school_id, shape)
        ]
        days.append({"day": day, "shape": shape, "periods": periods, "breaks": breaks})

    return {"today": week.DAYS[today.weekday()], "days": days}


# -- syllabus --------------------------------------------------------------------------


def syllabus_for(student: Student) -> dict:
    """Each subject the class is taught this year, and how many of its topics
    the class has covered - "Science: 14 of 22 topics covered"."""
    section_id = student.class_section_id
    if section_id is None:
        return {"subjects": []}

    subjects = {
        entry.subject_id: entry.subject.name
        for entry in TimetableService.this_year(TimetableService.for_class_section(section_id), student.school_id)
        if entry.subject_id
    }
    level = syllabus_scope.level_of_section(section_id)
    topics = list(
        syllabus_scope.for_level(
            SyllabusTopic.objects.filter(school_id=student.school_id, subject_id__in=subjects), level
        ).order_by("sequence_number", "id")
    )
    covered = set(
        SyllabusTopicProgress.objects.filter(
            class_section_id=section_id, syllabus_topic_id__in=[topic.id for topic in topics]
        ).values_list("syllabus_topic_id", flat=True)
    )

    rows = []
    for subject_id, name in sorted(subjects.items(), key=lambda item: item[1]):
        own = [topic for topic in topics if topic.subject_id == subject_id]
        done = [topic for topic in own if topic.id in covered]
        rows.append(
            {
                "subject": name,
                "total_topics": len(own),
                "covered_topics": len(done),
                "percent": percent_of(len(done), len(own)),
                # The next topics, so a parent knows what is coming.
                "next_topics": [topic.title for topic in own if topic.id not in covered][:3],
            }
        )

    return {"subjects": rows}
