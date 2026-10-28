"""A student's fee credit (docs/fees.md, F6 "Credit balance"): where it comes
from - an installment paid ahead that stopped applying, a payment for more
than was owed - how it pays what is owed, refunds, cancelling a receipt whose
credit has moved on, currencies, who may see and refund it, and where it
shows: the statement, the receipt, the PDFs and the Outstanding report.

Same school, year and frozen clock as test_fees_dues.py: 2026-27, "now" is
15 July 2026 in Kolkata, Class 8's Tuition is 1,000 due on 10 April, 10 July,
10 October and 10 January; Route A's bus fee is 600 on 10 April and 10
October, Route B's 800 on 10 October.
"""

import datetime as dt
from decimal import Decimal

from school import factories
from school.enums import FeeCreditKind, UserRole
from school.fees import credit, receipt_pdf, statement_pdf, ledger
from school.fees.dues import FeeDueService
from school.fees.receipts import FeeReceiptService
from school.models import AuditLog, FeeReceipt, StudentFeeCredit, StudentFeeDue

from .test_fees_dues import ROUTE_A, ROUTE_B
from .test_fees_receipts import ReceiptsTestCase

STUDENT_FEES = "/api/v1/fees/students"


class CreditTestCase(ReceiptsTestCase):
    def credit(self, student=None) -> Decimal:
        return credit.balance((student or self.aarav).id, "INR")

    def history(self, student=None) -> list[tuple]:
        """(kind, due label or receipt number, amount), oldest first."""
        rows = StudentFeeCredit.objects.filter(student=student or self.aarav).select_related(
            "student_fee_due", "fee_receipt"
        ).order_by("id")

        return [
            (
                row.kind,
                row.student_fee_due.label if row.student_fee_due_id else (
                    row.fee_receipt.receipt_number if row.fee_receipt_id else None
                ),
                str(row.amount),
            )
            for row in rows
        ]

    def refund(self, amount="100.00", user=None, student=None, **fields):
        body = {"amount": amount, "refund_date": "2026-07-15", "payment_mode": "cash",
                "reason": "Left the school", **fields}

        return self.as_user(user or self.accountant).post(
            f"{STUDENT_FEES}/{(student or self.aarav).id}/credit/refund", body, format="json"
        )

    def on_route_a(self):
        self.published(ROUTE_A, route=self.route_a)
        self.published(ROUTE_B, route=self.route_b)
        self.ride(self.aarav, self.route_a, self.stop_a)


# -- where credit comes from -----------------------------------------------------


class ARouteChange(CreditTestCase):
    def test_bus_fee_paid_ahead_follows_the_child_to_the_new_route(self):
        self.on_route_a()
        bus2 = self.due("Transport - Bus 2")
        self.paid(amount="600.00", allocations=[{"due_id": bus2.id, "amount": "600.00"}])

        self.ride(self.aarav, self.route_b, self.stop_b)

        bus2.refresh_from_db()
        self.assertEqual(("cancelled", "route_changed", Decimal("0.00")),
                         (bus2.status, bus2.cancelled_reason, bus2.paid_amount))
        # Credit pays the oldest line owed first: April's Tuition, not the
        # new route - every line is the family's to pay, oldest first.
        self.assertEqual(
            [("released", "Transport - Bus 2", "600.00"), ("applied", "Tuition - April", "-600.00")],
            self.history(),
        )
        self.assertEqual(Decimal("0.00"), self.credit())

    def test_moving_back_brings_the_old_installment_back_and_credit_pays_it_again(self):
        self.on_route_a()
        self.paid(amount="5200.00")  # everything: 4,000 tuition and 1,200 bus
        self.ride(self.aarav, self.route_b, self.stop_b)

        # Bus 2's 600 is credit, and pays 600 of Route B's 800.
        self.assertEqual(("partial", "600.00"), (self.due("Transport - Bus B").status,
                                                 str(self.due("Transport - Bus B").paid_amount)))

        self.ride(self.aarav, self.route_a, self.stop_a)

        # Route B's line, paid ahead, gives its 600 back; Bus 2 is revived
        # and the 600 pays it in full. Nothing was lost and nothing is owed
        # twice.
        self.assertEqual(("cancelled", "0.00"), (self.due("Transport - Bus B").status,
                                                 str(self.due("Transport - Bus B").paid_amount)))
        self.assertEqual(("paid", "600.00"), (self.due("Transport - Bus 2").status,
                                              str(self.due("Transport - Bus 2").paid_amount)))
        self.assertEqual(Decimal("0.00"), self.credit())

    def test_an_installment_already_due_stays_paid(self):
        self.on_route_a()
        self.paid(amount="5200.00")

        self.ride(self.aarav, self.route_b, self.stop_b)

        # April's bus fee fell due before the move: that month was his.
        self.assertEqual(("paid", "600.00"), (self.due("Transport - Bus 1").status,
                                              str(self.due("Transport - Bus 1").paid_amount)))

    def test_the_reconcile_says_what_credit_did_in_its_audit_row(self):
        self.on_route_a()
        self.paid(amount="5200.00")

        self.ride(self.aarav, self.route_b, self.stop_b)

        entry = AuditLog.objects.filter(action="fee_dues.synced").order_by("-id").first()
        self.assertEqual(
            {"released": 1, "credit_released": "600.00", "credit_applied": "600.00"},
            {key: entry.new_values[key] for key in ("released", "credit_released", "credit_applied")},
        )


class LeavingTheSchool(CreditTestCase):
    def test_everything_paid_ahead_is_held_as_credit(self):
        self.paid(amount="4000.00")

        self.as_user(self.admin).patch(f"/api/v1/students/{self.aarav.id}/deactivate")

        self.assertEqual(
            [("released", "Tuition - October", "1000.00"), ("released", "Tuition - January", "1000.00")],
            self.history(),
        )
        self.assertEqual(Decimal("2000.00"), self.credit())
        self.assertEqual({"left"}, set(StudentFeeDue.objects.filter(
            student=self.aarav, status="cancelled").values_list("cancelled_reason", flat=True)))

    def test_the_credit_is_refunded_and_the_refund_is_audited(self):
        self.paid(amount="4000.00")
        self.as_user(self.admin).patch(f"/api/v1/students/{self.aarav.id}/deactivate")

        response = self.refund("2000.00", payment_mode="bank_transfer", reference="UTR-881")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            ("refunded", "-2000.00", "bank_transfer", "Bank Transfer", "UTR-881", "Left the school", "2026-07-15"),
            tuple(response.data[key] for key in (
                "kind", "amount", "payment_mode", "payment_mode_label", "reference", "note", "entry_date"
            )),
        )
        self.assertEqual(Decimal("0.00"), self.credit())
        entry = AuditLog.objects.get(action="fee_credit.refunded")
        self.assertEqual(
            ({"credit": "2000.00"}, "2000.00", "0.00", self.accountant.id, self.school.id),
            (entry.old_values, entry.new_values["amount"], entry.new_values["credit"], entry.user_id,
             entry.school_id),
        )


class PayingMoreThanIsOwed(CreditTestCase):
    def test_the_rest_is_held_as_credit_with_the_receipt_named(self):
        data = self.paid(amount="4250.00")

        self.assertEqual([("overpaid", data["receipt_number"], "250.00")], self.history())
        self.assertEqual(
            sum((Decimal(row["amount"]) for row in data["allocations"]), Decimal("0")),
            Decimal(data["amount"]) - Decimal(data["credit_amount"]),
        )

    def test_a_fee_charged_later_is_paid_from_it_at_once(self):
        self.paid(amount="4250.00")

        self.on_route_a()

        self.assertEqual(("partial", "250.00"), (self.due("Transport - Bus 1").status,
                                                 str(self.due("Transport - Bus 1").paid_amount)))
        self.assertEqual(Decimal("0.00"), self.credit())

    def test_chosen_installments_must_still_add_up_to_the_payment(self):
        april = self.due("Tuition - April")

        errors = self.refused(self.pay(amount="1500.00", allocations=[{"due_id": april.id, "amount": "1000.00"}]))

        self.assertIn("allocations", errors)
        self.assertFalse(StudentFeeCredit.objects.exists())


# -- cancelling a receipt --------------------------------------------------------


class CancellingAReceipt(CreditTestCase):
    def test_its_credit_is_taken_back(self):
        data = self.paid(amount="4250.00")

        self.assertEqual(200, self.cancel(data["id"]).status_code)

        self.assertEqual(Decimal("0.00"), self.credit())
        self.assertEqual({"pending"}, {status for _, _, status in self.standing()})
        self.assertEqual(("reversed", data["receipt_number"], "-250.00"), self.history()[-1])
        entry = AuditLog.objects.get(action="fee_receipt.cancelled")
        self.assertEqual("250.00", entry.new_values["credit_reversed"])

    def test_credit_that_already_paid_something_else_is_taken_back_off_it(self):
        data = self.paid(amount="4250.00")
        self.on_route_a()  # the 250 pays Bus 1

        self.assertEqual(200, self.cancel(data["id"]).status_code)

        # As if the money had never been taken: everything owed again.
        self.assertEqual({"pending"}, {status for _, _, status in self.standing()})
        self.assertEqual(Decimal("0.00"), self.credit())
        self.assertEqual(
            [("returned", "Transport - Bus 1", "250.00"), ("reversed", data["receipt_number"], "-250.00")],
            self.history()[-2:],
        )

    def test_money_released_after_the_receipt_comes_back_too(self):
        self.on_route_a()
        bus2 = self.due("Transport - Bus 2")
        data = self.paid(amount="600.00", allocations=[{"due_id": bus2.id, "amount": "600.00"}])
        self.ride(self.aarav, self.route_b, self.stop_b)  # Bus 2's 600 -> credit -> April's Tuition

        self.assertEqual(200, self.cancel(data["id"]).status_code)

        self.assertEqual(("pending", "0.00"), (self.due("Tuition - April").status,
                                               str(self.due("Tuition - April").paid_amount)))
        self.assertEqual(Decimal("0.00"), self.credit())
        self.assertEqual(Decimal("0.00"), sum(
            StudentFeeDue.objects.filter(student=self.aarav).values_list("paid_amount", flat=True), Decimal("0")
        ))

    def test_refused_when_the_credit_was_refunded_and_nothing_changes(self):
        data = self.paid(amount="4250.00")
        self.assertEqual(201, self.refund("250.00").status_code)

        response = self.cancel(data["id"])

        self.assertEqual(409, response.status_code)
        self.assertEqual("FEE_RECEIPT_CREDIT_REFUNDED", response.data["code"])
        self.assertIn("INR 250.00", response.data["message"])
        self.assertEqual("valid", FeeReceipt.objects.get(pk=data["id"]).status)
        self.assertEqual({"paid"}, {status for _, _, status in self.standing()})


# -- currencies ------------------------------------------------------------------


class Currencies(CreditTestCase):
    def dollars(self, amount="100.00"):
        StudentFeeCredit.objects.create(
            school=self.school, student=self.aarav, currency_code="USD", kind=FeeCreditKind.OVERPAID,
            amount=Decimal(amount), entry_date=dt.date(2026, 7, 15),
        )

    def test_credit_in_one_currency_never_pays_a_due_in_another(self):
        self.dollars()

        FeeDueService.sync_student(self.aarav, self.year)

        self.assertEqual({"0.00"}, {paid for _, paid, _ in self.standing()})
        self.assertEqual({"USD": Decimal("100.00")}, credit.balances(self.aarav.id))

    def test_it_pays_dues_in_its_own_currency(self):
        self.dollars()
        StudentFeeDue.objects.filter(student=self.aarav, label="Tuition - January").update(currency_code="USD")

        FeeDueService.sync_student(self.aarav, self.year)

        self.assertEqual(("partial", "100.00"), (self.due("Tuition - January").status,
                                                 str(self.due("Tuition - January").paid_amount)))

    def test_a_refund_is_in_the_currency_named_and_never_more_than_held_in_it(self):
        self.dollars()

        self.assertEqual(["Aarav Shah has no credit in INR to refund."], self.refused(self.refund("10.00"))["amount"])
        self.assertEqual(
            ["Aarav Shah has only USD 100.00 in credit."],
            self.refused(self.refund("100.01", currency_code="USD"))["amount"],
        )
        self.assertEqual(201, self.refund("100.00", currency_code="usd").status_code)
        self.assertEqual({}, credit.balances(self.aarav.id))


# -- refunds: what is checked ----------------------------------------------------


class RefundValidation(CreditTestCase):
    def setUp(self):
        super().setUp()
        self.paid(amount="4100.00")  # 100 in credit

    def test_more_than_the_credit_is_refused(self):
        self.assertEqual(["Aarav Shah has only INR 100.00 in credit."],
                         self.refused(self.refund("100.01"))["amount"])
        self.assertEqual(Decimal("100.00"), self.credit())

    def test_every_field_is_checked(self):
        errors = self.refused(self.as_user(self.accountant).post(
            f"{STUDENT_FEES}/{self.aarav.id}/credit/refund", {}, format="json"
        ))

        self.assertEqual({"amount", "refund_date", "payment_mode", "reason"}, set(errors))

    def test_bad_values_are_refused(self):
        for fields, field in (
            ({"amount": "0.00"}, "amount"),
            ({"amount": "abc"}, "amount"),
            ({"refund_date": "2026-07-16"}, "refund_date"),
            ({"refund_date": "not a date"}, "refund_date"),
            ({"payment_mode": "barter"}, "payment_mode"),
            ({"payment_mode": "cheque"}, "reference"),
            ({"reason": "no"}, "reason"),
            ({"reason": "x" * 501}, "reason"),
            ({"reference": "x" * 101}, "reference"),
            ({"currency_code": "RUPEES"}, "currency_code"),
        ):
            with self.subTest(fields=fields):
                self.assertIn(field, self.refused(self.refund(**{"amount": "10.00", **fields})))

        self.assertEqual(Decimal("100.00"), self.credit())


# -- who may ---------------------------------------------------------------------


class WhoMay(CreditTestCase):
    def setUp(self):
        super().setUp()
        self.paid(amount="4100.00")

    def test_the_school_admin_and_accountant_may_read_and_refund(self):
        for user in (self.admin, self.accountant):
            with self.subTest(role=user.role):
                self.assertEqual(200, self.as_user(user).get(f"{STUDENT_FEES}/{self.aarav.id}/credit").status_code)
                self.assertEqual(201, self.refund("10.00", user=user).status_code)

    def test_a_teacher_may_do_neither(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.as_user(teacher).get(f"{STUDENT_FEES}/{self.aarav.id}/credit").status_code)
        self.assertEqual(403, self.refund("10.00", user=teacher).status_code)
        self.assertEqual(Decimal("100.00"), self.credit())

    def test_another_schools_staff_may_do_neither(self):
        other = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=other, module="fees")
        outsider = factories.UserFactory(school=other, role=UserRole.ACCOUNTANT)

        self.assertEqual(403, self.as_user(outsider).get(f"{STUDENT_FEES}/{self.aarav.id}/credit").status_code)
        self.assertEqual(403, self.refund("10.00", user=outsider).status_code)
        self.assertEqual(Decimal("100.00"), self.credit())

    def test_a_student_who_does_not_exist_is_a_404(self):
        self.assertEqual(404, self.as_user(self.accountant).get(f"{STUDENT_FEES}/999999/credit").status_code)

    def test_signed_out_is_refused(self):
        from rest_framework.test import APIClient

        self.assertEqual(401, APIClient().get(f"{STUDENT_FEES}/{self.aarav.id}/credit").status_code)


# -- where it shows --------------------------------------------------------------


class WhereItShows(CreditTestCase):
    def test_the_history_is_paginated_newest_first_with_labels(self):
        self.paid(amount="4100.00")
        self.refund("40.00")

        data = self.as_user(self.accountant).get(f"{STUDENT_FEES}/{self.aarav.id}/credit").data

        self.assertEqual(2, data["meta"]["total"])
        self.assertEqual(
            [("refunded", "Refunded to the family", "-40.00"), ("overpaid", "Paid more than was owed", "100.00")],
            [(row["kind"], row["kind_label"], row["amount"]) for row in data["data"]],
        )
        self.assertEqual("RCPT-2026-27-00001", data["data"][1]["receipt"]["receipt_number"])

    def test_the_statement_marks_what_credit_paid(self):
        self.on_route_a()
        bus2 = self.due("Transport - Bus 2")
        self.paid(amount="600.00", allocations=[{"due_id": bus2.id, "amount": "600.00"}])
        self.ride(self.aarav, self.route_b, self.stop_b)

        dues = self.as_user(self.accountant).get(f"{STUDENT_FEES}/{self.aarav.id}").data["dues"]

        self.assertEqual("600.00", next(due for due in dues if due["label"] == "Tuition - April")["paid_from_credit"])
        self.assertEqual("0.00", next(due for due in dues if due["label"] == "Transport - Bus 2")["paid_from_credit"])

    def test_the_receipt_pdf_shows_the_part_held_as_credit(self):
        data = self.paid(amount="4250.00")

        document = receipt_pdf.document(FeeReceiptService.load(data["id"]))

        self.assertIn("Held as credit", document)
        self.assertIn("INR 250.00", document)

    def test_a_receipt_without_credit_says_nothing_of_it(self):
        data = self.paid(amount="100.00")

        self.assertNotIn("Held as credit", receipt_pdf.document(FeeReceiptService.load(data["id"])))

    def test_the_statement_pdf_shows_the_credit_held(self):
        self.paid(amount="4250.00")

        page = statement_pdf.document(ledger.statement(self.aarav, self.year, dt.date(2026, 7, 15)))

        self.assertIn("Credit held for the next fees", page)

    def test_the_outstanding_report_totals_the_credit_families_hold(self):
        self.paid(amount="4250.00")

        data = self.as_user(self.accountant).get(
            "/api/v1/reports/fee-outstanding", {"from": "2026-07-01", "to": "2026-07-15"}
        ).data

        self.assertEqual([{"currency_code": "INR", "amount": "250.00"}], data["totals"]["credit_held"])
