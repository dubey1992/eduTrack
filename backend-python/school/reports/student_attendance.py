"""Attendance per student over a range.

Port of App\\Services\\Reports\\StudentAttendanceReport. The denominator is
the school's working days, not the days that happen to have a register - so a
class whose teacher never marked attendance reads as 0%, which is the truth,
rather than as having no data.
"""

from __future__ import annotations

from django.db.models import Count

from ..enums import AttendanceStatus, StudentStatus
from ..models import Attendance, Student, StudentEnrollment
from ..services import php_number
from .range import ReportRange, rate_of


def section_label(section) -> str | None:
    """"Grade 8 A", or nothing at all when a student has no class."""
    if section is None:
        return None

    return f"{section.school_class.name if section.school_class else ''} {section.name}".strip()


class StudentAttendanceReport:
    TITLE = "Student attendance"
    # Compared with the previous period when one is asked for (comparison.py).
    COMPARED_ROWS = [("attendance_rate", "Attendance %")]

    @staticmethod
    def row_key(row: dict):
        return row["student_id"]

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        students = self._roster(report_range, filters)
        marks = self._marks_by_student(report_range, [student.id for student in students])
        # Which class each of them was in while this range was being lived,
        # rather than the class they are in now (docs/promotion.md).
        classes = self._classes_during(report_range, students, filters)
        days = report_range.working_day_count()

        rows = []
        for student in students:
            counts = marks.get(student.id, {})
            present = counts.get(AttendanceStatus.PRESENT, 0)
            absent = counts.get(AttendanceStatus.ABSENT, 0)
            leave = counts.get(AttendanceStatus.LEAVE, 0)

            rows.append({
                "student_id": student.id,
                "admission_number": student.admission_number,
                "name": student.name,
                "class_section": classes.get(student.id),
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

    @staticmethod
    def _roster(report_range: ReportRange, filters: dict):
        """Who this report is about.

        The school's active students, plus anybody who has a mark inside the
        range - a child who has since graduated or left was there for the
        year being reported on, and a report that quietly dropped them would
        raise every percentage around them.
        """
        students = Student.objects.filter(school_id=report_range.school_id)
        section_id = filters.get("class_section_id")

        was_here = Attendance.objects.filter(
            school_id=report_range.school_id,
            attendance_date__range=(report_range.start, report_range.end),
        )

        if section_id:
            was_here = was_here.filter(class_section_id=section_id)

        attended = set(was_here.values_list("student_id", flat=True))
        here_now = students.filter(status=StudentStatus.ACTIVE)

        if section_id:
            here_now = here_now.filter(class_section_id=section_id)

        wanted = set(here_now.values_list("id", flat=True)) | attended

        return list(
            students.filter(id__in=wanted)
            .select_related("class_section__school_class")
            .order_by("first_name", "last_name", "id")
        )

    @staticmethod
    def _classes_during(report_range: ReportRange, students: list, filters: dict) -> dict:
        """The class each student sat in during the range.

        Read from the register itself, which snapshots the section on every
        row, and then from the year's enrollment where nobody ever took one.
        The student's own `class_section_id` is the last resort, because it
        is the present tense: after a promotion it names next year's class,
        and last year's report would read as though the year had been spent
        there.
        """
        labelled: dict[int, str] = {}
        ids = [student.id for student in students]

        marked = (
            Attendance.objects.filter(
                student_id__in=ids, attendance_date__range=(report_range.start, report_range.end)
            )
            .select_related("class_section__school_class")
            .order_by("student_id", "-attendance_date")
        )

        for row in marked:
            labelled.setdefault(row.student_id, section_label(row.class_section))

        missing = [student for student in students if student.id not in labelled]

        if missing:
            enrolled = (
                StudentEnrollment.objects.filter(
                    student_id__in=[student.id for student in missing],
                    academic_year__start_date__lte=report_range.end,
                    academic_year__end_date__gte=report_range.start,
                )
                .select_related("school_class", "class_section")
                .order_by("student_id", "-academic_year__start_date")
            )

            for row in enrolled:
                section = row.class_section.name if row.class_section_id else ""
                labelled.setdefault(row.student_id, f"{row.school_class.name} {section}".strip())

        for student in missing:
            labelled.setdefault(student.id, section_label(student.class_section))

        return labelled

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
