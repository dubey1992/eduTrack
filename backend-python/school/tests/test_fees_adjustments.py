"""Discounts, waivers and late fines (docs/fees.md, F4): what a discount takes
off which dues and when it gives it back, what a waiver forgives, the late
fine job, and how all three live with payments and the F2 reconcile. Who may
do it, the list and the statement's shape are test_fees_adjustments_api.py.

Same school, year and frozen clock as test_fees_dues.py: 2026-27, "now" is
15 July 2026, 11:30 in Kolkata. Class 8's Tuition is 1,000 due on 10 April,
10 July, 10 October and 10 January; Route A's bus fee 600 on 10 April and
10 October.
"""

import datetime as dt
import io
from decimal import Decimal
from unittest import mock

from django.core.management import CommandError, call_command
from django.db import IntegrityError, transaction

from school import factories
from school.enums import EnrollmentStatus, FeeDueStatus, StudentStatus
from school.fees import receipt_pdf
from school.fees.dues import FeeDueService, discount_for
from school.fees.fines import LateFineService, fine_label
from school.fees.receipts import FeeReceiptService
from school.models import (
    AuditLog,
    FeeConcession,
    FeeHead,
    FeeReceipt,
    ModuleSetting,
    StudentEnrollment,
    StudentFeeDue,
)

from .test_fees_dues import ROUTE_A, TUITION_9
from .test_fees_receipts import ReceiptsTestCase

CONCESSIONS = "/api/v1/fees/concessions"
DUES = "/api/v1/fees/dues"


def at(moment: dt.datetime):
    """The clock moved to another instant for the rest of a `with` block."""
    return mock.patch("django.utils.timezone.now", return_value=moment)


class AdjustmentsTestCase(ReceiptsTestCase):
    # -- discounts ----------------------------------------------------------

    def concede(self, kind="fixed", value="500.00", head="tuition", student=None, user=None, reason="Sibling",
                year=None):
        head_id = {"tuition": self.tuition.id, "transport": self.transport.id, None: None}[head]
        body = {
            "student_id": (student or self.aarav).id,
            "academic_year_id": (year or self.year).id,
            "fee_head_id": head_id,
            "kind": kind,
            "value": value,
            "reason": reason,
        }

        return self.as_user(user or self.accountant).post(CONCESSIONS, body, format="json")

    def conceded(self, *args, **kwargs) -> dict:
        response = self.concede(*args, **kwargs)
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def revoke(self, concession_id, user=None, reason=None):
        body = {} if reason is None else {"reason": reason}

        return self.as_user(user or self.accountant).delete(f"{CONCESSIONS}/{concession_id}", body, format="json")

    def discounts(self, student=None) -> list[tuple]:
        """(label, discount, paid, status) per due, oldest first."""
        return [
            (due.label, str(due.discount_amount), str(due.paid_amount), due.status)
            for due in StudentFeeDue.objects.filter(student=student or self.aarav).order_by("due_date", "label", "id")
        ]

    # -- waivers -------------------------------------------------------------

    def waive(self, due, reason="Hardship case", user=None):
        return self.as_user(user or self.accountant).post(f"{DUES}/{due.id}/waive", {"reason": reason}, format="json")

    def waived(self, due, **kwargs) -> dict:
        response = self.waive(due, **kwargs)
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    # -- fines ---------------------------------------------------------------

    def fines_on(self, amount=50, grace=5, school=None):
        ModuleSetting.objects.filter(school=school or self.school, module="fees").update(
            settings={"late_fine_amount": amount, "late_fine_grace_days": grace}
        )

    def fines(self, student=None) -> list[tuple]:
        """(label, due date, amount, status, the installment's label) per fine."""
        return [
            (fine.label, fine.due_date.isoformat(), str(fine.amount), fine.status, fine.fine_for_due.label)
            for fine in StudentFeeDue.objects.filter(student=student or self.aarav, kind="late_fine")
            .select_related("fine_for_due").order_by("fine_for_due__due_date", "id")
        ]

    def run_fines(self, *args) -> str:
        out = io.StringIO()
        call_command("apply_late_fines", *args, stdout=out)

        return out.getvalue()


# -- discounts --------------------------------------------------------------------


class Discounts(AdjustmentsTestCase):
    def test_a_fixed_amount_comes_off_each_installment_of_its_fee_type(self):
        self.conceded("fixed", "500.00")

        self.assertEqual(
            [
                ("Tuition - April", "500.00", "0.00", "pending"),
                ("Tuition - July", "500.00", "0.00", "pending"),
                ("Tuition - October", "500.00", "0.00", "pending"),
                ("Tuition - January", "500.00", "0.00", "pending"),
            ],
            self.discounts(),
        )

    def test_a_percentage_comes_off_each_installment_rounded_to_the_cent(self):
        self.conceded("percent", "33.33")

        self.assertEqual({"333.30"}, {discount for _, discount, _, _ in self.discounts()})

    def test_one_fee_type_or_every_one(self):
        self.published(ROUTE_A, route=self.route_a)
        self.ride(self.aarav, self.route_a, self.stop_a)

        tuition_only = self.conceded("fixed", "100.00", head="tuition")
        self.assertEqual(
            {"Tuition": {"100.00"}, "Transport": {"0.00"}},
            self.by_head(),
        )

        self.revoke(tuition_only["id"])
        self.conceded("fixed", "100.00", head=None)
        self.assertEqual({"Tuition": {"100.00"}, "Transport": {"100.00"}}, self.by_head())

        self.conceded("percent", "50", head="transport")
        self.assertEqual({"Tuition": {"100.00"}, "Transport": {"400.00"}}, self.by_head())

    def by_head(self) -> dict:
        found: dict[str, set] = {}

        for due in StudentFeeDue.objects.filter(student=self.aarav).select_related("fee_head"):
            found.setdefault(due.fee_head.name, set()).add(str(due.discount_amount))

        return found

    def test_several_discounts_on_one_installment_add_up(self):
        self.conceded("fixed", "300.00")
        self.conceded("percent", "10")

        self.assertEqual({"400.00"}, {discount for _, discount, _, _ in self.discounts()})

    def test_a_discount_never_takes_a_due_below_what_has_been_paid_or_below_zero(self):
        april = self.due("Tuition - April")
        self.paid(amount="800.00", allocations=[{"due_id": april.id, "amount": "800.00"}])

        self.conceded("fixed", "500.00")
        self.conceded("percent", "100")

        april.refresh_from_db()
        # 1,500 of discount asked for; only the 200 not yet paid is left.
        self.assertEqual((Decimal("200.00"), "partial"), (april.discount_amount, april.status))
        self.assertEqual(
            {"1000.00"},
            {d for label, d, _, _ in self.discounts() if label != "Tuition - April"},
        )

    def test_a_partly_paid_due_takes_the_discount_on_what_is_left(self):
        april = self.due("Tuition - April")
        self.paid(amount="300.00", allocations=[{"due_id": april.id, "amount": "300.00"}])

        self.conceded("fixed", "500.00")

        april.refresh_from_db()
        self.assertEqual(("500.00", "300.00", "partial"),
                         (str(april.discount_amount), str(april.paid_amount), april.status))

        # And the rest can be paid: 200.
        self.paid(amount="200.00", allocations=[{"due_id": april.id, "amount": "200.00"}])
        april.refresh_from_db()
        self.assertEqual(FeeDueStatus.PAID, april.status)

    def test_a_paid_due_is_never_reopened_or_discounted(self):
        april = self.due("Tuition - April")
        self.paid(amount="1000.00", allocations=[{"due_id": april.id, "amount": "1000.00"}])

        concession = self.conceded("fixed", "500.00")

        self.assertEqual(("Tuition - April", "0.00", "1000.00", "paid"), self.discounts()[0])

        self.revoke(concession["id"])
        self.assertEqual(("Tuition - April", "0.00", "1000.00", "paid"), self.discounts()[0])

    def test_a_paid_due_keeps_the_discount_it_was_paid_under_when_the_discount_is_revoked(self):
        concession = self.conceded("fixed", "500.00")
        april = self.due("Tuition - April")
        self.paid(amount="500.00", allocations=[{"due_id": april.id, "amount": "500.00"}])

        self.revoke(concession["id"])

        self.assertEqual(("Tuition - April", "500.00", "500.00", "paid"), self.discounts()[0])
        self.assertEqual({"0.00"}, {d for _, d, _, _ in self.discounts()[1:]})

    def test_dues_created_later_in_the_year_get_the_discount(self):
        self.conceded("fixed", "100.00", head=None)
        self.published(ROUTE_A, route=self.route_a)

        self.ride(self.aarav, self.route_a, self.stop_a)

        transport = StudentFeeDue.objects.filter(student=self.aarav, fee_head=self.transport)
        self.assertEqual({Decimal("100.00")}, {due.discount_amount for due in transport})
        self.assertEqual(2, transport.count())

    def test_a_student_who_moves_class_keeps_the_discount_on_the_new_class_dues(self):
        self.published(TUITION_9, school_class=self.class9)
        self.conceded("fixed", "250.00")

        self.patch_student(self.aarav, {"class_section_id": self.section9.id})

        self.assertEqual(
            [
                ("Tuition - April", "250.00", "0.00", "pending"),
                ("Tuition - July", "250.00", "0.00", "pending"),
                ("Tuition - October", "250.00", "0.00", "cancelled"),
                ("Tuition - Term 2", "250.00", "0.00", "pending"),
                ("Tuition - January", "250.00", "0.00", "cancelled"),
                ("Tuition - Term 3", "250.00", "0.00", "pending"),
            ],
            self.discounts(),
        )

    def test_revoking_gives_the_dues_back(self):
        concession = self.conceded("percent", "25")

        response = self.revoke(concession["id"], reason="Given by mistake")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual({"0.00"}, {d for _, d, _, _ in self.discounts()})
        row = FeeConcession.objects.get(pk=concession["id"])
        self.assertIsNotNone(row.revoked_at)
        self.assertEqual(self.accountant.id, row.revoked_by_id)

    def test_a_whole_installment_discounted_owes_nothing_but_stays_open_so_revoking_restores_it(self):
        concession = self.conceded("percent", "100")
        april = self.due("Tuition - April")

        self.assertEqual(("1000.00", "pending"), (str(april.discount_amount), april.status))
        statement = self.as_user(self.accountant).get(f"/api/v1/fees/students/{self.aarav.id}").data
        self.assertEqual(("0.00", False), (statement["dues"][0]["balance"], statement["dues"][0]["is_overdue"]))
        self.assertEqual("0.00", statement["totals"]["balance"])
        # Nothing to pay on it: a payment now is all credit (F6).
        self.assertEqual([], self.paid(amount="10.00")["allocations"])

        self.revoke(concession["id"])
        april.refresh_from_db()
        # Owed again - and the 10 in credit goes straight onto it.
        self.assertEqual(("0.00", "partial", "10.00"), (str(april.discount_amount), april.status,
                                                        str(april.paid_amount)))

    def test_cancelling_a_receipt_puts_the_discount_back_on_what_it_paid(self):
        self.conceded("fixed", "500.00")
        april = self.due("Tuition - April")
        receipt = self.paid(amount="500.00", allocations=[{"due_id": april.id, "amount": "500.00"}])

        self.assertEqual(200, self.cancel(receipt["id"]).status_code)

        self.assertEqual(("Tuition - April", "500.00", "0.00", "pending"), self.discounts()[0])

    def test_the_arithmetic(self):
        due = StudentFeeDue(amount=Decimal("1000.00"), paid_amount=Decimal("0.00"), fee_head_id=1)
        concessions = [
            FeeConcession(kind="fixed", value=Decimal("100.00"), fee_head_id=None),
            FeeConcession(kind="percent", value=Decimal("12.5"), fee_head_id=1),
            FeeConcession(kind="fixed", value=Decimal("999.00"), fee_head_id=2),
        ]

        self.assertEqual(Decimal("225.00"), discount_for(due, concessions))
        self.assertEqual(Decimal("0.00"), discount_for(due, []))

        due.paid_amount = Decimal("900.00")
        self.assertEqual(Decimal("100.00"), discount_for(due, concessions))

    def test_audited(self):
        concession = self.conceded("fixed", "500.00")
        self.revoke(concession["id"], reason="Given by mistake")

        created = AuditLog.objects.get(action="fee_concession.created")
        revoked = AuditLog.objects.get(action="fee_concession.revoked")

        self.assertEqual(("fee_concession", concession["id"], self.school.id, self.accountant.id),
                         (created.entity_type, created.entity_id, created.school_id, created.user_id))
        self.assertEqual({"fixed", "500.00", "Sibling", 4},
                         {created.new_values["kind"], created.new_values["value"], created.new_values["reason"],
                          created.new_values["dues_updated"]})
        self.assertEqual("Given by mistake", revoked.new_values["reason"])
        # And the dues the reconcile changed, both times.
        self.assertEqual(2, AuditLog.objects.filter(action="fee_dues.synced", entity_type="fee_concession").count())


# -- waivers ----------------------------------------------------------------------


class Waivers(AdjustmentsTestCase):
    def test_a_pending_installment_is_forgiven_outright(self):
        april = self.due("Tuition - April")

        data = self.waived(april, reason="Hardship case")

        april.refresh_from_db()
        self.assertEqual(("waived", "Hardship case", self.accountant.id),
                         (april.status, april.waive_reason, april.waived_by_id))
        self.assertIsNotNone(april.waived_at)
        self.assertEqual(("waived", "0.00", "Hardship case", False),
                         (data["status"], data["balance"], data["waive_reason"], data["is_overdue"]))
        self.assertIsNotNone(data["waived_at"])
        self.assertEqual("installment", data["kind"])

    def test_a_partly_paid_one_keeps_what_was_paid_and_the_rest_is_forgiven(self):
        self.conceded("fixed", "100.00")
        april = self.due("Tuition - April")
        self.paid(amount="300.00", allocations=[{"due_id": april.id, "amount": "300.00"}])

        self.waived(april)

        april.refresh_from_db()
        self.assertEqual(("300.00", "100.00", "waived"),
                         (str(april.paid_amount), str(april.discount_amount), april.status))
        totals = self.as_user(self.accountant).get(f"/api/v1/fees/students/{self.aarav.id}").data["totals"]
        # 1,000 - 100 discount - 300 paid = 600 forgiven.
        self.assertEqual("600.00", totals["waived"])
        self.assertEqual("4000.00", totals["charged"])
        self.assertEqual("2700.00", totals["balance"])
        audit = AuditLog.objects.get(action="fee_due.waived")
        self.assertEqual(({"status": "partial", "balance": "600.00"}, "600.00", "Hardship case"),
                         (audit.old_values, audit.new_values["forgiven"], audit.new_values["reason"]))
        self.assertEqual(("student_fee_due", april.id), (audit.entity_type, audit.entity_id))

    def test_only_a_due_still_owed_can_be_waived(self):
        april, july = self.due("Tuition - April"), self.due("Tuition - July")
        self.paid(amount="1000.00", allocations=[{"due_id": april.id, "amount": "1000.00"}])
        self.waived(july)
        october = self.due("Tuition - October")
        StudentFeeDue.objects.filter(pk=october.id).update(status=FeeDueStatus.CANCELLED)

        for due in (april, july, october):
            with self.subTest(due=due.label):
                response = self.waive(due)
                self.assertEqual(409, response.status_code)
                self.assertEqual(("FEE_DUE_NOT_WAIVABLE", "Only an installment or fine still owed can be waived."),
                                 (response.data["code"], response.data["message"]))

        self.assertEqual(1, AuditLog.objects.filter(action="fee_due.waived").count())

    def test_a_waived_due_cannot_be_paid_and_the_reconcile_leaves_it_alone(self):
        july = self.due("Tuition - July")
        self.waived(july)

        errors = self.refused(self.pay(amount="10.00", allocations=[{"due_id": july.id, "amount": "10.00"}]))
        self.assertEqual(['Installment "Tuition - July" was waived and can\'t be paid.'], errors["allocations"])

        FeeDueService.sync_student(self.aarav, self.year)
        self.conceded("fixed", "500.00")
        july.refresh_from_db()
        self.assertEqual(("waived", Decimal("0.00")), (july.status, july.discount_amount))

    def test_a_waived_due_drops_out_of_the_balances_list(self):
        self.waived(self.due("Tuition - April"))

        row = self.as_user(self.accountant).get(
            "/api/v1/fees/balances", {"academic_year_id": self.year.id}
        ).data["data"][0]

        self.assertEqual(("4000.00", "0.00", "3000.00", "1000.00"),
                         (row["charged"], row["paid"], row["balance"], row["overdue"]))

    def test_a_reason_is_required(self):
        april = self.due("Tuition - April")

        for body, message in (({}, "The reason field is required."),
                              ({"reason": "ab"}, "The reason field must be at least 3 characters."),
                              ({"reason": "x" * 256}, "The reason field must not be greater than 255 characters.")):
            with self.subTest(body=body):
                response = self.as_user(self.accountant).post(f"{DUES}/{april.id}/waive", body, format="json")
                self.assertEqual(422, response.status_code)
                self.assertEqual([message], response.data["details"]["errors"]["reason"])

        self.assertEqual(FeeDueStatus.PENDING, self.due("Tuition - April").status)


# -- late fines -----------------------------------------------------------------------


class LateFines(AdjustmentsTestCase):
    def setUp(self):
        super().setUp()
        self.fines_on(amount=50, grace=5)

    def test_one_fine_per_installment_unpaid_past_its_grace(self):
        output = self.run_fines("--school", str(self.school.id))

        # April (due 10 April) is fined; July (10 July + 5 days = today) is not yet.
        self.assertEqual(
            [("Late fine - Tuition - April", "2026-07-15", "50.00", "pending", "Tuition - April")],
            self.fines(),
        )
        fine = StudentFeeDue.objects.get(kind="late_fine")
        april = self.due("Tuition - April")
        self.assertEqual(
            (self.tuition.id, self.year.id, "INR", None, None, Decimal("0.00"), april.id),
            (fine.fee_head_id, fine.academic_year_id, fine.currency_code, fine.fee_structure_id,
             fine.fee_installment_id, fine.discount_amount, fine.fine_for_due_id),
        )
        self.assertIn(f"School {self.school.id}: 1 fines of 50.00 added for 1 students.", output)

    def test_the_grace_boundary_exactly(self):
        # 10 July + 5 days = 15 July: not before today, so no fine.
        self.run_fines()
        self.assertNotIn("Tuition - July", [parent for *_, parent in self.fines()])

        # A day later it is.
        with at(dt.datetime(2026, 7, 16, 6, 0, tzinfo=dt.timezone.utc)):
            self.run_fines()

        self.assertEqual(
            [("Tuition - April", "2026-07-15"), ("Tuition - July", "2026-07-16")],
            [(parent, day) for _, day, _, _, parent in self.fines()],
        )

    def test_the_day_is_the_schools_not_the_servers(self):
        # 20:00 UTC on 15 July is 01:30 on 16 July in Kolkata.
        with at(dt.datetime(2026, 7, 15, 20, 0, tzinfo=dt.timezone.utc)):
            self.run_fines()

        self.assertEqual(
            [("Tuition - April", "2026-07-16"), ("Tuition - July", "2026-07-16")],
            [(parent, day) for _, day, _, _, parent in self.fines()],
        )

    def test_running_twice_fines_once_and_the_database_refuses_a_second(self):
        self.run_fines()
        output = self.run_fines()

        self.assertEqual(1, len(self.fines()))
        self.assertIn("0 fines", output)
        self.assertEqual(1, AuditLog.objects.filter(action="fee_late_fines.applied").count())

        fine = StudentFeeDue.objects.get(kind="late_fine")
        fine.pk = None

        with self.assertRaises(IntegrityError), transaction.atomic():
            fine.save()

    def test_nobody_inactive_or_gone_is_fined(self):
        gone = self.student("Bina", status=StudentStatus.INACTIVE)
        left = self.student("Chetan")
        FeeDueService.sync_student(left, self.year)
        StudentFeeDue.objects.create(
            school=self.school, student=gone, academic_year=self.year, fee_head=self.tuition, label="Tuition - Old",
            due_date=dt.date(2026, 4, 10), amount="1000.00", currency_code="INR",
        )
        StudentEnrollment.objects.filter(student=left).update(status=EnrollmentStatus.LEFT)

        self.run_fines()

        self.assertEqual([], self.fines(gone))
        self.assertEqual([], self.fines(left))
        self.assertEqual(1, len(self.fines()))

    def test_no_fines_with_the_amount_at_zero_or_the_module_off(self):
        self.fines_on(amount=0)
        self.assertIn("nothing fined (late fine amount is 0)", self.run_fines("--school", str(self.school.id)))

        self.fines_on(amount=50)
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)
        self.assertIn("nothing fined (fees module off)", self.run_fines("--school", str(self.school.id)))
        self.assertEqual("No school has fees switched on. Nothing to do.\n", self.run_fines())

        self.assertEqual(0, StudentFeeDue.objects.filter(kind="late_fine").count())
        self.assertFalse(AuditLog.objects.filter(action="fee_late_fines.applied").exists())

    def test_the_defaults_fine_nobody(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(settings=None)

        self.run_fines()

        self.assertEqual([], self.fines())

    def test_a_paid_installment_is_not_fined_and_a_partly_paid_one_is(self):
        bina = self.student("Bina")
        FeeDueService.sync_student(bina, self.year)
        self.paid(amount="1000.00")
        self.paid(bina, amount="400.00")

        self.run_fines()

        self.assertEqual([], self.fines())
        self.assertEqual(["Tuition - April"], [parent for *_, parent in self.fines(bina)])

    def test_an_installment_a_discount_settled_is_not_fined(self):
        self.conceded("percent", "100")

        self.run_fines()

        self.assertEqual([], self.fines())

    def test_paying_the_installment_later_keeps_the_fine_and_waiving_the_fine_forgives_it(self):
        self.run_fines()
        fine = StudentFeeDue.objects.get(kind="late_fine")
        april = self.due("Tuition - April")

        self.paid(amount="1000.00", allocations=[{"due_id": april.id, "amount": "1000.00"}])
        fine.refresh_from_db()
        self.assertEqual("pending", fine.status)

        data = self.waived(fine, reason="Bank delay")
        self.assertEqual(("late_fine", april.id, "waived", "0.00"),
                         (data["kind"], data["fine_for_due_id"], data["status"], data["balance"]))

        # And a waived fine is not fined again, nor its installment.
        self.run_fines()
        self.assertEqual(1, StudentFeeDue.objects.filter(kind="late_fine").count())

    def test_a_fine_is_paid_like_any_due_oldest_first_by_its_date(self):
        self.run_fines()

        receipt = self.paid(amount="2050.00")

        self.assertEqual(
            ["Tuition - April", "Tuition - July", "Late fine - Tuition - April"],
            [row["label"] for row in receipt["allocations"]],
        )
        self.assertEqual("paid", StudentFeeDue.objects.get(kind="late_fine").status)
        # The PDF prints it, with its own label where an installment's name goes.
        pdf = receipt_pdf.render(FeeReceiptService.load(receipt["id"]))
        self.assertTrue(pdf.startswith(b"%PDF"))
        self.assertEqual("Late fine - Tuition - April",
                         receipt_pdf.installment_name(StudentFeeDue.objects.get(kind="late_fine")))

    def test_a_fine_is_never_discounted(self):
        self.run_fines()

        self.conceded("fixed", "10.00", head=None)
        self.conceded("fixed", "10.00", head="tuition")

        self.assertEqual(Decimal("0.00"), StudentFeeDue.objects.get(kind="late_fine").discount_amount)

    def test_the_reconcile_never_touches_a_fine_and_moving_class_leaves_it_owed(self):
        self.published(TUITION_9, school_class=self.class9)
        self.run_fines()

        self.patch_student(self.aarav, {"class_section_id": self.section9.id})
        call_command("sync_fee_dues", "--school", str(self.school.id), stdout=io.StringIO())

        fine = StudentFeeDue.objects.get(kind="late_fine")
        self.assertEqual(("pending", Decimal("50.00")), (fine.status, fine.amount))
        self.assertEqual("cancelled", self.due("Tuition - October").status)

    def test_a_student_who_left_keeps_the_fines_already_owed(self):
        self.run_fines()

        response = self.as_user(self.admin).patch(f"/api/v1/students/{self.aarav.id}/deactivate")
        self.assertEqual(200, response.status_code)

        self.assertEqual("pending", StudentFeeDue.objects.get(kind="late_fine").status)

    def test_every_school_with_fines_on_on_its_own_settings(self):
        other = factories.SchoolFactory(currency_code="USD", timezone="America/New_York")
        factories.ModuleSettingFactory(school=other, module="fees")
        self.fines_on(amount=7, grace=0, school=other)
        year = factories.AcademicYearFactory(
            school=other, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        student = factories.StudentFactory(school=other)
        head = FeeHead.objects.create(school=other, name="Tuition")
        StudentFeeDue.objects.create(
            school=other, student=student, academic_year=year, fee_head=head, label="Tuition - July",
            due_date=dt.date(2026, 7, 14), amount="100.00", currency_code="USD",
        )

        output = self.run_fines()

        self.assertIn(f"School {other.id}: 1 fines of 7.00 added for 1 students.", output)
        self.assertIn(f"School {self.school.id}: 1 fines of 50.00 added for 1 students.", output)
        self.assertIn("fines added : 2", output)
        fine = StudentFeeDue.objects.get(school=other, kind="late_fine")
        # New York's 15 July, 02:00: the fine is dated that day, in dollars.
        self.assertEqual((dt.date(2026, 7, 15), "USD"), (fine.due_date, fine.currency_code))
        audits = AuditLog.objects.filter(action="fee_late_fines.applied").order_by("school_id")
        self.assertEqual(
            [(self.school.id, {"fines": 1, "students": 1}), (other.id, {"fines": 1, "students": 1})],
            [(row.school_id, {"fines": row.new_values["fines"], "students": row.new_values["students"]})
             for row in audits],
        )
        self.assertIsNone(audits[0].user_id)

    def test_an_unknown_school_is_an_error(self):
        with self.assertRaises(CommandError):
            self.run_fines("--school", "999999")

    def test_the_label_fits_the_column(self):
        self.assertEqual(130, len(fine_label("x" * 130)))
        self.assertEqual("Late fine - Tuition - April", fine_label("Tuition - April"))

    def test_service_directly(self):
        run = LateFineService.apply(self.school.id)

        self.assertEqual((1, 1, Decimal("50.00"), None), (run.fines, run.students, run.amount, run.skipped))


# Receipts and fines live together in the receipt numbering too: unchanged.
class ReceiptsStillNumber(AdjustmentsTestCase):
    def test_a_fine_paid_on_its_own(self):
        self.fines_on(amount=50, grace=5)
        self.run_fines()
        fine = StudentFeeDue.objects.get(kind="late_fine")

        receipt = self.paid(amount="50.00", allocations=[{"due_id": fine.id, "amount": "50.00"}])

        self.assertEqual("RCPT-2026-27-00001", receipt["receipt_number"])
        self.assertEqual(Decimal("4000.00"), FeeReceipt.objects.get().balance_before - Decimal("50.00"))

    def test_route_fee_stays_discounted_by_an_all_heads_discount(self):
        self.conceded("fixed", "100.00", head=None)
        self.published(ROUTE_A, route=self.route_a)
        self.ride(self.aarav, self.route_a, self.stop_a)

        statement = self.as_user(self.accountant).get(f"/api/v1/fees/students/{self.aarav.id}").data

        # 4 Tuition installments and 2 bus ones, 100 off each.
        self.assertEqual("600.00", statement["totals"]["discount"])
        bus = next(due for due in statement["dues"] if due["label"] == "Transport - Bus 1")
        self.assertEqual((ROUTE_A[0][2], "100.00"), (bus["amount"], bus["discount_amount"]))
