"""Whether teaching is happening as timetabled, per subject.

Port of App\\Services\\Reports\\TeachingCoverageReport. "Scheduled" is worked
out from the timetable and the calendar rather than stored: a Monday period is
scheduled once for every working Monday in the range, so a holiday that
removes a day does not count the periods that would have run on it as missed.
"""

from __future__ import annotations

from collections import Counter

from django.db.models import Count

from ..models import DailyTeachingReport, Subject, SyllabusTopic, SyllabusTopicProgress, TimetableEntry
from ..services import php_number
from .range import ReportRange, rate_of


class TeachingCoverageReport:
    def build(self, report_range: ReportRange, filters: dict) -> dict:
        scheduled = self._scheduled_per_subject(report_range, filters)
        reported = self._reported_per_subject(report_range, filters)
        syllabus = self._syllabus_per_subject(report_range, filters)

        subjects = Subject.objects.filter(school_id=report_range.school_id)

        # Present but empty: a head of department who heads nothing sees no
        # subjects, not all of them.
        if "department_ids" in filters:
            subjects = subjects.filter(department_id__in=filters["department_ids"])

        rows = []
        for subject in subjects.select_related("department").order_by("name", "id"):
            periods_scheduled = scheduled.get(subject.id, 0)
            periods_reported = reported.get(subject.id, 0)
            topics = syllabus.get(subject.id, {"total": 0, "completed": 0})

            rows.append({
                "subject_id": subject.id,
                "subject": subject.name,
                "department": subject.department.name if subject.department else None,
                "periods_scheduled": periods_scheduled,
                "periods_reported": periods_reported,
                # Periods on the timetable that nobody filed a report for.
                "periods_missing": max(0, periods_scheduled - periods_reported),
                "coverage_rate": php_number(rate_of(periods_reported, periods_scheduled)),
                "topics_total": topics["total"],
                "topics_completed": topics["completed"],
                "syllabus_completion": php_number(rate_of(topics["completed"], topics["total"])),
            })

        total_scheduled = sum(row["periods_scheduled"] for row in rows)
        total_reported = sum(row["periods_reported"] for row in rows)

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": {
                "subjects": len(rows),
                "periods_scheduled": total_scheduled,
                "periods_reported": total_reported,
                "periods_missing": max(0, total_scheduled - total_reported),
                "coverage_rate": php_number(rate_of(total_reported, total_scheduled)),
            },
        }

    def headings(self) -> list[str]:
        return [
            "Subject", "Department", "Periods scheduled", "Reports filed", "Missing",
            "Coverage %", "Topics", "Topics completed", "Syllabus %",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["subject"], row["department"], row["periods_scheduled"], row["periods_reported"],
                row["periods_missing"], row["coverage_rate"], row["topics_total"], row["topics_completed"],
                row["syllabus_completion"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(int(totals[key]) for totals in branch_totals)

        return {
            "branches": len(branch_totals),
            "subjects": total("subjects"),
            "periods_scheduled": total("periods_scheduled"),
            "periods_reported": total("periods_reported"),
            "periods_missing": total("periods_missing"),
            # Periods reported over periods scheduled, across the group.
            "coverage_rate": php_number(rate_of(total("periods_reported"), total("periods_scheduled"))),
        }

    @staticmethod
    def _scheduled_per_subject(report_range: ReportRange, filters: dict) -> dict[int, int]:
        # How many working days fall on each weekday - {"monday": 3, ...}.
        working_days_by_weekday = Counter(date.strftime("%A").lower() for date in report_range.working_dates)

        entries = TimetableEntry.objects.filter(school_id=report_range.school_id)

        if filters.get("class_section_id"):
            entries = entries.filter(class_section_id=filters["class_section_id"])

        scheduled: dict[int, int] = {}

        for entry in entries.values("subject_id", "day_of_week").annotate(periods=Count("id")):
            days = working_days_by_weekday.get(entry["day_of_week"], 0)
            scheduled[entry["subject_id"]] = scheduled.get(entry["subject_id"], 0) + entry["periods"] * days

        return scheduled

    @staticmethod
    def _reported_per_subject(report_range: ReportRange, filters: dict) -> dict[int, int]:
        reports = DailyTeachingReport.objects.filter(
            school_id=report_range.school_id,
            report_date__range=(report_range.start, report_range.end),
            report_date__in=report_range.working_dates,
            # The inner join Laravel's query makes.
            timetable_entry__isnull=False,
        )

        if filters.get("class_section_id"):
            reports = reports.filter(timetable_entry__class_section_id=filters["class_section_id"])

        return {
            row["timetable_entry__subject_id"]: row["total"]
            for row in reports.values("timetable_entry__subject_id").annotate(total=Count("id"))
        }

    @staticmethod
    def _syllabus_per_subject(report_range: ReportRange, filters: dict) -> dict[int, dict[str, int]]:
        """Topics and how many have been marked complete, per subject.

        Not bounded by the range: a syllabus is cumulative progress through a
        year, and "35% covered" means 35% of the course, not of one month.
        """
        totals = SyllabusTopic.objects.filter(school_id=report_range.school_id).values("subject_id").annotate(
            total=Count("id")
        )

        completed = SyllabusTopicProgress.objects.filter(school_id=report_range.school_id)

        if filters.get("class_section_id"):
            completed = completed.filter(class_section_id=filters["class_section_id"])

        completed_by_subject = {
            row["syllabus_topic__subject_id"]: row["total"]
            for row in completed.values("syllabus_topic__subject_id").annotate(
                total=Count("syllabus_topic_id", distinct=True)
            )
        }

        return {
            row["subject_id"]: {"total": row["total"], "completed": completed_by_subject.get(row["subject_id"], 0)}
            for row in totals
        }
