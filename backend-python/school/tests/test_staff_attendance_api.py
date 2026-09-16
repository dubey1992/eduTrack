"""The staff register, over HTTP.

It shares the student register's day-rules - no holiday, no weekend,
submitting is not correcting - so those are asserted once here rather than
repeated in full, and the file leans on what is different:

**An HOD marks it**, which is the one place in the product an HOD writes
outside their own record. And **which staff they may mark is narrowed to their
own departments**, in the form as well as the roster, so a hand-made request
cannot reach a colleague in another department.

**Nobody is told.** Staff attendance is a record the school keeps, not news
anybody is waiting for.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import StaffAttendanceStatus, UserRole
from school.models import Holiday, Message, StaffAttendance

A_SCHOOL_DAY = dt.date(2026, 9, 9)
A_SATURDAY = dt.date(2026, 9, 12)


class StaffAttendanceTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.arts = factories.DepartmentFactory(school=self.school, name="Arts")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        self.scientist = self.employee("EMP-SCI", self.science)
        self.artist = self.employee("EMP-ART", self.arts)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def employee(self, employee_id, department, role=UserRole.TEACHER):
        return factories.StaffProfileFactory(
            school=self.school,
            user=factories.UserFactory(school=self.school, role=role),
            employee_id=employee_id,
            department=department,
        )

    def marks(self, *profiles, status=StaffAttendanceStatus.PRESENT, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "attendance_date": A_SCHOOL_DAY.isoformat(),
            "records": [
                {"staff_profile_id": profile.id, "status": status}
                for profile in (profiles or (self.scientist, self.artist))
            ],
        }
        body.update(overrides)

        return body


class TheRosterScreen(StaffAttendanceTest):
    def test_it_lists_the_active_staff_with_no_marks_yet(self):
        response = self.client.get(
            f"/api/v1/staff-attendance/register?school_id={self.school.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertFalse(response.data["submitted"])
        self.assertEqual(
            ["EMP-ART", "EMP-SCI"], sorted(s["employee_id"] for s in response.data["staff"])
        )
        self.assertIsNone(response.data["staff"][0]["status"])

    def test_a_deactivated_employee_is_not_on_it(self):
        self.scientist.user.status = "inactive"
        self.scientist.user.save()

        response = self.client.get(
            f"/api/v1/staff-attendance/register?school_id={self.school.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(["EMP-ART"], [s["employee_id"] for s in response.data["staff"]])

    def test_it_can_be_narrowed_to_one_department(self):
        response = self.client.get(
            f"/api/v1/staff-attendance/register?school_id={self.school.id}"
            f"&department_id={self.science.id}&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(["EMP-SCI"], [s["employee_id"] for s in response.data["staff"]])

    def test_it_shows_the_marks_and_the_hours_once_submitted(self):
        self.client.post(
            "/api/v1/staff-attendance",
            self.marks(
                self.scientist,
                records=[
                    {
                        "staff_profile_id": self.scientist.id,
                        "status": "present",
                        "check_in": "08:05",
                        "check_out": "15:30",
                    }
                ],
            ),
            format="json",
        )

        response = self.client.get(
            f"/api/v1/staff-attendance/register?school_id={self.school.id}"
            f"&department_id={self.science.id}&date={A_SCHOOL_DAY.isoformat()}"
        )

        row = response.data["staff"][0]
        self.assertTrue(response.data["submitted"])
        self.assertEqual("08:05", row["check_in"])
        self.assertEqual("15:30", row["check_out"])
        self.assertEqual("7h 25m", row["working_hours"])

    def test_half_a_pair_of_times_reports_no_hours(self):
        # "0h 0m" would read as a day nobody worked rather than a day nobody
        # recorded.
        self.client.post(
            "/api/v1/staff-attendance",
            self.marks(
                records=[
                    {
                        "staff_profile_id": self.scientist.id,
                        "status": "present",
                        "check_in": "08:05",
                    }
                ]
            ),
            format="json",
        )

        response = self.client.get(
            f"/api/v1/staff-attendance/register?school_id={self.school.id}"
            f"&department_id={self.science.id}&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertIsNone(response.data["staff"][0]["working_hours"])


class MarkingIt(StaffAttendanceTest):
    def test_a_register_is_submitted(self):
        response = self.client.post("/api/v1/staff-attendance", self.marks(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(2, StaffAttendance.objects.count())

    def test_submitting_twice_is_refused(self):
        self.client.post("/api/v1/staff-attendance", self.marks(), format="json")

        response = self.client.post(
            "/api/v1/staff-attendance",
            self.marks(status=StaffAttendanceStatus.ABSENT),
            format="json",
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ATTENDANCE_ALREADY_SUBMITTED", response.data["code"])

    def test_correcting_is_its_own_action(self):
        self.client.post("/api/v1/staff-attendance", self.marks(), format="json")

        response = self.client.patch(
            "/api/v1/staff-attendance",
            self.marks(status=StaffAttendanceStatus.HALF_DAY),
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            ["half_day", "half_day"],
            sorted(StaffAttendance.objects.values_list("status", flat=True)),
        )

    def test_half_a_day_is_a_status_staff_have_and_students_do_not(self):
        response = self.client.post(
            "/api/v1/staff-attendance",
            self.marks(status=StaffAttendanceStatus.HALF_DAY),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_a_holiday_and_a_weekend_are_both_refused(self):
        Holiday.objects.create(
            school_id=self.school.id,
            name="Founders Day",
            type="school_event",
            start_date=A_SCHOOL_DAY,
            end_date=A_SCHOOL_DAY,
        )

        on_holiday = self.client.post("/api/v1/staff-attendance", self.marks(), format="json")
        on_saturday = self.client.post(
            "/api/v1/staff-attendance",
            self.marks(attendance_date=A_SATURDAY.isoformat()),
            format="json",
        )

        self.assertEqual("ATTENDANCE_ON_HOLIDAY", on_holiday.data["code"])
        self.assertEqual("NON_WORKING_DAY", on_saturday.data["code"])
        self.assertEqual(0, StaffAttendance.objects.count())

    def test_the_same_employee_twice_is_refused(self):
        response = self.client.post(
            "/api/v1/staff-attendance",
            self.marks(
                records=[
                    {"staff_profile_id": self.scientist.id, "status": "present"},
                    {"staff_profile_id": self.scientist.id, "status": "absent"},
                ]
            ),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn(
            "Each staff member can only appear once in the attendance records.",
            response.data["details"]["errors"]["records"],
        )

    def test_a_time_in_the_wrong_format_is_refused(self):
        response = self.client.post(
            "/api/v1/staff-attendance",
            self.marks(
                records=[
                    {
                        "staff_profile_id": self.scientist.id,
                        "status": "present",
                        "check_in": "8am",
                    }
                ]
            ),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_nobody_is_texted(self):
        # Staff attendance is a record the school keeps, not news anybody is
        # waiting for.
        self.client.post(
            "/api/v1/staff-attendance",
            self.marks(status=StaffAttendanceStatus.ABSENT),
            format="json",
        )

        self.assertEqual(0, Message.objects.count())


class AnHodMarksTheirOwnDepartment(StaffAttendanceTest):
    def setUp(self):
        super().setUp()
        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.science.hod_user_id = self.hod.id
        self.science.save()
        self.hod_client = self.as_user(self.hod)

    def test_their_roster_is_narrowed_to_it(self):
        response = self.hod_client.get(
            f"/api/v1/staff-attendance/register?date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(["EMP-SCI"], [s["employee_id"] for s in response.data["staff"]])

    def test_asking_for_another_department_does_not_widen_it(self):
        # Never trusted from the client, the same way a teacher only ever sees
        # their own sections.
        response = self.hod_client.get(
            f"/api/v1/staff-attendance/register?department_id={self.arts.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(["EMP-SCI"], [s["employee_id"] for s in response.data["staff"]])

    def test_they_may_mark_their_own_department(self):
        response = self.hod_client.post(
            "/api/v1/staff-attendance", self.marks(self.scientist), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_they_may_not_mark_another_department(self):
        # The roster narrowing is not enough on its own - a hand-made request
        # never sees the roster.
        response = self.hod_client.post(
            "/api/v1/staff-attendance", self.marks(self.artist), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("records", response.data["details"]["errors"])
        self.assertEqual(0, StaffAttendance.objects.count())

    def test_their_list_only_shows_their_own_department(self):
        self.client.post("/api/v1/staff-attendance", self.marks(), format="json")

        response = self.hod_client.get("/api/v1/staff-attendance?per_page=100")

        self.assertEqual(
            ["EMP-SCI"], [row["employee_id"] for row in response.data["data"]]
        )


class WhoMaySeeIt(StaffAttendanceTest):
    def test_an_ordinary_teacher_may_not(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, teacher.get("/api/v1/staff-attendance").status_code)
        self.assertEqual(
            403,
            teacher.post("/api/v1/staff-attendance", self.marks(), format="json").status_code,
        )

    def test_an_admin_from_another_school_may_not(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        response = outsider.post("/api/v1/staff-attendance", self.marks(), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(0, StaffAttendance.objects.count())

    def test_the_list_never_includes_another_schools_marks(self):
        self.client.post("/api/v1/staff-attendance", self.marks(), format="json")

        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual([], outsider.get("/api/v1/staff-attendance?per_page=100").data["data"])

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/staff-attendance").status_code)


class TheList(StaffAttendanceTest):
    def setUp(self):
        super().setUp()
        self.client.post("/api/v1/staff-attendance", self.marks(), format="json")

    def test_a_mark_comes_back_whole(self):
        row = self.client.get("/api/v1/staff-attendance").data["data"][0]

        for field in (
            "id", "school_id", "staff_profile_id", "employee_id", "staff_name",
            "department_name", "attendance_date", "status", "check_in", "check_out",
            "working_hours", "remarks", "marked_by", "marked_by_name",
        ):
            self.assertIn(field, row)

        self.assertEqual(self.admin.name, row["marked_by_name"])

    def test_it_filters_by_department_and_employee(self):
        by_department = self.client.get(
            f"/api/v1/staff-attendance?department_id={self.science.id}&per_page=100"
        )
        by_employee = self.client.get(
            f"/api/v1/staff-attendance?staff_profile_id={self.artist.id}&per_page=100"
        )

        self.assertEqual(["EMP-SCI"], [r["employee_id"] for r in by_department.data["data"]])
        self.assertEqual(["EMP-ART"], [r["employee_id"] for r in by_employee.data["data"]])
