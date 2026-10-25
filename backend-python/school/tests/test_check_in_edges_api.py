"""Check-in's edge cases, and the office's view of it on the web
(school/check_in.py, docs/staff-check-in.md "Edge cases").

Same pinned clock and pin as test_check_in_api: Monday 26 October 2026,
09:05 in Kolkata; the phone 50 m north of the school.
"""

import datetime as dt
from unittest import mock

from django.utils.timezone import now as real_now

from school import factories
from school.enums import UserRole
from school.models import StaffAttendance
from school.tests.test_check_in_api import (
    FIFTY_M_NORTH,
    MONDAY_0905,
    PIN,
    THREE_HUNDRED_M_NORTH,
    UTC,
    CheckInTestCase,
    at,
)


class EdgeCases(CheckInTestCase):
    def test_a_mock_location_is_refused_however_close_it_claims_to_be(self):
        response = self.check_in({**FIFTY_M_NORTH, "is_mocked": True})

        self.assertEqual("LOCATION_MOCKED", response.data["code"])
        self.assertFalse(StaffAttendance.objects.exists())

    def test_a_remembered_fix_is_refused_and_a_fresh_one_is_not(self):
        self.assertEqual("LOCATION_STALE", self.check_in({**FIFTY_M_NORTH, "fix_age_s": 600}).data["code"])
        self.assertEqual(200, self.check_in({**FIFTY_M_NORTH, "fix_age_s": 5}).status_code)

    def test_check_out_is_held_to_the_same_proof(self):
        self.check_in()

        self.assertEqual("LOCATION_MOCKED", self.check_out({**FIFTY_M_NORTH, "is_mocked": True}).data["code"])
        self.assertIsNone(self.row().check_out)

    def test_half_day_leave_lets_them_check_in_and_makes_it_a_half_day(self):
        leave = factories.StaffLeaveFactory(
            staff_profile=self.profile, leave_type="half_day", status="approved",
            start_date=dt.date(2026, 10, 26), end_date=dt.date(2026, 10, 26),
        )
        # What approving it writes on the register: "leave", even for a half day.
        StaffAttendance.objects.create(
            school=self.school, staff_profile=self.profile, attendance_date=dt.date(2026, 10, 26), status="leave",
            marked_by=leave.applied_by, created_at=real_now(), updated_at=real_now(),
        )

        before = self.call("me").data
        self.assertEqual((False, True, True), (before["on_leave"], before["half_day_leave"], before["can_check_in"]))

        response = self.check_in()

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("half_day", self.row().status)

    def test_half_day_leave_without_a_register_mark_still_ends_as_a_half_day(self):
        factories.StaffLeaveFactory(
            staff_profile=self.profile, leave_type="half_day", status="approved",
            start_date=dt.date(2026, 10, 26), end_date=dt.date(2026, 10, 26),
        )

        self.assertEqual("half_day", self.check_in().data["status"])

    def test_full_day_leave_still_refuses(self):
        factories.StaffLeaveFactory(
            staff_profile=self.profile, leave_type="casual", status="approved",
            start_date=dt.date(2026, 10, 26), end_date=dt.date(2026, 10, 26),
        )

        self.assertEqual("ON_LEAVE", self.check_in().data["code"])

    def test_a_fingerprint_check_in_first_is_named(self):
        StaffAttendance.objects.create(
            school=self.school, staff_profile=self.profile, attendance_date=dt.date(2026, 10, 26), status="present",
            check_in=dt.time(8, 10), marked_by=None, created_at=real_now(), updated_at=real_now(),
        )

        response = self.check_in()

        self.assertEqual("ALREADY_CHECKED_IN", response.data["code"])
        self.assertIn("fingerprint reader already checked you in at 08:10", response.data["message"])

    def test_two_phones_at_once_land_once_and_the_second_is_told(self):
        """The race: both read "no row", and the other phone inserts first.
        Simulated by the row appearing between the read and the insert."""
        from school import check_in as module

        real_assert_place = module._assert_place

        def a_second_phone_got_there_first(*args, **kwargs):
            StaffAttendance.objects.create(
                school=self.school, staff_profile=self.profile, attendance_date=dt.date(2026, 10, 26),
                status="present", check_in=dt.time(9, 4), marked_by=self.teacher,
                created_at=real_now(), updated_at=real_now(),
            )
            return real_assert_place(*args, **kwargs)

        with mock.patch.object(module, "_assert_place", a_second_phone_got_there_first):
            response = self.check_in()

        # A refusal, never a 500 from the unique key. (The row count is not
        # asserted: the simulated second phone wrote inside this request's
        # transaction, so the refusal rolls it back with it - a real one
        # commits on its own.)
        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("ALREADY_CHECKED_IN", response.data["code"])

    def test_a_day_they_forgot_to_check_out_of_is_reported(self):
        StaffAttendance.objects.create(
            school=self.school, staff_profile=self.profile, attendance_date=dt.date(2026, 10, 23), status="present",
            check_in=dt.time(8, 45), marked_by=self.teacher, created_at=real_now(), updated_at=real_now(),
        )

        self.assertEqual({"date": "2026-10-23", "check_in": "08:45"}, self.call("me").data["unfinished_day"])

    def test_an_office_mark_an_old_day_or_a_finished_day_is_not_reported(self):
        admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        for date, out, by in [
            (dt.date(2026, 10, 22), None, admin),
            (dt.date(2026, 10, 23), dt.time(16, 0), self.teacher),
            (dt.date(2026, 10, 1), None, self.teacher),
        ]:
            StaffAttendance.objects.create(
                school=self.school, staff_profile=self.profile, attendance_date=date, status="present",
                check_in=dt.time(8, 45), check_out=out, marked_by=by, created_at=real_now(), updated_at=real_now(),
            )

        self.assertIsNone(self.call("me").data["unfinished_day"])


class TheWebSeesIt(CheckInTestCase):
    """The office's side: the register says which times came from the app,
    and the day's check-ins and check-outs are listed with their distance."""

    def setUp(self):
        super().setUp()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def log(self, user=None, **params):
        with at(MONDAY_0905):
            return self.client_for(user or self.admin).get(
                "/api/v1/staff-attendance/check-ins", {"date": "2026-10-26", **params}
            )

    def my_register_row(self):
        with at(MONDAY_0905):
            register = self.client_for(self.admin).get("/api/v1/staff-attendance/register", {"date": "2026-10-26"})

        return next(row for row in register.data["staff"] if row["staff_profile_id"] == self.profile.id)

    def test_the_register_marks_a_time_that_came_from_the_app(self):
        self.check_in()

        self.assertTrue(self.my_register_row()["checked_in_from_app"])

    def test_once_the_office_corrects_the_day_it_is_no_longer_the_apps(self):
        self.check_in()
        StaffAttendance.objects.filter(pk=self.row().pk).update(marked_by=self.admin)

        self.assertFalse(self.my_register_row()["checked_in_from_app"])

    def test_the_log_lists_each_check_in_and_out_in_order_with_the_distance(self):
        self.check_in()
        self.check_out(instant=dt.datetime(2026, 10, 26, 10, 35, tzinfo=UTC))

        response = self.log()

        self.assertEqual(200, response.status_code, response.data)
        events = response.data["events"]
        self.assertEqual([("check_in", "09:05"), ("check_out", "16:05")], [(e["kind"], e["time"]) for e in events])
        self.assertTrue(all(45 <= e["distance_m"] <= 55 for e in events))
        self.assertEqual(self.teacher.name, events[0]["name"])

    def test_a_refused_attempt_is_not_in_the_log(self):
        self.check_in(THREE_HUNDRED_M_NORTH)

        self.assertEqual([], self.log().data["events"])

    def test_an_hod_sees_only_their_departments(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        department = factories.DepartmentFactory(school=self.school, hod_user=hod)
        self.check_in()

        self.assertEqual([], self.log(user=hod).data["events"], "the teacher is in no department of theirs")

        self.profile.department = department
        self.profile.save()

        self.assertEqual(1, len(self.log(user=hod).data["events"]))

    def test_a_teacher_cannot_read_the_log(self):
        self.check_in()

        self.assertEqual(403, self.log(user=self.teacher).status_code)

    def test_another_schools_admin_gets_their_own_school_whatever_they_ask(self):
        self.check_in()
        other = factories.SchoolFactory(latitude=PIN[0], longitude=PIN[1])
        other_admin = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)

        response = self.log(user=other_admin, school_id=self.school.id)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], response.data["events"])
