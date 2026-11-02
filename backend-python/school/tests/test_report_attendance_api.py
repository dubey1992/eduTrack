"""A teaching report needs its teacher at work that day (decided 2026-11-02).

Teachers were filing what they taught before anybody - themselves included -
had said they were in. So a report is filed only for a day its teacher is
marked present (checked in, punched in, or marked by the office), never for a
day of leave, approved or only applied for. Each refusal carries its own code,
because the app answers them differently: CHECK_IN_REQUIRED offers a check-in.

The rule is on unless a school switches it off (teaching_reports module,
`needs_attendance`).
"""

import datetime as dt
from unittest import mock

from django.utils.timezone import now as real_now

from school import factories
from school.enums import StaffAttendanceStatus
from school.models import DailyTeachingReport, ModuleSetting, StaffAttendance, StaffProfile

from .test_teaching_reports_api import A_MONDAY, TeachingReportCase

# Monday 14 September 2026, 10:00 in Kolkata - the day the entry runs.
MONDAY_MORNING = dt.datetime(2026, 9, 14, 4, 30, tzinfo=dt.timezone.utc)
A_MONDAY_BEFORE = A_MONDAY - dt.timedelta(days=7)


class ReportsNeedAttendance(TeachingReportCase):
    def setUp(self):
        super().setUp()
        # The case switches the rule off for the report tests; this file is
        # about the rule, so it goes back to how a school starts.
        ModuleSetting.objects.filter(school_id=self.school.id, module="teaching_reports").delete()
        self.profile = StaffProfile.objects.get(user_id=self.teacher.id)

        clock = mock.patch("django.utils.timezone.now", return_value=MONDAY_MORNING)
        clock.start()
        self.addCleanup(clock.stop)

    def register(self, status, date=A_MONDAY, **fields):
        return StaffAttendance.objects.create(
            school=self.school, staff_profile=self.profile, attendance_date=date, status=status,
            marked_by=self.admin, created_at=real_now(), updated_at=real_now(), **fields,
        )

    def leave(self, status, date=A_MONDAY, leave_type="casual"):
        return factories.StaffLeaveFactory(
            staff_profile=self.profile, start_date=date, end_date=date, status=status, leave_type=leave_type
        )

    def refused(self, code, **overrides):
        response = self.file(**overrides)

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual(code, response.data["code"])
        self.assertFalse(DailyTeachingReport.objects.exists())

        return response

    # -- today ----------------------------------------------------------------

    def test_nothing_on_the_register_today_asks_for_a_check_in(self):
        response = self.refused("CHECK_IN_REQUIRED")

        self.assertIn("Check in first", response.data["message"])

    def test_checked_in_today_files(self):
        self.register(StaffAttendanceStatus.PRESENT, check_in=dt.time(9, 5))

        self.assertEqual(201, self.file().status_code)

    def test_a_half_day_counts_as_at_work(self):
        self.register(StaffAttendanceStatus.HALF_DAY)

        self.assertEqual(201, self.file().status_code)

    def test_marked_absent_today_is_refused(self):
        self.register(StaffAttendanceStatus.ABSENT)

        self.refused("MARKED_ABSENT")

    # -- leave ----------------------------------------------------------------

    def test_approved_leave_is_refused(self):
        self.leave("approved")

        self.refused("ON_LEAVE")

    def test_leave_only_applied_for_is_refused_too(self):
        self.leave("pending")
        # Even with a mark - the request says they are not working that day.
        self.register(StaffAttendanceStatus.PRESENT)

        response = self.refused("LEAVE_APPLIED")

        self.assertIn("Withdraw", response.data["message"])

    def test_a_leave_mark_on_the_register_is_refused(self):
        self.register(StaffAttendanceStatus.LEAVE)

        self.refused("ON_LEAVE")

    def test_rejected_leave_does_not_count(self):
        self.leave("rejected")
        self.register(StaffAttendanceStatus.PRESENT)

        self.assertEqual(201, self.file().status_code)

    def test_half_day_leave_leaves_the_other_half_to_report(self):
        self.leave("approved", leave_type="half_day")
        self.register(StaffAttendanceStatus.HALF_DAY)

        self.assertEqual(201, self.file().status_code)

    # -- an earlier day -------------------------------------------------------

    def test_an_earlier_day_with_no_mark_is_refused(self):
        response = self.refused("NOT_PRESENT", report_date=A_MONDAY_BEFORE.isoformat())

        self.assertIn("09/07/2026", response.data["message"])

    def test_an_earlier_day_marked_present_files(self):
        self.register(StaffAttendanceStatus.PRESENT, date=A_MONDAY_BEFORE)

        self.assertEqual(201, self.file(report_date=A_MONDAY_BEFORE.isoformat()).status_code)

    # -- who it applies to ----------------------------------------------------

    def test_a_school_may_switch_it_off(self):
        factories.reports_without_attendance(self.school)

        self.assertEqual(201, self.file().status_code)

    def test_a_teacher_with_no_staff_record_is_not_held_to_it(self):
        """Nothing they could do would satisfy it."""
        StaffProfile.objects.filter(pk=self.profile.pk).delete()

        self.assertEqual(201, self.file().status_code)

    def test_the_setting_is_shown_switched_on(self):
        response = self.as_user(self.admin).get("/api/v1/settings/modules")

        self.assertEqual(200, response.status_code, response.data)
        reports = next(row for row in response.data if row["module"] == "teaching_reports")
        self.assertIs(True, reports["settings"]["needs_attendance"])
