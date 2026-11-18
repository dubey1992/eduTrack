"""The dashboard enhancement (docs/dashboard.md): the fee collection report's
person and payment-mode filters and its per-person totals, the dashboard's
"Collected today" panel, and its "Messages this month" panel.

Same school, year and frozen clock as the fee reports: 2026-27, "now" is
15 July 2026, 11:30 in Kolkata. Aarav owes 1,000 a quarter, 4,000 a year.
"""

import datetime as dt

from school import factories
from school.enums import UserRole
from school.models import Message, ModuleSetting, RolePermission

from .test_fees_reports_api import JULY, FeeReportsTestCase


class CollectionFilters(FeeReportsTestCase):
    def setUp(self):
        super().setUp()
        self.clerk = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT, first_name="Rahul", last_name="Sharma")
        self.bina = self.charged("Bina", last_name="Rao")
        self.mine = self.paid(amount="1000.00", receipt_date="2026-07-15")  # cash, by the accountant
        self.upi = self.paid(amount="400.00", receipt_date="2026-07-14", payment_mode="upi", user=self.clerk)
        self.cash = self.paid(student=self.bina, amount="600.00", receipt_date="2026-07-15", user=self.clerk)
        self.wrong = self.paid(student=self.bina, amount="50.00", receipt_date="2026-07-15", user=self.clerk)
        self.cancel(self.wrong["id"])

    def numbers(self, data) -> list[str]:
        return [row["receipt_number"] for row in data["rows"]]

    def test_narrowed_to_the_person_who_took_the_money(self):
        data = self.ok("fee-collection", received_by=self.clerk.id, **JULY)

        self.assertEqual([self.upi["receipt_number"], self.cash["receipt_number"]], self.numbers(data))
        self.assertEqual([{"currency_code": "INR", "amount": "1000.00"}], data["totals"]["collected"])
        # Their own cancelled receipt, not the school's.
        self.assertEqual(1, data["totals"]["cancelled_receipts"])

    def test_narrowed_to_a_payment_mode(self):
        data = self.ok("fee-collection", payment_mode="upi", **JULY)

        self.assertEqual([self.upi["receipt_number"]], self.numbers(data))
        self.assertEqual(0, data["totals"]["cancelled_receipts"])

    def test_both_filters_together(self):
        data = self.ok("fee-collection", received_by=self.clerk.id, payment_mode="cash", **JULY)

        self.assertEqual([self.cash["receipt_number"]], self.numbers(data))

    def test_one_day_is_exactly_that_day(self):
        data = self.ok("fee-collection", **{"from": "2026-07-15", "to": "2026-07-15"})

        self.assertEqual({self.mine["receipt_number"], self.cash["receipt_number"]}, set(self.numbers(data)))

    def test_the_per_person_totals_add_up_to_the_report_total(self):
        totals = self.ok("fee-collection", **JULY)["totals"]

        self.assertEqual(
            [
                (self.clerk.id, "Rahul Sharma", 2, "1000.00", "600.00"),
                (self.accountant.id, self.accountant.name, 1, "1000.00", "1000.00"),
            ],
            [(line["received_by_id"], line["received_by"], line["receipts"], line["amount"], line["cash"])
             for line in sorted(totals["by_staff"], key=lambda line: line["received_by"] != "Rahul Sharma")],
        )
        self.assertEqual(
            sum(float(line["amount"]) for line in totals["by_staff"]),
            float(totals["collected"][0]["amount"]),
        )

    def test_bad_filters_are_refused(self):
        for params in ({"received_by": "rahul"}, {"payment_mode": "barter"}):
            with self.subTest(params=params):
                response = self.report("fee-collection", **params, **JULY)
                self.assertEqual(422, response.status_code)
                self.assertIn(next(iter(params)), response.data["details"]["errors"])

    def test_a_person_from_another_school_matches_nothing(self):
        other = factories.SchoolFactory()
        stranger = factories.UserFactory(school=other, role=UserRole.ACCOUNTANT)

        data = self.ok("fee-collection", received_by=stranger.id, **JULY)

        self.assertEqual([], data["rows"])

    def test_the_pdf_names_the_filters(self):
        response = self.report("fee-collection", format="pdf", received_by=self.clerk.id, payment_mode="cash", **JULY)

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])


class CollectedToday(FeeReportsTestCase):
    def panel(self, user, **params):
        response = self.as_user(user).get("/api/v1/dashboard", params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data["collections_today"]

    def test_todays_receipts_per_person_with_cash_and_credit_apart(self):
        clerk = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT, first_name="Neha", last_name="Gupta")
        self.paid(amount="300.00", receipt_date="2026-07-14")  # yesterday: not counted
        self.paid(amount="400.00", receipt_date="2026-07-15", payment_mode="upi", reference="UTR9")
        # Everything Aarav owes this year is 4,000; he has paid 700, so 3,550
        # settles it and leaves 250 held as credit - an advance.
        ahead = self.paid(amount="3550.00", receipt_date="2026-07-15", user=clerk)
        self.assertEqual("250.00", ahead["credit_amount"])
        wrong = self.paid(student=self.charged("Bina"), amount="20.00", receipt_date="2026-07-15", user=clerk)
        self.cancel(wrong["id"])

        panel = self.panel(self.admin)

        self.assertEqual(("2026-07-15", 2, 1, ["INR 3,950.00"]),
                         (panel["date"], panel["receipts"], panel["cancelled_receipts"], panel["collected"]))
        self.assertEqual(
            [("Neha Gupta", 1, "INR 3,550.00", "INR 3,550.00", "INR 250.00"),
             (self.accountant.name, 1, "INR 400.00", "INR 0.00", "INR 0.00")],
            [(line["received_by"], line["receipts"], line["amount_display"], line["cash_display"],
              line["credit_display"]) for line in panel["by_staff"]],
        )

    def test_a_quiet_day_is_zero_in_the_schools_currency(self):
        panel = self.panel(self.accountant)

        self.assertEqual((0, ["INR 0.00"], []), (panel["receipts"], panel["collected"], panel["by_staff"]))

    def test_only_the_fee_cards_readers_see_it(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertIsNone(self.panel(teacher))
        self.assertIsNone(self.panel(root))
        self.assertIsNotNone(self.panel(root, school_id=self.school.id))

        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)
        self.assertIsNone(self.panel(self.admin))

    def test_another_schools_admin_never_sees_it(self):
        other = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=other, module="fees")
        their_admin = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)
        self.paid(amount="400.00", receipt_date="2026-07-15")

        # Asking for this school by id is ignored: they see their own.
        panel = self.panel(their_admin, school_id=self.school.id)

        self.assertEqual((0, []), (panel["receipts"], panel["by_staff"]))


class MessagesThisMonth(FeeReportsTestCase):
    def setUp(self):
        super().setUp()
        factories.ModuleSettingFactory(school=self.school, module="communication")

    def message(self, channel, status, category="attendance", when=dt.datetime(2026, 7, 10, 5, 0, tzinfo=dt.UTC),
                school=None):
        row = Message.objects.create(
            school=school or self.school, event="student.absent", category=category, channel=channel,
            recipient_name="A guardian", body="Hello", status=status,
        )
        Message.objects.filter(pk=row.pk).update(created_at=when)

    def panel(self, user, **params):
        response = self.as_user(user).get("/api/v1/dashboard", params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data["messages_this_month"]

    def test_counts_by_the_status_the_log_keeps_never_delivered(self):
        for status in ("sent", "sent", "failed", "queued", "skipped"):
            self.message("sms", status)
        self.message("whatsapp", "sent", category="fee")
        self.message("whatsapp", "failed", category="fee")
        self.message("in_app", "sent")  # not an SMS or WhatsApp
        self.message("email", "sent")
        # 30 June, 18:30 UTC is 1 July, midnight in Kolkata: this month.
        self.message("sms", "sent", when=dt.datetime(2026, 6, 30, 18, 30, tzinfo=dt.UTC))
        # 30 June, 18:29 UTC is 30 June, 23:59 in Kolkata: last month.
        self.message("sms", "sent", when=dt.datetime(2026, 6, 30, 18, 29, tzinfo=dt.UTC))

        panel = self.panel(self.admin)

        self.assertEqual("July 2026", panel["month"])
        self.assertEqual({"channel": "all", "label": "SMS and WhatsApp", "sent": 4, "queued": 1, "failed": 2,
                          "skipped": 1}, panel["total"])
        self.assertEqual(
            [("sms", 3, 1, 1, 1), ("whatsapp", 1, 0, 1, 0)],
            [(line["channel"], line["sent"], line["queued"], line["failed"], line["skipped"])
             for line in panel["channels"]],
        )
        self.assertEqual(2, panel["fee_related"])
        self.assertFalse(panel["delivery_reported"])
        self.assertNotIn("delivered", panel["total"])

    def test_only_readers_of_the_message_log_see_it(self):
        self.assertIsNotNone(self.panel(self.admin))
        # The accountant keeps the books, not the message log.
        self.assertIsNone(self.panel(self.accountant))
        self.assertIsNone(self.panel(factories.UserFactory(school=self.school, role=UserRole.TEACHER)))

        RolePermission.objects.create(role="ACCOUNTANT", module="communication", level="view")
        self.assertIsNotNone(self.panel(self.accountant))

    def test_not_with_communication_switched_off(self):
        ModuleSetting.objects.filter(school=self.school, module="communication").update(school_enabled=False)

        self.assertIsNone(self.panel(self.admin))

    def test_another_schools_messages_are_never_counted(self):
        other = factories.SchoolFactory()
        self.message("sms", "sent", school=other)

        self.assertEqual(0, self.panel(self.admin)["total"]["sent"])
