"""School365ai's own business details (docs/pdf-design.md, phase 5): only the
Super Admin reads or saves them, what is checked, and how they reach the
receipt a school gets for paying the platform."""

from school import factories, pdf_design, receipts
from school.enums import UserRole
from school.models import AuditLog, CompanyProfile, Payment

from .test_payments_api import PaymentApiTest

URL = "/api/v1/settings/company"

DETAILS = {
    "legal_name": "School365 AI Private Limited",
    "trading_name": "School365ai",
    "address": "4th Floor, Tech Park,",
    "city": "Pune",
    "state": "Maharashtra",
    "postal_code": "411001",
    "country": "India",
    "phone": "+91 20 4000 0000",
    "email": "billing@school365ai.com",
    "website": "school365ai.com",
    "tax_number": "27abcde1234f1z5",
    "registration_number": "u72900pn2026ptc000001",
}


class CompanyTestCase(PaymentApiTest):
    def save(self, user=None, **overrides):
        return self.as_user(user or self.root).put(URL, {**DETAILS, **overrides}, format="json")


class WhoMay(CompanyTestCase):
    def test_the_super_admin_reads_empty_details_before_the_first_save(self):
        response = self.client.get(URL)

        self.assertEqual(200, response.status_code)
        self.assertEqual((False, None), (response.data["is_saved"], response.data["legal_name"]))

    def test_the_super_admin_saves_them(self):
        response = self.save()

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(response.data["is_saved"])
        self.assertEqual("School365 AI Private Limited", response.data["legal_name"])
        # Tax and registration numbers are kept in capitals.
        self.assertEqual(("27ABCDE1234F1Z5", "U72900PN2026PTC000001"),
                         (response.data["tax_number"], response.data["registration_number"]))
        self.assertEqual(1, CompanyProfile.objects.count())

    def test_saving_again_changes_the_one_row_and_is_audited(self):
        self.save()
        self.save(phone="")

        self.assertEqual(1, CompanyProfile.objects.count())
        self.assertIsNone(CompanyProfile.objects.get().phone)
        self.assertEqual(2, AuditLog.objects.filter(module="company").count())

    def test_nobody_else_may_read_or_save_them(self):
        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.ACCOUNTANT, UserRole.TEACHER):
            with self.subTest(role=role):
                user = factories.UserFactory(school=self.school, role=role)

                self.assertEqual(403, self.as_user(user).get(URL).status_code)
                self.assertEqual(403, self.save(user=user).status_code)

        self.assertFalse(CompanyProfile.objects.exists())

    def test_signed_out_is_refused(self):
        from rest_framework.test import APIClient

        self.assertEqual(401, APIClient().get(URL).status_code)


class WhatIsChecked(CompanyTestCase):
    def test_the_legal_name_is_required(self):
        response = self.save(legal_name="")

        self.assertEqual(422, response.status_code)
        self.assertIn("legal_name", response.data["details"]["errors"])

    def test_bad_values_are_refused(self):
        for field, value in (
            ("email", "not-an-email"),
            ("website", "not a site"),
            ("logo_url", "file:///etc/passwd"),
            ("tax_number", "X" * 31),
            ("legal_name", "L" * 151),
        ):
            with self.subTest(field=field):
                response = self.save(**{field: value})

                self.assertEqual(422, response.status_code)
                self.assertIn(field, response.data["details"]["errors"])


class OnTheReceipt(CompanyTestCase):
    def payment(self, **overrides):
        created = self.client.post("/api/v1/payments", {**self.payload(), **overrides}, format="json")

        return Payment.objects.select_related("school", "created_by").get(pk=created.data["id"])

    def test_before_any_details_the_band_says_school365ai_alone(self):
        document = receipts.document(self.payment())

        self.assertIn('<div class="school-name">School365ai</div>', document)
        self.assertNotIn("Tax no.", document)
        self.assertEqual(0, pdf_design.style_errors(document))

    def test_the_saved_details_are_the_issuer(self):
        self.save()

        document = receipts.document(self.payment())

        for text in ("School365ai", "School365 AI Private Limited", "4th Floor, Tech Park, Pune, Maharashtra, 411001, India",
                     "Phone +91 20 4000 0000, billing@school365ai.com, school365ai.com", "Tax no. 27ABCDE1234F1Z5",
                     "Reg. no. U72900PN2026PTC000001", "PAYMENT RECEIPT"):
            self.assertIn(text, document)

    def test_it_says_everything_about_the_payment(self):
        payment = self.payment(amount="4500.00", paid_amount="1000.00", status="partial",
                               reference_number="UTR-42", notes="First of three")

        document = receipts.document(payment)

        for text in (self.school.name, f"RCPT-{payment.id:06d}", "Setup Fee", "09/01/2026", "Bank Transfer",
                     "UTR-42", "INR 4,500.00", "INR 1,000.00", "Indian Rupees One Thousand Only", "Balance due",
                     "INR 3,500.00", "First of three", "Page <pdf:pagenumber> of <pdf:pagecount>"):
            self.assertIn(text, document)
        self.assertEqual(0, pdf_design.style_errors(document))
        self.assertTrue(receipts.render(payment).startswith(b"%PDF"))

    def test_a_cancelled_payment_carries_the_stamp(self):
        document = receipts.document(self.payment(status="cancelled"))

        self.assertIn("CANCELLED", document)
