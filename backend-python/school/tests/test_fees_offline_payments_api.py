"""Fees taken offline (docs/offline-web.md, O4a): a payment the counter took
while the internet was down becomes the real receipt when it arrives - or,
when the dues were paid meanwhile or the day's books are closed, waits for
an Accountant or School Admin to keep it on the account or hand it back.
Sending it twice records it once; another school's never reaches it.
"""

import datetime as dt

from school import factories
from school.enums import UserRole
from school.models import AuditLog, FeeReceipt, OfflineFeePayment, School, StudentFeeCredit

from .test_fees_receipts import ReceiptsTestCase
from .test_fees_receipts_api import school_with_a_charged_student

OFFLINE = "/api/v1/fees/offline-payments"


class OfflineTestCase(ReceiptsTestCase):
    counter = 0

    def offline(self, student=None, amount="1000.00", user=None, **fields):
        OfflineTestCase.counter += 1
        body = {
            "client_id": f"client-{OfflineTestCase.counter:08d}",
            "provisional_number": f"P-K7Q2-{OfflineTestCase.counter}",
            "taken_at": "2026-07-15T04:30:00Z",
            "student_id": (student or self.aarav).id,
            "receipt_date": "2026-07-15",
            "amount": amount,
            "payment_mode": "cash",
            **fields,
        }
        return self.as_user(user or self.accountant).post(OFFLINE, body, format="json")

    def sent(self, *args, **kwargs) -> dict:
        response = self.offline(*args, **kwargs)
        self.assertEqual(201, response.status_code, response.data)
        return response.data

    def july(self) -> list[dict]:
        return [{"due_id": self.due("Tuition - July").id, "amount": "1000.00"}]

    def settle(self, payment_id, body, user=None):
        return self.as_user(user or self.accountant).post(f"{OFFLINE}/{payment_id}/settle", body, format="json")

    def lock_until(self, day: str):
        School.objects.filter(pk=self.school.id).update(fees_locked_until=day)


class Arriving(OfflineTestCase):
    def test_the_dues_still_owed_it_becomes_the_receipt_saying_where_it_came_from(self):
        data = self.sent(allocations=self.july(), note="Paid by his uncle")

        self.assertEqual("receipted", data["status"])
        self.assertIsNone(data["problem"])
        receipt = FeeReceipt.objects.get(pk=data["receipt"]["id"])
        self.assertEqual("RCPT-2026-27-00001", receipt.receipt_number)
        self.assertEqual("Paid by his uncle Taken offline on 2026-07-15 as P-K7Q2-%d." % OfflineTestCase.counter,
                         receipt.note)
        self.assertEqual(("Tuition - July", "1000.00", "paid"), self.standing()[1])
        self.assertEqual(self.accountant.name, data["taken_by"])

    def test_without_chosen_dues_it_pays_the_oldest_first_as_the_counter_would(self):
        data = self.sent(amount="1500.00")

        self.assertEqual("receipted", data["status"])
        self.assertEqual([("Tuition - April", "1000.00", "paid"), ("Tuition - July", "500.00", "partial")],
                         self.standing()[:2])

    def test_sent_twice_it_is_recorded_once(self):
        first = self.sent(allocations=self.july())
        again = self.as_user(self.accountant).post(OFFLINE, {
            "client_id": first["client_id"],
            "provisional_number": first["provisional_number"],
            "taken_at": "2026-07-15T04:30:00Z",
            "student_id": self.aarav.id,
            "receipt_date": "2026-07-15",
            "amount": "1000.00",
            "payment_mode": "cash",
            "allocations": self.july(),
        }, format="json")

        self.assertEqual(200, again.status_code, again.data)
        self.assertEqual(first["id"], again.data["id"])
        self.assertEqual(1, FeeReceipt.objects.count())
        self.assertEqual(1, OfflineFeePayment.objects.count())

    def test_dues_paid_meanwhile_keep_it_to_settle_with_what_was_found(self):
        self.paid(allocations=self.july())

        data = self.sent(allocations=self.july())

        self.assertEqual("to_settle", data["status"])
        self.assertEqual('Installment "Tuition - July" is already paid.', data["problem"])
        self.assertIsNone(data["receipt"])
        self.assertEqual(1, FeeReceipt.objects.count())
        self.assertEqual(("Tuition - July", "1000.00", "paid"), self.standing()[1])

    def test_a_closed_day_keeps_it_to_settle(self):
        self.lock_until("2026-07-15")

        data = self.sent(allocations=self.july())

        self.assertEqual("to_settle", data["status"])
        self.assertIn("closed up to", data["problem"])
        self.assertEqual(0, FeeReceipt.objects.count())

    def test_audited_either_way(self):
        self.sent(allocations=self.july())
        self.paid(allocations=[{"due_id": self.due("Tuition - October").id, "amount": "1000.00"}])
        self.sent(allocations=[{"due_id": self.due("Tuition - October").id, "amount": "1000.00"}])

        rows = AuditLog.objects.filter(action="offline_fee_payment.received").order_by("id")
        self.assertEqual(["receipted", "to_settle"], [row.new_values["status"] for row in rows])

    def test_shape_errors_are_named(self):
        for fields, field in (
            ({"payment_mode": "upi"}, "payment_mode"),
            ({"client_id": "short"}, "client_id"),
            ({"client_id": "bad id with spaces"}, "client_id"),
            ({"provisional_number": "RCPT-1"}, "provisional_number"),
            ({"taken_at": "this morning"}, "taken_at"),
            ({"taken_at": "2026-07-15T04:30:00"}, "taken_at"),
            ({"payment_mode": "cheque"}, "reference"),
            ({"amount": "0"}, "amount"),
            ({"receipt_date": "2026-07-16"}, "receipt_date"),
        ):
            with self.subTest(fields=fields):
                errors = self.refused(self.offline(**fields))
                self.assertIn(field, errors)

        self.assertEqual(0, OfflineFeePayment.objects.count())

    def test_a_cheque_with_its_number_is_taken(self):
        self.assertEqual("receipted", self.sent(payment_mode="cheque", reference="004512")["status"])


class WhoMaySend(OfflineTestCase):
    def test_a_school_admin_may(self):
        self.assertEqual("receipted", self.sent(user=self.admin)["status"])

    def test_a_teacher_or_the_super_admin_may_not(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        for user in (teacher, root):
            with self.subTest(role=user.role):
                self.assertEqual(403, self.offline(user=user).status_code)

        self.assertEqual(0, OfflineFeePayment.objects.count())

    def test_another_schools_student_is_invalid(self):
        _, _, their_student, _ = school_with_a_charged_student()

        self.assertIn("student_id", self.refused(self.offline(student=their_student)))

    def test_another_school_sending_the_same_client_id_is_its_own_payment(self):
        _, _, their_student, their_accountant = school_with_a_charged_student()
        ours = self.sent()
        theirs = self.as_user(their_accountant).post(OFFLINE, {
            "client_id": ours["client_id"],
            "provisional_number": "P-ZZ-1",
            "taken_at": "2026-07-15T04:30:00Z",
            "student_id": their_student.id,
            "receipt_date": "2026-07-15",
            "amount": "1000.00",
            "payment_mode": "cash",
        }, format="json")

        self.assertEqual(201, theirs.status_code, theirs.data)
        self.assertNotEqual(ours["id"], theirs.data["id"])
        self.assertEqual(their_student.id, theirs.data["student"]["id"])


class TheList(OfflineTestCase):
    def test_newest_first_filtered_by_status_and_only_the_schools_own(self):
        self.sent(allocations=self.july())
        self.paid(allocations=[{"due_id": self.due("Tuition - October").id, "amount": "1000.00"}])
        waiting = self.sent(allocations=[{"due_id": self.due("Tuition - October").id, "amount": "1000.00"}])
        _, _, their_student, their_accountant = school_with_a_charged_student()
        self.as_user(their_accountant).post(OFFLINE, {
            "client_id": "theirs-00000001", "provisional_number": "P-ZZ-1", "taken_at": "2026-07-15T04:30:00Z",
            "student_id": their_student.id, "receipt_date": "2026-07-15", "amount": "1000.00",
            "payment_mode": "cash",
        }, format="json")

        everything = self.as_user(self.accountant).get(OFFLINE).data["data"]
        to_settle = self.as_user(self.accountant).get(OFFLINE, {"status": "to_settle"}).data["data"]

        self.assertEqual(2, len(everything))
        self.assertEqual([waiting["id"]], [row["id"] for row in to_settle])
        self.assertEqual(422, self.as_user(self.accountant).get(OFFLINE, {"status": "lost"}).status_code)

    def test_a_teacher_may_not_read_it(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.as_user(teacher).get(OFFLINE).status_code)


class Settling(OfflineTestCase):
    def waiting(self) -> dict:
        self.lock_until("2026-07-15")
        data = self.sent(allocations=self.july())
        self.assertEqual("to_settle", data["status"])
        return data

    def test_kept_on_the_account_it_becomes_a_receipt_dated_today_when_its_day_is_closed(self):
        payment = self.waiting()
        School.objects.filter(pk=self.school.id).update(fees_locked_until="2026-07-14")

        response = self.settle(payment["id"], {"action": "credit"})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("credited", response.data["status"])
        receipt = FeeReceipt.objects.get(pk=response.data["receipt"]["id"])
        self.assertEqual(dt.date(2026, 7, 15), receipt.receipt_date)
        self.assertIn(payment["provisional_number"], receipt.note)
        self.assertEqual(self.accountant.name, response.data["settled_by"])

    def test_kept_with_nothing_owed_the_whole_payment_is_credit(self):
        payment = self.waiting()
        School.objects.filter(pk=self.school.id).update(fees_locked_until=None)
        for label in ("April", "July", "October", "January"):
            self.paid(allocations=[{"due_id": self.due(f"Tuition - {label}").id, "amount": "1000.00"}])

        response = self.settle(payment["id"], {"action": "credit", "reason": "Kept for next term"})

        self.assertEqual("credited", response.data["status"])
        credit = StudentFeeCredit.objects.get(student=self.aarav)
        self.assertEqual("1000.00", str(credit.amount))

    def test_still_closed_today_keeping_it_is_refused_and_it_stays_to_settle(self):
        payment = self.waiting()

        response = self.settle(payment["id"], {"action": "credit"})

        self.assertEqual(422, response.status_code)
        self.assertEqual("FEES_LOCKED", response.data["code"])
        self.assertEqual("to_settle", OfflineFeePayment.objects.get(pk=payment["id"]).status)

    def test_handed_back_needs_how_and_why_and_makes_no_receipt(self):
        payment = self.waiting()

        errors = self.refused(self.settle(payment["id"], {"action": "refund"}))
        self.assertIn("reason", errors)
        self.assertIn("refund_mode", errors)
        self.assertIn("reference", self.refused(self.settle(payment["id"], {
            "action": "refund", "reason": "Paid twice", "refund_mode": "cheque",
        })))

        response = self.settle(payment["id"], {"action": "refund", "reason": "Paid twice", "refund_mode": "cash"},
                               user=self.admin)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("refunded", response.data["status"])
        self.assertEqual("cash", response.data["refund_mode"])
        self.assertEqual("Paid twice", response.data["settle_note"])
        self.assertIsNone(response.data["receipt"])
        self.assertEqual(0, FeeReceipt.objects.count())
        self.assertTrue(AuditLog.objects.filter(action="offline_fee_payment.refunded").exists())

    def test_settled_once_only(self):
        payment = self.waiting()
        self.settle(payment["id"], {"action": "refund", "reason": "Paid twice", "refund_mode": "cash"})

        again = self.settle(payment["id"], {"action": "credit"})

        self.assertEqual(409, again.status_code)
        self.assertEqual("OFFLINE_PAYMENT_SETTLED", again.data["code"])

    def test_a_receipted_payment_has_nothing_to_settle(self):
        payment = self.sent(allocations=self.july())

        self.assertEqual(409, self.settle(payment["id"], {"action": "credit"}).status_code)

    def test_an_unknown_action_is_named(self):
        self.assertIn("action", self.refused(self.settle(self.waiting()["id"], {"action": "keep"})))

    def test_only_an_accountant_or_school_admin_of_that_school_settles(self):
        payment = self.waiting()
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        _, _, _, their_accountant = school_with_a_charged_student()
        body = {"action": "refund", "reason": "Paid twice", "refund_mode": "cash"}

        for user in (teacher, hod, root, their_accountant):
            with self.subTest(role=user.role, school=user.school_id):
                self.assertEqual(403, self.settle(payment["id"], body, user=user).status_code)

        self.assertEqual("to_settle", OfflineFeePayment.objects.get(pk=payment["id"]).status)
        self.assertEqual(404, self.settle(999999, body).status_code)
