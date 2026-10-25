"""Checking in and out from the phone, over HTTP (school/check_in.py).

The clock is pinned: Monday 26 October 2026, 09:05 in Kolkata (03:35 UTC).
The school's pin is in New Delhi; 0.00045 degrees of latitude is about 50 m.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils.timezone import now as real_now
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AuditLog, Holiday, StaffAttendance

UTC = dt.timezone.utc
MONDAY_0905 = dt.datetime(2026, 10, 26, 3, 35, tzinfo=UTC)
PIN = (28.6139000, 77.2090000)
FIFTY_M_NORTH = {"latitude": PIN[0] + 0.00045, "longitude": PIN[1], "accuracy_m": 12}
THREE_HUNDRED_M_NORTH = {"latitude": PIN[0] + 0.0027, "longitude": PIN[1], "accuracy_m": 12}


def at(instant):
    return mock.patch("django.utils.timezone.now", return_value=instant)


class CheckInTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(
            timezone="Asia/Kolkata", working_days="1111100", latitude=PIN[0], longitude=PIN[1]
        )
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.profile = factories.StaffProfileFactory(user=self.teacher, school=self.school)
        # The first bell, which is what "late" is measured against.
        factories.PeriodFactory(school=self.school, period_number=1, start_time=dt.time(9, 0), end_time=dt.time(9, 45))

    def client_for(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def call(self, path, body=None, user=None, instant=MONDAY_0905):
        client = self.client_for(user or self.teacher)

        with at(instant):
            if body is None:
                return client.get("/api/v1/staff-attendance/" + path)

            return client.post("/api/v1/staff-attendance/" + path, body, format="json")

    def check_in(self, body=None, **kwargs):
        return self.call("me/check-in", body if body is not None else FIFTY_M_NORTH, **kwargs)

    def check_out(self, body=None, **kwargs):
        return self.call("me/check-out", body if body is not None else FIFTY_M_NORTH, **kwargs)

    def setting(self, **values):
        factories.ModuleSettingFactory(school=self.school, module="staff_attendance", settings=values)

    def row(self):
        return StaffAttendance.objects.get(staff_profile=self.profile, attendance_date=dt.date(2026, 10, 26))


class CheckingIn(CheckInTestCase):
    def test_before_anything_the_day_offers_a_check_in(self):
        response = self.call("me")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("2026-10-26", "09:05", True, 100), (
            response.data["date"], response.data["now"], response.data["enabled"], response.data["radius_m"]
        ))
        self.assertTrue(response.data["can_check_in"])
        self.assertFalse(response.data["can_check_out"])
        self.assertIsNone(response.data["status"])

    def test_within_the_radius_marks_the_day_present_with_the_time(self):
        response = self.check_in()

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("present", "09:05"), (response.data["status"], response.data["check_in"]))
        self.assertTrue(response.data["late"], "the first bell was at 09:00")
        self.assertTrue(response.data["can_check_out"])

        row = self.row()
        self.assertEqual((self.school.id, "present", dt.time(9, 5), self.teacher.id), (
            row.school_id, row.status, row.check_in, row.marked_by_id
        ))

    def test_on_time_is_not_late(self):
        response = self.check_in(instant=dt.datetime(2026, 10, 26, 3, 20, tzinfo=UTC))  # 08:50

        self.assertFalse(response.data["late"])

    def test_the_audit_keeps_the_distance_and_never_the_coordinates(self):
        self.check_in()

        entry = AuditLog.objects.get(action="staff_attendance.checked_in")
        self.assertEqual(self.school.id, entry.school_id)
        self.assertIn(entry.new_values["distance_m"], range(45, 56))
        self.assertNotIn("latitude", str(entry.new_values))
        self.assertNotIn(str(FIFTY_M_NORTH["latitude"]), str(entry.new_values))

    def test_too_far_from_school_is_refused_with_the_distance(self):
        response = self.check_in(THREE_HUNDRED_M_NORTH)

        self.assertEqual(422, response.status_code)
        self.assertEqual("OUTSIDE_SCHOOL", response.data["code"])
        self.assertIn("300 m from school", response.data["message"])
        self.assertFalse(StaffAttendance.objects.exists())

    def test_the_school_may_widen_the_radius(self):
        self.setting(check_in_radius_m=400)

        self.assertEqual(200, self.check_in(THREE_HUNDRED_M_NORTH).status_code)

    def test_a_vague_fix_is_refused_rather_than_guessed_at(self):
        response = self.check_in({**FIFTY_M_NORTH, "accuracy_m": 450})

        self.assertEqual(422, response.status_code)
        self.assertEqual("LOCATION_TOO_VAGUE", response.data["code"])
        self.assertFalse(StaffAttendance.objects.exists())

    def test_without_a_pin_on_the_map_nobody_can_check_in(self):
        self.school.latitude = None
        self.school.longitude = None
        self.school.save()

        self.assertEqual("NO_SCHOOL_LOCATION", self.check_in().data["code"])
        day = self.call("me").data
        self.assertFalse(day["can_check_in"])
        self.assertIn("location", day["blocked_reason"])

    def test_a_second_check_in_is_refused_and_the_first_time_stands(self):
        self.check_in()
        response = self.check_in(instant=dt.datetime(2026, 10, 26, 5, 0, tzinfo=UTC))

        self.assertEqual("ALREADY_CHECKED_IN", response.data["code"])
        self.assertEqual(dt.time(9, 5), self.row().check_in)

    def test_the_day_is_the_schools_not_the_servers(self):
        # 22:00 UTC on Sunday is already 03:30 on Monday in Kolkata.
        response = self.check_in(instant=dt.datetime(2026, 10, 25, 22, 0, tzinfo=UTC))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("2026-10-26", response.data["date"])

    def test_where_the_phone_is_must_be_given(self):
        response = self.check_in({"latitude": PIN[0]})

        self.assertEqual(422, response.status_code)
        self.assertIn("longitude", response.data["details"]["errors"])


class CheckingOut(CheckInTestCase):
    def test_before_checking_in_there_is_nothing_to_check_out_from(self):
        response = self.check_out()

        self.assertEqual("NOT_CHECKED_IN", response.data["code"])

    def test_records_the_leaving_time_and_the_hours(self):
        self.check_in()
        response = self.check_out(instant=dt.datetime(2026, 10, 26, 10, 35, tzinfo=UTC))  # 16:05

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("16:05", "7h 0m"), (response.data["check_out"], response.data["working_hours"]))
        self.assertEqual(dt.time(16, 5), self.row().check_out)

    def test_checking_out_again_keeps_the_later_time(self):
        self.check_in()
        self.check_out(instant=dt.datetime(2026, 10, 26, 10, 35, tzinfo=UTC))
        self.check_out(instant=dt.datetime(2026, 10, 26, 12, 5, tzinfo=UTC))  # 17:35

        self.assertEqual(dt.time(17, 35), self.row().check_out)

    def test_checking_out_from_home_is_refused(self):
        self.check_in()
        response = self.check_out(THREE_HUNDRED_M_NORTH)

        self.assertEqual("OUTSIDE_SCHOOL", response.data["code"])
        self.assertIsNone(self.row().check_out)


class ClosedDaysAndLeave(CheckInTestCase):
    def test_a_holiday_is_refused(self):
        Holiday.objects.create(
            school_id=self.school.id, name="Diwali", type="religious",
            start_date=dt.date(2026, 10, 26), end_date=dt.date(2026, 10, 26), created_at=real_now(), updated_at=real_now(),
        )

        self.assertEqual("ATTENDANCE_ON_HOLIDAY", self.check_in().data["code"])
        self.assertIn("Diwali", self.call("me").data["blocked_reason"])

    def test_a_day_the_school_does_not_run_is_refused(self):
        response = self.check_in(instant=dt.datetime(2026, 10, 25, 4, 0, tzinfo=UTC))  # Sunday

        self.assertEqual("NON_WORKING_DAY", response.data["code"])

    def test_approved_leave_is_refused_and_pending_leave_is_not(self):
        factories.StaffLeaveFactory(
            staff_profile=self.profile, start_date=dt.date(2026, 10, 27), end_date=dt.date(2026, 10, 27), status="pending"
        )
        self.assertEqual(200, self.check_in().status_code)

        StaffAttendance.objects.all().delete()
        factories.StaffLeaveFactory(
            staff_profile=self.profile, start_date=dt.date(2026, 10, 26), end_date=dt.date(2026, 10, 26), status="approved"
        )
        response = self.check_in()

        self.assertEqual("ON_LEAVE", response.data["code"])
        self.assertTrue(self.call("me").data["on_leave"])


class AndTheOffice(CheckInTestCase):
    def office_marks(self, status):
        StaffAttendance.objects.create(
            school=self.school, staff_profile=self.profile, attendance_date=dt.date(2026, 10, 26), status=status,
            marked_by=factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN),
            created_at=real_now(), updated_at=real_now(),
        )

    def test_absent_before_arriving_becomes_present_on_arrival(self):
        self.office_marks("absent")

        response = self.check_in()

        self.assertEqual(("present", "09:05"), (response.data["status"], response.data["check_in"]))
        self.assertEqual(1, StaffAttendance.objects.count())

    def test_a_half_day_the_office_chose_stands(self):
        self.office_marks("half_day")

        self.assertEqual("half_day", self.check_in().data["status"])

    def test_leave_on_the_register_is_refused(self):
        self.office_marks("leave")

        self.assertEqual("ON_LEAVE", self.check_in().data["code"])

    def test_the_app_says_when_somebody_else_marked_the_day(self):
        self.office_marks("absent")

        self.assertTrue(self.call("me").data["marked_by_someone_else"])

    def test_the_office_register_shows_the_check_in_and_can_still_correct_it(self):
        self.check_in()
        admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        with at(MONDAY_0905):
            register = self.client_for(admin).get(
                "/api/v1/staff-attendance/register", {"date": "2026-10-26"}
            )
        mine = next(row for row in register.data["staff"] if row["staff_profile_id"] == self.profile.id)

        self.assertEqual(("present", "09:05", True), (mine["status"], mine["check_in"], mine["late"]))
        self.assertTrue(register.data["submitted"], "so the screen corrects rather than submits")

        with at(MONDAY_0905):
            corrected = self.client_for(admin).patch(
                "/api/v1/staff-attendance",
                {"attendance_date": "2026-10-26", "records": [
                    {"staff_profile_id": self.profile.id, "status": "half_day", "check_in": "09:05"},
                ]},
                format="json",
            )

        self.assertEqual(200, corrected.status_code, corrected.data)
        self.assertEqual("half_day", self.row().status)


class SwitchesAndWho(CheckInTestCase):
    def test_a_school_that_switches_it_off_marks_in_the_office(self):
        self.setting(app_check_in=False)

        self.assertEqual("CHECK_IN_OFF", self.check_in().data["code"])
        day = self.call("me").data
        self.assertEqual((False, False), (day["enabled"], day["can_check_in"]))

    def test_with_staff_attendance_switched_off_it_is_refused_as_such(self):
        factories.ModuleSettingFactory(school=self.school, module="staff_attendance", school_enabled=False)

        response = self.check_in()

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_every_member_of_staff_may_check_in(self):
        for role in (UserRole.HOD, UserRole.STAFF, UserRole.ACCOUNTANT, UserRole.TRANSPORT_MANAGER):
            user = factories.UserFactory(school=self.school, role=role)
            factories.StaffProfileFactory(user=user, school=self.school)

            self.assertEqual(200, self.check_in(user=user).status_code, role)

    def test_a_super_admin_has_no_staff_record_to_mark(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        response = self.check_in(user=root)

        self.assertEqual(422, response.status_code)
        self.assertEqual("NO_STAFF_RECORD", response.data["code"])

    def test_nothing_in_the_request_can_check_in_somebody_else(self):
        other_school = factories.SchoolFactory(latitude=PIN[0], longitude=PIN[1])
        colleague = factories.StaffProfileFactory(school=self.school)

        self.check_in({**FIFTY_M_NORTH, "staff_profile_id": colleague.id, "school_id": other_school.id})

        self.assertEqual([self.profile.id], list(StaffAttendance.objects.values_list("staff_profile_id", flat=True)))
        self.assertEqual(self.school.id, self.row().school_id)

    def test_signed_out_is_refused(self):
        self.assertEqual(401, APIClient().post("/api/v1/staff-attendance/me/check-in", FIFTY_M_NORTH).status_code)
