"""Analytics, A1 (docs/analytics.md): a measure week by week or month by
month, over HTTP.

The rules that matter: each point is the figure the report itself gives for
that period, a period with no working day is a gap rather than a zero, the
snapshot measures read what was recorded and never guess before the first
record, money stays apart by currency, and who may chart a figure is who may
read its report.
"""

import datetime as dt
from io import StringIO
from unittest import mock

from django.core.management import CommandError, call_command
from django.test import SimpleTestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import analytics, factories
from school.analytics import MONTH, WEEK, record_snapshot
from school.enums import UserRole
from school.models import AnalyticsSchoolDay, AnalyticsSchoolFeeDay, RolePermission

from .test_fees_reports_api import FeeReportsTestCase
from .test_reports_api import ReportTestCase, client_for, holiday

SERIES = "/api/v1/analytics/series"
MEASURES = "/api/v1/analytics/measures"


class Periods(SimpleTestCase):
    def test_weeks_run_monday_to_sunday_and_are_cut_to_the_range(self):
        # Wednesday 2 to Thursday 17 September 2026.
        spans = analytics.periods(dt.date(2026, 9, 2), dt.date(2026, 9, 17), WEEK)

        self.assertEqual(
            [
                (dt.date(2026, 9, 2), dt.date(2026, 9, 6)),
                (dt.date(2026, 9, 7), dt.date(2026, 9, 13)),
                (dt.date(2026, 9, 14), dt.date(2026, 9, 17)),
            ],
            spans,
        )

    def test_months_cross_the_year_end_and_keep_february_short(self):
        spans = analytics.periods(dt.date(2026, 12, 15), dt.date(2027, 3, 2), MONTH)

        self.assertEqual(
            [
                (dt.date(2026, 12, 15), dt.date(2026, 12, 31)),
                (dt.date(2027, 1, 1), dt.date(2027, 1, 31)),
                (dt.date(2027, 2, 1), dt.date(2027, 2, 28)),
                (dt.date(2027, 3, 1), dt.date(2027, 3, 2)),
            ],
            spans,
        )

    def test_the_default_range_is_twelve_periods_ending_with_today_s(self):
        today = dt.date(2026, 9, 14)

        self.assertEqual(dt.date(2025, 10, 1), analytics.default_from(today, MONTH))
        self.assertEqual(12, analytics.period_count(analytics.default_from(today, WEEK), today, WEEK))


class AnalyticsTestCase(ReportTestCase):
    """Monday 14 September 2026, as in the report tests: 7-11 September is a
    full working week in the past."""

    def chart(self, user, measure, **params):
        query = {"measure": measure, **params}

        return client_for(user).get(SERIES, query)

    def points(self, user, measure, **params) -> list[dict]:
        response = self.chart(user, measure, **params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data["points"]


class StudentAttendance(AnalyticsTestCase):
    def test_each_week_is_the_report_s_rate_for_that_week(self):
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark(day, "present")
        self.mark("2026-09-10", "absent")

        response = self.chart(self.admin, "student_attendance_rate", interval="week", **{"from": "2026-08-31", "to": "2026-09-11"})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            {"measure": "student_attendance_rate", "label": "Student attendance", "unit": "percent", "interval": "week",
             "from": "2026-08-31", "to": "2026-09-11"},
            {key: value for key, value in response.data.items() if key != "points"},
        )
        self.assertEqual(
            [
                {"from": "2026-08-31", "to": "2026-09-06", "working_days": 5, "value": 0},
                {"from": "2026-09-07", "to": "2026-09-11", "working_days": 5, "value": 60},
            ],
            response.data["points"],
        )

        # The same figure the report prints for the same week.
        report = self.get(self.admin, "student-attendance", **{"from": "2026-09-07", "to": "2026-09-11"})
        self.assertEqual(report.data["totals"]["attendance_rate"], response.data["points"][1]["value"])

    def test_a_week_of_holidays_is_a_gap_not_a_zero(self):
        for day in ("2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"):
            holiday(self.school, day, f"Break {day}")

        points = self.points(self.admin, "student_attendance_rate", interval="week", **{"from": "2026-08-31", "to": "2026-09-06"})

        self.assertEqual([{"from": "2026-08-31", "to": "2026-09-06", "working_days": 0, "value": None}], points)

    def test_months_are_cut_to_the_range(self):
        self.mark("2026-09-07", "present")

        points = self.points(self.admin, "student_attendance_rate", **{"from": "2026-08-15", "to": "2026-09-14"})

        self.assertEqual(
            [("2026-08-15", "2026-08-31"), ("2026-09-01", "2026-09-14")], [(p["from"], p["to"]) for p in points]
        )
        # One present day out of the ten September has run so far.
        self.assertEqual(10, points[1]["value"])

    def test_one_class_alone(self):
        other = factories.ClassSectionFactory(school_class=self.section.school_class, name="B")
        absent = factories.StudentFactory(class_section=other)
        self.mark("2026-09-07", "present")
        self.mark("2026-09-07", "absent", student=absent)
        span = {"from": "2026-09-07", "to": "2026-09-07"}

        whole = self.points(self.admin, "student_attendance_rate", **span)[0]["value"]
        one = self.points(self.admin, "student_attendance_rate", class_section_id=self.section.id, **span)[0]["value"]

        self.assertEqual((50, 100), (whole, one))

    def test_with_no_range_the_last_twelve_months(self):
        points = self.points(self.admin, "student_attendance_rate")

        self.assertEqual(12, len(points))
        self.assertEqual(("2025-10-01", "2026-09-14"), (points[0]["from"], points[-1]["to"]))


class OtherMeasures(AnalyticsTestCase):
    def test_staff_attendance_counts_a_half_day_as_half(self):
        profile = factories.StaffProfileFactory(user=self.teacher)
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark_staff(profile, day, "present")
        self.mark_staff(profile, "2026-09-10", "half_day")

        points = self.points(self.admin, "staff_attendance_rate", **{"from": "2026-09-07", "to": "2026-09-11"})

        # Three and a half days of five. Unrounded across the school: a
        # day's rounding is one person's, not a staff room's.
        self.assertEqual(70, points[0]["value"])

    def test_a_school_with_no_timetable_has_no_coverage_rather_than_none_filed(self):
        points = self.points(self.admin, "teaching_coverage_rate", **{"from": "2026-09-07", "to": "2026-09-11"})

        self.assertIsNone(points[0]["value"])

    def test_measures_that_count_nothing_say_nought(self):
        points = self.points(self.admin, "syllabus_topics_completed", **{"from": "2026-09-07", "to": "2026-09-11"})

        self.assertEqual(0, points[0]["value"])


class Snapshots(AnalyticsTestCase):
    def test_before_the_first_snapshot_there_is_no_figure(self):
        points = self.points(self.admin, "active_students", **{"from": "2026-08-01", "to": "2026-09-14"})

        self.assertEqual([None, None], [point["value"] for point in points])

    def test_a_period_reads_its_last_snapshot(self):
        record_snapshot(self.school.id, dt.date(2026, 9, 1), timezone.now())
        factories.StudentFactory(class_section=self.section)
        record_snapshot(self.school.id, dt.date(2026, 9, 14), timezone.now())

        points = self.points(self.admin, "active_students", **{"from": "2026-08-01", "to": "2026-09-14"})

        self.assertEqual([None, 2], [point["value"] for point in points])

    def test_staff_on_roll_counts_only_those_who_can_still_sign_in(self):
        factories.StaffProfileFactory(user=self.teacher)
        factories.StaffProfileFactory(user__school=self.school, user__status="inactive")
        record_snapshot(self.school.id, dt.date(2026, 9, 14), timezone.now())

        points = self.points(self.admin, "active_staff", **{"from": "2026-09-01", "to": "2026-09-14"})

        self.assertEqual(1, points[0]["value"])

    def test_the_command_runs_twice_a_day_without_doubling(self):
        out = StringIO()
        call_command("record_analytics_snapshots", "--school", self.school.id, stdout=out)
        factories.StudentFactory(class_section=self.section)
        call_command("record_analytics_snapshots", "--school", self.school.id, stdout=out)

        days = AnalyticsSchoolDay.objects.filter(school=self.school)
        self.assertEqual([(dt.date(2026, 9, 14), 2)], [(day.snapshot_date, day.active_students) for day in days])
        self.assertIn(f"School {self.school.id}: recorded for 2026-09-14.", out.getvalue())

    def test_the_day_is_the_school_s_own(self):
        # 20:00 UTC on Monday 14th is already Tuesday 15th in Kolkata.
        self.school.timezone = "Asia/Kolkata"
        self.school.save()

        late = dt.datetime(2026, 9, 14, 20, 0, tzinfo=dt.timezone.utc)
        with mock.patch("django.utils.timezone.now", return_value=late):
            call_command("record_analytics_snapshots", "--school", self.school.id, stdout=StringIO())

        self.assertEqual(
            [dt.date(2026, 9, 15)], list(AnalyticsSchoolDay.objects.filter(school=self.school).values_list("snapshot_date", flat=True))
        )

    def test_an_unknown_school_is_refused(self):
        with self.assertRaises(CommandError):
            call_command("record_analytics_snapshots", "--school", 999999, stdout=StringIO())

    def test_owing_nothing_is_recorded_as_nought_in_the_school_s_currency(self):
        record_snapshot(self.school.id, dt.date(2026, 9, 14), timezone.now())

        lines = AnalyticsSchoolFeeDay.objects.filter(school=self.school)
        self.assertEqual(
            [(self.school.currency_code, "0.00", "0.00")],
            [(line.currency_code, f"{line.outstanding:.2f}", f"{line.overdue:.2f}") for line in lines],
        )


class TheForm(AnalyticsTestCase):
    def errors(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]

    def test_a_measure_is_required_and_must_be_one_we_chart(self):
        self.assertEqual({"measure": ["Pick what to chart."]}, self.errors(client_for(self.admin).get(SERIES)))
        self.assertEqual(
            {"measure": ["The selected measure is invalid."]}, self.errors(self.chart(self.admin, "happiness"))
        )

    def test_week_or_month_only(self):
        errors = self.errors(self.chart(self.admin, "student_attendance_rate", interval="day"))

        self.assertEqual({"interval": ["Chart by week or by month."]}, errors)

    def test_the_report_s_date_rules_still_apply(self):
        errors = self.errors(self.chart(self.admin, "student_attendance_rate", to="2026-09-20"))

        self.assertEqual({"to": ["A report cannot run past today."]}, errors)

    def test_an_end_before_the_start_is_refused(self):
        errors = self.errors(
            self.chart(self.admin, "student_attendance_rate", **{"from": "2026-09-10", "to": "2026-09-01"})
        )

        self.assertEqual({"to": ["The end of the range must not be before its start."]}, errors)

    def test_too_many_periods_is_refused(self):
        weeks = self.chart(self.admin, "student_attendance_rate", interval="week", **{"from": "2025-01-01"})
        months = self.chart(self.admin, "student_attendance_rate", **{"from": "2024-01-01"})

        self.assertEqual({"from": ["A chart by week covers at most 53 weeks. Pick a shorter range."]}, self.errors(weeks))
        self.assertEqual({"from": ["A chart by month covers at most 24 months. Pick a shorter range."]}, self.errors(months))

    def test_two_years_of_months_is_allowed(self):
        self.assertEqual(24, len(self.points(self.admin, "student_attendance_rate", **{"from": "2024-10-01"})))


class WhoMayChart(AnalyticsTestCase):
    def test_each_measure_has_its_report_s_audience(self):
        allowed = {
            UserRole.SCHOOL_ADMIN: {"student_attendance_rate", "staff_attendance_rate", "teaching_coverage_rate",
                                    "active_students"},
            UserRole.HOD: {"staff_attendance_rate", "teaching_coverage_rate"},
            UserRole.ACCOUNTANT: {"staff_attendance_rate"},
            UserRole.TEACHER: set(),
            UserRole.STAFF: set(),
            UserRole.TRANSPORT_MANAGER: set(),
        }
        measures = ("student_attendance_rate", "staff_attendance_rate", "teaching_coverage_rate", "active_students")

        for role, charts in allowed.items():
            user = factories.UserFactory(school=self.school, role=role)
            for measure in measures:
                with self.subTest(role=role, measure=measure):
                    expected = 200 if measure in charts else 403
                    self.assertEqual(expected, self.chart(user, measure).status_code)

    def test_the_picker_lists_only_what_its_reader_may_chart(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)

        admin = [m["key"] for m in client_for(self.admin).get(MEASURES).data["data"]]
        head = [m["key"] for m in client_for(hod).get(MEASURES).data["data"]]

        self.assertIn("student_attendance_rate", admin)
        # This school has no fees module, so nobody here is offered a fee chart.
        self.assertNotIn("fees_collected", admin)
        self.assertEqual(
            ["staff_attendance_rate", "teaching_coverage_rate", "syllabus_topics_completed", "test_average"], head
        )

    def test_a_head_of_department_charts_only_their_own_departments(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        mine = factories.DepartmentFactory(school=self.school, hod_user=hod)
        theirs = factories.DepartmentFactory(school=self.school)
        present = factories.StaffProfileFactory(user__school=self.school, department=mine)
        away = factories.StaffProfileFactory(user__school=self.school, department=theirs)
        self.mark_staff(present, "2026-09-07", "present")
        self.mark_staff(away, "2026-09-07", "absent")
        day = {"from": "2026-09-07", "to": "2026-09-07"}

        self.assertEqual(100, self.points(hod, "staff_attendance_rate", **day)[0]["value"])
        # Naming another department narrows to nobody, not to theirs.
        self.assertIsNone(self.points(hod, "staff_attendance_rate", department_id=theirs.id, **day)[0]["value"])
        self.assertEqual(50, self.points(self.admin, "staff_attendance_rate", **day)[0]["value"])

    def test_a_school_admin_naming_another_school_charts_their_own(self):
        other = factories.SchoolFactory(timezone="UTC")
        record_snapshot(other.id, dt.date(2026, 9, 14), timezone.now())

        points = self.points(self.admin, "active_students", school_id=other.id, **{"from": "2026-09-01"})

        self.assertEqual([None], [point["value"] for point in points], "never the other school's figure")

    def test_a_super_admin_names_a_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        record_snapshot(self.school.id, dt.date(2026, 9, 14), timezone.now())

        refused = self.chart(root, "active_students")
        named = self.chart(root, "active_students", school_id=self.school.id, **{"from": "2026-09-01"})

        self.assertEqual({"school_id": ["Pick a school to report on."]}, refused.data["details"]["errors"])
        self.assertEqual([1], [point["value"] for point in named.data["points"]])

    def test_a_role_the_matrix_denies_reports_cannot_chart(self):
        RolePermission.objects.filter(role=UserRole.SCHOOL_ADMIN, module="reports").delete()
        RolePermission.objects.create(role=UserRole.SCHOOL_ADMIN, module="reports", level="none",
                                      created_at=timezone.now(), updated_at=timezone.now())

        self.assertEqual(403, self.chart(self.admin, "student_attendance_rate").status_code)

    def test_fee_charts_are_refused_where_fees_are_off(self):
        response = self.chart(self.admin, "fees_collected")

        self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))

    def test_an_unauthenticated_caller_gets_nothing(self):
        self.assertEqual(401, APIClient().get(SERIES, {"measure": "active_students"}).status_code)
        self.assertEqual(401, APIClient().get(MEASURES).status_code)


class Fees(FeeReportsTestCase):
    """15 July 2026 in Kolkata. Aarav owes Class 8's Tuition: 1,000 due on
    10 April and 10 July, and two more still to come."""

    def chart(self, user, measure, **params):
        return self.as_user(user).get(SERIES, {"measure": measure, **params})

    def test_collected_is_per_month_and_per_currency(self):
        self.paid(amount="1000.00", receipt_date="2026-06-20")
        self.paid(amount="400.00", receipt_date="2026-07-10")
        bina = self.charged("Bina", last_name="Rao")
        self.in_dollars(bina)
        self.paid(student=bina, amount="10.00", receipt_date="2026-07-14")

        response = self.chart(self.accountant, "fees_collected", **{"from": "2026-06-01", "to": "2026-07-15"})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("money", response.data["unit"])
        self.assertEqual(
            [
                [{"currency_code": "INR", "amount": "1000.00"}],
                [{"currency_code": "INR", "amount": "400.00"}, {"currency_code": "USD", "amount": "10.00"}],
            ],
            [point["amounts"] for point in response.data["points"]],
        )

    def test_outstanding_and_overdue_are_what_the_report_said_that_day(self):
        record_snapshot(self.school.id, dt.date(2026, 7, 15), timezone.now())
        report = self.ok("fee-outstanding", **{"from": "2026-07-01", "to": "2026-07-15"})["totals"]["by_currency"][0]

        span = {"from": "2026-07-01", "to": "2026-07-15"}
        outstanding = self.chart(self.accountant, "fee_outstanding", **span).data["points"][0]["amounts"]
        overdue = self.chart(self.accountant, "fee_overdue", **span).data["points"][0]["amounts"]

        # April's and July's 1,000, both past their due dates.
        self.assertEqual([{"currency_code": "INR", "amount": "2000.00"}], outstanding)
        self.assertEqual([{"currency_code": "INR", "amount": "2000.00"}], overdue)
        self.assertEqual(report["balance"], outstanding[0]["amount"])

    def test_a_payment_after_the_snapshot_does_not_rewrite_it(self):
        record_snapshot(self.school.id, dt.date(2026, 7, 15), timezone.now())
        self.paid(amount="1000.00")

        amounts = self.chart(self.accountant, "fee_outstanding", **{"from": "2026-07-01"}).data["points"][0]["amounts"]

        self.assertEqual([{"currency_code": "INR", "amount": "2000.00"}], amounts)

    def test_who_may_chart_fees(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.ACCOUNTANT)
        record_snapshot(self.school.id, dt.date(2026, 7, 15), timezone.now())

        self.assertEqual(200, self.chart(self.admin, "fees_collected").status_code)
        self.assertEqual(200, self.chart(self.accountant, "fee_outstanding").status_code)
        self.assertEqual(403, self.chart(teacher, "fees_collected").status_code)
        # Another school's accountant, naming this school, is refused rather
        # than shown it: fees are off where they work.
        self.assertEqual(403, self.chart(stranger, "fee_outstanding", school_id=self.school.id).status_code)

    def test_the_picker_offers_fee_charts_where_fees_are_on(self):
        keys = [m["key"] for m in self.as_user(self.accountant).get(MEASURES).data["data"]]

        self.assertEqual(["staff_attendance_rate", "fees_collected", "fee_outstanding", "fee_overdue"], keys)
