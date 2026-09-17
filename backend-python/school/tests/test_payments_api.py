"""Payments, the queue that carries their receipts, and the PDF itself.

Three things here are worth testing hardest.

**The money is Decimal all the way down.** The column is `decimal(12,2)` and
somebody eventually reconciles these figures by hand; a float would put a
fraction of a paisa into a ledger.

**The status is derived, never taken at face value**, so a payment can never
read "Paid" with a balance outstanding. Cancelled is the exception, because it
is a decision rather than an arithmetic result.

**Totals are grouped by currency and never summed across them** (CLAUDE.md
rule 5). A single blended total would be a number that is true in no currency.
"""

from decimal import Decimal

from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, queue, receipts, tokens
from school.enums import UserRole
from school.models import Payment, QueuedJob


class PaymentApiTest(TestCase):
    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.school = factories.SchoolFactory(currency_code="INR")
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.client = self.as_user(self.root)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "payment_type": "setup_fee",
            "amount": "4500.00",
            "payment_date": "2026-09-01",
            "payment_mode": "bank_transfer",
            "status": "paid",
        }
        body.update(overrides)

        return body


class RecordingAPayment(PaymentApiTest):
    def test_a_payment_is_recorded_and_comes_back_whole(self):
        response = self.client.post("/api/v1/payments", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("4500.00", response.data["amount"])
        self.assertEqual("4500.00", response.data["paid_amount"])
        self.assertEqual("0.00", response.data["remaining_amount"])
        self.assertEqual("paid", response.data["status"])
        self.assertEqual(self.root.id, response.data["created_by"])

    def test_the_currency_comes_from_the_school_not_the_request(self):
        # Copied at the moment of payment and never trusted from the client,
        # so a historical payment stays correct even if the school's currency
        # is later changed (CLAUDE.md rule 5).
        response = self.client.post(
            "/api/v1/payments", self.payload(currency_code="USD"), format="json"
        )

        self.assertEqual("INR", response.data["currency_code"])

    def test_money_keeps_its_paise(self):
        response = self.client.post(
            "/api/v1/payments", self.payload(amount="1234.56"), format="json"
        )

        self.assertEqual("1234.56", response.data["amount"])
        self.assertEqual(Decimal("1234.56"), Payment.objects.get(pk=response.data["id"]).amount)

    def test_a_third_decimal_place_is_refused(self):
        # The column would round it silently, which is how a ledger stops
        # adding up.
        response = self.client.post(
            "/api/v1/payments", self.payload(amount="100.005"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("amount", response.data["details"]["errors"])

    def test_an_amount_of_nothing_is_refused(self):
        response = self.client.post("/api/v1/payments", self.payload(amount="0"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("amount", response.data["details"]["errors"])

    def test_a_part_payment_derives_its_own_status(self):
        response = self.client.post(
            "/api/v1/payments",
            self.payload(amount="4500.00", paid_amount="1000.00", status="paid"),
            format="json",
        )

        # "paid" was asked for and the figures say otherwise. The figures win.
        self.assertEqual("partial", response.data["status"])
        self.assertEqual("3500.00", response.data["remaining_amount"])

    def test_nothing_received_is_pending_whatever_was_asked_for(self):
        response = self.client.post(
            "/api/v1/payments",
            self.payload(paid_amount="0", status="paid"),
            format="json",
        )

        self.assertEqual("pending", response.data["status"])

    def test_cancelled_survives_the_figures(self):
        # A decision rather than an arithmetic result, so it is the one status
        # that is taken at face value - and nothing is owed on it.
        response = self.client.post(
            "/api/v1/payments",
            self.payload(amount="4500.00", status="cancelled"),
            format="json",
        )

        self.assertEqual("cancelled", response.data["status"])
        self.assertEqual("0.00", response.data["remaining_amount"])

    def test_more_received_than_agreed_is_refused(self):
        response = self.client.post(
            "/api/v1/payments",
            self.payload(amount="1000.00", paid_amount="1500.00"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The amount received cannot be more than the payment amount.",
            response.data["details"]["errors"]["paid_amount"][0],
        )

    def test_a_school_that_does_not_exist_is_refused(self):
        response = self.client.post(
            "/api/v1/payments", self.payload(school_id=999999), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("school_id", response.data["details"]["errors"])

    def test_an_unknown_payment_type_or_mode_is_refused(self):
        for field, value in (("payment_type", "bribe"), ("payment_mode", "goat")):
            with self.subTest(field=field):
                response = self.client.post(
                    "/api/v1/payments", self.payload(**{field: value}), format="json"
                )

                self.assertEqual(422, response.status_code, field)
                self.assertIn(field, response.data["details"]["errors"])


class EditingAPayment(PaymentApiTest):
    def setUp(self):
        super().setUp()
        self.payment = self.client.post(
            "/api/v1/payments",
            self.payload(amount="4500.00", paid_amount="1000.00"),
            format="json",
        ).data

    def test_receiving_the_rest_settles_it(self):
        response = self.client.patch(
            f"/api/v1/payments/{self.payment['id']}",
            {"paid_amount": "4500.00"},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("paid", response.data["status"])
        self.assertEqual("0.00", response.data["remaining_amount"])

    def test_lowering_the_amount_cannot_leave_more_paid_than_is_owed(self):
        response = self.client.patch(
            f"/api/v1/payments/{self.payment['id']}", {"amount": "500.00"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("500.00", response.data["paid_amount"])
        self.assertEqual("paid", response.data["status"])

    def test_the_school_and_currency_are_fixed_at_creation(self):
        elsewhere = factories.SchoolFactory(currency_code="USD")

        self.client.patch(
            f"/api/v1/payments/{self.payment['id']}",
            {"school_id": elsewhere.id, "currency_code": "USD"},
            format="json",
        )

        stored = Payment.objects.get(pk=self.payment["id"])
        self.assertEqual(self.school.id, stored.school_id)
        self.assertEqual("INR", stored.currency_code)


class TheReceiptIsQueuedNotSent(PaymentApiTest):
    def queued(self):
        return QueuedJob.objects.filter(name="payment_receipt")

    def test_recording_a_payment_queues_its_receipt(self):
        # Queued, not sent: a mail server being down must never be why a
        # payment fails to save.
        response = self.client.post("/api/v1/payments", self.payload(), format="json")

        self.assertEqual(1, self.queued().count())
        self.assertEqual(
            {"payment_id": response.data["id"]}, self.queued().first().payload
        )
        self.assertEqual([], mail.outbox, "nothing is sent during the request")

    def test_changing_the_money_queues_another(self):
        created = self.client.post(
            "/api/v1/payments", self.payload(paid_amount="1000.00"), format="json"
        ).data
        self.queued().delete()

        self.client.patch(
            f"/api/v1/payments/{created['id']}", {"paid_amount": "4500.00"}, format="json"
        )

        self.assertEqual(1, self.queued().count())

    def test_correcting_a_reference_number_does_not(self):
        # Re-sending a receipt because somebody fixed a typo would be noise.
        created = self.client.post("/api/v1/payments", self.payload(), format="json").data
        self.queued().delete()

        self.client.patch(
            f"/api/v1/payments/{created['id']}", {"reference_number": "NEFT-9912"}, format="json"
        )

        self.assertEqual(0, self.queued().count())

    def test_asking_for_it_again_queues_it_again(self):
        created = self.client.post("/api/v1/payments", self.payload(), format="json").data
        self.queued().delete()

        response = self.client.post(f"/api/v1/payments/{created['id']}/receipt")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(1, self.queued().count())

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_the_worker_sends_it_to_the_schools_admins(self):
        admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        created = self.client.post("/api/v1/payments", self.payload(), format="json").data

        result = queue.work()

        self.assertEqual({"done": 1, "failed": 0}, result)
        self.assertEqual(1, len(mail.outbox))
        self.assertEqual([admin.email], mail.outbox[0].to)
        self.assertEqual(1, len(mail.outbox[0].attachments))
        self.assertTrue(mail.outbox[0].attachments[0][0].endswith(".pdf"))

        # And the payment records that the school has been told.
        self.assertIsNotNone(Payment.objects.get(pk=created["id"]).receipt_sent_at)

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_a_school_with_no_active_admin_is_not_a_failure(self):
        # Newly onboarded, or its only admin deactivated. Worth a log line,
        # not worth retrying forever.
        self.client.post("/api/v1/payments", self.payload(), format="json")

        with self.assertLogs("school.jobs", level="INFO"):
            result = queue.work()

        self.assertEqual({"done": 1, "failed": 0}, result)
        self.assertEqual([], mail.outbox)


class TheSummary(PaymentApiTest):
    def test_totals_are_grouped_by_currency_and_never_blended(self):
        # "4,500 INR and 12,000 USD", never one number. This is a recording
        # system, not a forex one.
        dollars = factories.SchoolFactory(currency_code="USD")

        self.client.post("/api/v1/payments", self.payload(amount="4500.00"), format="json")
        self.client.post(
            "/api/v1/payments",
            self.payload(school_id=dollars.id, amount="12000.00"),
            format="json",
        )

        response = self.client.get("/api/v1/payments/summary")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [
                {"currency_code": "INR", "total": "4500.00"},
                {"currency_code": "USD", "total": "12000.00"},
            ],
            response.data["total_by_currency"],
        )

    def test_collected_counts_the_part_of_a_part_payment_that_arrived(self):
        self.client.post(
            "/api/v1/payments",
            self.payload(amount="4500.00", paid_amount="1000.00"),
            format="json",
        )

        response = self.client.get("/api/v1/payments/summary")

        self.assertEqual(
            [{"currency_code": "INR", "total": "1000.00"}], response.data["total_by_currency"]
        )
        self.assertEqual(
            [{"currency_code": "INR", "total": "3500.00"}], response.data["pending_by_currency"]
        )
        self.assertEqual(1, response.data["pending_count"])

    def test_a_cancelled_payment_counts_for_nothing(self):
        self.client.post(
            "/api/v1/payments", self.payload(amount="4500.00", status="cancelled"), format="json"
        )

        response = self.client.get("/api/v1/payments/summary")

        self.assertEqual([], response.data["total_by_currency"])
        self.assertEqual([], response.data["pending_by_currency"])
        self.assertEqual(0, response.data["pending_count"])


class TheReceiptDocument(PaymentApiTest):
    def a_payment(self, **overrides) -> Payment:
        created = self.client.post("/api/v1/payments", self.payload(**overrides), format="json")

        return Payment.objects.select_related("school", "created_by").get(pk=created.data["id"])

    def test_it_downloads_as_a_pdf(self):
        payment = self.a_payment()

        response = self.client.get(f"/api/v1/payments/{payment.id}/receipt")

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertIn(f'filename="RCPT-{payment.id:06d}.pdf"', response["Content-Disposition"])
        self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_the_receipt_number_is_stable_for_a_payment(self):
        # So a school re-sent the same receipt files it over the one it
        # already has rather than beside it.
        payment = self.a_payment()

        self.assertEqual(
            receipts.receipt_number(payment), receipts.receipt_number(payment)
        )
        self.assertEqual(f"RCPT-{payment.id:06d}", receipts.receipt_number(payment))

    def test_a_part_payment_says_plainly_what_is_still_owed(self):
        payment = self.a_payment(amount="4500.00", paid_amount="1000.00")

        document = receipts.document(payment)

        self.assertIn("Balance due", document)
        self.assertIn("INR 3,500.00", document)
        self.assertIn("remains outstanding", document)

    def test_a_settled_payment_does_not(self):
        document = receipts.document(self.a_payment())

        self.assertIn("Paid in full", document)
        self.assertNotIn("Balance due", document)

    def test_a_cancelled_payment_owes_nothing(self):
        document = receipts.document(self.a_payment(status="cancelled"))

        self.assertIn("This payment has been cancelled", document)
        self.assertIn("INR 0.00", document)

    def test_a_name_with_an_ampersand_does_not_break_the_document(self):
        # Typed by people. An unescaped one would either break the render or,
        # worse, be treated as markup.
        self.school.name = "Smith & Jones High"
        self.school.save()

        document = receipts.document(self.a_payment())

        self.assertIn("Smith &amp; Jones High", document)
        self.assertNotIn("Smith & Jones High", document)


class OnlyThePlatformSeesPayments(PaymentApiTest):
    """The one module where a School Admin has no access at all - not even to
    their own school's rows. Onboarding a school and recording what it paid
    are things the platform does."""

    def test_nobody_but_a_super_admin_reaches_any_of_it(self):
        created = self.client.post("/api/v1/payments", self.payload(), format="json").data

        for role in (
            UserRole.SCHOOL_ADMIN,
            UserRole.GROUP_ADMIN,
            UserRole.HOD,
            UserRole.TEACHER,
            UserRole.STAFF,
            UserRole.TRANSPORT_MANAGER,
            UserRole.ACCOUNTANT,
        ):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, client.get("/api/v1/payments").status_code)
                self.assertEqual(403, client.get("/api/v1/payments/summary").status_code)
                self.assertEqual(403, client.get(f"/api/v1/payments/{created['id']}").status_code)
                self.assertEqual(
                    403,
                    client.get(f"/api/v1/payments/{created['id']}/receipt").status_code,
                )
                self.assertEqual(
                    403, client.post("/api/v1/payments", self.payload(), format="json").status_code
                )

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/payments").status_code)
