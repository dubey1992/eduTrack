"""How far each class has got through each subject's syllabus (Phase 20).

Phase 18's teaching coverage report gives syllabus completion per subject,
across every class that studies it. This splits it by class section: one line
per section and subject, so "Physics is 40% covered" becomes "8 A is at 70%
and 8 B at 10%", which is the conversation a head of department has to have.

Which lines there are: every section of the school's current academic year,
with every subject whose class levels include that section's class and which
has a syllabus - a subject with no topics has nothing to be through.

Completion is not bounded by the range: it is progress through a year's
course. The range decides one column, **completed in period** - topics marked
complete between its first and last day at the school - and that is the
figure the previous-period comparison reads.
"""

from __future__ import annotations

import zoneinfo

from django.db.models import Count

from ..clock import SchoolClock
from ..models import ClassSection, Subject, SyllabusTopic, SyllabusTopicProgress, TimetableEntry
from ..services import php_number
from .range import ReportRange, rate_of


class SyllabusProgressReport:
    TITLE = "Syllabus progress by class"
    PDF_NOTE = "Syllabus % is progress through the year's course; only 'Completed in period' depends on the dates."
    # Compared with the previous period when one is asked for (comparison.py).
    COMPARED_ROWS = [("completed_in_period", "Completed in period")]

    @staticmethod
    def row_key(row: dict):
        return (row["class_section_id"], row["subject_id"])

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        school_id = report_range.school_id

        sections = ClassSection.objects.filter(
            school_class__school_id=school_id, school_class__academic_year__is_current=True
        ).select_related("school_class")
        if filters.get("class_section_id"):
            sections = sections.filter(id=filters["class_section_id"])
        sections = list(sections.order_by("school_class__level", "school_class__name", "name", "id"))

        subjects = Subject.objects.filter(school_id=school_id).select_related("department")
        if filters.get("department_id"):
            subjects = subjects.filter(department_id=filters["department_id"])
        # A head of department sees their own departments and no others.
        # Present but empty means they head none, so they see nothing.
        if "department_ids" in filters:
            subjects = subjects.filter(department_id__in=filters["department_ids"])
        subjects = list(subjects.order_by("name", "id"))

        topics = self._topics_per_subject(school_id)
        progress = self._progress(report_range, [section.id for section in sections])
        zone = zoneinfo.ZoneInfo(SchoolClock.for_school(school_id).timezone())
        teachers = self._teachers(school_id, [section.id for section in sections])

        rows = []
        for section in sections:
            level = section.school_class.level

            for subject in subjects:
                total = topics.get(subject.id, 0)
                if total == 0 or not subject.min_class_level <= level <= subject.max_class_level:
                    continue

                done = progress.get((section.id, subject.id), {})
                completed = done.get("completed", 0)
                last = done.get("last")

                rows.append({
                    "class_section_id": section.id,
                    "class_section": f"{section.school_class.name} {section.name}",
                    "subject_id": subject.id,
                    "subject": subject.name,
                    "department": subject.department.name if subject.department else None,
                    "teacher": ", ".join(teachers.get((section.id, subject.id), [])) or None,
                    "topics_total": total,
                    "topics_completed": completed,
                    "syllabus_completion": php_number(rate_of(completed, total)),
                    "completed_in_period": done.get("in_period", 0),
                    # The school's calendar date, not the UTC one.
                    "last_completed_on": None if last is None else last.astimezone(zone).date().isoformat(),
                })

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": self._totals(rows),
        }

    def headings(self) -> list[str]:
        return [
            "Class", "Subject", "Department", "Teacher", "Topics", "Topics completed", "Syllabus %",
            "Completed in period", "Last completed on",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["class_section"], row["subject"], row["department"], row["teacher"], row["topics_total"],
                row["topics_completed"], row["syllabus_completion"], row["completed_in_period"],
                row["last_completed_on"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(totals[key] for totals in branch_totals)

        return {
            "branches": len(branch_totals),
            "classes_and_subjects": total("classes_and_subjects"),
            "topics_total": total("topics_total"),
            "topics_completed": total("topics_completed"),
            # Topics completed over topics set, across the group - never an
            # average of the branches' percentages.
            "syllabus_completion": php_number(rate_of(total("topics_completed"), total("topics_total"))),
            "completed_in_period": total("completed_in_period"),
        }

    @staticmethod
    def _totals(rows: list[dict]) -> dict:
        topics = sum(row["topics_total"] for row in rows)
        completed = sum(row["topics_completed"] for row in rows)

        return {
            "classes_and_subjects": len(rows),
            "topics_total": topics,
            "topics_completed": completed,
            "syllabus_completion": php_number(rate_of(completed, topics)),
            "completed_in_period": sum(row["completed_in_period"] for row in rows),
        }

    @staticmethod
    def _topics_per_subject(school_id: int) -> dict[int, int]:
        return dict(
            SyllabusTopic.objects.filter(school_id=school_id)
            .values("subject_id")
            .annotate(total=Count("id"))
            .values_list("subject_id", "total")
        )

    @staticmethod
    def _progress(report_range: ReportRange, section_ids: list[int]) -> dict[tuple, dict]:
        """Per (section, subject): topics completed, how many of them inside
        the range, and when the last one was.

        `completed_at` is an instant, so the range is turned into the school's
        own day boundaries - a topic finished at 11 pm is on that day at the
        school, whatever the date in UTC.
        """
        clock = SchoolClock.for_school(report_range.school_id)
        start = clock.start_of_day_utc(report_range.start)
        end = clock.end_of_day_utc(report_range.end)  # exclusive

        progress: dict[tuple, dict] = {}
        rows = SyllabusTopicProgress.objects.filter(
            school_id=report_range.school_id, class_section_id__in=section_ids
        ).values_list("class_section_id", "syllabus_topic__subject_id", "completed_at")

        for section_id, subject_id, completed_at in rows:
            entry = progress.setdefault((section_id, subject_id), {"completed": 0, "in_period": 0, "last": None})
            entry["completed"] += 1
            if start <= completed_at < end:
                entry["in_period"] += 1
            if entry["last"] is None or completed_at > entry["last"]:
                entry["last"] = completed_at

        return progress

    @staticmethod
    def _teachers(school_id: int, section_ids: list[int]) -> dict[tuple, list[str]]:
        """Who teaches each subject to each section, from the timetable."""
        teachers: dict[tuple, set[str]] = {}

        entries = TimetableEntry.objects.filter(
            school_id=school_id, class_section_id__in=section_ids, teacher__isnull=False
        ).select_related("teacher")

        for entry in entries:
            teachers.setdefault((entry.class_section_id, entry.subject_id), set()).add(entry.teacher.name)

        return {key: sorted(names) for key, names in teachers.items()}
