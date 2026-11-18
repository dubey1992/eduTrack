"""Advances paid to staff, recovered from payslips (docs/dashboard.md, D4).

The payroll test school: September 2026, the clock on the 30th. Rahul (the
teacher) earns 30,000 basic + 6,000 HRA - 1,800 PF.
"""

import datetime as dt
from decimal import Decimal

from school import factories
from school.enums import UserRole
from school.models import AuditLog, PayslipLine, School, StaffAdvance

from .test_payroll_api import PayrollTestCase

ADVANCES = "/api/v1/payroll/advances"


class AdvanceTestCase(PayrollTestCase):
    def setUp(self):
        super().setUp()
        self.set_salaries()

    def record(self, user=None, **overrides):
        body = {
            "staff_profile_id": self.teacher_profile.id,
            "amount": "3000.00",
            "paid_on": "2026-07-20",
            "payment_mode": "cash",
            "monthly_recovery": "2000.00",
            "reason": "Medical emergency",
            **overrides,
        }

        return self.as_user(user or self.accountant).post(ADVANCES, body, format="json")

    def recorded(self, **overrides) -> dict:
        response = self.record(**overrides)
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def run_month(self, month: int) -> dict:
        response = self.generate(month=month)
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def advance(self, advance_id) -> dict:
        return self.as_user(self.accountant).get(f"{ADVANCES}/{advance_id}").data

    def recovery_lines(self, run_id) -> list[tuple]:
        return list(
            PayslipLine.objects.filter(payslip__payroll_run_id=run_id, source="advance")
            .order_by("id")
            .values_list("type", "name", "amount")
        )


class Recording(AdvanceTestCase):
    def test_an_advance_is_logged_in_the_schools_currency_and_audited(self):
        data = self.recorded()

        self.assertEqual(
            ("3000.00", "INR", "2000.00", "2026-08-01", "August 2026", "active", "0.00", "3000.00", True),
            tuple(data[key] for key in ("amount", "currency_code", "monthly_recovery", "recovery_starts",
                                        "recovery_starts_label", "status", "recovered", "remaining", "can_cancel")),
        )
        self.assertEqual(("Rahul Verma", "TCH-1", []), (data["employee_name"], data["employee_code"], data["recoveries"]))
        self.assertTrue(AuditLog.objects.filter(action="staff_advance.created", entity_id=data["id"]).exists())

    def test_recovery_can_start_in_a_later_month(self):
        self.assertEqual("2026-10-01", self.recorded(recovery_starts="2026-10")["recovery_starts"])

    def test_the_rules(self):
        cases = {
            "monthly_recovery": {"monthly_recovery": "4000.00"},
            "paid_on": {"paid_on": "2026-10-01"},
            "payment_mode": {"payment_mode": "barter"},
            "recovery_starts": {"recovery_starts": "2026-06"},
            "reason": {"reason": "x"},
            "amount": {"amount": "0"},
        }
        for field, body in cases.items():
            with self.subTest(field=field):
                response = self.record(**body)
                self.assertEqual(422, response.status_code, response.data)
                self.assertIn(field, response.data["details"]["errors"])

        self.assertIn("recovery_starts", self.record(recovery_starts="2026-13").data["details"]["errors"])
        self.assertEqual(0, StaffAdvance.objects.count())

    def test_the_fee_books_date_lock_does_not_touch_it(self):
        School.objects.filter(pk=self.school.pk).update(fees_locked_until=dt.date(2026, 9, 30))

        self.assertEqual(201, self.record(paid_on="2026-09-10").status_code)


class Recovering(AdvanceTestCase):
    def test_each_run_takes_the_monthly_amount_and_the_last_takes_only_what_is_left(self):
        advance = self.recorded()  # 3,000 at 2,000 a month from August

        august = self.run_month(8)
        self.assertEqual([("deduction", "Advance recovery", Decimal("2000.00"))], self.recovery_lines(august["id"]))
        # On a draft it is pending, not recovered.
        self.assertEqual(("0.00", "2000.00", "3000.00"),
                         tuple(self.advance(advance["id"])[key] for key in ("recovered", "pending", "remaining")))

        self.finalize(august["id"])
        self.assertEqual(("2000.00", "0.00", "1000.00"),
                         tuple(self.advance(advance["id"])[key] for key in ("recovered", "pending", "remaining")))

        september = self.run_month(9)
        self.assertEqual([("deduction", "Advance recovery", Decimal("1000.00"))], self.recovery_lines(september["id"]))
        self.finalize(september["id"])

        done = self.advance(advance["id"])
        self.assertEqual(("repaid", "3000.00", "0.00", False),
                         (done["status"], done["recovered"], done["remaining"], done["can_cancel"]))
        self.assertEqual([("August 2026", "2000.00"), ("September 2026", "1000.00")],
                         [(row["period_label"], row["amount"]) for row in done["recoveries"]])

    def test_the_line_says_what_it_repays_and_reaches_the_payslip(self):
        advance = self.recorded()
        run = self.run_month(8)

        slip = self.payslip_of(run["id"], self.teacher_profile)
        line = self.as_user(self.accountant).get(f"/api/v1/payroll/payslips/{slip.id}").data["lines"][-1]

        self.assertEqual(("Advance recovery", "2000.00", advance["id"], False),
                         (line["name"], line["amount"], line["staff_advance_id"], line["is_adjustment"]))
        self.assertEqual("Advance of INR 3,000.00 paid 07/20/2026: INR 1,000.00 left after this", line["note"])

    def test_regenerating_a_draft_never_counts_it_twice(self):
        advance = self.recorded()
        run = self.run_month(8)

        for _ in range(2):
            response = self.as_user(self.accountant).post(f"/api/v1/payroll/runs/{run['id']}/regenerate")
            self.assertEqual(200, response.status_code, response.data)

        self.assertEqual(1, len(self.recovery_lines(run["id"])))
        self.assertEqual("2000.00", self.advance(advance["id"])["pending"])

    def test_never_more_than_the_payslip_can_bear(self):
        self.recorded(amount="90000.00", monthly_recovery="90000.00")
        run = self.run_month(8)

        slip = self.payslip_of(run["id"], self.teacher_profile)
        self.assertEqual((Decimal("0.00"), Decimal("0.00")), (slip.net_pay, slip.shortfall))
        # Basic and HRA, less PF: all the month could give.
        self.assertEqual(slip.gross_earnings - Decimal("1800.00"), self.recovery_lines(run["id"])[0][2])

    def test_two_advances_are_recovered_oldest_first(self):
        self.recorded(amount="1000.00", monthly_recovery="1000.00", paid_on="2026-07-01")
        self.recorded(amount="500.00", monthly_recovery="500.00", paid_on="2026-07-15")

        run = self.run_month(8)

        self.assertEqual([Decimal("1000.00"), Decimal("500.00")], [row[2] for row in self.recovery_lines(run["id"])])

    def test_nothing_before_recovery_starts_and_nothing_for_anybody_else(self):
        self.recorded(recovery_starts="2026-09")

        august = self.run_month(8)

        self.assertEqual([], self.recovery_lines(august["id"]))


class Cancelling(AdvanceTestCase):
    def cancel(self, advance_id, reason="Entered twice", user=None):
        return self.as_user(user or self.accountant).post(f"{ADVANCES}/{advance_id}/cancel", {"reason": reason}, format="json")

    def test_while_nothing_is_recovered_it_is_cancelled_and_a_draft_stops_recovering_it(self):
        advance = self.recorded()
        run = self.run_month(8)
        slip = self.payslip_of(run["id"], self.teacher_profile)
        before = slip.net_pay

        response = self.cancel(advance["id"])

        self.assertEqual(("cancelled", "0.00"), (response.data["status"], response.data["remaining"]))
        slip.refresh_from_db()
        self.assertEqual(before + Decimal("2000.00"), slip.net_pay)
        self.assertEqual([], self.recovery_lines(run["id"]))
        self.assertTrue(AuditLog.objects.filter(action="staff_advance.cancelled").exists())

    def test_once_partly_recovered_it_stays(self):
        advance = self.recorded()
        self.finalize(self.run_month(8)["id"])

        response = self.cancel(advance["id"])

        self.assertEqual((409, "STAFF_ADVANCE_NOT_CANCELLABLE"), (response.status_code, response.data["code"]))

    def test_twice_is_refused_and_a_reason_is_needed(self):
        advance = self.recorded()

        self.assertEqual(422, self.cancel(advance["id"], reason="").status_code)
        self.assertEqual(200, self.cancel(advance["id"]).status_code)
        self.assertEqual(409, self.cancel(advance["id"]).status_code)


class WhoMay(AdvanceTestCase):
    def test_the_accountant_and_school_admin_record_and_a_teacher_does_not(self):
        self.assertEqual(201, self.record().status_code)
        self.assertEqual(201, self.record(user=self.admin).status_code)
        self.assertEqual(403, self.record(user=self.teacher).status_code)
        self.assertEqual(403, self.as_user(self.teacher).get(ADVANCES).status_code)

    def test_a_super_admin_reads_but_records_nothing(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.recorded()

        self.assertEqual(1, self.as_user(root).get(ADVANCES, {"school_id": self.school.id}).data["meta"]["total"])
        self.assertEqual(403, self.record(user=root).status_code)

    def test_another_schools_admin_can_neither_pay_nor_see_this_schools_staff(self):
        other = factories.SchoolFactory()
        their_admin = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)
        advance = self.recorded()

        self.assertEqual(403, self.record(user=their_admin).status_code)
        self.assertEqual(0, self.as_user(their_admin).get(ADVANCES).data["meta"]["total"])
        self.assertEqual(403, self.as_user(their_admin).get(f"{ADVANCES}/{advance['id']}").status_code)

    def test_an_unknown_employee_is_a_validation_error(self):
        response = self.record(staff_profile_id=999999)

        self.assertEqual(422, response.status_code)
        self.assertIn("staff_profile_id", response.data["details"]["errors"])


class TheList(AdvanceTestCase):
    def test_filtered_by_what_is_left(self):
        repaid = self.recorded(amount="2000.00")
        open_ = self.recorded(staff_profile_id=self.accountant_profile.id, amount="500.00", monthly_recovery="100.00")
        cancelled = self.recorded(amount="100.00", monthly_recovery="100.00", reason="Wrong person")
        self.as_user(self.accountant).post(f"{ADVANCES}/{cancelled['id']}/cancel", {"reason": "Entered twice"}, format="json")
        self.finalize(self.run_month(8)["id"])

        def ids(status):
            return [row["id"] for row in self.as_user(self.accountant).get(ADVANCES, {"status": status}).data["data"]]

        self.assertEqual([repaid["id"]], ids("repaid"))
        self.assertEqual([open_["id"]], ids("active"))
        self.assertEqual([cancelled["id"]], ids("cancelled"))
        self.assertEqual(3, len(ids("")))
