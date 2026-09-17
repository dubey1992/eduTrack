"""The HOD department report, over HTTP.

Most of this file is Laravel's own fixture, ported number for number: a month
with holidays, a teacher who was present, late, on a half day, absent and on
leave, a timetable, two reports and a half-covered syllabus. Every metric the
page shows is asserted against the figure Laravel's test asserts, so a port
that computed any of them differently fails here before it reaches a diff.

Three things are about the *wire*, not the arithmetic, and each is a place
PHP and Python disagree by default:

- **Whole floats.** PHP writes 50.0 as `50`; Python's json writes `50.0`.
- **Rounding.** PHP rounds halves away from zero; Python rounds them to even.
- **The month.** Carbon's createFromFormat('Y-m') takes the missing day from
  today, so February asked for on March 30th used to compute March. Fixed on
  both backends; the test for it freezes the clock on the 30th.
"""

import datetime as dt
import json
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole, UserStatus
from school.models import DailyTeachingReport, Holiday, StaffAttendance, SyllabusTopicProgress
from school.services import php_number, php_round_1

MONTH = "2026-08"


class HodReportTestCase(TestCase):
    def setUp(self):
        cache.clear()

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def report(self, user, query=f"?month={MONTH}"):
        return self.as_user(user).get("/api/v1/hod/department-report" + query)

    def make_department(self, school=None):
        school = school or factories.SchoolFactory()
        hod = factories.UserFactory(school=school, role=UserRole.HOD, first_name="Meera")
        department = factories.DepartmentFactory(school=school, hod_user=hod)
        factories.StaffProfileFactory(school=school, user=hod, department=department)

        teacher = factories.UserFactory(school=school, role=UserRole.TEACHER, first_name="Priya")
        profile = factories.StaffProfileFactory(school=school, user=teacher, department=department)

        return school, department, hod, teacher, profile

    def section(self, school):
        return factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                school=school, academic_year=factories.AcademicYearFactory(school=school)
            )
        )

    def holiday(self, school, start, end=None, name="Founders Day"):
        Holiday.objects.create(
            school_id=school.id, name=name, type="school_event", start_date=start, end_date=end or start
        )

    def attend(self, profile, date, status, check_in=None):
        StaffAttendance.objects.create(
            school_id=profile.school_id,
            staff_profile_id=profile.id,
            attendance_date=date,
            status=status,
            check_in=check_in,
            marked_by_id=profile.user_id,
        )

    def row(self, response, user):
        return next((row for row in response.data["data"] if row["user_id"] == user.id), None)


class MetricsTest(HodReportTestCase):
    """August 2026: 21 weekdays; Fri 14th and Mon 24th-Tue 25th are holidays,
    leaving 18 working days."""

    def setUp(self):
        super().setUp()
        school, department, hod, teacher, profile = self.make_department()
        self.school, self.hod, self.teacher, self.profile = school, hod, teacher, profile

        self.holiday(school, dt.date(2026, 8, 14))
        self.holiday(school, dt.date(2026, 8, 24), dt.date(2026, 8, 25), name="Monsoon break")

        first = factories.PeriodFactory(school=school, period_number=1, start_time=dt.time(9, 0), end_time=dt.time(9, 45))
        second = factories.PeriodFactory(school=school, period_number=2, start_time=dt.time(9, 45), end_time=dt.time(10, 30))

        section_a = self.section(school)
        section_b = self.section(school)
        maths = factories.SubjectFactory(school=school, department=department)
        science = factories.SubjectFactory(school=school, department=department)

        def slot(section, subject, period, day):
            return factories.TimetableEntryFactory(
                school=school, class_section=section, subject=subject, period=period, day_of_week=day, teacher=teacher
            )

        monday_1 = slot(section_a, maths, first, "monday")
        monday_2 = slot(section_a, maths, second, "monday")
        slot(section_b, science, first, "tuesday")
        slot(section_a, maths, first, "wednesday")

        self.attend(profile, dt.date(2026, 8, 3), "present", dt.time(9, 15))
        self.attend(profile, dt.date(2026, 8, 4), "half_day", dt.time(8, 50))
        self.attend(profile, dt.date(2026, 8, 5), "absent")
        self.attend(profile, dt.date(2026, 8, 6), "leave")

        factories.DailyTeachingReportFactory(
            timetable_entry=monday_1, report_date=dt.date(2026, 8, 3), reviewed_by=hod, reviewed_at=timezone.now()
        )
        factories.DailyTeachingReportFactory(timetable_entry=monday_2, report_date=dt.date(2026, 8, 3))

        # Thu-Fri (2 working days); Jul 30-Sat Aug 1, whose only August day is
        # a weekend (0); a half-day leave on a Monday (0.5); a pending request
        # that must not count.
        factories.StaffLeaveFactory(staff_profile=profile, start_date=dt.date(2026, 8, 6), end_date=dt.date(2026, 8, 7), status="approved")
        factories.StaffLeaveFactory(staff_profile=profile, start_date=dt.date(2026, 7, 30), end_date=dt.date(2026, 8, 1), status="approved")
        factories.StaffLeaveFactory(staff_profile=profile, start_date=dt.date(2026, 8, 10), end_date=dt.date(2026, 8, 10), status="approved", leave_type="half_day")
        factories.StaffLeaveFactory(staff_profile=profile, start_date=dt.date(2026, 8, 12), end_date=dt.date(2026, 8, 14), status="pending")

        maths_topics = [factories.SyllabusTopicFactory(subject=maths, sequence_number=n) for n in range(1, 5)]
        for n in range(1, 3):
            factories.SyllabusTopicFactory(subject=science, sequence_number=n)

        for topic, section in ((maths_topics[0], section_a), (maths_topics[1], section_a), (maths_topics[2], section_b)):
            # The last is for a section Priya does not teach maths in, so it
            # must not count towards her syllabus.
            SyllabusTopicProgress.objects.create(
                school_id=school.id, syllabus_topic=topic, class_section=section, completed_by=teacher, completed_at=timezone.now()
            )

    def test_every_metric_for_a_teacher(self):
        response = self.report(self.hod)
        row = self.row(response, self.teacher)

        self.assertEqual(18, response.data["working_days"])
        self.assertEqual(self.profile.id, row["staff_profile_id"])
        self.assertEqual(self.teacher.name, row["teacher_name"])
        self.assertEqual(self.profile.employee_id, row["employee_id"])
        self.assertEqual(8.3, row["attendance_percent"])    # (1 + 0.5) / 18
        self.assertEqual(2.5, row["leave_days"])            # Thu+Fri + a half day
        self.assertEqual(1, row["late_marks"])              # 09:15 against a 09:00 first period
        self.assertEqual(15, row["classes_assigned"])       # Mon 4x2 (24th a holiday) + Tue 3 + Wed 4
        self.assertEqual(3, row["classes_taught"])          # present Mon 3rd (2) + half day Tue 4th (1)
        self.assertEqual(2, row["reports_submitted"])
        self.assertEqual(1, row["reports_pending_review"])
        self.assertEqual(33, row["syllabus_percent"])       # 2 of 4 maths + 2 science
        self.assertEqual("review", row["status"])

    def test_department_wide_figures(self):
        response = self.report(self.hod)

        # Priya's 1.5 credits and the HOD's none, over 18 days for 2 teachers.
        self.assertEqual(2, response.data["teacher_count"])
        self.assertEqual(4.2, response.data["avg_attendance_percent"])
        self.assertEqual(2.5, response.data["leave_days"])
        self.assertEqual(1, response.data["late_marks"])

    def test_a_teacher_with_no_activity_is_on_track_with_zero_metrics(self):
        row = self.row(self.report(self.hod), self.hod)

        self.assertEqual(
            (0, 0, 0, 0, 0, "on_track"),
            (row["attendance_percent"], row["classes_assigned"], row["classes_taught"],
             row["reports_submitted"], row["syllabus_percent"], row["status"]),
        )

    def test_whole_numbers_go_out_without_a_fraction_as_php_writes_them(self):
        # The HOD's attendance is 0.0 and a whole-day leave total is 2.0 in
        # both languages; only Python would write them as `0.0` and `2.0`.
        body = self.report(self.hod).content.decode()
        hod_row = json.dumps(self.row(self.report(self.hod), self.hod))

        self.assertIn('"attendance_percent": 0,', hod_row)
        self.assertNotIn(".0,", body.replace("8.3,", "").replace("4.2,", "").replace("2.5,", ""))

    def test_a_month_that_is_all_vacation_has_no_working_days_and_divides_by_nothing(self):
        self.holiday(self.school, dt.date(2026, 5, 1), dt.date(2026, 5, 31), name="Summer")

        response = self.report(self.hod, "?month=2026-05")

        self.assertEqual(
            (0, 0, 0, 0),
            (response.data["working_days"], response.data["avg_attendance_percent"],
             response.data["late_marks"], response.data["leave_days"]),
        )
        self.assertEqual(0, self.row(response, self.teacher)["classes_assigned"])


class ScopeTest(HodReportTestCase):
    def test_an_hod_sees_their_own_department(self):
        _, department, hod, teacher, _ = self.make_department()

        response = self.report(hod)

        self.assertEqual(200, response.status_code)
        self.assertEqual([{"id": department.id, "name": department.name}], response.data["departments"])
        self.assertIsNotNone(self.row(response, teacher))

    def test_an_hod_may_name_their_own_department(self):
        _, department, hod, _, _ = self.make_department()

        self.assertEqual(200, self.report(hod, f"?month={MONTH}&department_id={department.id}").status_code)

    def test_an_hod_cannot_ask_for_another_department(self):
        school, _, hod, _, _ = self.make_department()
        other = factories.DepartmentFactory(school=school, name="Arts")

        self.assertEqual(403, self.report(hod, f"?month={MONTH}&department_id={other.id}").status_code)

    def test_an_hod_without_a_filter_sees_only_departments_they_head(self):
        school, _, hod, _, _ = self.make_department()
        other = factories.DepartmentFactory(school=school, name="Arts")
        outsider = factories.UserFactory(school=school, role=UserRole.TEACHER)
        factories.StaffProfileFactory(school=school, user=outsider, department=other)

        response = self.report(hod)

        self.assertIsNone(self.row(response, outsider))

    def test_an_hod_heading_two_departments_sees_both(self):
        school, _, hod, _, _ = self.make_department()
        second = factories.DepartmentFactory(school=school, name="Arts", hod_user=hod)
        artist = factories.UserFactory(school=school, role=UserRole.TEACHER)
        factories.StaffProfileFactory(school=school, user=artist, department=second)

        response = self.report(hod)

        self.assertEqual(2, len(response.data["departments"]))
        self.assertIsNotNone(self.row(response, artist))

    def test_a_school_admin_sees_every_department_of_their_school(self):
        school, _, _, _, _ = self.make_department()
        factories.DepartmentFactory(school=school, name="Arts")
        admin = factories.UserFactory(school=school, role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(2, len(self.report(admin).data["departments"]))

    def test_a_school_admin_cannot_name_another_schools_department(self):
        _, foreign, _, _, _ = self.make_department()
        admin = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        response = self.report(admin, f"?month={MONTH}&department_id={foreign.id}")

        self.assertEqual(422, response.status_code)
        self.assertIn("department_id", response.data["details"]["errors"])

    def test_a_school_admin_never_sees_another_schools_teachers(self):
        _, _, _, foreign_teacher, _ = self.make_department()
        admin = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        # Even naming the other school: the school_id is not theirs to choose.
        foreign_school = foreign_teacher.school_id
        response = self.report(admin, f"?month={MONTH}&school_id={foreign_school}")

        self.assertIsNone(self.row(response, foreign_teacher))

    def test_a_super_admin_names_the_school(self):
        school, _, _, teacher, _ = self.make_department()
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        missing = self.report(root)
        named = self.report(root, f"?month={MONTH}&school_id={school.id}")

        self.assertEqual(422, missing.status_code)
        self.assertIn("school_id", missing.data["details"]["errors"])
        self.assertIsNotNone(self.row(named, teacher))

    def test_teachers_staff_and_transport_managers_do_not_see_it(self):
        school, _, _, teacher, _ = self.make_department()

        for user in (
            teacher,
            factories.UserFactory(school=school, role=UserRole.STAFF),
            factories.UserFactory(school=school, role=UserRole.TRANSPORT_MANAGER),
        ):
            self.assertEqual(403, self.report(user).status_code, user.role)

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get("/api/v1/hod/department-report").status_code)

    def test_inactive_teachers_and_non_teaching_roles_are_left_out(self):
        school, department, hod, _, _ = self.make_department()
        inactive = factories.UserFactory(school=school, role=UserRole.TEACHER, status=UserStatus.INACTIVE)
        clerk = factories.UserFactory(school=school, role=UserRole.STAFF)
        for user in (inactive, clerk):
            factories.StaffProfileFactory(school=school, user=user, department=department)

        response = self.report(hod)

        self.assertEqual(2, response.data["teacher_count"])
        self.assertIsNone(self.row(response, inactive))
        self.assertIsNone(self.row(response, clerk))


class InputTest(HodReportTestCase):
    def test_the_month_must_be_year_dash_month(self):
        _, _, hod, _, _ = self.make_department()

        for bad in ("2026-9", "2026-13", "08-2026", "August"):
            response = self.report(hod, f"?month={bad}")

            with self.subTest(month=bad):
                self.assertEqual(
                    ["The month field must match the format Y-m."], response.data["details"]["errors"]["month"]
                )

    def test_a_department_that_is_not_there_is_invalid(self):
        _, _, hod, _, _ = self.make_department()

        response = self.report(hod, f"?month={MONTH}&department_id=999999")

        self.assertEqual(
            ["The selected department id is invalid."], response.data["details"]["errors"]["department_id"]
        )

    def test_rows_are_ordered_by_first_name_and_paginated(self):
        school, department, hod, _, _ = self.make_department()
        hod.first_name = "Zara"
        hod.save()
        anil = factories.UserFactory(school=school, role=UserRole.TEACHER, first_name="Anil")
        factories.StaffProfileFactory(school=school, user=anil, department=department)

        first = self.report(hod, f"?month={MONTH}&per_page=2")
        second = self.report(hod, f"?month={MONTH}&per_page=2&page=2")

        self.assertEqual({"current_page": 1, "last_page": 2, "total": 3, "per_page": 2}, first.data["meta"])
        self.assertEqual(anil.name, first.data["data"][0]["teacher_name"])
        self.assertEqual(3, first.data["teacher_count"])
        self.assertEqual([hod.id], [row["user_id"] for row in second.data["data"]])

    def test_a_page_past_the_end_is_empty(self):
        _, _, hod, _, _ = self.make_department()

        response = self.report(hod, f"?month={MONTH}&page=5")

        self.assertEqual(200, response.status_code)
        self.assertEqual([], response.data["data"])
        self.assertEqual(5, response.data["meta"]["current_page"])


class CalendarTest(HodReportTestCase):
    def at(self, instant):
        return mock.patch("django.utils.timezone.now", return_value=instant)

    def test_working_days_are_weekdays_less_holidays(self):
        school, _, hod, _, _ = self.make_department()
        # May 2026: 21 weekdays, Fri 1st a holiday, a Sat-Sun break changes nothing.
        self.holiday(school, dt.date(2026, 5, 1))
        self.holiday(school, dt.date(2026, 5, 9), dt.date(2026, 5, 10))

        self.assertEqual(20, self.report(hod, "?month=2026-05").data["working_days"])

    def test_another_schools_holidays_do_not_count(self):
        _, _, hod, _, _ = self.make_department()
        self.holiday(factories.SchoolFactory(), dt.date(2026, 5, 1))

        self.assertEqual(21, self.report(hod, "?month=2026-05").data["working_days"])

    def test_a_shorter_month_asked_for_late_in_a_month_is_still_that_month(self):
        # February 2026 has 20 weekdays; March up to the 30th has 21. Laravel
        # used to answer 21 under February's label.
        _, _, hod, _, _ = self.make_department()

        with self.at(dt.datetime(2026, 3, 30, 4, 30, tzinfo=dt.timezone.utc)):
            response = self.report(hod, "?month=2026-02")

        self.assertEqual(("2026-02", 20), (response.data["month"], response.data["working_days"]))

    def test_the_current_month_counts_only_up_to_today_at_the_school(self):
        # 20:00 UTC on Tue 15 Sep is already Wed 16 Sep in Kolkata, so the
        # school has reached 12 working days, not 11.
        school, _, hod, _, _ = self.make_department(factories.SchoolFactory(timezone="Asia/Kolkata"))

        with self.at(dt.datetime(2026, 9, 15, 20, 0, tzinfo=dt.timezone.utc)):
            response = self.report(hod, "?month=2026-09")

        self.assertEqual(12, response.data["working_days"])

    def test_the_month_defaults_to_the_schools_current_month(self):
        _, _, hod, _, _ = self.make_department(factories.SchoolFactory(timezone="Asia/Kolkata"))

        # 20:00 UTC on 30 September is already 1 October in Kolkata.
        with self.at(dt.datetime(2026, 9, 30, 20, 0, tzinfo=dt.timezone.utc)):
            response = self.report(hod, "")

        self.assertEqual("2026-10", response.data["month"])

    def test_a_future_month_has_no_working_days_yet(self):
        _, _, hod, _, _ = self.make_department()

        with self.at(dt.datetime(2026, 9, 17, 10, 0, tzinfo=dt.timezone.utc)):
            response = self.report(hod, "?month=2026-11")

        self.assertEqual(0, response.data["working_days"])

    def test_late_marks_are_zero_when_the_school_has_no_periods(self):
        _, _, hod, teacher, profile = self.make_department()
        self.attend(profile, dt.date(2026, 8, 3), "present", dt.time(11, 30))

        response = self.report(hod)

        self.assertEqual((0, 0), (response.data["late_marks"], self.row(response, teacher)["late_marks"]))


class PhpArithmeticTest(TestCase):
    def test_round_takes_halves_away_from_zero(self):
        self.assertEqual(6.3, php_round_1(6.25))     # Python's round() says 6.2
        self.assertEqual(0.2, php_round_1(0.15))     # 0.1499999... in binary, pre-rounded first
        self.assertEqual(8.3, php_round_1(1.5 / 18 * 100))
        self.assertEqual(4.2, php_round_1(1.5 / 36 * 100))

    def test_whole_floats_become_ints_and_nothing_else_changes(self):
        self.assertEqual((50, int), (php_number(50.0), type(php_number(50.0))))
        self.assertEqual((0, int), (php_number(0.0), type(php_number(0.0))))
        self.assertEqual(66.7, php_number(66.7))
        self.assertEqual((3, int), (php_number(3), type(php_number(3))))
