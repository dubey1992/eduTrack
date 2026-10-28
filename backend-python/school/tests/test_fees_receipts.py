"""Taking money at the office (docs/fees.md, F3 "Collection & receipts"): how a
payment is spread or allocated, what it refuses, the numbering, cancelling,
how receipts and the F2 reconcile live together, the email and the PDF. Who
may do it, and the list, are test_fees_receipts_api.py.

Same school, year and frozen clock as test_fees_dues.py: 2026-27, "now" is
15 July 2026 in Kolkata, Class 8's Tuition is 1,000 due on 10 April, 10 July,
10 October and 10 January.
"""

import datetime as dt
import threading
import time
import types
from unittest import mock
from decimal import Decimal

from django.core import mail
from django.db import IntegrityError, connection, transaction
from django.test import SimpleTestCase, TransactionTestCase

from school import factories, queue
from school.enums import FeeDueStatus, UserRole
from school.fees import receipt_pdf
from school.fees.dues import FeeDueService
from school.fees.receipts import FeeReceiptService, number_for
from school.fees.words import amount_in_words
from school.models import (
    AcademicYear,
    AuditLog,
    FeeHead,
    FeeInstallment,
    FeeReceipt,
    FeeReceiptAllocation,
    FeeReceiptSequence,
    FeeStructure,
    QueuedJob,
    School,
    StudentFeeDue,
)

from .test_fees_dues import ROUTE_A, TUITION_8, TUITION_9, DuesTestCase

RECEIPTS = "/api/v1/fees/receipts"
MODULE_SETTINGS = "/api/v1/settings/modules/fees"


class ReceiptsTestCase(DuesTestCase):
    def setUp(self):
        super().setUp()
        self.aarav = self.student("Aarav", last_name="Shah", admission_number="ADM-1")
        self.tuition8 = self.published(TUITION_8, school_class=self.class8)

    def pay(self, student=None, amount="1000.00", allocations=None, user=None, **fields):
        body = {
            "student_id": (student or self.aarav).id,
            "receipt_date": "2026-07-15",
            "amount": amount,
            "payment_mode": "cash",
            **fields,
        }

        if allocations is not None:
            body["allocations"] = allocations

        return self.as_user(user or self.accountant).post(RECEIPTS, body, format="json")

    def paid(self, *args, **kwargs) -> dict:
        response = self.pay(*args, **kwargs)
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def refused(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]

    def due(self, label, student=None) -> StudentFeeDue:
        return StudentFeeDue.objects.get(student=student or self.aarav, label=label)

    def standing(self, student=None) -> list[tuple]:
        """(label, paid, status) for each of a student's dues, oldest first."""
        return [
            (due.label, str(due.paid_amount), due.status)
            for due in StudentFeeDue.objects.filter(student=student or self.aarav).order_by("due_date", "id")
        ]

    def cancel(self, receipt_id, reason="Entered against the wrong student", user=None):
        return self.as_user(user or self.accountant).post(
            f"{RECEIPTS}/{receipt_id}/cancel", {"reason": reason}, format="json"
        )

    def last_year(self):
        """2025-26, with a Class 7 Tuition of 500 due 10 February 2026 that
        Aarav still owes."""
        year = factories.AcademicYearFactory(
            school=self.school, name="2025-26", start_date=dt.date(2025, 4, 1), end_date=dt.date(2026, 3, 31),
            is_current=False,
        )
        class7 = factories.SchoolClassFactory(academic_year=year, name="Class 7", level=7)
        section7 = factories.ClassSectionFactory(school_class=class7, name="A")
        factories.StudentEnrollmentFactory(
            student=self.aarav, school=self.school, academic_year=year, school_class=class7, class_section=section7,
        )
        self.aarav.admission_date = dt.date(2025, 4, 1)
        self.aarav.save(update_fields=["admission_date"])
        self.fee([("February", dt.date(2026, 2, 10), "500.00")], school_class=class7, year=year, status="published")
        FeeDueService.sync_student(self.aarav, year)

        return year


# -- the receipt number ---------------------------------------------------------


class TheNumber(ReceiptsTestCase):
    def test_the_year_token_is_the_years_name_with_runs_of_anything_else_made_one_hyphen(self):
        for name, expected in (
            ("2026-27", "RCPT-2026-27-00001"),
            ("2026 / 27", "RCPT-2026-27-00001"),
            ("AY 2026--27 (main)", "RCPT-AY-2026-27-main-00001"),
            ("2026", "RCPT-2026-00001"),
        ):
            with self.subTest(name=name):
                self.assertEqual(expected, number_for(types.SimpleNamespace(name=name), 1))

        self.assertEqual("RCPT-2026-27-00042", number_for(self.year, 42))

    def test_numbers_are_sequential_and_a_refused_payment_uses_none(self):
        first = self.paid(amount="100.00")
        self.refused(self.pay(amount="99999.00"))
        second = self.paid(amount="100.00")

        self.assertEqual(["RCPT-2026-27-00001", "RCPT-2026-27-00002"],
                         [first["receipt_number"], second["receipt_number"]])
        self.assertEqual(2, FeeReceiptSequence.objects.get(school=self.school, academic_year=self.year).last_number)

    def test_a_cancelled_receipt_keeps_its_number_and_it_is_never_reused(self):
        first = self.paid(amount="100.00")
        self.assertEqual(200, self.cancel(first["id"]).status_code)

        second = self.paid(amount="100.00")

        self.assertEqual("RCPT-2026-27-00001", FeeReceipt.objects.get(pk=first["id"]).receipt_number)
        self.assertEqual("RCPT-2026-27-00002", second["receipt_number"])

    def test_numbers_belong_to_the_year_the_receipt_date_falls_in(self):
        last = self.last_year()

        old = self.paid(amount="100.00", receipt_date="2026-03-20")
        new = self.paid(amount="100.00")
        older = self.paid(amount="100.00", receipt_date="2025-12-01")

        self.assertEqual(
            [("RCPT-2025-26-00001", last.id), ("RCPT-2026-27-00001", self.year.id), ("RCPT-2025-26-00002", last.id)],
            [(row["receipt_number"], row["academic_year"]["id"]) for row in (old, new, older)],
        )

    def test_each_school_counts_on_its_own(self):
        other = factories.SchoolFactory(currency_code="INR", timezone="Asia/Kolkata")
        factories.ModuleSettingFactory(school=other, module="fees")
        other_year = factories.AcademicYearFactory(
            school=other, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        other_class = factories.SchoolClassFactory(academic_year=other_year, name="Class 8", level=8)
        other_section = factories.ClassSectionFactory(school_class=other_class)
        theirs = factories.StudentFactory(school=other, class_section=other_section, admission_date=dt.date(2026, 4, 1))
        factories.StudentEnrollmentFactory(student=theirs, school=other, academic_year=other_year,
                                           school_class=other_class, class_section=other_section)
        tuition = FeeHead.objects.create(school=other, name="Tuition")
        structure = FeeStructure.objects.create(
            school=other, academic_year=other_year, school_class=other_class, fee_head=tuition, amount="1000.00",
            currency_code="INR", frequency="yearly", status="published",
        )
        FeeInstallment.objects.create(fee_structure=structure, sequence=1, label="Year", due_date=dt.date(2026, 4, 10),
                                      amount="1000.00")
        FeeDueService.sync_student(theirs, other_year)
        their_accountant = factories.UserFactory(school=other, role=UserRole.ACCOUNTANT)

        self.paid(amount="100.00")
        self.paid(amount="100.00")
        theirs_first = self.paid(theirs, amount="100.00", user=their_accountant)

        self.assertEqual("RCPT-2026-27-00001", theirs_first["receipt_number"])

    def test_the_database_refuses_a_second_receipt_with_the_same_number_in_a_school(self):
        self.paid(amount="100.00")
        receipt = FeeReceipt.objects.get()
        receipt.pk = None

        with self.assertRaises(IntegrityError), transaction.atomic():
            receipt.save()


# -- spreading and choosing -------------------------------------------------------


class Spreading(ReceiptsTestCase):
    def test_a_payment_is_spread_oldest_first_across_years(self):
        self.last_year()

        data = self.paid(amount="1800.00")

        self.assertEqual(
            [
                ("Tuition - February", "500.00", "paid"),
                ("Tuition - April", "1000.00", "paid"),
                ("Tuition - July", "300.00", "partial"),
                ("Tuition - October", "0.00", "pending"),
                ("Tuition - January", "0.00", "pending"),
            ],
            self.standing(),
        )
        self.assertEqual(
            [("Tuition - February", "2026-02-10", "500.00"), ("Tuition - April", "2026-04-10", "1000.00"),
             ("Tuition - July", "2026-07-10", "300.00")],
            [(row["label"], row["due_date"], row["amount"]) for row in data["allocations"]],
        )
        self.assertEqual("2700.00", data["student_balance"])
        self.assertEqual("INR", data["currency_code"])

    def test_paying_more_than_is_owed_is_refused(self):
        errors = self.refused(self.pay(amount="4000.01"))

        self.assertEqual(
            ["This is more than Aarav Shah owes (INR 4,000.00). Advance payments are not taken."], errors["amount"]
        )
        self.assertFalse(FeeReceipt.objects.exists())

    def test_a_student_who_owes_nothing_cannot_pay(self):
        self.paid(amount="4000.00")

        self.assertEqual(["Aarav Shah owes nothing right now."], self.refused(self.pay(amount="1.00"))["amount"])

    def test_dues_in_two_currencies_are_never_added_together(self):
        StudentFeeDue.objects.filter(student=self.aarav, label="Tuition - January").update(currency_code="USD")

        errors = self.refused(self.pay(amount="100.00"))

        self.assertEqual(
            ["Aarav Shah owes in more than one currency (INR, USD). "
             "Choose the installments to pay, one currency at a time."],
            errors["allocations"],
        )


class Choosing(ReceiptsTestCase):
    def test_the_office_can_choose_what_each_installment_gets(self):
        july, october = self.due("Tuition - July"), self.due("Tuition - October")

        data = self.paid(amount="1200.00", allocations=[
            {"due_id": october.id, "amount": "200.00"}, {"due_id": july.id, "amount": "1000.00"},
        ])

        self.assertEqual(
            [("Tuition - April", "0.00", "pending"), ("Tuition - July", "1000.00", "paid"),
             ("Tuition - October", "200.00", "partial"), ("Tuition - January", "0.00", "pending")],
            self.standing(),
        )
        self.assertEqual([july.id, october.id], [row["due_id"] for row in data["allocations"]])

    def test_more_than_an_installment_has_left_is_refused(self):
        july = self.due("Tuition - July")
        self.paid(amount="250.00", allocations=[{"due_id": july.id, "amount": "250.00"}])

        errors = self.refused(self.pay(amount="800.00", allocations=[{"due_id": july.id, "amount": "800.00"}]))

        self.assertEqual(['Installment "Tuition - July" has only INR 750.00 left to pay.'], errors["allocations"])

    def test_another_students_installment_is_invalid(self):
        bina = self.student("Bina")
        FeeDueService.sync_student(bina, self.year)
        theirs = self.due("Tuition - July", bina)

        errors = self.refused(self.pay(amount="100.00", allocations=[{"due_id": theirs.id, "amount": "100.00"}]))

        self.assertEqual(["The selected installment is invalid."], errors["allocations"])
        self.assertEqual("0.00", str(StudentFeeDue.objects.get(pk=theirs.id).paid_amount))

    def test_paid_waived_and_cancelled_installments_cannot_be_paid(self):
        april, july, october = (self.due(f"Tuition - {month}") for month in ("April", "July", "October"))
        self.paid(amount="1000.00", allocations=[{"due_id": april.id, "amount": "1000.00"}])
        StudentFeeDue.objects.filter(pk=july.id).update(status=FeeDueStatus.WAIVED)
        StudentFeeDue.objects.filter(pk=october.id).update(status=FeeDueStatus.CANCELLED)

        errors = self.refused(self.pay(amount="300.00", allocations=[
            {"due_id": april.id, "amount": "100.00"}, {"due_id": july.id, "amount": "100.00"},
            {"due_id": october.id, "amount": "100.00"},
        ]))

        self.assertEqual(
            ['Installment "Tuition - April" is already paid.',
             'Installment "Tuition - July" was waived and can\'t be paid.',
             'Installment "Tuition - October" was cancelled and can\'t be paid.'],
            errors["allocations"],
        )

    def test_an_installment_listed_twice_is_refused(self):
        july = self.due("Tuition - July")

        errors = self.refused(self.pay(amount="200.00", allocations=[
            {"due_id": july.id, "amount": "100.00"}, {"due_id": july.id, "amount": "100.00"},
        ]))

        self.assertEqual(['Installment "Tuition - July" is listed more than once.'], errors["allocations"])

    def test_the_lines_must_add_up_to_the_payment(self):
        july = self.due("Tuition - July")

        errors = self.refused(self.pay(amount="1000.00", allocations=[{"due_id": july.id, "amount": "900.00"}]))

        self.assertEqual(
            ["The amounts against each installment add up to 900.00 but the payment is 1,000.00."],
            errors["allocations"],
        )

    def test_malformed_lines_are_named_by_position(self):
        errors = self.refused(self.pay(amount="100.00", allocations=[{"due_id": "x", "amount": "0"}]))

        self.assertEqual(["Line 1 needs an installment (due_id) and an amount more than zero."], errors["allocations"])
        self.assertIn("allocations", self.refused(self.pay(amount="100.00", allocations=[])))

    def test_installments_in_two_currencies_cannot_share_a_receipt(self):
        july, october = self.due("Tuition - July"), self.due("Tuition - October")
        StudentFeeDue.objects.filter(pk=october.id).update(currency_code="USD")

        errors = self.refused(self.pay(amount="200.00", allocations=[
            {"due_id": july.id, "amount": "100.00"}, {"due_id": october.id, "amount": "100.00"},
        ]))

        self.assertEqual(["Every installment on one receipt must be in the same currency."], errors["allocations"])

    def test_the_receipt_takes_the_currency_of_the_dues_it_pays(self):
        october = self.due("Tuition - October")
        StudentFeeDue.objects.filter(pk=october.id).update(currency_code="USD")

        data = self.paid(amount="100.00", allocations=[{"due_id": october.id, "amount": "100.00"}])

        self.assertEqual("USD", data["currency_code"])


class PartPayments(ReceiptsTestCase):
    def switch_off(self):
        response = self.as_user(self.admin).put(
            MODULE_SETTINGS, {"settings": {"allow_part_payment": False}}, format="json"
        )
        self.assertEqual(200, response.status_code, response.data)

    def test_part_payments_are_allowed_by_default(self):
        self.paid(amount="500.00")

        self.assertEqual(("500.00", "partial"), self.standing()[0][1:])

    def test_switched_off_a_payment_must_settle_every_installment_it_touches(self):
        self.switch_off()
        july = self.due("Tuition - July")

        message = "Part payments are switched off for this school - pay each installment in full."
        self.assertEqual([message], self.refused(self.pay(amount="1500.00"))["amount"])
        self.assertEqual(
            [message],
            self.refused(self.pay(amount="500.00", allocations=[{"due_id": july.id, "amount": "500.00"}]))[
                "allocations"
            ],
        )

        self.paid(amount="2000.00")
        self.assertEqual(
            [("Tuition - April", "1000.00", "paid"), ("Tuition - July", "1000.00", "paid")], self.standing()[:2]
        )

    def test_switched_off_the_rest_of_a_part_paid_installment_may_still_be_paid(self):
        self.paid(amount="400.00")
        self.switch_off()

        self.paid(amount="600.00")

        self.assertEqual(("1000.00", "paid"), self.standing()[0][1:])


# -- what the form must hold --------------------------------------------------------


class TheForm(ReceiptsTestCase):
    def test_every_required_field_is_named(self):
        response = self.as_user(self.accountant).post(RECEIPTS, {}, format="json")

        errors = self.refused(response)
        self.assertEqual({"student_id", "amount", "receipt_date", "payment_mode"}, set(errors))

    def test_a_date_in_the_schools_future_is_refused(self):
        self.assertEqual(
            ["The receipt date can't be in the future."], self.refused(self.pay(receipt_date="2026-07-16"))["receipt_date"]
        )
        self.assertIn("receipt_date", self.refused(self.pay(receipt_date="15/07/2026")))

    def test_a_date_no_academic_year_covers_is_refused(self):
        self.assertEqual(
            ["No academic year covers this date. Add one under Academic Years first."],
            self.refused(self.pay(receipt_date="2026-03-31"))["receipt_date"],
        )

    def test_a_cheque_needs_its_number_and_the_mode_must_be_known(self):
        self.assertEqual(["Enter the cheque number."], self.refused(self.pay(payment_mode="cheque"))["reference"])
        self.assertIn("payment_mode", self.refused(self.pay(payment_mode="bitcoin")))

        data = self.paid(payment_mode="cheque", reference="000123", note="Drawn on SBI")

        self.assertEqual(("cheque", "Cheque", "000123", "Drawn on SBI"),
                         (data["payment_mode"], data["payment_mode_label"], data["reference"], data["note"]))

    def test_lengths_and_amounts(self):
        errors = self.refused(self.pay(amount="0", reference="x" * 101, note="y" * 501))

        self.assertEqual({"amount", "reference", "note"}, set(errors))
        self.assertIn("amount", self.refused(self.pay(amount="10.001")))

    def test_every_mode_is_accepted_with_its_label(self):
        labels = {}

        for mode in ("cash", "bank_transfer", "upi", "card", "online_transfer"):
            labels[mode] = self.paid(amount="10.00", payment_mode=mode)["payment_mode_label"]

        self.assertEqual(
            {"cash": "Cash", "bank_transfer": "Bank Transfer", "upi": "UPI", "card": "Card",
             "online_transfer": "Online Transfer"},
            labels,
        )


# -- the receipt itself --------------------------------------------------------------


class TheReceipt(ReceiptsTestCase):
    def test_the_resource_says_everything_the_screen_shows(self):
        data = self.paid(amount="1500.00", note="Paid by father")

        self.assertEqual(
            {
                "receipt_number": "RCPT-2026-27-00001", "receipt_date": "2026-07-15", "amount": "1500.00",
                "currency_code": "INR", "payment_mode": "cash", "payment_mode_label": "Cash", "reference": None,
                "note": "Paid by father", "status": "valid",
                "student": {"id": self.aarav.id, "name": "Aarav Shah", "admission_number": "ADM-1",
                            "class_name": "Class 8", "section_name": "A"},
                "academic_year": {"id": self.year.id, "name": "2026-27"},
                "received_by": {"id": self.accountant.id, "name": self.accountant.name},
                "cancelled_at": None, "cancelled_by": None, "cancel_reason": None, "emailed_at": None,
                "balance_before": "4000.00", "balance_after": "2500.00", "student_balance": "2500.00",
                "email_queued": False,
            },
            {key: value for key, value in data.items() if key not in ("id", "allocations", "created_at")},
        )
        self.assertIsNotNone(data["created_at"])

    def test_recording_one_is_audited(self):
        data = self.paid(amount="1500.00")

        entry = AuditLog.objects.get(action="fee_receipt.created")
        april, july = self.due("Tuition - April"), self.due("Tuition - July")
        self.assertEqual(("fees", "fee_receipt", data["id"], self.school.id, self.accountant.id),
                         (entry.module, entry.entity_type, entry.entity_id, entry.school_id, entry.user_id))
        self.assertEqual(
            {"receipt_number": "RCPT-2026-27-00001", "amount": "1500.00", "currency_code": "INR",
             "payment_mode": "cash",
             "allocations": [{"due_id": april.id, "amount": "1000.00"}, {"due_id": july.id, "amount": "500.00"}]},
            entry.new_values,
        )

    def test_the_statement_lists_the_years_receipts_newest_first(self):
        first = self.paid(amount="100.00", receipt_date="2026-07-01")
        second = self.paid(amount="200.00", payment_mode="upi")
        self.cancel(first["id"])

        data = self.as_user(self.accountant).get(f"/api/v1/fees/students/{self.aarav.id}").data

        self.assertEqual(
            [
                {"id": second["id"], "receipt_number": "RCPT-2026-27-00002", "receipt_date": "2026-07-15",
                 "amount": "200.00", "payment_mode_label": "UPI", "status": "valid"},
                {"id": first["id"], "receipt_number": "RCPT-2026-27-00001", "receipt_date": "2026-07-01",
                 "amount": "100.00", "payment_mode_label": "Cash", "status": "cancelled"},
            ],
            data["receipts"],
        )
        self.assertEqual("200.00", data["totals"]["paid"])


# -- cancelling ------------------------------------------------------------------------


class Cancelling(ReceiptsTestCase):
    def test_cancelling_puts_the_money_back_on_the_dues_and_keeps_the_receipt(self):
        first = self.paid(amount="1500.00")
        self.paid(amount="300.00")

        response = self.cancel(first["id"], reason="  Cheque bounced  ")

        self.assertEqual(200, response.status_code, response.data)
        data = response.data
        self.assertEqual(("cancelled", "Cheque bounced", {"id": self.accountant.id, "name": self.accountant.name}),
                         (data["status"], data["cancel_reason"], data["cancelled_by"]))
        self.assertIsNotNone(data["cancelled_at"])
        self.assertEqual("RCPT-2026-27-00001", data["receipt_number"])
        self.assertEqual(2, len(data["allocations"]), "the allocations are kept")
        self.assertEqual(2, FeeReceiptAllocation.objects.filter(fee_receipt_id=first["id"]).count())
        # The second receipt had paid 300 more on July; that stays.
        self.assertEqual(
            [("Tuition - April", "0.00", "pending"), ("Tuition - July", "300.00", "partial"),
             ("Tuition - October", "0.00", "pending"), ("Tuition - January", "0.00", "pending")],
            self.standing(),
        )
        self.assertEqual("3700.00", data["student_balance"])

    def test_cancelling_twice_is_a_conflict(self):
        first = self.paid(amount="100.00")
        self.cancel(first["id"])

        response = self.cancel(first["id"])

        self.assertEqual(409, response.status_code)
        self.assertEqual("FEE_RECEIPT_CANCELLED", response.data["code"])
        self.assertEqual("This receipt is already cancelled.", response.data["message"])
        self.assertEqual(("0.00", "pending"), self.standing()[0][1:])

    def test_a_reason_is_required(self):
        first = self.paid(amount="100.00")

        for reason in (None, "", "ab", "x" * 501):
            with self.subTest(reason=reason):
                body = {} if reason is None else {"reason": reason}
                response = self.as_user(self.accountant).post(f"{RECEIPTS}/{first['id']}/cancel", body, format="json")
                self.assertIn("reason", self.refused(response))

        self.assertEqual("valid", FeeReceipt.objects.get(pk=first["id"]).status)

    def test_cancelling_is_audited_with_before_and_after(self):
        first = self.paid(amount="100.00")
        self.cancel(first["id"], reason="Typed the wrong amount")

        entry = AuditLog.objects.get(action="fee_receipt.cancelled")
        april = self.due("Tuition - April")
        self.assertEqual({"status": "valid"}, entry.old_values)
        self.assertEqual(
            {"status": "cancelled", "receipt_number": "RCPT-2026-27-00001", "reason": "Typed the wrong amount",
             "allocations": [{"due_id": april.id, "amount": "100.00"}]},
            entry.new_values,
        )

    def test_a_cancelled_or_waived_due_keeps_its_status_and_only_its_paid_amount_moves(self):
        october = self.due("Tuition - October")
        first = self.paid(amount="400.00", allocations=[{"due_id": october.id, "amount": "400.00"}])
        StudentFeeDue.objects.filter(pk=october.id).update(status=FeeDueStatus.WAIVED)

        self.cancel(first["id"])

        october.refresh_from_db()
        self.assertEqual((Decimal("0.00"), "waived"), (october.paid_amount, october.status))


# -- receipts and the F2 reconcile ---------------------------------------------------------


class AndTheReconcile(ReceiptsTestCase):
    def test_a_class_change_keeps_a_part_paid_future_installment(self):
        october = self.due("Tuition - October")
        self.paid(amount="400.00", allocations=[{"due_id": october.id, "amount": "400.00"}])
        self.published(TUITION_9, school_class=self.class9)

        self.patch_student(self.aarav, {"class_section_id": self.section9.id})

        october.refresh_from_db()
        self.assertEqual((Decimal("400.00"), "partial", None), (october.paid_amount, october.status,
                                                                  october.cancelled_reason))
        # The untouched January line is cancelled as F2 always did.
        self.assertEqual("cancelled", self.due("Tuition - January").status)

    def test_editing_the_fee_never_takes_an_installment_below_what_was_paid(self):
        july = self.due("Tuition - July")
        self.paid(amount="700.00", allocations=[{"due_id": july.id, "amount": "700.00"}])
        rows = [dict(label=label, due_date=due.isoformat(), amount="500.00" if label == "July" else amount)
                for label, due, amount in TUITION_8]

        response = self.as_user(self.accountant).put(
            f"/api/v1/fees/structures/{self.tuition8.id}",
            {"amount": "3500.00", "frequency": "term", "installments": rows}, format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        july.refresh_from_db()
        # Cut to 500, it stays at the 700 paid - and is now settled.
        self.assertEqual((Decimal("700.00"), Decimal("700.00"), "paid"), (july.amount, july.paid_amount, july.status))

    def test_cancelling_after_a_move_lets_the_reconcile_cancel_the_unpaid_future_line(self):
        october, july = self.due("Tuition - October"), self.due("Tuition - July")
        receipt = self.paid(amount="1400.00", allocations=[
            {"due_id": october.id, "amount": "1000.00"}, {"due_id": july.id, "amount": "400.00"},
        ])
        self.published(TUITION_9, school_class=self.class9)
        self.patch_student(self.aarav, {"class_section_id": self.section9.id})
        self.assertEqual("paid", self.due("Tuition - October").status, "paid, so the move left it alone")

        self.cancel(receipt["id"])

        october.refresh_from_db()
        july.refresh_from_db()
        # October falls due after today and is no longer Aarav's class's fee.
        self.assertEqual(("cancelled", "class_changed", Decimal("0.00")),
                         (october.status, october.cancelled_reason, october.paid_amount))
        # July was due before the move, so it stays owed.
        self.assertEqual(("pending", Decimal("0.00")), (july.status, july.paid_amount))
        self.assertTrue(AuditLog.objects.filter(action="fee_dues.synced", entity_type="fee_receipt",
                                                entity_id=receipt["id"]).exists())

    def test_a_route_fee_is_paid_like_any_other(self):
        self.published(ROUTE_A, route=self.route_a)
        self.ride(self.aarav, self.route_a, self.stop_a)

        self.paid(amount="1600.00")

        # Both due on 10 April: the older line (Tuition, charged first) first.
        self.assertEqual(
            [("Tuition - April", "1000.00", "paid"), ("Transport - Bus 1", "600.00", "paid")], self.standing()[:2]
        )


# -- the email and the PDF -------------------------------------------------------------------


class TheEmail(ReceiptsTestCase):
    def jobs(self):
        return QueuedJob.objects.filter(name="fee_receipt_email")

    def test_ticking_email_queues_it_when_the_guardian_has_an_address(self):
        self.aarav.guardian_email = "meera@example.com"
        self.aarav.save(update_fields=["guardian_email"])

        data = self.paid(amount="100.00", email_to_guardian=True)

        self.assertTrue(data["email_queued"])
        self.assertEqual([{"receipt_id": data["id"]}], [job.payload for job in self.jobs()])

        self.assertEqual({"done": 1, "failed": 0}, queue.work())
        self.assertEqual(["meera@example.com"], mail.outbox[0].to)
        self.assertIn("RCPT-2026-27-00001", mail.outbox[0].subject)
        name, content, kind = mail.outbox[0].attachments[0]
        self.assertEqual(("RCPT-2026-27-00001.pdf", "application/pdf"), (name, kind))
        self.assertTrue(content.startswith(b"%PDF-"))
        self.assertIsNotNone(FeeReceipt.objects.get(pk=data["id"]).emailed_at)

    def test_without_an_address_nothing_is_queued_and_the_answer_says_so(self):
        data = self.paid(amount="100.00", email_to_guardian=True)

        self.assertFalse(data["email_queued"])
        self.assertFalse(self.jobs().exists())

    def test_not_ticked_nothing_is_queued(self):
        self.aarav.guardian_email = "meera@example.com"
        self.aarav.save(update_fields=["guardian_email"])

        self.assertFalse(self.paid(amount="100.00")["email_queued"])
        self.assertFalse(self.jobs().exists())

    def test_emailing_later_needs_a_guardian_address(self):
        data = self.paid(amount="100.00")

        response = self.as_user(self.accountant).post(f"{RECEIPTS}/{data['id']}/email")

        self.assertEqual(["This student has no guardian email address."], self.refused(response)["guardian_email"])

        self.aarav.guardian_email = "meera@example.com"
        self.aarav.save(update_fields=["guardian_email"])
        response = self.as_user(self.accountant).post(f"{RECEIPTS}/{data['id']}/email")

        self.assertEqual(202, response.status_code)
        self.assertEqual({"queued": True}, response.data)
        self.assertEqual(1, self.jobs().count())

    def test_the_job_sends_nothing_when_the_address_was_removed_since(self):
        self.aarav.guardian_email = "meera@example.com"
        self.aarav.save(update_fields=["guardian_email"])
        data = self.paid(amount="100.00", email_to_guardian=True)
        self.aarav.guardian_email = None
        self.aarav.save(update_fields=["guardian_email"])

        queue.work()

        self.assertEqual([], mail.outbox)
        self.assertIsNone(FeeReceipt.objects.get(pk=data["id"]).emailed_at)


class ThePdf(ReceiptsTestCase):
    def test_it_downloads_as_a_pdf_named_by_its_number(self):
        data = self.paid(amount="100.00")

        response = self.as_user(self.accountant).get(f"{RECEIPTS}/{data['id']}/pdf")

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertEqual('attachment; filename="RCPT-2026-27-00001.pdf"', response["Content-Disposition"])
        self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_it_carries_every_detail_of_the_school_the_student_and_the_payment(self):
        School.objects.filter(pk=self.school.id).update(registration_number="CBSE/2019/04512")
        self.aarav.roll_number = "14"
        self.aarav.guardian_name = "Meera Shah"
        self.aarav.guardian_mobile = "+91 98200 12345"
        self.aarav.save()
        data = self.paid(amount="1500.50", payment_mode="cheque", reference="000123", note="Paid at the desk")

        document = receipt_pdf.document(FeeReceiptService.load(data["id"]))

        for text in (
            "Sunrise Public School", "1 Test Road", "Testing", "000000", "Phone +91 9000000000",
            "Reg. no. CBSE/2019/04512", "FEE RECEIPT", "RCPT-2026-27-00001", "07/15/2026", "2026-27",
            "Cheque 000123", self.accountant.name, "Aarav Shah", "ADM-1", "Class 8 - A", "14", "Meera Shah",
            # The fee type and the installment sit in columns of their own, so
            # the installment is printed without the "Tuition - " prefix.
            "+91 98200 12345", "<td>Tuition</td><td>April</td>", "04/10/2026", "INR 1,000.00",
            "<td>Tuition</td><td>July</td>", "07/10/2026",
            "INR 500.50", "Total received", "INR 1,500.50",
            "Indian Rupees One Thousand Five Hundred and Fifty Paise Only",
            "Owed before this payment", "INR 4,000.00", "Paid now", "Still owed after this payment",
            "INR 2,499.50", "Paid at the desk", "This is a computer-generated receipt and needs no signature.",
            "Issued 07/15/2026 11:30 AM (Asia/Kolkata)", "Powered by School365ai",
        ):
            self.assertIn(text, document)

        self.assertNotIn("CANCELLED", document)

    def test_empty_optional_details_are_left_out_never_printed_as_none(self):
        School.objects.filter(pk=self.school.id).update(
            address="", city="", state="", postal_code="", country="", phone="", registration_number=None,
            logo_url=None,
        )
        self.aarav.roll_number = None
        self.aarav.guardian_mobile = None
        self.aarav.save()
        data = self.paid(amount="100.00")

        document = receipt_pdf.document(FeeReceiptService.load(data["id"]))

        for absent in ("None", "Reg. no.", "Roll no.", "Guardian mobile", "Phone", "Note", "<img"):
            self.assertNotIn(absent, document)

        self.assertTrue(receipt_pdf.render(FeeReceiptService.load(data["id"])).startswith(b"%PDF-"))

    def test_the_balances_are_the_ones_frozen_on_the_receipt(self):
        first = self.paid(amount="1000.00")
        self.paid(amount="500.00")

        # A later payment moves the account, not what the first receipt says.
        data = self.as_user(self.accountant).get(f"{RECEIPTS}/{first['id']}").data
        document = receipt_pdf.document(FeeReceiptService.load(first["id"]))

        self.assertEqual(("4000.00", "3000.00", "2500.00"),
                         (data["balance_before"], data["balance_after"], data["student_balance"]))
        self.assertIn("INR 4,000.00", document)
        self.assertIn("INR 3,000.00", document)

    def test_a_logo_that_cannot_be_fetched_costs_only_the_logo(self):
        School.objects.filter(pk=self.school.id).update(logo_url="https://logo.invalid/school.png")
        data = self.paid(amount="100.00")

        with mock.patch("urllib.request.urlopen", side_effect=OSError("unreachable")),                 self.assertLogs("school.fees.receipt_pdf", "WARNING"):
            pdf = receipt_pdf.render(FeeReceiptService.load(data["id"]))

        self.assertTrue(pdf.startswith(b"%PDF-"))
        self.assertIsNone(receipt_pdf.logo_data_uri("file:///etc/passwd"))

    def test_a_cancelled_one_is_stamped_with_its_reason_who_and_when(self):
        data = self.paid(amount="100.00")
        self.cancel(data["id"], reason="Cheque <bounced>")

        document = receipt_pdf.document(FeeReceiptService.load(data["id"]))

        for text in ("CANCELLED", "Reason: Cheque &lt;bounced&gt;",
                     f"Cancelled by {self.accountant.name}, on 07/15/2026 11:30 AM", "INR 100.00"):
            self.assertIn(text, document)

        self.assertTrue(receipt_pdf.render(FeeReceiptService.load(data["id"])).startswith(b"%PDF-"))


class AmountInWords(SimpleTestCase):
    def test_whole_amounts_with_the_currency_name(self):
        for value, code, expected in (
            ("2000", "INR", "Indian Rupees Two Thousand Only"),
            ("0", "USD", "US Dollars Zero Only"),
            ("1", "GBP", "Pounds Sterling One Only"),
            ("15", "INR", "Indian Rupees Fifteen Only"),
            ("101", "INR", "Indian Rupees One Hundred One Only"),
            ("1234567", "USD", "US Dollars One Million Two Hundred Thirty-Four Thousand Five Hundred Sixty-Seven Only"),
            ("9999999999.99", "INR",
             "Indian Rupees Nine Billion Nine Hundred Ninety-Nine Million Nine Hundred Ninety-Nine Thousand "
             "Nine Hundred Ninety-Nine and Ninety-Nine Paise Only"),
        ):
            with self.subTest(value=value):
                self.assertEqual(expected, amount_in_words(Decimal(value), code))

    def test_the_minor_unit(self):
        self.assertEqual("Indian Rupees Two Thousand and Fifty Paise Only", amount_in_words(Decimal("2000.50"), "INR"))
        self.assertEqual("US Dollars Twelve and Five Cents Only", amount_in_words(Decimal("12.05"), "USD"))
        self.assertEqual("Nigerian Naira Zero and Ninety Kobo Only", amount_in_words(Decimal("0.90"), "NGN"))

    def test_an_unknown_code_is_printed_as_itself(self):
        self.assertEqual("XYZ Seven and Twenty Hundredths Only", amount_in_words(Decimal("7.20"), "XYZ"))

    def test_out_of_range_is_refused(self):
        for value in ("-1", "10000000000"):
            with self.assertRaises(ValueError):
                amount_in_words(Decimal(value), "INR")


# -- two clerks at once -------------------------------------------------------------------------


class TwoClerksAtOnce(TransactionTestCase):
    """Committed transactions on real connections, so the row lock is
    really taken: the second payment waits for the first and gets the next
    number - never the same one, never a gap."""

    def setUp(self):
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )

    def tearDown(self):
        # Removed by hand: in a --parallel worker the test runner's managed
        # flip has not happened, so the flush after a TransactionTestCase
        # skips these tables and the rows would outlive the test.
        FeeReceiptSequence.objects.filter(school=self.school).delete()
        AcademicYear.objects.filter(school=self.school).delete()
        School.objects.filter(pk=self.school.pk).delete()

    def take_numbers(self, hold_first: float) -> list[tuple[str, float]]:
        """Two transactions take a number each. The first holds its lock for
        `hold_first` seconds before committing. Returns each one's number and
        how long taking it took."""
        results: dict[str, tuple[str, float]] = {}
        first_has_it = threading.Event()

        def clerk(name: str) -> None:
            try:
                if name == "second":
                    first_has_it.wait(5)

                with transaction.atomic():
                    started = time.monotonic()
                    number = FeeReceiptService.next_number(self.school.id, self.year)
                    took = time.monotonic() - started

                    if name == "first":
                        first_has_it.set()
                        time.sleep(hold_first)

                results[name] = (number, took)
            finally:
                connection.close()

        threads = [threading.Thread(target=clerk, args=(name,)) for name in ("first", "second")]

        for thread in threads:
            thread.start()

        for thread in threads:
            thread.join(15)

        return [results["first"], results["second"]]

    def test_the_second_waits_for_the_first_and_takes_the_next_number(self):
        # No counter row yet: both race to create it, too.
        (first, _), (second, waited) = self.take_numbers(hold_first=0.8)

        self.assertEqual(("RCPT-2026-27-00001", "RCPT-2026-27-00002"), (first, second))
        self.assertGreater(waited, 0.5, "the second number was taken only once the first committed")
        self.assertEqual(
            [(self.year.id, 2)],
            list(FeeReceiptSequence.objects.filter(school=self.school).values_list("academic_year_id", "last_number")),
        )

    def test_with_the_counter_already_there(self):
        FeeReceiptSequence.objects.create(school=self.school, academic_year=self.year, last_number=7)

        (first, _), (second, waited) = self.take_numbers(hold_first=0.8)

        self.assertEqual(("RCPT-2026-27-00008", "RCPT-2026-27-00009"), (first, second))
        self.assertGreater(waited, 0.5)

    def test_a_number_taken_by_a_payment_that_fails_is_given_back(self):
        with self.assertRaises(RuntimeError), transaction.atomic():
            FeeReceiptService.next_number(self.school.id, self.year)
            raise RuntimeError("the payment failed after taking its number")

        with transaction.atomic():
            self.assertEqual("RCPT-2026-27-00001", FeeReceiptService.next_number(self.school.id, self.year))

