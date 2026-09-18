"""Attendance per student over a range.

Port of App\\Services\\Reports\\StudentAttendanceReport. The denominator is
the school's working days, not the days that happen to have a register - so a
class whose teacher never marked attendance reads as 0%, which is the truth,
rather than as having no data.
"""

from __future__ import annotations

from django.db.models import Count

from ..enums import AttendanceStatus, StudentStatus
from ..models import Attendance, Student
from ..services import php_number
from .range import ReportRange, rate_of


class StudentAttendanceReport:
    TITLE = "Student attendance"
    # Compared with the previous period when one is asked for (comparison.py).
    COMPARED_ROWS = [("attendance_rate", "Attendance %")]

    @staticmethod
    def row_key(row: dict):
        return row["student_id"]

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        students = Student.objects.filter(school_id=report_range.school_id, status=StudentStatus.ACTIVE)

        if filters.get("class_section_id"):
            students = students.filter(class_section_id=filters["class_section_id"])

        students = list(
            students.select_related("class_section__school_class").order_by("first_name", "last_name", "id")
        )
        marks = self._marks_by_student(report_range, [student.id for student in students])
        days = report_range.working_day_count()

        rows = []
        for student in students:
            counts = marks.get(student.id, {})
            present = counts.get(AttendanceStatus.PRESENT, 0)
            absent = counts.get(AttendanceStatus.ABSENT, 0)
            leave = counts.get(AttendanceStatus.LEAVE, 0)
            section = student.class_section

            rows.append({
                "student_id": student.id,
                "admission_number": student.admission_number,
                "name": student.name,
                "class_section": (
                    None
                    if section is None
                    else f"{section.school_class.name if section.school_class else ''} {section.name}".strip()
                ),
                "working_days": days,
                "present": present,
                "absent": absent,
                "leave": leave,
                # Days with no mark at all - nobody said this student was away,
                # only that the register was never taken.
                "not_marked": max(0, days - present - absent - leave),
                "attendance_rate": php_number(report_range.rate(present)),
            })

        totals = self._totals(rows, report_range)

        # Chronic absentees (Phase 20): only the students whose rate is under
        # the threshold. The totals still describe the whole class - a class
        # rate worked out from its weakest students alone would be no rate at
        # all - and say how many fell under. A student with no rate (a range
        # with no working day) is not under anything.
        below = filters.get("below")
        if below is not None:
            rows = [row for row in rows if row["attendance_rate"] is not None and row["attendance_rate"] < below]
            totals["below"] = php_number(below)
            totals["students_below"] = len(rows)

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": totals,
        }

    def headings(self) -> list[str]:
        return ["Admission No.", "Student", "Class", "Working days", "Present", "Absent", "Leave", "Not marked", "Attendance %"]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["admission_number"], row["name"], row["class_section"], row["working_days"],
                row["present"], row["absent"], row["leave"], row["not_marked"], row["attendance_rate"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(int(totals[key]) for totals in branch_totals)

        # Recomputed from raw counts, never averaged: each branch measures
        # against its own working days.
        possible = sum(int(totals["students"]) * int(totals["working_days"]) for totals in branch_totals)

        combined = {
            "branches": len(branch_totals),
            "students": total("students"),
            "present": total("present"),
            "absent": total("absent"),
            "leave": total("leave"),
            "not_marked": total("not_marked"),
            "attendance_rate": php_number(rate_of(total("present"), possible)),
        }

        if branch_totals and all("students_below" in totals for totals in branch_totals):
            combined["below"] = branch_totals[0]["below"]
            combined["students_below"] = total("students_below")

        return combined

    @staticmethod
    def _marks_by_student(report_range: ReportRange, student_ids: list[int]) -> dict[int, dict[str, int]]:
        """One grouped query for every student's marks. A day that has since
        become a holiday is no longer a working day, so its marks stop
        counting towards a rate measured against working days."""
        marks: dict[int, dict[str, int]] = {}

        grouped = (
            Attendance.objects.filter(
                school_id=report_range.school_id,
                student_id__in=student_ids,
                attendance_date__range=(report_range.start, report_range.end),
                attendance_date__in=report_range.working_dates,
            )
            .values("student_id", "status")
            .annotate(total=Count("id"))
        )

        for row in grouped:
            marks.setdefault(row["student_id"], {})[row["status"]] = row["total"]

        return marks

    @staticmethod
    def _totals(rows: list[dict], report_range: ReportRange) -> dict:
        present = sum(row["present"] for row in rows)
        days = report_range.working_day_count()

        return {
            "students": len(rows),
            "working_days": days,
            "present": present,
            "absent": sum(row["absent"] for row in rows),
            "leave": sum(row["leave"] for row in rows),
            "not_marked": sum(row["not_marked"] for row in rows),
            "attendance_rate": php_number(rate_of(present, len(rows) * days)),
        }
