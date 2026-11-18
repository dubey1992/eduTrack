"""The fee books' date lock (docs/dashboard.md, D3).

Same frozen clock as every fee test: "now" is 15 July 2026, 11:30 in
Kolkata. Aarav owes 1,000 a quarter, due 10 April, July, October, January.
"""

from school import factories
from school.enums import UserRole
from school.models import AuditLog, School, StudentFeeDue

from .test_fees_adjustments import AdjustmentsTestCase
from .test_fees_credit import CreditTestCase

LOCK = "/api/v1/fees/lock"


class LockTestCase(AdjustmentsTestCase):
    def lock(self, until, user=None, **body):
        return self.as_user(user or self.accountant).put(LOCK, {"locked_until": until, **body}, format="json")

    def locked(self, until, **kwargs) -> dict:
        response = self.lock(until, **kwargs)
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def refused_by_lock(self, response):
        self.assertEqual((422, "FEES_LOCKED"), (response.status_code, response.data["code"]), response.data)


class ReadingAndMoving(LockTestCase):
    def test_nothing_is_locked_to_begin_with(self):
        data = self.as_user(self.admin).get(LOCK).data

        self.assertEqual({"school_id": self.school.id, "locked_until": None, "today": "2026-07-15",
                          "can_change": True}, data)

    def test_the_accountant_and_the_school_admin_lock_and_both_are_audited(self):
        self.assertEqual("2026-07-14", self.locked("2026-07-14")["locked_until"])
        self.assertEqual("2026-07-15", self.locked("2026-07-15", user=self.admin)["locked_until"])

        entries = list(AuditLog.objects.filter(module="fees", action="fees.locked").order_by("id"))
        self.assertEqual(
            [({"locked_until": None}, "2026-07-14", self.accountant.id),
             ({"locked_until": "2026-07-14"}, "2026-07-15", self.admin.id)],
            [(entry.old_values, entry.new_values["locked_until"], entry.user_id) for entry in entries],
        )

    def test_a_day_to_come_cannot_be_locked(self):
        response = self.lock("2026-07-16")

        self.assertEqual(422, response.status_code)
        self.assertIn("locked_until", response.data["details"]["errors"])

    def test_nonsense_is_refused(self):
        self.assertEqual(422, self.lock("yesterday").status_code)

    def test_reopening_closed_days_needs_a_reason_and_is_audited_with_it(self):
        self.locked("2026-07-14")

        for until in ("2026-07-01", None):
            response = self.lock(until)
            self.assertEqual(422, response.status_code, until)
            self.assertIn("reason", response.data["details"]["errors"])

        self.assertEqual("2026-07-01", self.locked("2026-07-01", reason="Receipt entered on the wrong day")["locked_until"])
        self.assertIsNone(self.locked(None, reason="Audit finished")["locked_until"])

        entries = AuditLog.objects.filter(action="fees.unlocked").order_by("id")
        self.assertEqual(["Receipt entered on the wrong day", "Audit finished"],
                         [entry.new_values["reason"] for entry in entries])

    def test_moving_it_on_needs_no_reason(self):
        self.locked("2026-07-01")

        self.assertEqual("2026-07-14", self.locked("2026-07-14")["locked_until"])


class WhoMayMoveIt(LockTestCase):
    def test_a_teacher_or_head_neither_reads_nor_moves_it(self):
        for role in (UserRole.TEACHER, UserRole.HOD):
            user = factories.UserFactory(school=self.school, role=role)
            self.assertEqual(403, self.as_user(user).get(LOCK).status_code, role)
            self.assertEqual(403, self.lock("2026-07-14", user=user).status_code, role)

    def test_a_super_admin_reads_a_school_s_lock_but_does_not_move_it(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        data = self.as_user(root).get(LOCK, {"school_id": self.school.id}).data
        self.assertFalse(data["can_change"])
        self.assertEqual(403, self.lock("2026-07-14", user=root, school_id=self.school.id).status_code)

    def test_a_head_given_fees_by_the_matrix_still_cannot_move_it(self):
        from school.models import RolePermission

        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        RolePermission.objects.create(role="HOD", module="fees", level="manage")

        self.assertFalse(self.as_user(hod).get(LOCK).data["can_change"])
        self.assertEqual(403, self.lock("2026-07-14", user=hod).status_code)

    def test_another_school_s_admin_cannot_lock_this_school(self):
        other = factories.SchoolFactory(currency_code="USD")
        factories.ModuleSettingFactory(school=other, module="fees")
        their_admin = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)

        # Naming this school is ignored: they lock their own.
        data = self.locked("2026-07-14", user=their_admin, school_id=self.school.id)

        self.assertEqual(other.id, data["school_id"])
        self.assertIsNone(School.objects.get(pk=self.school.id).fees_locked_until)


class WhatALockStops(LockTestCase):
    def test_a_receipt_dated_on_or_before_the_lock_is_refused_and_a_later_one_is_not(self):
        self.locked("2026-07-14")

        self.refused_by_lock(self.pay(receipt_date="2026-07-14"))
        self.refused_by_lock(self.pay(receipt_date="2026-06-30"))
        self.assertEqual(201, self.pay(receipt_date="2026-07-15").status_code)

    def test_the_refusal_says_until_when_and_who_can_reopen(self):
        self.locked("2026-07-14")

        response = self.pay(receipt_date="2026-07-10")

        self.assertIn("07/14/2026", response.data["message"])
        self.assertIn("School Admin or Accountant", response.data["message"])
        self.assertEqual({"locked_until": "2026-07-14"}, response.data["details"])

    def test_a_closed_day_s_receipt_cannot_be_cancelled_and_an_open_one_can(self):
        old = self.paid(receipt_date="2026-07-10")
        today = self.paid(amount="200.00", receipt_date="2026-07-15")
        self.locked("2026-07-14")

        self.refused_by_lock(self.cancel(old["id"]))
        self.assertEqual(200, self.cancel(today["id"]).status_code)

    def test_discounts_and_waivers_are_dated_today(self):
        self.locked("2026-07-14")
        self.assertEqual(201, self.concede().status_code)

        self.locked("2026-07-15")
        self.refused_by_lock(self.concede(value="100.00", reason="Second child"))
        self.refused_by_lock(self.waive(self.due("Tuition - July")))

    def test_a_discount_cannot_be_revoked_on_a_closed_day(self):
        concession = self.conceded()
        self.locked("2026-07-15")

        self.refused_by_lock(self.revoke(concession["id"]))

    def test_late_fines_are_not_charged_on_a_closed_day(self):
        self.fines_on(amount=50, grace=2)
        self.locked("2026-07-15")

        out = self.run_fines()

        self.assertEqual([], self.fines())
        self.assertIn("locked", out)

    def test_nothing_changed_when_a_receipt_is_refused(self):
        self.locked("2026-07-14")
        before = list(StudentFeeDue.objects.filter(student=self.aarav).values_list("paid_amount", flat=True))

        self.pay(receipt_date="2026-07-01")

        self.assertEqual(before, list(StudentFeeDue.objects.filter(student=self.aarav).values_list("paid_amount", flat=True)))

    def test_another_school_s_lock_changes_nothing_here(self):
        other = factories.SchoolFactory(fees_locked_until="2026-07-15")

        self.assertEqual(201, self.pay(receipt_date="2026-07-10").status_code)
        self.assertEqual("2026-07-15", str(School.objects.get(pk=other.pk).fees_locked_until))


class Refunds(CreditTestCase):
    def test_a_refund_dated_on_a_closed_day_is_refused(self):
        self.paid(amount="4250.00")  # 250 held as credit
        self.as_user(self.accountant).put(LOCK, {"locked_until": "2026-07-14"}, format="json")

        refused = self.refund("50.00", refund_date="2026-07-14")
        self.assertEqual((422, "FEES_LOCKED"), (refused.status_code, refused.data["code"]))

        self.assertEqual(201, self.refund("50.00", refund_date="2026-07-15").status_code)
