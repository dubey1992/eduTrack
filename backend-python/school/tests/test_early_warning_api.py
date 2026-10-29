"""Student early warning, A3 (docs/analytics.md), over HTTP.

Monday 14 September 2026, as in the report tests. What matters: each signal
fires at its line and not a hair above it, says nothing without enough to go
on, follows the school's own thresholds, and is shown only to the people
decided on 2026-10-29 - admins everything, a class teacher their own class,
a head of department the test signals from their own subjects.
"""

import datetime as dt

from rest_framework.test import APIClient

from school import factories
from school.enums import UserRole
from school.services import HolidayService

from .test_reports_api import ReportTestCase, client_for

URL = "/api/v1/analytics/early-warning"
TODAY = dt.date(2026, 9, 14)


class EarlyWarningTestCase(ReportTestCase):
    def setUp(self):
        super().setUp()
        dates = HolidayService.working_dates(self.school.id, TODAY - dt.timedelta(days=200), TODAY)
        self.window = [day.isoformat() for day in dates[-30:]]
        self.before = [day.isoformat() for day in dates[-60:-30]]
        self.department = factories.DepartmentFactory(school=self.school, name="Science")
        self.subject = factories.SubjectFactory(department=self.department, name="Physics")
        self.term = factories.AcademicTermFactory(academic_year=self.year, school=self.school)

    def register(self, days, absent=0, student=None, status_when_away="absent"):
        """Marks [student] on each of [days], away on the last [absent]."""
        for index, day in enumerate(days):
            self.mark(day, status_when_away if index >= len(days) - absent else "present", student)

    def result(self, on: str, scored: int, student=None, subject=None, out_of: int = 20):
        assessment = factories.AssessmentFactory(
            class_section=self.section, academic_term=self.term, subject=subject or self.subject,
            assessment_date=dt.date.fromisoformat(on),
            max_marks=out_of, status="published", created_by=self.teacher,
        )
        factories.AssessmentMarkFactory(assessment=assessment, student=student or self.student, marks_obtained=scored)

    def look(self, user, **params):
        response = client_for(user).get(URL, params)
        self.assertEqual(200, response.status_code, getattr(response, "data", response))

        return response.data

    def flags(self, user=None, **params) -> dict:
        """student id -> the codes of their signals."""
        data = self.look(user or self.admin, **params)

        return {row["student_id"]: [signal["code"] for signal in row["signals"]] for row in data["data"]}


class Attendance(EarlyWarningTestCase):
    def test_under_the_line_over_the_last_thirty_school_days(self):
        self.register(self.window, absent=10)

        data = self.look(self.admin)

        row = data["data"][0]
        self.assertEqual(("at_risk", self.student.id), (row["level"], row["student_id"]))
        self.assertEqual(
            {"code": "low_attendance", "value": 66.7, "previous": None,
             "message": "Attendance 66.7% over the last 30 school days, below 75%."},
            row["signals"][0],
        )
        self.assertEqual("Grade 8 A", row["class_section"])

    def test_on_the_line_is_not_under_it(self):
        self.register(self.window[-20:], absent=5)  # 15 of 20: exactly 75%

        self.assertEqual({}, self.flags())

    def test_too_few_marked_days_says_nothing(self):
        # Nine absences in a row: worrying, but not yet a rate.
        self.register(self.window[-9:], absent=9)

        self.assertEqual({}, self.flags())

    def test_days_nobody_marked_do_not_count_against_the_child(self):
        # Present on all of the 12 days anybody took the register.
        self.register(self.window[-12:])

        self.assertEqual({}, self.flags())

    def test_a_fall_is_flagged_even_above_the_line(self):
        self.register(self.before)
        self.register(self.window, absent=4)  # 86.7%, from 100%

        row = self.look(self.admin)["data"][0]

        self.assertEqual(["falling_attendance"], [signal["code"] for signal in row["signals"]])
        self.assertEqual("Attendance down 13.3 points, from 100% to 86.7%.", row["signals"][0]["message"])
        self.assertEqual(100, row["signals"][0]["previous"])

    def test_low_and_falling_is_high_risk(self):
        self.register(self.before)
        self.register(self.window, absent=12)

        row = self.look(self.admin)["data"][0]

        self.assertEqual("high", row["level"])
        self.assertEqual(["low_attendance", "falling_attendance"], [signal["code"] for signal in row["signals"]])

    def test_the_school_sets_its_own_lines(self):
        factories.ModuleSettingFactory(
            school=self.school, module="reports",
            settings={"early_warning_attendance_below": 90, "early_warning_drop_points": 20},
        )
        self.register(self.before)
        self.register(self.window, absent=4)  # 86.7%: under 90, but only 13.3 down

        data = self.look(self.admin)

        self.assertEqual(["low_attendance"], [s["code"] for s in data["data"][0]["signals"]])
        self.assertEqual({"attendance_below": 90, "drop_points": 20, "pass_mark": 33}, data["summary"]["thresholds"])

    def test_a_school_without_attendance_gets_no_attendance_signals(self):
        factories.ModuleSettingFactory(school=self.school, module="attendance", school_enabled=False)
        self.register(self.window, absent=20)

        self.assertEqual({}, self.flags())


class Marks(EarlyWarningTestCase):
    def test_under_the_pass_mark_over_the_last_ninety_days(self):
        self.result("2026-08-20", 5)
        self.result("2026-09-10", 6)  # 25% and 30%

        row = self.look(self.admin)["data"][0]

        self.assertEqual(
            "Test average 27.5% over the last 90 days, below the 33% pass mark.", row["signals"][0]["message"]
        )

    def test_one_result_is_not_enough(self):
        self.result("2026-09-10", 2)

        self.assertEqual({}, self.flags())

    def test_a_fall_against_the_ninety_days_before(self):
        self.result("2026-05-10", 18)
        self.result("2026-05-20", 18)  # 90%
        self.result("2026-08-20", 12)
        self.result("2026-09-10", 12)  # 60%

        self.assertEqual({self.student.id: ["falling_marks"]}, self.flags())

    def test_unpublished_results_do_not_count(self):
        assessment = factories.AssessmentFactory(
            class_section=self.section, academic_term=self.term, subject=self.subject,
            assessment_date=dt.date(2026, 9, 1), status="draft",
        )
        factories.AssessmentMarkFactory(assessment=assessment, student=self.student, marks_obtained=0)
        self.result("2026-09-10", 1)

        self.assertEqual({}, self.flags())


class TheList(EarlyWarningTestCase):
    def test_highest_risk_first_with_counts_and_a_level_filter(self):
        sliding = factories.StudentFactory(class_section=self.section, first_name="Zara")
        self.register(self.window, absent=10)  # Arjun: low only
        self.register(self.before, student=sliding)
        self.register(self.window, absent=12, student=sliding)  # Zara: low and falling

        data = self.look(self.admin)

        self.assertEqual([sliding.id, self.student.id], [row["student_id"] for row in data["data"]])
        self.assertEqual({"high": 1, "at_risk": 1}, data["summary"]["counts"])
        self.assertEqual("2026-09-14", data["summary"]["as_of"])
        self.assertEqual(self.window[0], data["summary"]["windows"]["attendance"]["from"])

        high = self.look(self.admin, level="high")
        self.assertEqual([sliding.id], [row["student_id"] for row in high["data"]])
        # The counts are the whole list's, whatever the filter.
        self.assertEqual({"high": 1, "at_risk": 1}, high["summary"]["counts"])
        self.assertEqual(1, high["meta"]["total"])

    def test_one_class_alone(self):
        other = factories.StudentFactory(
            class_section=factories.ClassSectionFactory(school_class=self.section.school_class, name="B")
        )
        self.register(self.window, absent=10)
        self.register(self.window, absent=10, student=other)

        self.assertEqual([self.student.id], list(self.flags(class_section_id=self.section.id)))

    def test_a_student_who_has_left_is_not_listed(self):
        self.register(self.window, absent=10)
        self.student.status = "inactive"
        self.student.save()

        self.assertEqual({}, self.flags())

    def test_an_unknown_level_is_refused(self):
        response = client_for(self.admin).get(URL, {"level": "panic"})

        self.assertEqual(422, response.status_code)
        self.assertEqual({"level": ["The selected level is invalid."]}, response.data["details"]["errors"])


class WhoSees(EarlyWarningTestCase):
    def setUp(self):
        super().setUp()
        self.other_section = factories.ClassSectionFactory(school_class=self.section.school_class, name="B")
        self.other = factories.StudentFactory(class_section=self.other_section, first_name="Neha")
        # Both of them low on attendance and on Physics.
        for student in (self.student, self.other):
            self.register(self.window, absent=10, student=student)
            self.result("2026-08-20", 4, student=student)
            self.result("2026-09-10", 4, student=student)

    def test_an_admin_sees_every_student_and_every_signal(self):
        self.assertEqual(
            {self.student.id: ["low_attendance", "low_marks"], self.other.id: ["low_attendance", "low_marks"]},
            self.flags(self.admin),
        )

    def test_a_class_teacher_sees_their_own_class_only(self):
        # self.teacher is Grade 8 A's class teacher.
        self.assertEqual({self.student.id: ["low_attendance", "low_marks"]}, self.flags(self.teacher))
        # Naming the other class does not widen it.
        self.assertEqual({}, self.flags(self.teacher, class_section_id=self.other_section.id))

    def test_a_teacher_with_no_class_sees_nobody(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        data = self.look(teacher)

        self.assertEqual([], data["data"])
        self.assertEqual({"high": 0, "at_risk": 0}, data["summary"]["counts"])

    def test_a_head_of_department_sees_only_their_subjects_test_signals(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.department.hod_user = hod
        self.department.save()

        self.assertEqual({self.student.id: ["low_marks"], self.other.id: ["low_marks"]}, self.flags(hod))

    def test_a_head_of_another_department_sees_nothing_of_physics(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        factories.DepartmentFactory(school=self.school, name="Languages", hod_user=hod)

        self.assertEqual({}, self.flags(hod))

    def test_a_head_of_department_who_is_also_a_class_teacher_sees_their_class_in_full(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.department.hod_user = hod
        self.department.save()
        self.other_section.class_teacher = hod
        self.other_section.save()

        self.assertEqual(
            {self.student.id: ["low_marks"], self.other.id: ["low_attendance", "low_marks"]}, self.flags(hod)
        )

    def test_other_roles_are_refused(self):
        for role in (UserRole.STAFF, UserRole.ACCOUNTANT, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                user = factories.UserFactory(school=self.school, role=role)
                self.assertEqual(403, client_for(user).get(URL).status_code)

    def test_a_school_admin_naming_another_school_sees_their_own(self):
        other_school = factories.SchoolFactory(timezone="UTC")

        self.assertEqual(
            {self.student.id, self.other.id}, set(self.flags(self.admin, school_id=other_school.id))
        )

    def test_a_teacher_of_another_school_sees_none_of_these_students(self):
        stranger = factories.UserFactory(school=factories.SchoolFactory(timezone="UTC"), role=UserRole.TEACHER)

        self.assertEqual({}, self.flags(stranger, school_id=self.school.id))

    def test_a_super_admin_names_a_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        refused = client_for(root).get(URL)
        self.assertEqual(422, refused.status_code)
        self.assertEqual({"school_id": ["Pick a school to report on."]}, refused.data["details"]["errors"])
        self.assertEqual(2, len(self.flags(root, school_id=self.school.id)))

    def test_a_school_with_reports_off_has_no_early_warning(self):
        factories.ModuleSettingFactory(school=self.school, module="reports", school_enabled=False)

        for user in (self.admin, self.teacher):
            with self.subTest(role=user.role):
                response = client_for(user).get(URL)
                self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))

    def test_an_unauthenticated_caller_gets_nothing(self):
        self.assertEqual(401, APIClient().get(URL).status_code)
