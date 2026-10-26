"""A forgotten check-out, closed by the hourly job (school/check_in.py).

The school is in Kolkata and runs Monday to Friday in full, Saturday as a
half day. Its last bell is at 15:30 (13:00 on the half day). Monday 26
October 2026 is the day somebody checked in and never out.
"""

import datetime as dt
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.test import TestCase

from school import factories
from school.check_in import AUTO_CLOSED_NOTE, close_forgotten_check_outs
from school.enums import UserRole
from school.models import AuditLog, StaffAttendance

UTC = dt.timezone.utc
MONDAY = dt.date(2026, 10, 26)
SATURDAY = dt.date(2026, 10, 31)
# 18:30 UTC is midnight in Kolkata: Monday is over from then on.
MONDAY_2330_KOLKATA = dt.datetime(2026, 10, 26, 18, 0, tzinfo=UTC)
TUESDAY_0030_KOLKATA = dt.datetime(2026, 10, 26, 19, 0, tzinfo=UTC)


class ForgottenCheckOut(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata", working_days="1111120")
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.profile = factories.StaffProfileFactory(user=self.teacher, school=self.school)
        self.office = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        for number, start, end in [(1, (9, 0), (9, 45)), (7, (14, 45), (15, 30))]:
            factories.PeriodFactory(
                school=self.school, period_number=number, start_time=dt.time(*start), end_time=dt.time(*end)
            )
        factories.PeriodFactory(
            school=self.school, period_number=1, day_shape="half", start_time=dt.time(9, 0), end_time=dt.time(13, 0)
        )

    def day(self, date=MONDAY, check_in=dt.time(9, 5), marked_by="self", **fields):
        marker = {"self": self.teacher, "device": None, "office": self.office}[marked_by]

        return StaffAttendance.objects.create(
            school=self.school, staff_profile=self.profile, attendance_date=date, status="present",
            check_in=check_in, marked_by=marker, **fields,
        )

    def close(self, instant=TUESDAY_0030_KOLKATA) -> int:
        with mock.patch("django.utils.timezone.now", return_value=instant):
            return close_forgotten_check_outs()

    # -- closed -------------------------------------------------------------------

    def test_an_app_check_in_is_closed_at_the_last_bell_with_a_note(self):
        row = self.day()

        self.assertEqual(1, self.close())

        row.refresh_from_db()
        self.assertEqual(dt.time(15, 30), row.check_out)
        self.assertEqual(AUTO_CLOSED_NOTE, row.remarks)
        self.assertEqual("present", row.status, "closing a day never changes what it was")

    def test_a_reader_punch_with_no_second_punch_is_closed_too(self):
        row = self.day(marked_by="device")

        self.assertEqual(1, self.close())

        row.refresh_from_db()
        self.assertEqual(dt.time(15, 30), row.check_out)

    def test_a_half_day_closes_at_the_half_day_bell(self):
        row = self.day(date=SATURDAY)

        self.close(dt.datetime(2026, 10, 31, 19, 0, tzinfo=UTC))

        row.refresh_from_db()
        self.assertEqual(dt.time(13, 0), row.check_out)

    def test_remarks_already_there_are_kept(self):
        row = self.day(remarks="Bus duty.")

        self.close()

        row.refresh_from_db()
        self.assertEqual(f"Bus duty. {AUTO_CLOSED_NOTE}", row.remarks)

    def test_the_closing_is_audited_with_no_person_behind_it(self):
        row = self.day()

        self.close()

        entry = AuditLog.objects.get(action="staff_attendance.auto_closed")
        self.assertEqual((self.school.id, row.id, None), (entry.school_id, entry.entity_id, entry.user_id))
        self.assertEqual({"attendance_date": "2026-10-26", "check_out": "15:30"}, entry.new_values)

    def test_the_hourly_command_runs_it(self):
        row = self.day()
        out = StringIO()

        with mock.patch("django.utils.timezone.now", return_value=TUESDAY_0030_KOLKATA):
            call_command("close_open_trips", stdout=out)

        row.refresh_from_db()
        self.assertEqual(dt.time(15, 30), row.check_out)
        self.assertIn("staff days closed : 1", out.getvalue())

    # -- left alone ---------------------------------------------------------------

    def test_not_while_the_school_day_is_still_on(self):
        row = self.day()

        self.assertEqual(0, self.close(MONDAY_2330_KOLKATA), "they may still check out before midnight")

        row.refresh_from_db()
        self.assertIsNone(row.check_out)

    def test_a_day_that_was_checked_out_is_untouched(self):
        row = self.day(check_out=dt.time(16, 10))

        self.assertEqual(0, self.close())

        row.refresh_from_db()
        self.assertEqual((dt.time(16, 10), None), (row.check_out, row.remarks))

    def test_a_time_the_office_wrote_in_is_the_offices_to_complete(self):
        row = self.day(marked_by="office")

        self.assertEqual(0, self.close())

        row.refresh_from_db()
        self.assertIsNone(row.check_out)

    def test_a_day_with_no_check_in_is_not_given_a_check_out(self):
        row = self.day(check_in=None)

        self.assertEqual(0, self.close())

        row.refresh_from_db()
        self.assertIsNone(row.check_out)

    def test_a_check_in_after_the_last_bell_has_no_closing_time_to_give(self):
        row = self.day(check_in=dt.time(16, 0))

        self.assertEqual(0, self.close())

        row.refresh_from_db()
        self.assertIsNone(row.check_out)

    def test_a_school_with_no_bell_schedule_is_left_to_the_office(self):
        other = factories.SchoolFactory(timezone="Asia/Kolkata", working_days="1111100")
        person = factories.UserFactory(school=other, role=UserRole.TEACHER)
        profile = factories.StaffProfileFactory(user=person, school=other)
        row = StaffAttendance.objects.create(
            school=other, staff_profile=profile, attendance_date=MONDAY, status="present",
            check_in=dt.time(9, 0), marked_by=person,
        )

        self.close()

        row.refresh_from_db()
        self.assertIsNone(row.check_out)

    def test_older_than_a_week_is_history_and_left_alone(self):
        row = self.day(date=MONDAY - dt.timedelta(days=10))

        self.assertEqual(0, self.close())

        row.refresh_from_db()
        self.assertIsNone(row.check_out)

    def test_running_twice_closes_once(self):
        self.day()

        self.assertEqual(1, self.close())
        self.assertEqual(0, self.close())
        self.assertEqual(1, AuditLog.objects.filter(action="staff_attendance.auto_closed").count())

    def test_each_school_waits_for_its_own_midnight(self):
        # Dubai is 90 minutes behind Kolkata: at 00:30 in Kolkata it is
        # still 23:00 on Monday there.
        dubai = factories.SchoolFactory(timezone="Asia/Dubai", working_days="1111100")
        factories.PeriodFactory(school=dubai, period_number=1, start_time=dt.time(8, 0), end_time=dt.time(14, 0))
        person = factories.UserFactory(school=dubai, role=UserRole.TEACHER)
        profile = factories.StaffProfileFactory(user=person, school=dubai)
        in_dubai = StaffAttendance.objects.create(
            school=dubai, staff_profile=profile, attendance_date=MONDAY, status="present",
            check_in=dt.time(8, 0), marked_by=person,
        )
        in_kolkata = self.day()

        self.close()

        in_dubai.refresh_from_db()
        in_kolkata.refresh_from_db()
        self.assertIsNone(in_dubai.check_out)
        self.assertEqual(dt.time(15, 30), in_kolkata.check_out)
