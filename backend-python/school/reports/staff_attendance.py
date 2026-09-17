"""Attendance and leave per staff member over a range.

Port of App\\Services\\Reports\\StaffAttendanceReport. Leave is counted from
the attendance marks rather than from the leave requests, because that is what
actually happened: an approved request writes a Leave mark on each working day
it covers. Approved requests are reported alongside, by type, for payroll.
"""

from __future__ import annotations

import functools
import math
import re

from django.db.models import Count

from ..enums import LeaveStatus, StaffAttendanceStatus
from ..models import StaffAttendance, StaffLeave, StaffProfile
from ..services import php_number
from .range import ReportRange

# A PHP "numeric string", which PHP 8 compares as a number rather than as text.
PHP_NUMERIC = re.compile(r"^\s*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\s*$")


def php_compare(left: str, right: str) -> int:
    """PHP's `<=>` on two strings, which is how Laravel's sortBy() orders
    names: two numeric strings as numbers, anything else byte by byte."""
    if PHP_NUMERIC.match(left) and PHP_NUMERIC.match(right):
        a, b = float(left), float(right)
    else:
        a, b = left.encode("utf-8"), right.encode("utf-8")

    return (a > b) - (a < b)


class StaffAttendanceReport:
    def build(self, report_range: ReportRange, filters: dict) -> dict:
        staff = StaffProfile.objects.filter(school_id=report_range.school_id)

        if filters.get("department_id"):
            staff = staff.filter(department_id=filters["department_id"])

        # A head of department sees their own departments and no others.
        # Present but empty means they head none, so they see nobody.
        if "department_ids" in filters:
            staff = staff.filter(department_id__in=filters["department_ids"])

        # By id first, so the stable sort by name keeps equal names in a fixed
        # order rather than whatever order the database felt like.
        staff = sorted(
            staff.select_related("user", "department").order_by("id"),
            key=functools.cmp_to_key(lambda a, b: php_compare(a.user.name, b.user.name)),
        )

        profile_ids = [profile.id for profile in staff]
        marks = self._marks_by_profile(report_range, profile_ids)
        leave_types = self._approved_leave_by_profile(report_range, profile_ids)
        days = report_range.working_day_count()

        rows = []
        for profile in staff:
            counts = marks.get(profile.id, {})
            present = counts.get(StaffAttendanceStatus.PRESENT, 0)
            half_day = counts.get(StaffAttendanceStatus.HALF_DAY, 0)
            absent = counts.get(StaffAttendanceStatus.ABSENT, 0)
            leave = counts.get(StaffAttendanceStatus.LEAVE, 0)

            rows.append({
                "staff_profile_id": profile.id,
                "employee_id": profile.employee_id,
                "name": profile.user.name,
                "department": profile.department.name if profile.department else None,
                "designation": profile.designation,
                "working_days": days,
                "present": present,
                "half_day": half_day,
                "absent": absent,
                "leave": leave,
                "not_marked": max(0, days - present - half_day - absent - leave),
                # A half day is half a day present - PHP's round() takes the
                # half up, where Python's would take it to even.
                "attendance_rate": php_number(report_range.rate(math.floor(present + half_day / 2 + 0.5))),
                # An empty PHP array goes out as [], a filled one as an object.
                "leave_by_type": leave_types.get(profile.id) or [],
            })

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": {
                "staff": len(rows),
                "working_days": days,
                "present": sum(row["present"] for row in rows),
                "absent": sum(row["absent"] for row in rows),
                "leave": sum(row["leave"] for row in rows),
                "not_marked": sum(row["not_marked"] for row in rows),
            },
        }

    def headings(self) -> list[str]:
        return [
            "Employee ID", "Name", "Department", "Designation", "Working days", "Present",
            "Half days", "Absent", "Leave", "Not marked", "Attendance %",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["employee_id"], row["name"], row["department"], row["designation"], row["working_days"],
                row["present"], row["half_day"], row["absent"], row["leave"], row["not_marked"], row["attendance_rate"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(int(totals[key]) for totals in branch_totals)

        return {
            "branches": len(branch_totals),
            "staff": total("staff"),
            "present": total("present"),
            "absent": total("absent"),
            "leave": total("leave"),
            "not_marked": total("not_marked"),
        }

    @staticmethod
    def _marks_by_profile(report_range: ReportRange, profile_ids: list[int]) -> dict[int, dict[str, int]]:
        marks: dict[int, dict[str, int]] = {}

        grouped = (
            StaffAttendance.objects.filter(
                school_id=report_range.school_id,
                staff_profile_id__in=profile_ids,
                attendance_date__range=(report_range.start, report_range.end),
                attendance_date__in=report_range.working_dates,
            )
            .values("staff_profile_id", "status")
            .annotate(total=Count("id"))
        )

        for row in grouped:
            marks.setdefault(row["staff_profile_id"], {})[row["status"]] = row["total"]

        return marks

    @staticmethod
    def _approved_leave_by_profile(report_range: ReportRange, profile_ids: list[int]) -> dict[int, dict[str, int]]:
        """Approved leave requests overlapping the range, counted by type."""
        leave: dict[int, dict[str, int]] = {}

        grouped = (
            StaffLeave.objects.filter(
                school_id=report_range.school_id,
                staff_profile_id__in=profile_ids,
                status=LeaveStatus.APPROVED,
                start_date__lte=report_range.end,
                end_date__gte=report_range.start,
            )
            .values("staff_profile_id", "leave_type")
            .annotate(total=Count("id"))
            .order_by("staff_profile_id", "leave_type")
        )

        for row in grouped:
            leave.setdefault(row["staff_profile_id"], {})[row["leave_type"]] = row["total"]

        return leave
