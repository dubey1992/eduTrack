"""How much leave each member of staff took over a range, and of what kind
(Phase 20).

Leave taken is counted from approved requests, in working days: a request
that runs over a weekend or a holiday takes no leave for those days, and one
that runs past either end of the range counts only the days inside it. A
half-day leave is half a day for each day it covers.

Alongside it, what is still waiting (pending requests), what was turned down,
and the days marked absent - absence with no leave behind it, which is the
figure a head of department most wants to see.
"""

from __future__ import annotations

from django.db.models import Count

from ..enums import LeaveStatus, LeaveType, StaffAttendanceStatus
from ..models import StaffAttendance, StaffLeave, StaffProfile
from ..services import HodReportService, php_number
from .range import ReportRange

TYPES = [LeaveType.CASUAL, LeaveType.MEDICAL, LeaveType.EARNED, LeaveType.HALF_DAY]


class LeaveUsageReport:
    TITLE = "Leave usage"
    # Compared with the previous period when one is asked for (comparison.py).
    COMPARED_ROWS = [("leave_days", "Leave days"), ("absent", "Absent days")]

    @staticmethod
    def row_key(row: dict):
        return row["staff_profile_id"]

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        staff = StaffProfile.objects.filter(school_id=report_range.school_id)

        if filters.get("department_id"):
            staff = staff.filter(department_id=filters["department_id"])

        # A head of department sees their own departments and no others.
        # Present but empty means they head none, so they see nobody.
        if "department_ids" in filters:
            staff = staff.filter(department_id__in=filters["department_ids"])

        staff = list(staff.select_related("user", "department").order_by("user__first_name", "user__last_name", "id"))
        profile_ids = [profile.id for profile in staff]

        requests = self._requests_by_profile(report_range, profile_ids)
        absent = self._absences_by_profile(report_range, profile_ids)

        rows = []
        for profile in staff:
            mine = requests.get(profile.id, [])
            taken = {leave_type: 0.0 for leave_type in TYPES}
            pending_days = 0.0

            for leave in mine:
                days = HodReportService.leave_days_within(leave, report_range.working_dates)
                if leave.status == LeaveStatus.APPROVED:
                    taken[leave.leave_type] = taken.get(leave.leave_type, 0.0) + days
                elif leave.status == LeaveStatus.PENDING:
                    pending_days += days

            rows.append({
                "staff_profile_id": profile.id,
                "employee_id": profile.employee_id,
                "name": profile.user.name,
                "department": profile.department.name if profile.department else None,
                **{str(leave_type): php_number(taken[leave_type]) for leave_type in TYPES},
                "leave_days": php_number(sum(taken.values())),
                "pending_requests": sum(1 for leave in mine if leave.status == LeaveStatus.PENDING),
                "pending_days": php_number(pending_days),
                "rejected_requests": sum(1 for leave in mine if leave.status == LeaveStatus.REJECTED),
                "absent": absent.get(profile.id, 0),
            })

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": self._totals(rows),
        }

    def headings(self) -> list[str]:
        return [
            "Employee ID", "Name", "Department", "Casual", "Medical", "Earned", "Half day", "Leave days",
            "Pending requests", "Pending days", "Rejected requests", "Absent days",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["employee_id"], row["name"], row["department"], row["casual"], row["medical"], row["earned"],
                row["half_day"], row["leave_days"], row["pending_requests"], row["pending_days"],
                row["rejected_requests"], row["absent"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        combined = {"branches": len(branch_totals)}

        for key in ("staff", "leave_days", "pending_requests", "rejected_requests", "absent"):
            combined[key] = php_number(sum(totals[key] for totals in branch_totals))

        return combined

    @staticmethod
    def _totals(rows: list[dict]) -> dict:
        return {
            "staff": len(rows),
            "leave_days": php_number(float(sum(row["leave_days"] for row in rows))),
            "pending_requests": sum(row["pending_requests"] for row in rows),
            "rejected_requests": sum(row["rejected_requests"] for row in rows),
            "absent": sum(row["absent"] for row in rows),
        }

    @staticmethod
    def _requests_by_profile(report_range: ReportRange, profile_ids: list[int]) -> dict[int, list]:
        """Every request that overlaps the range, whatever its status."""
        by_profile: dict[int, list] = {}

        overlapping = StaffLeave.objects.filter(
            school_id=report_range.school_id,
            staff_profile_id__in=profile_ids,
            start_date__lte=report_range.end,
            end_date__gte=report_range.start,
        ).order_by("start_date", "id")

        for leave in overlapping:
            by_profile.setdefault(leave.staff_profile_id, []).append(leave)

        return by_profile

    @staticmethod
    def _absences_by_profile(report_range: ReportRange, profile_ids: list[int]) -> dict[int, int]:
        """Working days marked absent. A day since declared a holiday stops
        counting, as it does in every other report."""
        return dict(
            StaffAttendance.objects.filter(
                school_id=report_range.school_id,
                staff_profile_id__in=profile_ids,
                status=StaffAttendanceStatus.ABSENT,
                attendance_date__range=(report_range.start, report_range.end),
                attendance_date__in=report_range.working_dates,
            )
            .values("staff_profile_id")
            .annotate(total=Count("id"))
            .values_list("staff_profile_id", "total")
        )
