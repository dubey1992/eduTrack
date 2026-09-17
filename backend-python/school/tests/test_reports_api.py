"""Phase 18's four reports, over HTTP.

Ported from ReportsTest and GroupReportsTest. The figure that matters in all
of them is the denominator: every rate is out of the days the school actually
ran, from the same holiday calendar that decides whether a register may be
taken at all. And across a group, the combined rate is recomputed from raw
counts, never averaged, because each branch has its own calendar.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Attendance, Holiday, StaffAttendance, SyllabusTopicProgress, TransportTrip, TransportTripRider
from school.reports.staff_attendance import php_compare

# Monday 14 September 2026, midday UTC. Monday 7 to Friday 11 is five working
# days in the past.
NOW = dt.datetime(2026, 9, 14, 12, 0, tzinfo=dt.timezone.utc)
FROM, TO = "2026-09-07", "2026-09-11"
REPORTS = ("student-attendance", "staff-attendance", "teaching-coverage", "transport-usage")


def client_for(user) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

    return client


def holiday(school, day: str, name: str = "Founders Day") -> Holiday:
    return Holiday.objects.create(
        school=school, name=name, type="school_event", start_date=day, end_date=day, created_at=NOW, updated_at=NOW
    )


class ReportTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.school = factories.SchoolFactory(name="Sunrise Public School", timezone="UTC")
        self.year = factories.AcademicYearFactory(school=self.school)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER, first_name="Rahul", last_name="Verma")
        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Grade 8"),
            class_teacher=self.teacher,
            name="A",
        )
        self.student = factories.StudentFactory(
            class_section=self.section, first_name="Arjun", last_name="Kumar", admission_number="ADM-0042"
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def get(self, user, report: str, **params):
        query = {"from": FROM, "to": TO, **params}
        query = {key: value for key, value in query.items() if value is not None}

        return client_for(user).get(f"/api/v1/reports/{report}", query)

    def mark(self, day: str, status: str, student=None):
        student = student or self.student
        Attendance.objects.create(
            school_id=student.school_id, academic_year_id=student.class_section.school_class.academic_year_id,
            class_section_id=student.class_section_id, student=student, attendance_date=day, status=status,
            marked_by=self.teacher, created_at=NOW, updated_at=NOW,
        )

    def mark_staff(self, profile, day: str, status: str):
        StaffAttendance.objects.create(
            school_id=profile.school_id, staff_profile=profile, attendance_date=day, status=status,
            marked_by=self.admin, created_at=NOW, updated_at=NOW,
        )


class StudentAttendance(ReportTestCase):
    def test_the_rate_is_out_of_the_days_the_school_ran(self):
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark(day, "present")
        self.mark("2026-09-10", "absent")

        response = self.get(self.admin, "student-attendance")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual({"from": FROM, "to": TO, "working_days": 5}, response.data["range"])
        self.assertEqual(
            {
                "student_id": self.student.id, "admission_number": "ADM-0042", "name": "Arjun Kumar",
                "class_section": "Grade 8 A", "working_days": 5, "present": 3, "absent": 1, "leave": 0,
                # Said plainly rather than folded into "absent".
                "not_marked": 1, "attendance_rate": 60,
            },
            response.data["rows"][0],
        )
        # A whole rate goes out as PHP writes it: 60, not 60.0.
        self.assertIs(int, type(response.data["rows"][0]["attendance_rate"]))

    def test_a_holiday_inside_the_range_shrinks_the_denominator(self):
        holiday(self.school, "2026-09-09")
        for day in ("2026-09-07", "2026-09-08", "2026-09-10", "2026-09-11"):
            self.mark(day, "present")

        response = self.get(self.admin, "student-attendance")

        self.assertEqual((4, 100), (response.data["range"]["working_days"], response.data["rows"][0]["attendance_rate"]))

    def test_a_mark_on_a_day_that_later_became_a_holiday_stops_counting(self):
        self.mark("2026-09-09", "present")
        holiday(self.school, "2026-09-09", "Declared later")

        response = self.get(self.admin, "student-attendance")

        self.assertEqual((4, 0), (response.data["range"]["working_days"], response.data["rows"][0]["present"]))

    def test_a_range_of_only_weekend_has_no_rate_rather_than_zero(self):
        response = self.get(self.admin, "student-attendance", **{"from": "2026-09-12", "to": "2026-09-13"})

        self.assertEqual((0, None), (response.data["range"]["working_days"], response.data["rows"][0]["attendance_rate"]))
        self.assertIsNone(response.data["totals"]["attendance_rate"])

    def test_rates_round_halves_away_from_zero_to_one_decimal(self):
        # Two of three days is 66.666... -> 66.7; one of three 33.3.
        self.mark("2026-09-07", "present")
        self.mark("2026-09-08", "present")

        response = self.get(self.admin, "student-attendance", **{"from": "2026-09-07", "to": "2026-09-09"})

        self.assertEqual(66.7, response.data["rows"][0]["attendance_rate"])

    def test_a_range_ending_today_includes_today_at_a_school_east_of_utc(self):
        # 20:00 UTC on Monday 14th is Tuesday 15th in Kolkata: seven working
        # days from Monday 7th.
        self.school.timezone = "Asia/Kolkata"
        self.school.save()

        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 14, 20, 0, tzinfo=dt.timezone.utc)):
            response = self.get(self.admin, "student-attendance", to="2026-09-15")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("2026-09-15", 7), (response.data["range"]["to"], response.data["range"]["working_days"]))

    def test_no_range_means_this_month_so_far_at_the_school(self):
        response = self.get(self.admin, "student-attendance", **{"from": None, "to": None})

        # 1 to 14 September: ten weekdays.
        self.assertEqual({"from": "2026-09-01", "to": "2026-09-14", "working_days": 10}, response.data["range"])

    def test_the_report_can_be_narrowed_to_one_class_section(self):
        other = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Grade 9"), name="B"
        )
        factories.StudentFactory(class_section=other)

        response = self.get(self.admin, "student-attendance", class_section_id=self.section.id)

        self.assertEqual(["ADM-0042"], [row["admission_number"] for row in response.data["rows"]])

    def test_an_inactive_student_is_not_on_the_report(self):
        factories.StudentFactory(class_section=self.section, status="inactive")

        self.assertEqual(1, self.get(self.admin, "student-attendance").data["totals"]["students"])

    def test_students_who_share_a_name_are_listed_in_a_fixed_order(self):
        # Written with falling ids, so an order left to the database would be
        # the reverse of the order the ids give.
        ids = [
            factories.StudentFactory(
                id=9000 + n, class_section=self.section, first_name="Zoya", last_name="Khan", admission_number=f"TIE-{n}"
            ).id
            for n in (3, 2, 1)
        ]

        rows = self.get(self.admin, "student-attendance").data["rows"]

        self.assertEqual(sorted(ids), [row["student_id"] for row in rows if row["name"] == "Zoya Khan"])


class StaffAttendance_(ReportTestCase):
    def test_a_half_day_counts_as_half_a_day_present(self):
        profile = factories.StaffProfileFactory(user=self.teacher)
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark_staff(profile, day, "present")
        self.mark_staff(profile, "2026-09-10", "half_day")

        row = self.get(self.admin, "staff-attendance").data["rows"][0]

        # Three and a half days, rounded half up to four, out of five.
        self.assertEqual((3, 1, 1, 80), (row["present"], row["half_day"], row["not_marked"], row["attendance_rate"]))

    def test_two_and_a_half_days_round_up_as_php_rounds_them(self):
        # Python's round() takes 2.5 to 2, the even neighbour; PHP's takes it
        # to 3. Three of five is 60%, two would be 40%.
        profile = factories.StaffProfileFactory(user=self.teacher)
        self.mark_staff(profile, "2026-09-07", "present")
        self.mark_staff(profile, "2026-09-08", "present")
        self.mark_staff(profile, "2026-09-09", "half_day")

        self.assertEqual(60, self.get(self.admin, "staff-attendance").data["rows"][0]["attendance_rate"])

    def test_leave_approved_in_the_range_is_counted_by_type(self):
        profile = factories.StaffProfileFactory(user=self.teacher)
        factories.StaffLeaveFactory(staff_profile=profile, status="approved", leave_type="sick",
                                    start_date=dt.date(2026, 9, 10), end_date=dt.date(2026, 9, 14))
        factories.StaffLeaveFactory(staff_profile=profile, status="approved", leave_type="casual",
                                    start_date=dt.date(2026, 9, 1), end_date=dt.date(2026, 9, 7))
        factories.StaffLeaveFactory(staff_profile=profile, status="pending", leave_type="casual",
                                    start_date=dt.date(2026, 9, 8), end_date=dt.date(2026, 9, 8))
        factories.StaffLeaveFactory(staff_profile=profile, status="approved", leave_type="earned",
                                    start_date=dt.date(2026, 9, 12), end_date=dt.date(2026, 9, 20))
        other = factories.StaffProfileFactory(user__school=self.school)

        rows = {row["staff_profile_id"]: row for row in self.get(self.admin, "staff-attendance").data["rows"]}

        self.assertEqual({"casual": 1, "sick": 1}, rows[profile.id]["leave_by_type"])
        # None at all is an empty list, as PHP's empty array is written.
        self.assertEqual([], rows[other.id]["leave_by_type"])

    def test_a_department_filter_narrows_the_staff(self):
        science = factories.DepartmentFactory(school=self.school)
        factories.StaffProfileFactory(user=self.teacher, department=science, employee_id="EMP-SCI")
        factories.StaffProfileFactory(user__school=self.school, employee_id="EMP-NONE")

        rows = self.get(self.admin, "staff-attendance", department_id=science.id).data["rows"]

        self.assertEqual(["EMP-SCI"], [row["employee_id"] for row in rows])

    def test_staff_are_sorted_by_name_and_equal_names_by_id(self):
        def employee(pk, first):
            user = factories.UserFactory(school=self.school, role=UserRole.TEACHER, first_name=first, last_name="Nair")
            return factories.StaffProfileFactory(id=pk, user=user, employee_id=f"E-{pk}")

        employee(9003, "Priya")
        employee(9002, "Priya")
        employee(9001, "Anil")

        rows = self.get(self.admin, "staff-attendance").data["rows"]

        self.assertEqual([9001, 9002, 9003], [row["staff_profile_id"] for row in rows])

    def test_names_compare_the_way_php_compares_them(self):
        # Byte order, so capitals first; numeric strings as numbers.
        self.assertEqual(-1, php_compare("Zoya", "anil"))
        self.assertEqual(1, php_compare("10", "9"))
        self.assertEqual(-1, php_compare("10", "9a"))
        self.assertEqual(0, php_compare("", ""))


class TeachingCoverage(ReportTestCase):
    def test_scheduled_periods_follow_the_working_days_and_reports_count_against_them(self):
        maths = factories.SubjectFactory(department=factories.DepartmentFactory(school=self.school), name="Mathematics")
        monday = factories.TimetableEntryFactory(
            class_section=self.section, period=factories.PeriodFactory(school=self.school), subject=maths,
            teacher=self.teacher, day_of_week="monday",
        )
        factories.TimetableEntryFactory(
            class_section=self.section, period=factories.PeriodFactory(school=self.school), subject=maths,
            teacher=self.teacher, day_of_week="wednesday",
        )
        factories.DailyTeachingReportFactory(timetable_entry=monday, report_date=dt.date(2026, 9, 7))
        # Wednesday the 9th becomes a holiday: its period is not scheduled.
        holiday(self.school, "2026-09-09")
        for index in range(3):
            topic = factories.SyllabusTopicFactory(subject=maths)
            if index == 0:
                SyllabusTopicProgress.objects.create(
                    school=self.school, syllabus_topic=topic, class_section=self.section, completed_by=self.teacher,
                    completed_at=NOW, created_at=NOW, updated_at=NOW,
                )

        response = self.get(self.admin, "teaching-coverage")
        row = response.data["rows"][0]

        self.assertEqual(
            {
                "subject_id": maths.id, "subject": "Mathematics", "department": maths.department.name,
                "periods_scheduled": 1, "periods_reported": 1, "periods_missing": 0, "coverage_rate": 100,
                "topics_total": 3, "topics_completed": 1, "syllabus_completion": 33.3,
            },
            row,
        )
        self.assertEqual(
            {"subjects": 1, "periods_scheduled": 1, "periods_reported": 1, "periods_missing": 0, "coverage_rate": 100},
            response.data["totals"],
        )

    def test_a_halfway_percentage_rounds_up_as_php_rounds_it(self):
        # One topic of sixteen is 6.25%: PHP says 6.3, Python's round() 6.2.
        subject = factories.SubjectFactory(department=factories.DepartmentFactory(school=self.school))
        topics = [factories.SyllabusTopicFactory(subject=subject) for _ in range(16)]
        SyllabusTopicProgress.objects.create(
            school=self.school, syllabus_topic=topics[0], class_section=self.section, completed_by=self.teacher,
            completed_at=NOW, created_at=NOW, updated_at=NOW,
        )

        self.assertEqual(6.3, self.get(self.admin, "teaching-coverage").data["rows"][0]["syllabus_completion"])

    def test_subjects_that_share_a_name_are_listed_in_a_fixed_order(self):
        department = factories.DepartmentFactory(school=self.school)
        ids = [
            factories.SubjectFactory(id=9000 + n, department=department, name="Science", code=f"SCI-{4 - n}").id
            for n in (3, 2, 1)
        ]

        rows = self.get(self.admin, "teaching-coverage").data["rows"]

        self.assertEqual(sorted(ids), [row["subject_id"] for row in rows])

    def test_nothing_scheduled_has_no_rate(self):
        factories.SubjectFactory(department=factories.DepartmentFactory(school=self.school))

        row = self.get(self.admin, "teaching-coverage").data["rows"][0]

        self.assertEqual((0, None, None), (row["periods_scheduled"], row["coverage_rate"], row["syllabus_completion"]))


class TransportUsage(ReportTestCase):
    def test_trips_and_riders_are_counted_per_route(self):
        vehicle = factories.VehicleFactory(school=self.school, name="Bus 1")
        driver = factories.DriverFactory(school=self.school, name="Ramesh")
        route = factories.TransportRouteFactory(school=self.school, name="Route A", vehicle=vehicle, driver=driver)

        def trip(day, status, direction="pickup"):
            return TransportTrip.objects.create(
                school=self.school, route=route, vehicle=vehicle, driver=driver, trip_date=day, direction=direction,
                status=status,
                started_by=self.admin, started_at=NOW, created_at=NOW, updated_at=NOW,
            )

        completed = trip("2026-09-07", "completed")
        trip("2026-09-07", "completed", "drop")
        trip("2026-09-08", "cancelled")
        for index, status in enumerate(("boarded", "dropped", "dropped", "absent")):
            TransportTripRider.objects.create(
                trip=completed, student=factories.StudentFactory(class_section=self.section, admission_number=f"BUS-{index}"), stop_name="Gate", stop_sequence_number=1, status=status,
                created_at=NOW, updated_at=NOW,
            )

        row = self.get(self.admin, "transport-usage").data["rows"][0]

        self.assertEqual(
            {
                "route_id": route.id, "route": "Route A", "vehicle": "Bus 1", "driver": "Ramesh", "working_days": 5,
                "days_run": 1, "days_not_run": 4, "trips_completed": 2, "trips_cancelled": 1, "trips_in_progress": 0,
                "riders_boarded": 1, "riders_dropped": 2, "riders_absent": 1,
            },
            row,
        )


class WhoMayLook(ReportTestCase):
    def test_each_report_has_its_own_audience(self):
        allowed = {
            UserRole.SCHOOL_ADMIN: set(REPORTS),
            UserRole.HOD: {"staff-attendance", "teaching-coverage"},
            UserRole.TRANSPORT_MANAGER: {"transport-usage"},
            UserRole.TEACHER: set(),
            UserRole.STAFF: set(),
        }

        for role, reports in allowed.items():
            user = factories.UserFactory(school=self.school, role=role)
            for report in REPORTS:
                with self.subTest(role=role, report=report):
                    expected = 200 if report in reports else 403
                    self.assertEqual(expected, self.get(user, report).status_code)

    def test_a_malformed_request_is_422_even_for_someone_who_may_not_look(self):
        # The form runs before the role check, as in Laravel.
        self.assertEqual(422, self.get(self.teacher, "student-attendance", **{"from": "nope"}).status_code)

    def test_a_head_of_department_only_sees_their_own_departments(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        mine = factories.DepartmentFactory(school=self.school, hod_user=hod)
        theirs = factories.DepartmentFactory(school=self.school)
        factories.StaffProfileFactory(user__school=self.school, department=mine, employee_id="EMP-MINE")
        factories.StaffProfileFactory(user__school=self.school, department=theirs, employee_id="EMP-THEIRS")
        factories.SubjectFactory(department=mine, name="Physics")
        factories.SubjectFactory(department=theirs, name="History")

        staff = self.get(hod, "staff-attendance", department_id=theirs.id).data["rows"]
        self.assertEqual([], staff, "asking for another department narrows to nothing")

        staff = self.get(hod, "staff-attendance").data["rows"]
        subjects = self.get(hod, "teaching-coverage").data["rows"]
        self.assertEqual(["EMP-MINE"], [row["employee_id"] for row in staff])
        self.assertEqual(["Physics"], [row["subject"] for row in subjects])

    def test_a_head_of_department_who_heads_nothing_sees_nobody(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        department = factories.DepartmentFactory(school=self.school)
        factories.StaffProfileFactory(user__school=self.school, department=department)
        factories.SubjectFactory(department=department)

        # No departments is an empty scope, not the absence of one.
        for report in ("staff-attendance", "teaching-coverage"):
            self.assertEqual([], self.get(hod, report).data["rows"])

    def test_a_school_admin_cannot_report_on_another_school(self):
        other = factories.SchoolFactory(timezone="UTC")
        factories.StudentFactory(
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=factories.AcademicYearFactory(school=other), school=other)
            )
        )

        # Ignored for a school user - their report is always their own school's.
        rows = self.get(self.admin, "student-attendance", school_id=other.id).data["rows"]

        self.assertEqual([self.student.id], [row["student_id"] for row in rows])

    def test_a_super_admin_names_a_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        refused = self.get(root, "student-attendance")
        missing = self.get(root, "student-attendance", school_id=999999)
        named = self.get(root, "student-attendance", school_id=self.school.id)

        self.assertEqual({"school_id": ["Pick a school to report on."]}, refused.data["details"]["errors"])
        self.assertEqual({"school_id": ["The selected school id is invalid."]}, missing.data["details"]["errors"])
        self.assertEqual([self.student.id], [row["student_id"] for row in named.data["rows"]])

    def test_an_unauthenticated_caller_gets_nothing(self):
        self.assertEqual(401, APIClient().get("/api/v1/reports/student-attendance").status_code)


class TheForm(ReportTestCase):
    def errors(self, user=None, **params):
        response = self.get(user or self.admin, "student-attendance", **params)
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]

    def test_a_report_cannot_start_or_run_past_today(self):
        self.assertEqual(
            {
                "from": ["A report cannot start on a date that has not happened yet."],
                "to": ["A report cannot run past today."],
            },
            self.errors(**{"from": "2026-12-01", "to": "2026-12-31"}),
        )

    def test_the_end_cannot_come_before_the_start(self):
        self.assertEqual(
            {"to": ["The end of the range must not be before its start."]},
            self.errors(**{"from": "2026-09-10", "to": "2026-09-02"}),
        )

    def test_every_problem_is_reported_at_once(self):
        self.assertEqual(
            {
                "school_id": ["The school id field must be an integer."],
                "from": ["The from field must be a valid date."],
                "to": ["The to field must be a valid date."],
                "class_section_id": ["The class section id field must be an integer."],
                "department_id": ["The selected department id is invalid."],
                "format": ["The selected format is invalid."],
            },
            self.errors(school_id="abc", **{"from": "abc", "to": "2026-13-45"}, class_section_id="22.0",
                        department_id=999999, format="xml"),
        )

    def test_a_bad_start_does_not_also_make_the_end_backwards(self):
        # after_or_equal:from compares only with a `from` that is a date.
        self.assertEqual({"from": ["The from field must be a valid date."]}, self.errors(**{"from": "abc"}))

    def test_blank_values_are_nothing(self):
        response = self.get(self.admin, "student-attendance", **{"from": "", "to": " "}, class_section_id="", format="")

        self.assertEqual((200, "2026-09-01"), (response.status_code, response.data["range"]["from"]))


class AsCsv(ReportTestCase):
    def test_the_same_figures_come_back_as_a_csv_byte_for_byte(self):
        self.mark("2026-09-07", "present")
        self.mark("2026-09-08", "present")
        self.mark("2026-09-09", "absent")

        response = self.get(self.admin, "student-attendance", format="csv")

        self.assertEqual(200, response.status_code)
        self.assertEqual("text/csv; charset=UTF-8", response["Content-Type"])
        self.assertEqual(
            'attachment; filename="student-attendance-2026-09-07-to-2026-09-11.csv"', response["Content-Disposition"]
        )
        self.assertEqual(
            "﻿"
            '"Admission No.",Student,Class,"Working days",Present,Absent,Leave,"Not marked","Attendance %"\n'
            'ADM-0042,"Arjun Kumar","Grade 8 A",5,2,1,0,2,40\n',
            response.content.decode("utf-8"),
        )

    def test_a_missing_rate_and_a_fraction_read_as_a_spreadsheet_expects(self):
        self.mark("2026-09-07", "present")

        weekend = self.get(self.admin, "student-attendance", **{"from": "2026-09-12", "to": "2026-09-13"}, format="csv")
        third = self.get(self.admin, "student-attendance", **{"from": "2026-09-07", "to": "2026-09-09"}, format="csv")

        self.assertTrue(weekend.content.decode("utf-8").endswith(',0,0,0,0,0,-\n'))
        self.assertTrue(third.content.decode("utf-8").endswith(',3,1,0,0,2,33.3\n'))

    def test_every_report_answers_as_csv(self):
        for report in REPORTS:
            with self.subTest(report=report):
                response = self.get(self.admin, report, format="csv")
                self.assertEqual(200, response.status_code)
                self.assertTrue(response.content.startswith(b"\xef\xbb\xbf"))


class GroupReports(TestCase):
    """One report across a whole group."""

    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.group = factories.SchoolFactory(name="A Group", timezone="UTC")
        self.north = factories.SchoolFactory(name="B North", timezone="UTC", parent_school=self.group)
        self.south = factories.SchoolFactory(name="C South", timezone="UTC", parent_school=self.group)
        self.group_admin = factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)

    def students_at(self, school, count: int):
        year = factories.AcademicYearFactory(school=school)
        section = factories.ClassSectionFactory(school_class=factories.SchoolClassFactory(academic_year=year, school=school))

        return [factories.StudentFactory(class_section=section, admission_number=f"{school.id}-{n}") for n in range(count)]

    def mark(self, student, day: str, status: str):
        Attendance.objects.create(
            school_id=student.school_id, academic_year_id=student.class_section.school_class.academic_year_id,
            class_section_id=student.class_section_id, student=student, attendance_date=day, status=status,
            created_at=NOW, updated_at=NOW,
        )

    def get(self, user=None, report="student-attendance", **params):
        query = {"from": "2026-09-07", "to": "2026-09-09", **params}

        return client_for(user or self.group_admin).get(f"/api/v1/reports/{report}", query)

    def test_naming_no_branch_reports_on_every_branch_with_its_rows_labelled(self):
        self.students_at(self.north, 2)
        self.students_at(self.south, 1)

        data = self.get().data

        self.assertTrue(data["group"])
        self.assertEqual(["A Group", "B North", "C South"], [branch["school_name"] for branch in data["branches"]])
        self.assertEqual(3, data["totals"]["branches"])
        self.assertEqual(["B North", "B North", "C South"], [row["school_name"] for row in data["rows"]])
        self.assertEqual(self.north.id, data["rows"][0]["school_id"])

    def test_naming_a_branch_reports_on_that_branch_alone(self):
        self.students_at(self.north, 2)
        self.students_at(self.south, 5)

        data = self.get(school_id=self.north.id).data

        self.assertNotIn("group", data)
        self.assertNotIn("branches", data)
        self.assertEqual(2, len(data["rows"]))

    def test_a_group_report_never_reaches_outside_the_group(self):
        outsider = factories.SchoolFactory(name="Z Elsewhere", timezone="UTC")
        self.students_at(outsider, 4)
        self.students_at(self.north, 1)

        data = self.get(school_id=outsider.id).data

        self.assertNotIn("Z Elsewhere", [branch["school_name"] for branch in data["branches"]])
        self.assertEqual(1, data["totals"]["students"])

    def test_the_combined_rate_is_weighted_by_size_not_averaged(self):
        # North: 1 student present all 3 days (100%). South: 3 students present
        # 1 day each (33.3%). The average would be 66.7%; the truth is 6 of 12.
        [north_student] = self.students_at(self.north, 1)
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark(north_student, day, "present")
        for student in self.students_at(self.south, 3):
            self.mark(student, "2026-09-07", "present")

        totals = self.get().data["totals"]

        self.assertEqual(
            {"branches": 3, "students": 4, "present": 6, "absent": 0, "leave": 0, "not_marked": 6, "attendance_rate": 50},
            totals,
        )

    def test_each_branch_is_measured_against_its_own_working_days(self):
        # North: 1 student x 3 days, present all 3. South shut on the 8th: 3
        # students x 2 days, present 3 times. 6 of 9 possible, not 6 of 12 as
        # it would be if every branch had the busiest branch's days.
        holiday(self.south, "2026-09-08")
        [north_student] = self.students_at(self.north, 1)
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark(north_student, day, "present")
        for student in self.students_at(self.south, 3):
            self.mark(student, "2026-09-07", "present")

        self.assertEqual(66.7, self.get().data["totals"]["attendance_rate"])

    def test_a_branch_keeps_its_own_working_days_and_the_group_range_has_none(self):
        holiday(self.south, "2026-09-08")

        data = self.get().data
        branches = {branch["school_name"]: branch for branch in data["branches"]}

        self.assertEqual((3, 2), (branches["B North"]["range"]["working_days"], branches["C South"]["range"]["working_days"]))
        self.assertEqual({"from": "2026-09-07", "to": "2026-09-09"}, data["range"])

    def test_the_group_range_is_the_widest_the_branches_cover(self):
        # 20:00 UTC on the 14th is already the 15th in Kiritimati.
        self.south.timezone = "Pacific/Kiritimati"
        self.south.save()

        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 14, 20, 0, tzinfo=dt.timezone.utc)):
            data = client_for(self.group_admin).get("/api/v1/reports/staff-attendance").data

        self.assertEqual({"from": "2026-09-01", "to": "2026-09-15"}, data["range"])

    def test_a_group_with_nothing_in_it_still_answers(self):
        for report in REPORTS:
            with self.subTest(report=report):
                data = self.get(report=report).data
                self.assertTrue(data["group"])
                self.assertEqual(3, data["totals"]["branches"])

        self.assertIsNone(self.get().data["totals"]["attendance_rate"])
        self.assertIsNone(self.get(report="teaching-coverage").data["totals"]["coverage_rate"])

    def test_branches_that_share_a_name_are_listed_in_a_fixed_order(self):
        twin = factories.SchoolFactory(id=9000, name="B North", timezone="UTC", parent_school=self.group)

        names = [(branch["school_name"], branch["school_id"]) for branch in self.get().data["branches"]]

        self.assertEqual([("A Group", self.group.id), ("B North", self.north.id), ("B North", twin.id), ("C South", self.south.id)], names)

    def test_a_group_csv_names_the_branch_on_every_line(self):
        self.students_at(self.north, 1)
        self.students_at(self.south, 1)

        response = self.get(format="csv")
        lines = response.content.decode("utf-8-sig").splitlines()

        self.assertEqual(
            'attachment; filename="student-attendance-group-2026-09-07-to-2026-09-09.csv"', response["Content-Disposition"]
        )
        self.assertTrue(lines[0].startswith('School,"Admission No."'))
        self.assertTrue(lines[1].startswith('"B North",'))
        self.assertTrue(lines[2].startswith('"C South",'))

    def test_a_school_admin_in_a_group_gets_the_group_and_can_name_a_branch(self):
        admin = factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN)
        self.students_at(self.north, 1)
        self.students_at(self.south, 1)

        self.assertEqual(2, len(self.get(admin).data["rows"]))
        self.assertNotIn("group", self.get(admin, school_id=self.south.id).data)

    def test_a_lone_school_is_not_a_group(self):
        lone = factories.SchoolFactory(timezone="UTC")
        self.students_at(lone, 1)

        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN):
            data = self.get(factories.UserFactory(school=lone, role=role)).data
            self.assertNotIn("group", data)
            self.assertEqual(1, len(data["rows"]))
