"""The four Phase 18 reports, and the pieces they share.

Ports of App\\Services\\Reports and App\\Support\\Reports. Each report builds
one school's figures over a ReportRange; GroupReport runs a report once per
branch and stitches the results. The view decides which of the two a request
gets, and whether it goes out as JSON or as a CSV of the same rows.

The rule every one of them keeps: a rate is out of the days the school
actually ran - the same holiday calendar that decides whether a register may
be taken at all - so a report never contradicts the screen that refused to
mark a Saturday.
"""

from .staff_attendance import StaffAttendanceReport
from .student_attendance import StudentAttendanceReport
from .teaching_coverage import TeachingCoverageReport
from .transport_usage import TransportUsageReport

__all__ = [
    "StaffAttendanceReport",
    "StudentAttendanceReport",
    "TeachingCoverageReport",
    "TransportUsageReport",
]
