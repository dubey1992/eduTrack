"""A parent's view of their child's fees (docs/parent-student-app.md, F3).

What this file guards that a quick read would not:

- **The same numbers as the office.** The Family app's fees come from the
  staff ledger, so totals and balances match the accounts clerk's statement.
- **A parent's words for each instalment:** paid, part paid, due, overdue,
  waived. A cancelled instalment is not the family's concern and is left out;
  a cancelled receipt is shown, marked cancelled.
- **Only their own child's.** Another child's fees, and another child's
  receipt even through their own child's address, are a 404.
- **Both switches.** The Family App module and the Fees module must be on.
- **How to pay is the school's own words**, from its Fees settings, and a
  UPI ID the school types must look like one.
"""

import datetime as dt
from decimal import Decimal

from django.utils import timezone

from school import factories
from school.models import FeeHead, FeeReceipt, ModuleSetting, StudentFeeDue
from school.tests.test_family_f1_api import FAMILY, FamilyAppTest


class FeesTest(FamilyAppTest):
    def setUp(self):
        super().setUp()
        self.year.is_current = True
        self.year.save(update_fields=["is_current"])
        ModuleSetting.objects.update_or_create(
            school=self.school, module="fees",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {},
                      "created_at": timezone.now(), "updated_at": timezone.now()},
        )
        self.head = FeeHead.objects.create(school=self.school, name="Tuition", created_at=timezone.now(),
                                           updated_at=timezone.now())

    def due(self, label, days, amount, paid="0", status=None, student=None):
        if status is None:
            status = "paid" if paid == amount else ("partial" if Decimal(paid) > 0 else "pending")
        return StudentFeeDue.objects.create(
            school=self.school, student=student or self.child, academic_year=self.year, fee_head=self.head,
            label=label, due_date=self.today() + dt.timedelta(days=days), amount=Decimal(amount),
            paid_amount=Decimal(paid), currency_code="INR", status=status,
            created_at=timezone.now(), updated_at=timezone.now(),
        )

    def receipt(self, number, amount, student=None, status="valid"):
        return FeeReceipt.objects.create(
            school=self.school, student=student or self.child, academic_year=self.year, receipt_number=number,
            receipt_date=self.today(), amount=Decimal(amount), currency_code="INR", payment_mode="cash",
            received_by=self.admin, status=status, created_at=timezone.now(),
        )

    def fees(self, child=None):
        response = self.parent.get(f"{FAMILY}/children/{(child or self.child).id}/fees")
        self.assertEqual(200, response.status_code, getattr(response, "data", None))
        return response.data


class AParentSeesEachInstalment(FeesTest):
    def test_each_instalment_says_where_it_stands(self):
        self.due("Term 1", -40, "5000.00", paid="5000.00")
        self.due("Term 2", -5, "5000.00", paid="1000.00")
        self.due("Term 3", 20, "5000.00", paid="2000.00")
        self.due("Term 4", 60, "5000.00")
        self.due("Sports", -10, "800.00", status="waived")

        data = self.fees()

        self.assertEqual(
            [("Term 1", "paid"), ("Sports", "waived"), ("Term 2", "overdue"), ("Term 3", "part_paid"),
             ("Term 4", "due")],
            [(line["label"], line["status"]) for line in data["installments"]],
        )
        self.assertEqual(("4000.00", "3000.00"),
                         (data["installments"][2]["balance"], data["installments"][3]["balance"]))

    def test_the_totals_are_the_offices(self):
        self.due("Term 1", -40, "5000.00", paid="5000.00")
        self.due("Term 2", -5, "5000.00", paid="1000.00")
        self.due("Term 3", 20, "5000.00")

        totals = self.fees()["totals"]

        self.assertEqual(
            {"charged": "15000.00", "discount": "0.00", "paid": "6000.00", "balance": "9000.00",
             "overdue": "4000.00"},
            totals,
        )

    def test_a_cancelled_instalment_is_left_out(self):
        self.due("Term 1", 10, "5000.00")
        self.due("Bus", 10, "1200.00", status="cancelled")

        self.assertEqual(["Term 1"], [line["label"] for line in self.fees()["installments"]])

    def test_a_child_with_no_year_has_nothing_owed(self):
        self.year.delete()

        data = self.fees()

        self.assertEqual((None, [], []), (data["academic_year"], data["installments"], data["receipts"]))


class AParentSeesReceipts(FeesTest):
    def test_every_receipt_of_the_year_a_cancelled_one_marked(self):
        self.receipt("R-0001", "5000.00")
        self.receipt("R-0002", "300.00", status="cancelled")

        receipts = {line["number"]: line["cancelled"] for line in self.fees()["receipts"]}

        self.assertEqual({"R-0001": False, "R-0002": True}, receipts)

    def test_the_receipt_and_the_statement_download_as_pdfs(self):
        self.due("Term 1", -40, "5000.00", paid="5000.00")
        receipt = self.receipt("R-0001", "5000.00")

        for path in (f"children/{self.child.id}/receipts/{receipt.id}/pdf",
                     f"children/{self.child.id}/fees/statement.pdf"):
            with self.subTest(path=path):
                response = self.parent.get(f"{FAMILY}/{path}")
                self.assertEqual(200, response.status_code)
                self.assertEqual("application/pdf", response["Content-Type"])
                self.assertTrue(response.content.startswith(b"%PDF"))


class AParentSeesOnlyTheirOwnChildsFees(FeesTest):
    def test_another_familys_child_is_not_found(self):
        other = self.other_family_child()

        for path in (f"children/{other.id}/fees", f"children/{other.id}/fees/statement.pdf"):
            with self.subTest(path=path):
                self.assertEqual(404, self.parent.get(f"{FAMILY}/{path}").status_code)

    def test_another_childs_receipt_is_not_found_through_their_own_child(self):
        other = self.other_family_child()
        theirs = self.receipt("R-0009", "100.00", student=other)

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/receipts/{theirs.id}/pdf")

        self.assertEqual(404, response.status_code)

    def test_a_staff_session_is_refused(self):
        response = self.as_user(self.admin).get(f"{FAMILY}/children/{self.child.id}/fees")

        self.assertEqual(403, response.status_code)
        self.assertEqual("NOT_A_FAMILY_ACCOUNT", response.data["code"])

    def test_the_fees_module_switched_off_shows_nothing(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/fees")

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_the_family_app_switched_off_shows_nothing(self):
        ModuleSetting.objects.filter(school=self.school, module="family_app").update(school_enabled=False)

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/fees")

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])


class HowToPay(FeesTest):
    def save_settings(self, **settings):
        return self.as_user(self.admin).put("/api/v1/settings/modules/fees", {"settings": settings},
                                              format="json")

    def test_the_schools_own_words_reach_the_parent(self):
        self.school.phone = "+91 80 4000 1234"
        self.school.save(update_fields=["phone"])
        response = self.save_settings(pay_counter_hours="Mon-Sat, 9 am to 1 pm", pay_upi_id="greenfield@okaxis",
                                      pay_bank_details="Greenfield School\nA/c 1234567890, IFSC HDFC0001234")
        self.assertEqual(200, response.status_code, response.data)

        pay = self.fees()["how_to_pay"]

        self.assertEqual(
            {"counter_hours": "Mon-Sat, 9 am to 1 pm", "upi_id": "greenfield@okaxis",
             "bank_details": "Greenfield School\nA/c 1234567890, IFSC HDFC0001234",
             "office_phone": "+91 80 4000 1234"},
            pay,
        )

    def test_a_upi_app_is_told_whom_to_pay_and_whose_fees_they_are(self):
        data = self.fees()

        self.assertEqual(self.school.name, data["payee_name"])
        self.assertEqual(f"Fees - {self.child.name} ({self.child.admission_number})", data["payment_note"])

    def test_what_the_school_left_empty_is_not_shown(self):
        pay = self.fees()["how_to_pay"]

        self.assertEqual((None, None, None), (pay["counter_hours"], pay["bank_details"], pay["upi_id"]))

    def test_a_upi_id_must_look_like_one(self):
        response = self.save_settings(pay_upi_id="not a upi id")

        self.assertEqual(422, response.status_code)
        self.assertIn("Enter a UPI ID like schoolname@okaxis.", str(response.data))

    def test_text_is_kept_to_its_length(self):
        response = self.save_settings(pay_counter_hours="x" * 201)

        self.assertEqual(422, response.status_code)
        self.assertIn("200 characters or fewer", str(response.data))

    def test_text_must_be_text(self):
        response = self.save_settings(pay_counter_hours=12)

        self.assertEqual(422, response.status_code)
