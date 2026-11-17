"""The classic printed fee receipt (docs/document-styles.md, decided
2026-11-17): the summary frozen at the payment, the layout a school chooses,
and what an older receipt prints.

Same school, year and frozen clock as test_fees_dues.py: 2026-27, "now" is
15 July 2026 in Kolkata, Class 8's Tuition is 1,000 due on 10 April, 10 July,
10 October and 10 January.

Set RECEIPT_SAMPLES to a folder to have the scenario PDFs written there.
"""

import datetime as dt
import io
import os
from decimal import Decimal

from django.core.management import call_command
from django.test import SimpleTestCase

from school import factories, pdf_design
from school.enums import FeeDueKind
from school.fees import receipt_classic, receipt_pdf, receipt_summary
from school.fees.receipts import FeeReceiptService
from school.models import FeeReceipt, ModuleSetting, StudentFeeDue

from .test_fees_dues import ROUTE_A
from .test_fees_receipts import MODULE_SETTINGS, ReceiptsTestCase

D = Decimal


def figures(receipt: FeeReceipt) -> dict:
    return {
        "total": str(receipt.summary_total), "discount": str(receipt.summary_discount),
        "late_fee": str(receipt.summary_late_fee), "paid_earlier": str(receipt.summary_paid_earlier),
        "back_dues": str(receipt.summary_back_dues), "old_fee": str(receipt.summary_old_fee),
        "net": str(receipt.summary_net), "till": receipt.summary_till,
    }


class ClassicTestCase(ReceiptsTestCase):
    def receipt(self, data: dict) -> FeeReceipt:
        return FeeReceiptService.load(data["id"])

    def classic(self, school=None):
        ModuleSetting.objects.filter(school=school or self.school, module="fees").update(
            settings={"receipt_style": "classic"}
        )

    def html(self, data: dict, name: str | None = None) -> str:
        receipt = self.receipt(data)
        html = receipt_classic.document(receipt)
        self.assertEqual(0, pdf_design.style_errors(html), "xhtml2pdf dropped a cell's styles")
        folder = os.environ.get("RECEIPT_SAMPLES")

        if folder and name:
            os.makedirs(folder, exist_ok=True)

            with open(os.path.join(folder, f"{name}.pdf"), "wb") as handle:
                handle.write(pdf_design.render(html, name))

        return html


# -- what is frozen at the payment --------------------------------------------------


class TheFrozenSummary(ClassicTestCase):
    def test_two_months_paid_in_full(self):
        receipt = self.receipt(self.paid(amount="2000.00"))

        self.assertEqual(
            {"total": "2000.00", "discount": "0.00", "late_fee": "0.00", "paid_earlier": "0.00",
             "back_dues": "0.00", "old_fee": "0.00", "net": "2000.00", "till": "July"},
            figures(receipt),
        )
        self.assertEqual({D("1000.00")}, {line.charge_amount for line in receipt.allocations.all()})

    def test_a_later_month_paid_while_an_earlier_one_is_owed_carries_it_as_back_dues(self):
        july = self.due("Tuition - July")
        receipt = self.receipt(self.paid(amount="1000.00", allocations=[{"due_id": july.id, "amount": "1000.00"}]))

        self.assertEqual(("1000.00", "1000.00", "2000.00"), (
            str(receipt.summary_total), str(receipt.summary_back_dues), str(receipt.summary_net)))

    def test_installments_falling_due_after_the_month_are_not_counted(self):
        receipt = self.receipt(self.paid(amount="1000.00"))

        # April paid; July, October and January are still owed but come later.
        self.assertEqual(("April", "0.00", "1000.00"), (
            receipt.summary_till, str(receipt.summary_back_dues), str(receipt.summary_net)))

    def test_a_part_payment_keeps_the_full_charge_and_leaves_the_rest_as_dues(self):
        receipt = self.receipt(self.paid(amount="400.00"))

        self.assertEqual(("1000.00", "1000.00"), (str(receipt.summary_total), str(receipt.summary_net)))
        self.assertIn("600.00", self.html({"id": receipt.id}))

    def test_finishing_a_part_paid_month_counts_what_was_paid_earlier(self):
        self.paid(amount="400.00")
        receipt = self.receipt(self.paid(amount="600.00"))

        self.assertEqual(("1000.00", "400.00", "600.00"), (
            str(receipt.summary_total), str(receipt.summary_paid_earlier), str(receipt.summary_net)))
        self.assertIn("Paid Earlier", self.html({"id": receipt.id}))

    def test_a_discount_on_the_line_is_taken_off_the_net(self):
        StudentFeeDue.objects.filter(pk=self.due("Tuition - April").pk).update(discount_amount=D("150.00"))

        receipt = self.receipt(self.paid(amount="850.00"))

        self.assertEqual(("1000.00", "150.00", "850.00"), (
            str(receipt.summary_total), str(receipt.summary_discount), str(receipt.summary_net)))

    def test_a_late_fine_is_a_summary_figure_not_a_fee_line(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(
            settings={"late_fine_amount": 50, "late_fine_grace_days": 5}
        )
        call_command("apply_late_fines", stdout=io.StringIO())
        self.assertTrue(StudentFeeDue.objects.filter(student=self.aarav, kind=FeeDueKind.LATE_FINE).exists())

        april = self.due("Tuition - April")
        fine = StudentFeeDue.objects.get(student=self.aarav, kind=FeeDueKind.LATE_FINE)
        data = self.paid(amount="1050.00", allocations=[
            {"due_id": april.id, "amount": "1000.00"}, {"due_id": fine.id, "amount": "50.00"},
        ])
        receipt = self.receipt(data)

        self.assertEqual(("1000.00", "50.00", "1050.00"), (
            str(receipt.summary_total), str(receipt.summary_late_fee), str(receipt.summary_net)))
        html = self.html(data, "late-fine")
        self.assertNotIn("LATE FINE", html.split("Particulars")[1].split("Old Fee")[0].upper().replace("LATE FEE", ""))

    def test_an_earlier_years_fee_still_owed_is_old_fee(self):
        self.last_year()
        july = self.due("Tuition - July")

        receipt = self.receipt(self.paid(amount="1000.00", allocations=[{"due_id": july.id, "amount": "1000.00"}]))

        # February 2026's 500 from 2025-26; April's 1,000 is this year's back dues.
        self.assertEqual(("500.00", "1000.00", "2500.00"), (
            str(receipt.summary_old_fee), str(receipt.summary_back_dues), str(receipt.summary_net)))

    def test_paying_more_than_is_owed_shows_the_advance_and_no_negative_dues(self):
        data = self.paid(amount="5000.00")
        html = self.html(data, "advance")

        self.assertIn("Advance Held As Credit", html)
        self.assertNotIn("-1,000.00", html)

    def test_the_figures_do_not_move_when_the_account_does_later(self):
        data = self.paid(amount="1000.00")
        before = figures(self.receipt(data))

        # A discount given afterwards, and the next month paid.
        StudentFeeDue.objects.filter(pk=self.due("Tuition - April").pk).update(discount_amount=D("300.00"))
        self.paid(amount="1000.00")

        self.assertEqual(before, figures(self.receipt(data)))


# -- what the classic layout prints ------------------------------------------------


class TheLayout(ClassicTestCase):
    def test_month_wise_lines_and_the_installment_months_in_the_header(self):
        html = self.html(self.paid(amount="2000.00"), "two-months")

        self.assertIn("TUITION (APRIL)", html)
        self.assertIn("TUITION (JULY)", html)
        self.assertIn("Installment Month : APRIL - JULY", html)
        self.assertIn("Net Amount Till JULY", html)
        self.assertIn("Signature Of Accountant", html)

    def test_the_school_and_the_student_come_from_their_records(self):
        html = self.html(self.paid(amount="1000.00"))

        self.assertIn("SUNRISE PUBLIC SCHOOL", html)
        self.assertIn("ADM-1", html)
        self.assertIn("AARAV SHAH", html)
        self.assertIn("2026-27", html)
        self.assertIn("Class 8", html)

    def test_the_amount_in_words_reads_lakhs_for_rupees(self):
        html = self.html(self.paid(amount="2000.00"))

        self.assertIn("Indian Rupees Two Thousand Only", html)

    def test_the_bus_route_is_the_one_the_transport_fee_was_charged_for(self):
        self.published(ROUTE_A, route=self.route_a)
        self.ride(self.aarav, self.route_a, self.stop_a)

        html = self.html(self.paid(amount="1600.00"), "with-transport")

        self.assertIn("ROUTE A", html)
        self.assertIn("TRANSPORT (BUS 1)", html)

    def test_no_transport_no_route_line(self):
        self.assertNotIn(">Route<", self.html(self.paid(amount="1000.00")))

    def test_the_guardian_name(self):
        self.assertIn("Guardian Name", self.html(self.paid(amount="1000.00")))

    def test_remarks_carry_the_mode_and_reference(self):
        html = self.html(self.paid(amount="1000.00", payment_mode="upi", reference="UPI-778812"))

        self.assertIn("Remarks : UPI - UPI-778812", html)

    def test_a_long_name_and_address_still_render(self):
        self.aarav.first_name = "Venkatanarasimharajuvaripeta Subrahmanya"
        self.aarav.address = "House 42, Behind the Old Temple, " * 4
        self.aarav.save(update_fields=["first_name", "address"])

        data = self.paid(amount="1000.00")
        self.html(data, "long-name")

        self.assertTrue(pdf_design.render(receipt_classic.document(self.receipt(data)), "x").startswith(b"%PDF"))

    def test_a_cancelled_receipt_says_so(self):
        data = self.paid(amount="1000.00")
        self.cancel(data["id"])

        self.assertIn("CANCELLED", self.html(data, "cancelled"))


class OlderReceipts(ClassicTestCase):
    def test_a_receipt_from_before_the_summary_prints_what_it_froze_and_nothing_invented(self):
        data = self.paid(amount="1000.00")
        FeeReceipt.objects.filter(pk=data["id"]).update(
            summary_total=None, summary_discount=None, summary_late_fee=None, summary_paid_earlier=None,
            summary_back_dues=None, summary_old_fee=None, summary_net=None, summary_till=None,
        )
        receipt = self.receipt(data)

        html = self.html(data, "older-receipt")

        self.assertNotIn("Old Fee", html)
        self.assertNotIn("Back Dues", html)
        self.assertNotIn("Net Amount Till", html)
        # Its frozen balance before: all four installments, 4,000.
        self.assertEqual(D("4000.00"), receipt.balance_before)
        self.assertIn("4,000.00", html)
        self.assertIn("3,000.00", html)


# -- choosing the layout -------------------------------------------------------------


class ChoosingTheLayout(ClassicTestCase):
    def test_standard_is_the_default_and_unchanged(self):
        receipt = self.receipt(self.paid(amount="1000.00"))

        html = receipt_pdf.styled_document(receipt)

        self.assertIn("FEES PAID", html)
        self.assertNotIn("Signature Of Accountant", html)

    def test_a_school_that_chooses_classic_gets_it_everywhere_the_receipt_is_rendered(self):
        self.classic()
        data = self.paid(amount="1000.00")

        self.assertIn("Signature Of Accountant", receipt_pdf.styled_document(self.receipt(data)))

        response = self.as_user(self.accountant).get(f"/api/v1/fees/receipts/{data['id']}/pdf")
        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF"))

    def test_another_schools_choice_does_not_reach_this_one(self):
        other = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=other, module="fees")
        self.classic(school=other)

        self.assertIn("FEES PAID", receipt_pdf.styled_document(self.receipt(self.paid(amount="1000.00"))))

    def test_the_setting_is_offered_as_a_choice(self):
        response = self.as_user(self.admin).get("/api/v1/settings/modules")

        fees = next(row for row in response.data if row["module"] == "fees")
        schema = {row["key"]: row for row in fees["settings_schema"]}["receipt_style"]
        self.assertEqual("choice", schema["type"])
        self.assertEqual(
            [{"value": "standard", "label": "Standard"}, {"value": "classic", "label": "Classic printed"}],
            schema["choices"],
        )

    def test_the_admin_chooses_classic(self):
        response = self.as_user(self.admin).put(
            MODULE_SETTINGS, {"settings": {"receipt_style": "classic"}}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("classic", response.data["settings"]["receipt_style"])

    def test_a_value_that_is_not_one_of_the_choices_is_refused(self):
        response = self.as_user(self.admin).put(
            MODULE_SETTINGS, {"settings": {"receipt_style": "fancy"}}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("Fee receipt layout must be one of: Standard, Classic printed.", str(response.data))

    def test_an_accountant_may_not_change_the_layout(self):
        response = self.as_user(self.accountant).put(
            MODULE_SETTINGS, {"settings": {"receipt_style": "classic"}}, format="json"
        )

        self.assertEqual(403, response.status_code)


# -- the arithmetic on its own ------------------------------------------------------


class Due:
    def __init__(self, id, amount, due_date, *, year=1, discount="0", paid="0", kind="installment",
                 status="pending", label="Tuition - April"):
        self.id = id
        self.amount = D(amount)
        self.discount_amount = D(discount)
        self.paid_amount = D(paid)
        self.due_date = due_date
        self.academic_year_id = year
        self.kind = kind
        self.status = status
        self.label = label
        self.fee_installment = None
        self.fee_head = type("Head", (), {"name": "Tuition"})()


class TheArithmetic(SimpleTestCase):
    def summarize(self, paid, others=(), year=1):
        return receipt_summary.summarize(list(paid), list(others), year_id=year, receipt_date=dt.date(2026, 7, 15))

    def test_net_is_total_less_discount_plus_fine_less_paid_earlier_plus_back_and_old(self):
        summary = self.summarize(
            [Due(1, "1000", dt.date(2026, 7, 10), discount="100", paid="200", label="Tuition - July"),
             Due(2, "50", dt.date(2026, 7, 20), kind="late_fine")],
            [Due(3, "1000", dt.date(2026, 4, 10)), Due(4, "500", dt.date(2026, 2, 10), year=0),
             Due(5, "1000", dt.date(2026, 10, 10))],
        )

        self.assertEqual((D("1000"), D("100"), D("50"), D("200"), D("1000"), D("500")), (
            summary.total, summary.discount, summary.late_fee, summary.paid_earlier, summary.back_dues,
            summary.old_fee))
        self.assertEqual(D("2250"), summary.net)
        self.assertEqual("July", summary.till)

    def test_waived_and_cancelled_dues_owe_nothing(self):
        summary = self.summarize(
            [Due(1, "1000", dt.date(2026, 7, 10))],
            [Due(2, "1000", dt.date(2026, 4, 10), status="waived"), Due(3, "800", dt.date(2026, 5, 10),
                                                                       status="cancelled")],
        )

        self.assertEqual(D("0"), summary.back_dues)

    def test_a_payment_that_is_all_credit_runs_to_its_own_date(self):
        summary = self.summarize([], [Due(2, "1000", dt.date(2026, 4, 10))])

        self.assertEqual((None, D("1000")), (summary.till, summary.net))

    def test_nothing_owed_and_nothing_paid_is_zero_everywhere(self):
        summary = self.summarize([])

        self.assertEqual(D("0"), summary.net)
