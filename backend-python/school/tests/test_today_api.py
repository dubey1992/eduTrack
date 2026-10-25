"""A teacher's day, over HTTP (docs/teacher-app.md, T1).

The clock is pinned throughout: Monday 26 October 2026, 10:15 in Kolkata,
which is 04:45 UTC. The teacher has period 1 (done), period 3 (upcoming) and
is class teacher of 8 A.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils.timezone import now as real_now
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Attendance, Holiday

UTC = dt.timezone.utc
MONDAY_1015_IST = dt.datetime(2026, 10, 26, 4, 45, tzinfo=UTC)


def at(instant):
    return mock.patch("django.utils.timezone.now", return_value=instant)


class TodayTestCase(TestCase):
    def setUp(self):
        cache.clear()
        # Saturday is a half day, Sunday closed.
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata", working_days="1111120")
        self.year = factories.AcademicYearFactory(school=self.school)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.other = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        grade8 = factories.SchoolClassFactory(academic_year=self.year, name="Grade 8")
        grade9 = factories.SchoolClassFactory(academic_year=self.year, name="Grade 9")
        self.eight_a = factories.ClassSectionFactory(school_class=grade8, name="A", class_teacher=self.teacher)
        self.nine_a = factories.ClassSectionFactory(school_class=grade9, name="A")

        department = factories.DepartmentFactory(school=self.school)
        self.maths = factories.SubjectFactory(department=department, name="Mathematics")
        self.science = factories.SubjectFactory(department=department, name="Science")

        self.p1 = self.period(1, dt.time(9, 0), dt.time(9, 45))
        self.p2 = self.period(2, dt.time(10, 0), dt.time(10, 45))
        self.p3 = self.period(3, dt.time(11, 0), dt.time(11, 45))

        self.first = self.entry(self.eight_a, self.p1, self.maths, self.teacher)
        self.third = self.entry(self.nine_a, self.p3, self.science, self.teacher)
        # Somebody else's period, at the time this teacher is free.
        self.entry(self.eight_a, self.p2, self.science, self.other)

    def period(self, number, start, end, shape="full"):
        return factories.PeriodFactory(
            school=self.school, period_number=number, start_time=start, end_time=end, day_shape=shape
        )

    def entry(self, section, period, subject, teacher, day="monday"):
        return factories.TimetableEntryFactory(
            class_section=section, period=period, subject=subject, teacher=teacher, day_of_week=day
        )

    def client_for(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def today(self, user=None, instant=MONDAY_1015_IST, query=""):
        with at(instant):
            response = self.client_for(user or self.teacher).get("/api/v1/timetable/today" + query)

        self.assertEqual(200, response.status_code, getattr(response, "data", None))

        return response.data


class TheDay(TodayTestCase):
    def test_my_periods_in_order_with_the_one_that_is_over_marked(self):
        data = self.today()

        self.assertEqual(("2026-10-26", "monday", "10:15"), (data["date"], data["weekday"], data["now"]))
        self.assertEqual({"is_open": True, "shape": "full", "holiday": None}, data["school_day"])
        self.assertEqual(
            [(1, "09:00", "done", "Grade 8 A", "Mathematics"), (3, "11:00", "upcoming", "Grade 9 A", "Science")],
            [(p["period_number"], p["start_time"], p["state"], p["class_section"], p["subject"]) for p in data["periods"]],
        )

    def test_the_period_under_way_is_current(self):
        data = self.today(instant=dt.datetime(2026, 10, 26, 5, 35, tzinfo=UTC))  # 11:05 IST

        self.assertEqual(["done", "current"], [p["state"] for p in data["periods"]])

    def test_a_report_is_owed_for_a_period_that_has_started_and_not_for_one_to_come(self):
        data = self.today()

        self.assertEqual([False, False], [p["report"]["filed"] for p in data["periods"]])
        self.assertEqual(1, data["owed"]["reports"], "period 1 is over; period 3 has not started")

    def test_a_filed_report_is_shown_with_its_id_and_no_longer_owed(self):
        report = factories.DailyTeachingReportFactory(
            timetable_entry=self.first, teacher=self.teacher, report_date=dt.date(2026, 10, 26)
        )

        data = self.today()

        self.assertEqual({"filed": True, "id": report.id}, data["periods"][0]["report"])
        self.assertEqual(0, data["owed"]["reports"])

    def test_a_report_for_another_day_does_not_count(self):
        factories.DailyTeachingReportFactory(
            timetable_entry=self.first, teacher=self.teacher, report_date=dt.date(2026, 10, 19)
        )

        self.assertFalse(self.today()["periods"][0]["report"]["filed"])

    def test_the_day_is_the_schools_not_the_servers(self):
        # 23:00 UTC on Sunday is already 04:30 on Monday in Kolkata.
        data = self.today(instant=dt.datetime(2026, 10, 25, 23, 0, tzinfo=UTC))

        self.assertEqual(("2026-10-26", "04:30"), (data["date"], data["now"]))
        self.assertEqual(["upcoming", "upcoming"], [p["state"] for p in data["periods"]])

    def test_last_years_timetable_is_not_today(self):
        old_year = factories.AcademicYearFactory(school=self.school, is_current=False)
        old_section = factories.ClassSectionFactory(school_class=factories.SchoolClassFactory(academic_year=old_year))
        self.entry(old_section, self.p2, self.maths, self.teacher)

        self.assertEqual([1, 3], [p["period_number"] for p in self.today()["periods"]])


class TheRegister(TodayTestCase):
    def test_my_class_register_is_listed_once_and_owed(self):
        data = self.today()

        self.assertEqual(
            [{"class_section_id": self.eight_a.id, "class_section": "Grade 8 A", "submitted": False}],
            data["registers"],
        )
        self.assertEqual(1, data["owed"]["registers"])

    def test_a_submitted_register_is_no_longer_owed(self):
        student = factories.StudentFactory(class_section=self.eight_a, school=self.school)
        Attendance.objects.create(
            school_id=self.school.id, academic_year_id=self.year.id, class_section_id=self.eight_a.id,
            student=student, attendance_date=dt.date(2026, 10, 26), status="present",
            created_at=real_now(), updated_at=real_now(),
        )

        data = self.today()

        self.assertTrue(data["registers"][0]["submitted"])
        self.assertEqual(0, data["owed"]["registers"])

    def test_a_teacher_who_is_nobodys_class_teacher_owes_no_register(self):
        self.assertEqual([], self.today(user=self.other)["registers"])


class ClosedDays(TodayTestCase):
    def test_a_holiday_closes_the_day_and_owes_nothing(self):
        Holiday.objects.create(
            school_id=self.school.id, name="Diwali", type="religious",
            start_date=dt.date(2026, 10, 26), end_date=dt.date(2026, 10, 26),
            created_at=real_now(), updated_at=real_now(),
        )

        data = self.today()

        self.assertFalse(data["school_day"]["is_open"])
        self.assertEqual("Diwali", data["school_day"]["holiday"]["name"])
        self.assertEqual(([], []), (data["periods"], data["registers"]))
        self.assertEqual({"reports": 0, "registers": 0}, data["owed"])

    def test_a_day_the_school_does_not_run_is_closed(self):
        data = self.today(instant=dt.datetime(2026, 10, 25, 5, 0, tzinfo=UTC))  # Sunday

        self.assertEqual({"is_open": False, "shape": None, "holiday": None}, data["school_day"])
        self.assertEqual([], data["periods"])

    def test_a_half_day_rings_only_its_own_bells(self):
        short = self.period(1, dt.time(9, 0), dt.time(9, 30), shape="half")
        self.entry(self.eight_a, short, self.maths, self.teacher, day="saturday")
        # A full-day period entered on Saturday by mistake is not a bell that rings.
        self.entry(self.nine_a, self.p3, self.science, self.teacher, day="saturday")

        data = self.today(instant=dt.datetime(2026, 10, 31, 4, 0, tzinfo=UTC))  # Saturday 09:30 IST

        self.assertEqual("half", data["school_day"]["shape"])
        self.assertEqual([("09:00", "09:30", "done")], [(p["start_time"], p["end_time"], p["state"]) for p in data["periods"]])


class Leave(TodayTestCase):
    def setUp(self):
        super().setUp()
        self.profile = factories.StaffProfileFactory(user=self.teacher, school=self.school)

    def leave(self, start, end, status="approved"):
        return factories.StaffLeaveFactory(staff_profile=self.profile, start_date=start, end_date=end, status=status)

    def test_on_approved_leave_today_nothing_is_owed(self):
        mine = self.leave(dt.date(2026, 10, 26), dt.date(2026, 10, 27))

        data = self.today()

        self.assertEqual(mine.id, data["leave"]["today"]["id"])
        self.assertEqual({"reports": 0, "registers": 0}, data["owed"])
        self.assertEqual(2, len(data["periods"]), "the day is still shown")

    def test_this_weeks_approved_leave_is_listed_and_others_are_not(self):
        later = self.leave(dt.date(2026, 10, 29), dt.date(2026, 10, 30))
        self.leave(dt.date(2026, 10, 28), dt.date(2026, 10, 28), status="pending")
        self.leave(dt.date(2026, 11, 3), dt.date(2026, 11, 4))

        data = self.today()

        self.assertIsNone(data["leave"]["today"])
        self.assertEqual([later.id], [leave["id"] for leave in data["leave"]["this_week"]])
        self.assertEqual(1, data["owed"]["reports"])


class Access(TodayTestCase):
    def test_an_hod_gets_their_own_day(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.entry(self.nine_a, self.p2, self.maths, hod)

        self.assertEqual([2], [p["period_number"] for p in self.today(user=hod)["periods"]])

    def test_there_is_no_asking_for_somebody_elses_day(self):
        data = self.today(user=self.other, query=f"?teacher_id={self.teacher.id}")

        self.assertEqual([2], [p["period_number"] for p in data["periods"]], "still the caller's own")

    def test_a_role_without_the_timetable_is_refused(self):
        driver = factories.UserFactory(school=self.school, role=UserRole.DRIVER)

        with at(MONDAY_1015_IST):
            response = self.client_for(driver).get("/api/v1/timetable/today")

        self.assertEqual(403, response.status_code)

    def test_signed_out_is_refused(self):
        self.assertEqual(401, APIClient().get("/api/v1/timetable/today").status_code)
