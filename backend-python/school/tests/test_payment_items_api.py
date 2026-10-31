"""One payment, several services.

A Super Admin ticks the services a school is paying for - Setup Fee, Annual
Maintenance, Additional Service, and any "other" fees they name - and types an
amount beside each. The payment's total is the sum of those, worked out by the
server, and the receipt lists every one.
"""

from django.core import mail
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, receipts, tokens
from school.enums import UserRole
from school.models import AuditLog, Payment, PaymentItem


class PaymentItemsTest(TestCase):
    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.school = factories.SchoolFactory(currency_code="INR", name="Greenfield Public School")
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.client = self.as_user(self.root)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, items, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "items": items,
            "payment_date": "2026-11-01",
            "payment_mode": "bank_transfer",
            "status": "paid",
        }
        body.update(overrides)

        return body

    THREE = [
        {"service": "setup_fee", "amount": "25000.00"},
        {"service": "additional_service", "amount": "12000.50"},
        {"service": "other", "name": "Staff training day", "amount": "5000"},
    ]

    def record(self, items=None, **overrides):
        return self.client.post("/api/v1/payments", self.payload(self.THREE if items is None else items, **overrides), format="json")


class RecordingSeveralServices(PaymentItemsTest):
    def test_the_total_is_the_sum_of_the_services(self):
        response = self.record()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("42000.50", response.data["amount"])
        self.assertEqual("42000.50", response.data["paid_amount"])
        self.assertEqual("paid", response.data["status"])

    def test_every_service_comes_back_in_the_order_entered(self):
        response = self.record()

        self.assertEqual(
            [
                ("setup_fee", None, "Setup Fee", "25000.00"),
                ("additional_service", None, "Additional Service", "12000.50"),
                ("other", "Staff training day", "Staff training day", "5000.00"),
            ],
            [(i["service"], i["name"], i["label"], i["amount"]) for i in response.data["items"]],
        )
        self.assertEqual("Setup Fee + 2 more", response.data["services_summary"])

    def test_a_total_sent_by_the_client_is_ignored(self):
        response = self.record(amount="1.00")

        self.assertEqual("42000.50", response.data["amount"])

    def test_each_line_carries_the_schools_currency(self):
        self.record(currency_code="USD")

        self.assertEqual({"INR"}, set(PaymentItem.objects.values_list("currency_code", flat=True)))

    def test_several_other_fees_can_sit_side_by_side(self):
        response = self.record([
            {"service": "other", "name": "Data migration", "amount": "3000"},
            {"service": "other", "name": "Extra SMS pack", "amount": "750"},
        ])

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("3750.00", response.data["amount"])
        self.assertEqual("Data migration + 1 more", response.data["services_summary"])

    def test_a_part_payment_is_against_the_whole_total(self):
        response = self.record(paid_amount="20000.00")

        self.assertEqual("partial", response.data["status"])
        self.assertEqual("22000.50", response.data["remaining_amount"])

    def test_received_more_than_the_total_is_refused(self):
        response = self.record(paid_amount="50000.00")

        self.assertEqual(422, response.status_code)
        self.assertIn("paid_amount", response.data["details"]["errors"])

    def test_the_audit_log_records_the_services(self):
        response = self.record()

        entry = AuditLog.objects.get(action="payment.created", entity_id=response.data["id"])
        self.assertEqual(3, len(entry.new_values["items"]))
        self.assertEqual("Staff training day", entry.new_values["items"][2]["name"])

    def test_the_old_single_service_shape_still_works(self):
        response = self.client.post(
            "/api/v1/payments",
            {"school_id": self.school.id, "payment_type": "annual_maintenance", "amount": "9000",
             "payment_date": "2026-11-01", "payment_mode": "cash", "status": "paid"},
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Annual Maintenance", response.data["services_summary"])
        self.assertEqual(1, len(response.data["items"]))


class RefusingABadList(PaymentItemsTest):
    def refused(self, items) -> dict:
        response = self.record(items)
        self.assertEqual(422, response.status_code, response.data)
        self.assertFalse(Payment.objects.exists())

        return response.data["details"]["errors"]

    def test_no_service_at_all(self):
        self.assertEqual(["Choose at least one service."], self.refused([])["items"])

    def test_nothing_sent_for_the_services(self):
        response = self.client.post(
            "/api/v1/payments",
            {"school_id": self.school.id, "payment_date": "2026-11-01", "payment_mode": "cash", "status": "paid"},
            format="json",
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("items", response.data["details"]["errors"])

    def test_an_amount_of_zero_or_less(self):
        details = self.refused([{"service": "setup_fee", "amount": "0"}])

        self.assertEqual(["The amount must be more than 0."], details["items.0.amount"])

    def test_a_missing_amount(self):
        details = self.refused([{"service": "setup_fee"}, {"service": "other", "name": "Kit", "amount": ""}])

        self.assertEqual(["Enter an amount."], details["items.0.amount"])
        self.assertEqual(["Enter an amount."], details["items.1.amount"])

    def test_a_third_decimal_place(self):
        details = self.refused([{"service": "setup_fee", "amount": "10.005"}])

        self.assertIn("items.0.amount", details)

    def test_an_other_fee_with_no_name(self):
        details = self.refused([{"service": "other", "name": "   ", "amount": "100"}])

        self.assertEqual(["Say what this fee is for."], details["items.0.name"])

    def test_an_other_fee_name_that_is_too_long(self):
        details = self.refused([{"service": "other", "name": "x" * 101, "amount": "100"}])

        self.assertIn("items.0.name", details)

    def test_a_service_that_is_not_on_the_list(self):
        details = self.refused([{"service": "transport_fee", "amount": "100"}])

        self.assertEqual(["Choose a service from the list."], details["items.0.service"])

    def test_the_same_fixed_service_twice(self):
        details = self.refused([
            {"service": "setup_fee", "amount": "100"},
            {"service": "setup_fee", "amount": "200"},
        ])

        self.assertEqual(["Setup Fee is listed twice."], details["items.1.service"])

    def test_more_lines_than_a_receipt_should_hold(self):
        details = self.refused([{"service": "other", "name": f"Fee {n}", "amount": "1"} for n in range(21)])

        self.assertIn("items", details)

    def test_items_that_are_not_a_list(self):
        self.assertIn("items", self.refused("setup_fee"))


class EditingTheServices(PaymentItemsTest):
    def setUp(self):
        super().setUp()
        self.payment_id = self.record().data["id"]

    def edit(self, body):
        return self.client.patch(f"/api/v1/payments/{self.payment_id}", body, format="json")

    def test_new_lines_replace_the_old_and_the_total_follows(self):
        response = self.edit({"items": [
            {"service": "annual_maintenance", "amount": "8000"},
            {"service": "other", "name": "Extra SMS pack", "amount": "750"},
        ]})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("8750.00", response.data["amount"])
        self.assertEqual(["Annual Maintenance", "Extra SMS pack"], [i["label"] for i in response.data["items"]])
        self.assertEqual(2, PaymentItem.objects.filter(payment_id=self.payment_id).count())
        # Still Paid, and paid in full at the new total.
        self.assertEqual("8750.00", response.data["paid_amount"])

    def test_changing_only_the_status_leaves_the_services_alone(self):
        response = self.edit({"status": "cancelled"})

        self.assertEqual("cancelled", response.data["status"])
        self.assertEqual(3, len(response.data["items"]))
        self.assertEqual("42000.50", response.data["amount"])

    def test_the_audit_log_shows_the_services_before_and_after(self):
        self.edit({"items": [{"service": "setup_fee", "amount": "25000"}]})

        entry = AuditLog.objects.filter(action="payment.updated", entity_id=self.payment_id).latest("id")
        self.assertEqual(3, len(entry.old_values["items"]))
        self.assertEqual(1, len(entry.new_values["items"]))

    def test_a_single_amount_cannot_overwrite_several_services(self):
        response = self.edit({"amount": "100"})

        self.assertEqual(422, response.status_code)
        self.assertIn("items", response.data["details"]["errors"])

    def test_a_bad_line_on_edit_is_refused_and_nothing_changes(self):
        response = self.edit({"items": [{"service": "other", "amount": "10"}]})

        self.assertEqual(422, response.status_code)
        self.assertEqual(3, PaymentItem.objects.filter(payment_id=self.payment_id).count())


class TheListAndItsFilter(PaymentItemsTest):
    def test_filtering_by_a_service_finds_a_payment_that_includes_it(self):
        several = self.record().data["id"]
        only_setup = self.record([{"service": "setup_fee", "amount": "100"}]).data["id"]

        response = self.client.get("/api/v1/payments", {"payment_type": "additional_service"})

        self.assertEqual([several], [row["id"] for row in response.data["data"]])
        self.assertNotIn(only_setup, [row["id"] for row in response.data["data"]])

    def test_each_row_lists_its_services(self):
        self.record()

        row = self.client.get("/api/v1/payments").data["data"][0]

        self.assertEqual("Setup Fee + 2 more", row["services_summary"])
        self.assertEqual(3, len(row["items"]))


class TheReceiptListsEveryService(PaymentItemsTest):
    def document(self, items=None) -> str:
        payment_id = self.record(items).data["id"]
        payment = Payment.objects.select_related("school", "created_by").get(pk=payment_id)

        return receipts.document(payment)

    def test_one_row_per_service_with_its_amount(self):
        document = self.document()

        self.assertIn("Setup Fee", document)
        self.assertIn("INR 25,000.00", document)
        self.assertIn("Additional Service", document)
        self.assertIn("INR 12,000.50", document)
        self.assertIn("Staff training day", document)
        self.assertIn("INR 5,000.00", document)
        self.assertIn("INR 42,000.50", document)

    def test_a_name_typed_by_a_person_is_escaped(self):
        document = self.document([{"service": "other", "name": "Books & <b>kits</b>", "amount": "10"}])

        self.assertIn("Books &amp; &lt;b&gt;kits&lt;/b&gt;", document)
        self.assertNotIn("<b>kits</b>", document)

    def test_a_single_service_reads_as_it_always_did(self):
        document = self.document([{"service": "setup_fee", "amount": "100"}])

        self.assertIn("Setup Fee - Greenfield Public School", document)

    def test_it_still_renders_as_a_pdf(self):
        payment_id = self.record().data["id"]

        response = self.client.get(f"/api/v1/payments/{payment_id}/receipt")

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF-"))


class OnlyASuperAdmin(PaymentItemsTest):
    def test_a_school_admin_cannot_record_one(self):
        admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        response = self.as_user(admin).post("/api/v1/payments", self.payload(self.THREE), format="json")

        self.assertEqual(403, response.status_code)
        self.assertFalse(Payment.objects.exists())
