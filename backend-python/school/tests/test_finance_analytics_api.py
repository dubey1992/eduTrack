"""Finance analytics, A5 (docs/analytics.md), over HTTP.

The fee report tests' school and clock: 15 July 2026 in Kolkata. Aarav
(Class 8 - A) owes Class 8's Tuition, 1,000 due on 10 April, 10 July,
10 October and 10 January. What matters: every figure is per currency and
never added across them, cancelled and waived money is no money, the look
ahead is only what is scheduled, and payroll is shown only to whoever may
read it.
"""

import datetime as dt

from django.utils import timezone
from rest_framework.test import APIClient

from school import factories
from school.analytics import record_snapshot
from school.enums import UserRole
from school.models import ModuleSetting, RolePermission, StudentFeeDue

from .test_advanced_reports_api import payslip
from .test_fees_reports_api import FeeReportsTestCase

URL = "/api/v1/analytics/finance"
SPAN = {"from": "2026-04-01", "to": "2026-07-15"}


class FinanceTestCase(FeeReportsTestCase):
    def look(self, user=None, **params):
        response = self.as_user(user or self.accountant).get(URL, {**SPAN, **params})
        self.assertEqual(200, response.status_code, getattr(response, "data", response))

        return response.data

    def month(self, data, key, start):
        return next(row for row in data[key] if row["from"] == start)


class Collection(FinanceTestCase):
    def test_each_month_what_fell_due_what_came_in_and_how_much_is_paid_so_far(self):
        self.paid(amount="1000.00", receipt_date="2026-07-15")  # goes to April's installment first

        data = self.look()

        self.assertEqual(
            ["2026-04-01", "2026-05-01", "2026-06-01", "2026-07-01"], [m["from"] for m in data["months"]]
        )
        april = self.month(data, "collection", "2026-04-01")["amounts"]
        july = self.month(data, "collection", "2026-07-01")["amounts"]
        self.assertEqual(
            [{"currency_code": "INR", "due": "1000.00", "collected": "0.00", "paid_so_far": "1000.00", "rate": 100.0}],
            april,
        )
        self.assertEqual(
            [{"currency_code": "INR", "due": "1000.00", "collected": "1000.00", "paid_so_far": "0.00", "rate": 0.0}],
            july,
        )
        # A month with nothing due and nothing in says so with no lines.
        self.assertEqual([], self.month(data, "collection", "2026-05-01")["amounts"])

    def test_currencies_are_kept_apart(self):
        bina = self.charged("Bina", last_name="Rao")
        self.in_dollars(bina)

        july = self.month(self.look(), "collection", "2026-07-01")["amounts"]

        self.assertEqual(["INR", "USD"], [line["currency_code"] for line in july])
        self.assertEqual(("1000.00", "1000.00"), (july[0]["due"], july[1]["due"]))

    def test_a_cancelled_receipt_brought_nothing_in_and_a_waived_due_was_never_owed(self):
        wrong = self.paid(amount="1000.00", receipt_date="2026-07-12")
        self.cancel(wrong["id"])
        StudentFeeDue.objects.filter(student=self.aarav, due_date=dt.date(2026, 7, 10)).update(status="waived")

        july = self.month(self.look(), "collection", "2026-07-01")["amounts"]

        self.assertEqual([], july)

    def test_more_than_two_years_is_refused(self):
        response = self.as_user(self.accountant).get(URL, {"from": "2024-01-01", "to": "2026-07-15"})

        self.assertEqual(422, response.status_code)
        self.assertEqual({"from": ["Finance covers at most 24 months. Pick a shorter range."]},
                         response.data["details"]["errors"])


class ByClassAndAhead(FinanceTestCase):
    def test_each_class_charged_paid_and_owing_as_at_today(self):
        self.paid(amount="1000.00", receipt_date="2026-07-15")

        rows = self.look()["by_class"]

        self.assertEqual(
            [{"class_section": "Class 8 A", "currency_code": "INR", "charged": "2000.00", "paid": "1000.00",
              "outstanding": "1000.00", "overdue": "1000.00", "rate": 50.0}],
            [{key: row[key] for key in ("class_section", "currency_code", "charged", "paid", "outstanding",
                                         "overdue", "rate")} for row in rows],
        )

    def test_the_next_three_months_are_what_is_scheduled_and_unpaid(self):
        upcoming = self.look()["upcoming"]

        self.assertEqual(["2026-08-01", "2026-09-01", "2026-10-01"], [m["from"] for m in upcoming])
        self.assertEqual(([], [], [{"currency_code": "INR", "due": "1000.00"}]),
                         tuple(m["amounts"] for m in upcoming))


class OverdueByAge(FinanceTestCase):
    def test_nothing_before_the_first_night_that_recorded_ages(self):
        data = self.look()

        self.assertEqual([None] * 4, [m["amounts"] for m in data["overdue_by_age"]])

    def test_a_month_reads_its_last_recorded_night(self):
        record_snapshot(self.school.id, dt.date(2026, 7, 15), timezone.now())

        july = self.month(self.look(), "overdue_by_age", "2026-07-01")

        self.assertEqual("2026-07-15", july["as_of"])
        # April's 1,000 is 96 days late; July's is 5.
        self.assertEqual(
            [{"currency_code": "INR", "overdue_0_30": "1000.00", "overdue_31_60": "0.00", "overdue_61_plus": "1000.00"}],
            july["amounts"],
        )


class FeesAndPayroll(FinanceTestCase):
    def setUp(self):
        super().setUp()
        factories.ModuleSettingFactory(school=self.school, module="payroll")
        self.profile = factories.StaffProfileFactory(user=self.accountant)

    def test_fees_in_against_the_payroll_finalized_for_the_month(self):
        self.paid(amount="1000.00", receipt_date="2026-07-15")
        payslip(self.profile, 2026, 7, "800.00")
        payslip(factories.StaffProfileFactory(user__school=self.school), 2026, 6, "500.00", run_status="draft")

        data = self.look()

        self.assertEqual([{"currency_code": "INR", "fees_in": "1000.00", "payroll_out": "800.00"}],
                         self.month(data, "fees_vs_payroll", "2026-07-01")["amounts"])
        # A draft run is not money that left.
        self.assertEqual([], self.month(data, "fees_vs_payroll", "2026-06-01")["amounts"])

    def test_someone_who_may_read_fees_but_not_payroll_does_not_see_it(self):
        clerk = factories.UserFactory(school=self.school, role=UserRole.STAFF)
        # The matrix lets staff read fees, as a school might for a clerk.
        RolePermission.objects.update_or_create(
            role=UserRole.STAFF, module="fees",
            defaults={"level": "view", "created_at": timezone.now(), "updated_at": timezone.now()},
        )

        data = self.look(clerk)

        self.assertNotIn("fees_vs_payroll", data)
        self.assertIn("collection", data)


class WhoSees(FinanceTestCase):
    def test_the_fee_audience_reads_it_and_a_teacher_does_not(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(200, self.as_user(self.admin).get(URL, SPAN).status_code)
        self.assertEqual(403, self.as_user(teacher).get(URL, SPAN).status_code)
        self.assertEqual(401, APIClient().get(URL).status_code)

    def test_another_school_s_accountant_sees_their_own_not_this(self):
        other = factories.SchoolFactory(timezone="Asia/Kolkata")
        factories.ModuleSettingFactory(school=other, module="fees")
        theirs = factories.UserFactory(school=other, role=UserRole.ACCOUNTANT)

        data = self.look(theirs, school_id=self.school.id)

        self.assertEqual([], data["by_class"], "never this school's families")

    def test_a_school_without_fees_has_no_finance(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        response = self.as_user(self.accountant).get(URL, SPAN)

        self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))

    def test_a_super_admin_names_a_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertEqual(422, self.as_user(root).get(URL, SPAN).status_code)
        self.assertEqual(200, self.as_user(root).get(URL, {**SPAN, "school_id": self.school.id}).status_code)
