"""The landing screen, for each role.

Every role gets the same shape - cards, an attendance trend, things wanting
attention - and what goes in them is decided by who is asking, never by what
they send. A school user's figures are always their own school's.
"""

import datetime as dt
from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Attendance, Holiday, Payment, TransportTrip

# Monday 14 September 2026, midday UTC.
NOW = dt.datetime(2026, 9, 14, 12, 0, tzinfo=dt.timezone.utc)
TODAY = "2026-09-14"


class DashboardTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.school = factories.SchoolFactory(name="Sunrise Public School", timezone="UTC")
        self.year = factories.AcademicYearFactory(school=self.school)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=self.year, school=self.school),
            class_teacher=self.teacher,
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def dashboard(self, user, **params) -> dict:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
        response = client.get("/api/v1/dashboard", params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    @staticmethod
    def cards(data) -> dict:
        return {card["key"]: card for card in data["cards"]}

    def mark(self, student, day, status):
        Attendance.objects.create(
            school_id=student.school_id, academic_year_id=student.class_section.school_class.academic_year_id,
            class_section_id=student.class_section_id, student=student, attendance_date=day, status=status,
            created_at=NOW, updated_at=NOW,
        )


class SchoolAdmin(DashboardTestCase):
    def test_the_school_at_a_glance(self):
        students = [factories.StudentFactory(class_section=self.section) for _ in range(3)]
        factories.StudentFactory(class_section=self.section, status="inactive")
        factories.StaffProfileFactory(user=self.teacher)
        self.mark(students[0], TODAY, "present")
        self.mark(students[1], TODAY, "present")
        self.mark(students[2], TODAY, "absent")
        factories.TransportRouteFactory(school=self.school)
        factories.TransportRouteFactory(school=self.school, status="inactive")

        data = self.dashboard(self.admin)

        self.assertEqual(
            {"role": "SCHOOL_ADMIN", "school_id": self.school.id, "as_of": TODAY, "is_working_day": True, "holiday": None},
            {key: data[key] for key in ("role", "school_id", "as_of", "is_working_day", "holiday")},
        )
        self.assertEqual(
            [
                {"key": "students", "label": "Students", "value": "3", "hint": "on the roll", "tone": "neutral"},
                {"key": "staff", "label": "Teachers & staff", "value": "1", "hint": "on the payroll", "tone": "neutral"},
                # Two of three, to one decimal, written as PHP writes a float.
                {"key": "attendance", "label": "Attendance today", "value": "66.7%", "hint": "of students present", "tone": "neutral"},
                {"key": "transport", "label": "Trips today", "value": "0", "hint": "1 active routes", "tone": "neutral"},
            ],
            data["cards"],
        )
        self.assertEqual([], data["attention"])

    def test_the_trend_is_the_last_seven_working_days_oldest_first(self):
        student = factories.StudentFactory(class_section=self.section)
        self.mark(student, "2026-09-11", "present")
        Holiday.objects.create(school=self.school, name="Founders Day", type="school_event",
                               start_date="2026-09-09", end_date="2026-09-09", created_at=NOW, updated_at=NOW)

        trend = self.dashboard(self.admin)["attendance_trend"]

        # No weekend, no holiday, and a whole rate written without its ".0".
        self.assertEqual(
            ["2026-09-03", "2026-09-04", "2026-09-07", "2026-09-08", "2026-09-10", "2026-09-11", "2026-09-14"],
            [point["date"] for point in trend],
        )
        self.assertEqual({"date": "2026-09-11", "label": "11 Sep", "attendance_rate": 100}, trend[5])
        self.assertIsNone(trend[6]["attendance_rate"])

    def test_what_wants_attention(self):
        factories.MessageFactory(school=self.school, status="failed")
        factories.MessageFactory(school=self.school, status="failed")
        factories.StaffLeaveFactory(staff_profile=factories.StaffProfileFactory(user=self.teacher), status="pending")

        self.assertEqual(
            [
                {"key": "attendance", "message": "No attendance has been marked yet today."},
                {"key": "messages", "message": "2 messages failed to send and can be retried."},
                {"key": "leave", "message": "1 leave requests are waiting for a decision."},
            ],
            self.dashboard(self.admin)["attention"],
        )

    def test_a_holiday_is_named_and_asks_for_no_register(self):
        Holiday.objects.create(school=self.school, name="Founders Day", type="school_event",
                               start_date=TODAY, end_date=TODAY, created_at=NOW, updated_at=NOW)

        data = self.dashboard(self.admin)

        self.assertEqual((False, "Founders Day", []), (data["is_working_day"], data["holiday"], data["attention"]))

    def test_another_school_cannot_be_named(self):
        other = factories.SchoolFactory()
        factories.StudentFactory(class_section=factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=factories.AcademicYearFactory(school=other), school=other)
        ))

        data = self.dashboard(self.admin, school_id=other.id)

        self.assertEqual((self.school.id, "0"), (data["school_id"], self.cards(data)["students"]["value"]))


class SuperAdmin(DashboardTestCase):
    def setUp(self):
        super().setUp()
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

    def payment(self, currency, paid, status="paid"):
        Payment.objects.create(
            school=factories.SchoolFactory(currency_code=currency), payment_type="setup_fee", amount=Decimal(paid),
            paid_amount=Decimal(paid), currency_code=currency, payment_date="2026-09-01", payment_mode="cash",
            status=status, created_by=self.root, created_at=NOW, updated_at=NOW,
        )

    def test_the_platform_groups_money_by_currency_and_never_blends_it(self):
        self.payment("USD", "12000.00")
        self.payment("NGN", "250000.50")
        self.payment("INR", "450000.00")
        self.payment("USD", "500.00", status="partial")
        self.payment("EUR", "900.00", status="cancelled")
        self.payment("GBP", "0.00", status="pending")

        data = self.dashboard(self.root)
        cards = self.cards(data)

        self.assertEqual((None, False, None, []), (data["school_id"], data["is_working_day"], data["holiday"], data["attendance_trend"]))
        self.assertEqual("INR 450,000.00 + NGN 250,000.50 + USD 12,500.00", cards["collected"]["value"])
        self.assertEqual(("2", "warning"), (cards["outstanding"]["value"], cards["outstanding"]["tone"]))
        # The school every test has, and one per payment.
        self.assertEqual(("7", "7 active"), (cards["schools"]["value"], cards["schools"]["hint"]))

    def test_nothing_collected_reads_as_a_dash(self):
        self.assertEqual("-", self.cards(self.dashboard(self.root))["collected"]["value"])

    def test_a_named_school_gets_that_schools_dashboard(self):
        data = self.dashboard(self.root, school_id=self.school.id)

        self.assertEqual((self.school.id, "students"), (data["school_id"], data["cards"][0]["key"]))

    def test_a_junk_or_blank_school_id_is_read_the_way_php_casts_it(self):
        self.assertEqual(0, self.dashboard(self.root, school_id="abc")["school_id"])
        self.assertIsNone(self.dashboard(self.root, school_id="")["school_id"])


class Group(DashboardTestCase):
    def setUp(self):
        super().setUp()
        self.group = factories.SchoolFactory(name="A Group", timezone="UTC")
        self.north = factories.SchoolFactory(name="B North", timezone="UTC", parent_school=self.group)
        self.south = factories.SchoolFactory(name="C South", timezone="UTC", parent_school=self.group)
        self.group_admin = factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)

    def student_at(self, school):
        year = factories.AcademicYearFactory(school=school)
        return factories.StudentFactory(class_section=factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=year, school=school)
        ))

    def test_the_whole_group_rolled_up_with_unmarked_branches_named(self):
        north = self.student_at(self.north)
        south = self.student_at(self.south)
        self.student_at(self.school)  # outside the group
        self.mark(north, TODAY, "present")
        self.mark(south, TODAY, "absent")

        data = self.dashboard(self.group_admin)
        cards = self.cards(data)

        self.assertEqual((None, False), (data["school_id"], data["is_working_day"]))
        self.assertEqual(("3", "2", "50%"), (cards["branches"]["value"], cards["students"]["value"], cards["attendance"]["value"]))
        self.assertEqual(
            [{"key": f"attendance-{self.group.id}", "message": "A Group has not marked attendance today."}],
            data["attention"],
        )

    def test_one_branch_can_be_named_but_nothing_outside(self):
        self.student_at(self.north)
        self.student_at(self.school)

        branch = self.dashboard(self.group_admin, school_id=self.north.id)
        outside = self.dashboard(self.group_admin, school_id=self.school.id)

        self.assertEqual((self.north.id, "1"), (branch["school_id"], self.cards(branch)["students"]["value"]))
        self.assertIsNone(outside["school_id"])
        self.assertEqual("3", self.cards(outside)["branches"]["value"])


class EverybodyElse(DashboardTestCase):
    def test_a_head_of_department(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        mine = factories.DepartmentFactory(school=self.school, hod_user=hod)
        theirs = factories.DepartmentFactory(school=self.school)
        factories.StaffProfileFactory(user=self.teacher, department=mine)
        entry = factories.TimetableEntryFactory(
            class_section=self.section, period=factories.PeriodFactory(school=self.school),
            subject=factories.SubjectFactory(department=mine), teacher=self.teacher,
        )
        factories.DailyTeachingReportFactory(timetable_entry=entry, report_date=dt.date(2026, 9, 7))
        factories.DailyTeachingReportFactory(timetable_entry=entry, report_date=dt.date(2026, 9, 14), reviewed_at=NOW)
        factories.DailyTeachingReportFactory(timetable_entry=factories.TimetableEntryFactory(
            class_section=self.section, period=factories.PeriodFactory(school=self.school),
            subject=factories.SubjectFactory(department=theirs), teacher=self.teacher,
        ))

        data = self.dashboard(hod)

        self.assertEqual(
            [("departments", "1", "neutral"), ("teachers", "1", "neutral"), ("reviews", "1", "warning")],
            [(card["key"], card["value"], card["tone"]) for card in data["cards"]],
        )
        self.assertEqual([{"key": "reviews", "message": "1 teaching reports are waiting for your review."}], data["attention"])
        self.assertEqual(7, len(data["attendance_trend"]))

    def test_a_head_of_department_who_heads_nothing(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        factories.DailyTeachingReportFactory(timetable_entry=factories.TimetableEntryFactory(
            class_section=self.section, period=factories.PeriodFactory(school=self.school),
            subject=factories.SubjectFactory(department=factories.DepartmentFactory(school=self.school)),
        ))

        data = self.dashboard(hod)

        self.assertEqual(["0", "0", "0"], [card["value"] for card in data["cards"]])
        self.assertEqual([], data["attention"])

    def test_a_teacher(self):
        for day in ("monday", "monday", "tuesday"):
            entry = factories.TimetableEntryFactory(
                class_section=self.section, period=factories.PeriodFactory(school=self.school), teacher=self.teacher,
                subject=factories.SubjectFactory(department=factories.DepartmentFactory(school=self.school)), day_of_week=day,
            )
        factories.DailyTeachingReportFactory(timetable_entry=entry, report_date=dt.date(2026, 9, 14))

        data = self.dashboard(self.teacher)

        self.assertEqual(
            [("periods", "2", "neutral"), ("reports", "1/2", "warning"), ("register", "1", "warning")],
            [(card["key"], card["value"], card["tone"]) for card in data["cards"]],
        )
        self.assertEqual(
            [{"key": "register", "message": "Today's register has not been marked for your class yet."}], data["attention"]
        )

    def test_a_teacher_whose_register_is_marked_or_whose_school_is_shut(self):
        self.mark(factories.StudentFactory(class_section=self.section), TODAY, "present")
        self.assertEqual("0", self.cards(self.dashboard(self.teacher))["register"]["value"])

        Attendance.objects.all().delete()
        Holiday.objects.create(school=self.school, name="Founders Day", type="school_event",
                               start_date=TODAY, end_date=TODAY, created_at=NOW, updated_at=NOW)
        self.assertEqual("0", self.cards(self.dashboard(self.teacher))["register"]["value"])

    def test_a_transport_manager(self):
        manager = factories.UserFactory(school=self.school, role=UserRole.TRANSPORT_MANAGER)
        vehicle = factories.VehicleFactory(school=self.school)
        driver = factories.DriverFactory(school=self.school)
        route = factories.TransportRouteFactory(school=self.school, vehicle=vehicle, driver=driver)
        for status, day in (("in_progress", TODAY), ("completed", TODAY), ("completed", "2026-09-11")):
            TransportTrip.objects.create(
                school=self.school, route=route, vehicle=vehicle, driver=driver, trip_date=day, direction="pickup",
                status=status, started_by=manager, started_at=NOW, created_at=NOW, updated_at=NOW,
            )

        self.assertEqual(
            [("routes", "1"), ("running", "1"), ("completed", "1")],
            [(card["key"], card["value"]) for card in self.dashboard(manager)["cards"]],
        )

    def test_staff(self):
        clerk = factories.UserFactory(school=self.school, role=UserRole.STAFF)
        factories.StaffLeaveFactory(staff_profile=factories.StaffProfileFactory(user=clerk), status="pending")
        factories.MessageFactory(school=self.school, user=clerk, channel="in_app")
        factories.MessageFactory(school=self.school, user=clerk, channel="in_app", read_at=NOW)
        factories.MessageFactory(school=self.school, user=clerk, channel="sms")

        self.assertEqual(
            [("leave", "1", "neutral"), ("inbox", "1", "warning")],
            [(card["key"], card["value"], card["tone"]) for card in self.dashboard(clerk)["cards"]],
        )

    def test_a_school_user_cannot_point_it_at_another_school(self):
        other = factories.SchoolFactory()

        self.assertEqual(self.school.id, self.dashboard(self.teacher, school_id=other.id)["school_id"])

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get("/api/v1/dashboard").status_code)
