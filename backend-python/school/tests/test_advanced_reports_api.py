"""Phase 20's reporting, over HTTP: three new reports, the chronic-absentee
filter, the previous-period comparison, and PDF export.

Built on test_reports_api's world - Monday 14 September 2026, reporting on
Monday 7 to Friday 11 - so the Phase 18 rules those tests pin (every rate out
of the days the school ran) are the same ones these lean on.
"""

import datetime as dt
from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.test import TestCase

from school import factories
from school.enums import UserRole
from school.models import PayrollRun, Payslip, SyllabusTopicProgress
from school.reports import StudentAttendanceReport, pdf
from school.tests.test_reports_api import FROM, NOW, TO, ReportTestCase, client_for, holiday

NEW_REPORTS = ("payroll-summary", "leave-usage", "syllabus-progress")
ALL_REPORTS = ("student-attendance", "staff-attendance", "teaching-coverage", "transport-usage", *NEW_REPORTS)


def payslip(profile, year: int, month: int, net: str, *, run_status="finalized", paid=False, currency="INR",
            gross=None, deductions="0.00") -> Payslip:
    run, _ = PayrollRun.objects.get_or_create(
        school_id=profile.school_id, year=year, month=month,
        defaults={"status": run_status, "currency_code": currency, "working_days": 21, "created_at": NOW,
                  "updated_at": NOW},
    )
    gross = gross or str(Decimal(net) + Decimal(deductions))

    return Payslip.objects.create(
        payroll_run=run, school_id=profile.school_id, staff_profile=profile, employee_name=profile.user.name,
        employee_code=profile.employee_id, designation=profile.designation,
        department_name=profile.department.name if profile.department else None, currency_code=currency,
        working_days=21, paid_days=21, absent_days=0, half_days=0, unmarked_days=0, gross_earnings=gross,
        total_deductions=deductions, net_pay=net, shortfall=0, status="paid" if paid else "unpaid",
        paid_on=dt.date(2026, 9, 1) if paid else None, created_at=NOW, updated_at=NOW,
    )


class PayrollSummary(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)
        self.maths = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.tara = factories.StaffProfileFactory(user=self.teacher, department=self.maths, employee_id="EMP-T")
        self.sunil = factories.StaffProfileFactory(
            user=factories.UserFactory(school=self.school, role=UserRole.STAFF, first_name="Sunil", last_name="Das"),
            employee_id="EMP-S",
        )

    def test_it_totals_the_finalized_runs_of_the_months_the_range_touches(self):
        payslip(self.tara, 2026, 9, "30000.00", deductions="1800.00", paid=True)
        payslip(self.sunil, 2026, 9, "18000.00")
        # August is outside 7-11 September, and says nothing about it.
        payslip(self.tara, 2026, 8, "99999.00")

        response = self.get(self.accountant, "payroll-summary")

        self.assertEqual(200, response.status_code, response.data)
        rows = {row["employee_id"]: row for row in response.data["rows"]}
        self.assertEqual(
            {
                "staff_profile_id": self.tara.id, "employee_id": "EMP-T", "name": "Rahul Verma",
                "department": "Mathematics", "designation": "Teacher", "currency_code": "INR", "payslips": 1,
                "paid_days": 21.0, "gross": "31800.00", "deductions": "1800.00", "net": "30000.00",
                "paid": "30000.00", "unpaid": "0.00",
            },
            rows["EMP-T"],
        )
        self.assertEqual(("0.00", "18000.00"), (rows["EMP-S"]["paid"], rows["EMP-S"]["unpaid"]))
        self.assertEqual(
            {
                "employees": 2, "payslips": 2, "months": ["2026-09"],
                "by_currency": [{"currency_code": "INR", "gross": "49800.00", "deductions": "1800.00",
                                 "net": "48000.00", "paid": "30000.00", "unpaid": "18000.00"}],
            },
            response.data["totals"],
        )

    def test_a_draft_run_is_not_reported_as_spent(self):
        payslip(self.tara, 2026, 9, "30000.00", run_status="draft")

        data = self.get(self.accountant, "payroll-summary").data

        self.assertEqual([], data["rows"])
        self.assertEqual([], data["totals"]["by_currency"])

    def test_a_range_across_months_adds_each_month_up(self):
        payslip(self.tara, 2026, 8, "30000.00", paid=True)
        payslip(self.tara, 2026, 9, "27857.14")

        row = self.get(self.accountant, "payroll-summary", **{"from": "2026-08-20"}).data["rows"][0]

        self.assertEqual((2, "57857.14", "30000.00", "27857.14"), (row["payslips"], row["net"], row["paid"], row["unpaid"]))

    def test_money_in_two_currencies_is_never_added_together(self):
        payslip(self.tara, 2026, 8, "30000.00", currency="INR")
        slip = payslip(self.tara, 2026, 9, "400.00", currency="USD")
        slip.payroll_run.currency_code = "USD"
        slip.payroll_run.save()

        data = self.get(self.accountant, "payroll-summary", **{"from": "2026-08-01"}).data

        # One line per currency for the same employee, and a total per currency.
        self.assertEqual([("INR", "30000.00"), ("USD", "400.00")], [(r["currency_code"], r["net"]) for r in data["rows"]])
        self.assertEqual(["INR", "USD"], [entry["currency_code"] for entry in data["totals"]["by_currency"]])
        self.assertEqual(1, data["totals"]["employees"])

    def test_the_department_filter_narrows_it(self):
        payslip(self.tara, 2026, 9, "30000.00")
        payslip(self.sunil, 2026, 9, "18000.00")

        rows = self.get(self.accountant, "payroll-summary", department_id=self.maths.id).data["rows"]

        self.assertEqual(["EMP-T"], [row["employee_id"] for row in rows])

    def test_who_may_see_it(self):
        payslip(self.tara, 2026, 9, "30000.00")
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)

        self.assertEqual(200, self.get(self.accountant, "payroll-summary").status_code)
        self.assertEqual(200, self.get(self.admin, "payroll-summary").status_code)
        self.assertEqual(1, len(self.get(root, "payroll-summary", school_id=self.school.id).data["rows"]))
        for denied in (hod, self.teacher, factories.UserFactory(school=self.school, role=UserRole.STAFF),
                       factories.UserFactory(school=self.school, role=UserRole.TRANSPORT_MANAGER)):
            self.assertEqual(403, self.get(denied, "payroll-summary").status_code, denied.role)

    def test_an_accountant_never_sees_another_schools_payroll(self):
        payslip(self.tara, 2026, 9, "30000.00")
        elsewhere = factories.SchoolFactory(timezone="UTC")
        their_accountant = factories.UserFactory(school=elsewhere, role=UserRole.ACCOUNTANT)

        # Naming this school changes nothing: the school is theirs, not the request's.
        data = self.get(their_accountant, "payroll-summary", school_id=self.school.id).data

        self.assertEqual([], data["rows"])


class LeaveUsage(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.profile = factories.StaffProfileFactory(user=self.teacher, department=self.science)

    def leave(self, status: str, leave_type: str, start: str, end: str, profile=None):
        return factories.StaffLeaveFactory(
            staff_profile=profile or self.profile, status=status, leave_type=leave_type,
            start_date=dt.date.fromisoformat(start), end_date=dt.date.fromisoformat(end),
        )

    def row(self, user=None, **params):
        rows = self.get(user or self.admin, "leave-usage", **params).data["rows"]
        return next(row for row in rows if row["staff_profile_id"] == self.profile.id)

    def test_leave_taken_is_counted_in_working_days_inside_the_range(self):
        # Thursday 3 to Tuesday 8: only the 7th and 8th are inside the range.
        self.leave("approved", "casual", "2026-09-03", "2026-09-08")
        # Wednesday 9 is a holiday, Saturday 12 and Sunday 13 are a weekend.
        holiday(self.school, "2026-09-09")
        self.leave("approved", "medical", "2026-09-09", "2026-09-13")
        self.leave("approved", "half_day", "2026-09-11", "2026-09-11")

        row = self.row()

        # Casual 2 (7th, 8th), medical 2 (10th, 11th), half day 0.5.
        self.assertEqual((2, 2, 0, 0.5, 4.5), (row["casual"], row["medical"], row["earned"], row["half_day"],
                                               row["leave_days"]))

    def test_pending_rejected_and_unexcused_absence_are_shown_beside_it(self):
        self.leave("pending", "earned", "2026-09-10", "2026-09-11")
        self.leave("rejected", "casual", "2026-09-07", "2026-09-07")
        self.mark_staff(self.profile, "2026-09-08", "absent")
        # A mark on a day since declared a holiday is not a working day, and
        # counts for nothing.
        self.mark_staff(self.profile, "2026-09-09", "absent")
        holiday(self.school, "2026-09-09")

        row = self.row()

        self.assertEqual((1, 2, 1, 1, 0), (row["pending_requests"], row["pending_days"], row["rejected_requests"],
                                           row["absent"], row["leave_days"]))

    def test_a_head_of_department_sees_only_their_own_departments(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.science.hod_user = hod
        self.science.save()
        outsider = factories.StaffProfileFactory(user__school=self.school)

        rows = self.get(hod, "leave-usage").data["rows"]

        self.assertEqual([self.profile.id], [row["staff_profile_id"] for row in rows])
        self.assertNotIn(outsider.id, [row["staff_profile_id"] for row in rows])

    def test_who_may_see_it(self):
        accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)

        self.assertEqual(200, self.get(self.admin, "leave-usage").status_code)
        for denied in (self.teacher, accountant, factories.UserFactory(school=self.school, role=UserRole.STAFF)):
            self.assertEqual(403, self.get(denied, "leave-usage").status_code, denied.role)


class SyllabusProgress(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.physics = factories.SubjectFactory(department=self.science, name="Physics", min_class_level=1,
                                                max_class_level=12)
        self.topics = [factories.SyllabusTopicFactory(subject=self.physics) for _ in range(4)]
        self.section.school_class.level = 8
        self.section.school_class.save()
        self.section_b = factories.ClassSectionFactory(school_class=self.section.school_class, name="B")

    def complete(self, topic, section, at: dt.datetime):
        SyllabusTopicProgress.objects.create(
            school=self.school, syllabus_topic=topic, class_section=section, completed_by=self.teacher,
            completed_at=at, created_at=NOW, updated_at=NOW,
        )

    def test_each_section_is_measured_through_each_subject_separately(self):
        self.complete(self.topics[0], self.section, dt.datetime(2026, 8, 20, 9, tzinfo=dt.timezone.utc))
        self.complete(self.topics[1], self.section, dt.datetime(2026, 9, 8, 9, tzinfo=dt.timezone.utc))
        self.complete(self.topics[2], self.section, dt.datetime(2026, 9, 10, 9, tzinfo=dt.timezone.utc))
        factories.TimetableEntryFactory(class_section=self.section, subject=self.physics, teacher=self.teacher,
                                        period=factories.PeriodFactory(school=self.school))

        response = self.get(self.admin, "syllabus-progress")

        self.assertEqual(200, response.status_code, response.data)
        rows = {row["class_section"]: row for row in response.data["rows"]}
        self.assertEqual(
            {
                "class_section_id": self.section.id, "class_section": "Grade 8 A", "subject_id": self.physics.id,
                "subject": "Physics", "department": "Science", "teacher": "Rahul Verma", "topics_total": 4,
                "topics_completed": 3, "syllabus_completion": 75, "completed_in_period": 2,
                "last_completed_on": "2026-09-10",
            },
            rows["Grade 8 A"],
        )
        # Section B has not started, and nobody teaches it Physics yet.
        self.assertEqual((0, 0, None), (rows["Grade 8 B"]["topics_completed"], rows["Grade 8 B"]["syllabus_completion"],
                                        rows["Grade 8 B"]["teacher"]))
        self.assertEqual(
            {"classes_and_subjects": 2, "topics_total": 8, "topics_completed": 3, "syllabus_completion": 37.5,
             "completed_in_period": 2},
            response.data["totals"],
        )

    def test_the_period_and_last_date_are_the_schools_days_not_utc(self):
        self.school.timezone = "Asia/Kolkata"
        self.school.save()
        # 20:00 UTC on Friday 11 is 01:30 on Saturday 12 in Kolkata - after the range.
        self.complete(self.topics[0], self.section, dt.datetime(2026, 9, 11, 20, tzinfo=dt.timezone.utc))

        row = self.get(self.admin, "syllabus-progress").data["rows"][0]

        self.assertEqual((0, "2026-09-12"), (row["completed_in_period"], row["last_completed_on"]))

    def test_only_subjects_that_apply_and_have_a_syllabus_are_listed(self):
        factories.SubjectFactory(department=self.science, name="Chemistry")  # no topics
        senior = factories.SubjectFactory(department=self.science, name="Astrophysics", min_class_level=11,
                                          max_class_level=12)
        factories.SyllabusTopicFactory(subject=senior)
        old_year = factories.AcademicYearFactory(school=self.school, name="2025-26", is_current=False)
        factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=old_year, school=self.school, name="Old"),
        )

        rows = self.get(self.admin, "syllabus-progress").data["rows"]

        self.assertEqual({"Physics"}, {row["subject"] for row in rows})
        self.assertEqual({"Grade 8 A", "Grade 8 B"}, {row["class_section"] for row in rows})

    def test_a_head_of_department_sees_only_their_own_subjects(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        humanities = factories.DepartmentFactory(school=self.school, name="Humanities", hod_user=hod)
        history = factories.SubjectFactory(department=humanities, name="History")
        factories.SyllabusTopicFactory(subject=history)

        rows = self.get(hod, "syllabus-progress").data["rows"]

        self.assertEqual({"History"}, {row["subject"] for row in rows})

    def test_who_may_see_it(self):
        self.assertEqual(200, self.get(self.admin, "syllabus-progress").status_code)
        for role in (UserRole.TEACHER, UserRole.ACCOUNTANT, UserRole.TRANSPORT_MANAGER, UserRole.STAFF):
            user = factories.UserFactory(school=self.school, role=role)
            self.assertEqual(403, self.get(user, "syllabus-progress").status_code, role)


class ChronicAbsentees(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.regular = factories.StudentFactory(class_section=self.section, first_name="Bina", admission_number="ADM-2")
        for day in ("2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11"):
            self.mark(day, "present", student=self.regular)
        self.mark("2026-09-07", "present")
        self.mark("2026-09-08", "absent")

    def test_only_students_under_the_threshold_are_listed_but_the_totals_are_the_whole_class(self):
        data = self.get(self.admin, "student-attendance", below=75).data

        self.assertEqual(["ADM-0042"], [row["admission_number"] for row in data["rows"]])
        self.assertEqual((2, 60, 75, 1), (data["totals"]["students"], data["totals"]["attendance_rate"],
                                          data["totals"]["below"], data["totals"]["students_below"]))

    def test_a_student_with_no_rate_is_not_under_anything(self):
        data = self.get(self.admin, "student-attendance", below=75, **{"from": "2026-09-12", "to": "2026-09-13"}).data

        self.assertEqual(([], 0), (data["rows"], data["totals"]["students_below"]))

    def test_the_threshold_must_be_a_percentage(self):
        for value in ("0", "101", "abc", "-5"):
            response = self.get(self.admin, "student-attendance", below=value)
            self.assertEqual(422, response.status_code, value)
            self.assertIn("below", response.data["details"]["errors"])

    def test_without_it_the_report_is_exactly_phase_18s(self):
        data = self.get(self.admin, "student-attendance").data

        self.assertEqual(2, len(data["rows"]))
        self.assertNotIn("students_below", data["totals"])
        self.assertNotIn("comparison", data)
        self.assertNotIn("previous", data["rows"][0])


class PreviousPeriod(ReportTestCase):
    def test_every_rate_comes_with_the_same_length_period_before_it(self):
        # 7-11 September is compared with 2-6 September: Wednesday 2 to
        # Friday 4 are its working days, the weekend is not.
        self.mark("2026-09-02", "present")
        self.mark("2026-09-03", "absent")
        self.mark("2026-09-04", "absent")
        for day in ("2026-09-07", "2026-09-08", "2026-09-09"):
            self.mark(day, "present")

        data = self.get(self.admin, "student-attendance", compare=1).data

        self.assertEqual({"from": "2026-09-02", "to": "2026-09-06", "working_days": 3}, data["comparison"]["range"])
        self.assertEqual(33.3, data["comparison"]["totals"]["attendance_rate"])
        self.assertEqual({"attendance_rate": 33.3}, data["rows"][0]["previous"])
        self.assertEqual(60, data["rows"][0]["attendance_rate"])

    def test_a_row_that_did_not_exist_before_has_nothing_to_compare_with(self):
        route_later = factories.TransportRouteFactory(school=self.school, name="New Route")
        route_later.created_at = NOW
        route_later.save()

        rows = self.get(self.admin, "transport-usage", compare="true").data["rows"]

        # The route is on both halves - it is the trip data that is absent -
        # so the previous figures are zeros, not missing.
        self.assertEqual({"days_run": 0, "riders_boarded": 0}, rows[0]["previous"])

    def test_the_previous_period_is_everybody_not_just_those_under_the_threshold(self):
        self.mark("2026-09-02", "present")
        self.mark("2026-09-03", "present")
        self.mark("2026-09-04", "present")
        self.mark("2026-09-07", "present")

        data = self.get(self.admin, "student-attendance", compare=1, below=50).data

        # Under 50% now, but 100% before - which is the point of showing it.
        self.assertEqual((20, {"attendance_rate": 100}), (data["rows"][0]["attendance_rate"], data["rows"][0]["previous"]))

    def test_compare_must_be_true_or_false(self):
        response = self.get(self.admin, "student-attendance", compare="maybe")

        self.assertEqual(422, response.status_code)
        self.assertIn("compare", response.data["details"]["errors"])

    def test_every_report_can_be_compared(self):
        factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)

        for report in ALL_REPORTS:
            data = self.get(self.admin, report, compare=1).data
            self.assertIn("comparison", data, report)
            self.assertEqual("2026-09-02", data["comparison"]["range"]["from"], report)

    def test_the_csv_carries_the_previous_figures_in_their_own_columns(self):
        self.mark("2026-09-02", "present")

        response = self.get(self.admin, "student-attendance", compare=1, format="csv")

        header, line = response.content.decode("utf-8-sig").splitlines()[:2]
        self.assertTrue(header.endswith(",\"Attendance % (previous period)\"") or header.endswith(",Attendance % (previous period)"))
        self.assertTrue(line.endswith(",33.3"), line)


class GroupComparison(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)
        self.group = factories.SchoolFactory(name="A Group", timezone="UTC")
        self.north = factories.SchoolFactory(name="B North", timezone="UTC", parent_school=self.group)
        self.south = factories.SchoolFactory(name="C South", timezone="UTC", parent_school=self.group, currency_code="USD")
        self.group_admin = factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)

    def test_a_groups_payroll_keeps_each_currency_apart_now_and_before(self):
        north = factories.StaffProfileFactory(user__school=self.north)
        south = factories.StaffProfileFactory(user__school=self.south)
        payslip(north, 2026, 9, "1000.00")
        payslip(south, 2026, 9, "50.00", currency="USD")
        payslip(north, 2026, 8, "900.00")

        data = client_for(self.group_admin).get(
            "/api/v1/reports/payroll-summary", {"from": "2026-09-01", "to": "2026-09-11", "compare": 1}
        ).data

        self.assertEqual([("INR", "1000.00"), ("USD", "50.00")],
                         [(entry["currency_code"], entry["net"]) for entry in data["totals"]["by_currency"]])
        # 1-11 September against 21-31 August: August's run, INR only.
        self.assertEqual([("INR", "900.00")],
                         [(entry["currency_code"], entry["net"]) for entry in data["comparison"]["totals"]["by_currency"]])

    def test_a_group_pdf_covers_every_branch(self):
        response = client_for(self.group_admin).get(
            "/api/v1/reports/student-attendance", {"from": "2026-09-07", "to": "2026-09-11", "format": "pdf"}
        )

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF"))
        self.assertEqual('attachment; filename="student-attendance-group-2026-09-07-to-2026-09-11.pdf"',
                         response["Content-Disposition"])


class AsPdf(ReportTestCase):
    def test_every_report_answers_as_a_pdf(self):
        factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)

        for report in ALL_REPORTS:
            response = self.get(self.admin, report, format="pdf")
            self.assertEqual(200, response.status_code, report)
            self.assertEqual("application/pdf", response["Content-Type"], report)
            self.assertTrue(response.content.startswith(b"%PDF"), report)
            self.assertEqual(f'attachment; filename="{report}-{FROM}-to-{TO}.pdf"', response["Content-Disposition"])

    def test_the_pdf_states_the_school_the_period_and_the_same_figures(self):
        self.mark("2026-09-07", "present")
        self.mark("2026-09-02", "present")
        report = StudentAttendanceReport()
        built = self.get(self.admin, "student-attendance", compare=1).data

        document = pdf.document(report, built, school_label="Sunrise Public School", generated_at="09/14/2026 12:00 PM")

        for text in ("Sunrise Public School", "Student attendance", "2026-09-07 to 2026-09-11", "5 working days",
                     "Arjun Kumar", "ADM-0042", "Attendance % (previous period)", "2026-09-02 to 2026-09-06",
                     "Generated 09/14/2026 12:00 PM"):
            self.assertIn(text, document)
        # A zero is written as 0, never as a blank cell.
        self.assertIn("<td>0</td>", document)

    def test_a_name_with_markup_in_it_is_printed_not_obeyed(self):
        self.student.first_name = "<b>Arjun</b>"
        self.student.save()

        document = pdf.document(StudentAttendanceReport(), self.get(self.admin, "student-attendance").data,
                                school_label="Sunrise & Co", generated_at="now")

        self.assertIn("&lt;b&gt;Arjun&lt;/b&gt;", document)
        self.assertIn("Sunrise &amp; Co", document)

    def test_a_pdf_obeys_the_same_rules_as_the_screen(self):
        # The format changes nothing about who may look.
        self.assertEqual(403, self.get(self.teacher, "payroll-summary", format="pdf").status_code)
        self.assertEqual(422, self.get(self.admin, "student-attendance", format="xml").status_code)
