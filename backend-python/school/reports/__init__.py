"""The reports - Phase 18's four and Phase 20's three - and the pieces they
share.

Ports of App\\Services\\Reports and App\\Support\\Reports. Each report builds
one school's figures over a ReportRange; GroupReport runs a report once per
branch and stitches the results. The view decides which of the two a request
gets, and whether it goes out as JSON or as a CSV of the same rows.

The rule every one of them keeps: a rate is out of the days the school
actually ran - the same holiday calendar that decides whether a register may
be taken at all - so a report never contradicts the screen that refused to
mark a Saturday.
"""

from .leave_usage import LeaveUsageReport
from .payroll_summary import PayrollSummaryReport
from .staff_attendance import StaffAttendanceReport
from .student_attendance import StudentAttendanceReport
from .syllabus_progress import SyllabusProgressReport
from .teaching_coverage import TeachingCoverageReport
from .transport_usage import TransportUsageReport

__all__ = [
    "LeaveUsageReport",
    "PayrollSummaryReport",
    "StaffAttendanceReport",
    "StudentAttendanceReport",
    "SyllabusProgressReport",
    "TeachingCoverageReport",
    "TransportUsageReport",
]
