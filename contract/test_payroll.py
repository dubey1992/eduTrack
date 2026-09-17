"""Payroll (Phase 19) - served by the Python backend only.

Laravel was frozen before payroll was built (docs/python-migration.md), so
against Laravel these are skipped rather than failed, and its coverage figure
is not charged for them. Against Django they walk the whole run: a salary, a
draft with an adjustment, finalizing, paying, the PDF, and the employee
reading their own payslip - asserting the shapes the Flutter payroll screens
read, and that another school's admin reaches none of it.
"""

from __future__ import annotations

import datetime as dt
import unittest
import zoneinfo

import coverage
import shapes
import world


class Payroll(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/payroll/runs")
        if probe.status == 404:
            raise unittest.SkipTest("payroll is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert Payroll.WORLD is not None
        return Payroll.WORLD

    def ok(self, response, where: str, status: int = 200):
        self.assertEqual(status, response.status, f"{where}\n{response!r}")
        return response.body

    def test_a_month_from_salary_to_payslip(self):
        admin = self.w.admin
        profile = self.w.staff_profile_id
        # The world's schools keep India's calendar; "this month" is theirs.
        today = dt.datetime.now(zoneinfo.ZoneInfo("Asia/Kolkata")).date()

        salaries = admin.get("/payroll/salaries")
        shapes.assert_paginated(self, salaries, "GET /payroll/salaries")
        for row in salaries.data:
            shapes.assert_shape(self, row, shapes.EMPLOYEE_SALARY, "an employee on the salary list")

        saved = self.ok(
            admin.put(
                f"/payroll/salaries/{profile}",
                {
                    "basic_salary": "30000.00",
                    "components": [
                        {"type": "earning", "name": "HRA", "amount": "6000.00"},
                        {"type": "deduction", "name": "PF", "amount": "1800.00"},
                    ],
                },
            ),
            "PUT /payroll/salaries/{id}",
        )
        shapes.assert_shape(self, saved["salary"], shapes.SALARY, "a saved salary")
        self.assertEqual("INR", saved["salary"]["currency_code"], "the school's currency, not the caller's")
        read = self.ok(admin.get(f"/payroll/salaries/{profile}"), "GET /payroll/salaries/{id}")
        self.assertEqual("36000.00", read["salary"]["gross_monthly"])

        run = self.ok(admin.post("/payroll/runs", {"year": today.year, "month": today.month}), "POST /payroll/runs", 201)
        shapes.assert_shape(self, run, shapes.PAYROLL_RUN, "a generated run")
        self.assertEqual("draft", run["status"])
        self.assertIn("missing_salaries", run)

        listed = admin.get("/payroll/runs")
        shapes.assert_paginated(self, listed, "GET /payroll/runs")
        self.ok(admin.get(f"/payroll/runs/{run['id']}"), "GET /payroll/runs/{id}")

        slips = admin.get(f"/payroll/runs/{run['id']}/payslips")
        shapes.assert_paginated(self, slips, "GET /payroll/runs/{id}/payslips")
        mine = next(slip for slip in slips.data if slip["staff_profile_id"] == profile)
        shapes.assert_shape(self, mine, shapes.PAYSLIP, "a payslip in a run")

        adjusted = self.ok(
            admin.post(
                f"/payroll/payslips/{mine['id']}/adjustments",
                {"type": "earning", "name": "Exam duty", "amount": "1500.00", "note": "Board exams"},
            ),
            "POST adjustments",
            201,
        )
        line = next(line for line in adjusted["lines"] if line["is_adjustment"])
        self.ok(admin.delete(f"/payroll/payslips/{mine['id']}/adjustments/{line['id']}"), "DELETE an adjustment")
        self.ok(admin.post(f"/payroll/runs/{run['id']}/regenerate"), "POST regenerate")

        # The employee cannot see a draft.
        self.assertEqual(403, self.w.staff_client.get(f"/payroll/payslips/{mine['id']}").status)

        finalized = self.ok(admin.post(f"/payroll/runs/{run['id']}/finalize"), "POST finalize")
        self.assertEqual("finalized", finalized["status"])

        locked = admin.post(f"/payroll/runs/{run['id']}/regenerate")
        shapes.assert_error(self, locked, 409, "regenerating a finalized run")
        self.assertEqual("PAYROLL_RUN_LOCKED", locked.body["code"])

        paid_on = today.isoformat()
        paid = self.ok(
            admin.post(f"/payroll/payslips/{mine['id']}/pay", {"paid_on": paid_on, "payment_mode": "bank_transfer"}),
            "POST pay a payslip",
        )
        shapes.assert_shape(self, paid, shapes.PAYSLIP, "a paid payslip")
        self.assertEqual("paid", paid["status"])

        settled = self.ok(
            admin.post(f"/payroll/runs/{run['id']}/pay", {"paid_on": paid_on, "payment_mode": "cash"}),
            "POST pay the rest",
        )
        self.assertEqual("paid", settled["status"])

        pdf = admin.get(f"/payroll/payslips/{mine['id']}/pdf")
        self.assertEqual(200, pdf.status, f"GET the payslip PDF\n{pdf!r}")
        self.ok(admin.post(f"/payroll/payslips/{mine['id']}/email"), "POST email the payslip")

        own = self.w.staff_client.get("/payroll/my-payslips")
        shapes.assert_paginated(self, own, "GET /payroll/my-payslips")
        self.assertIn(mine["id"], [slip["id"] for slip in own.data])
        self.ok(self.w.staff_client.get(f"/payroll/payslips/{mine['id']}"), "an employee reads their own payslip")

    def test_a_draft_can_be_thrown_away(self):
        # A month long past, so it never collides with this month's run.
        draft = self.ok(self.w.admin.post("/payroll/runs", {"year": 2025, "month": 1}), "POST an old month", 201)

        gone = self.w.admin.delete(f"/payroll/runs/{draft['id']}")

        self.assertEqual(204, gone.status, f"DELETE a draft run\n{gone!r}")

    def test_another_school_reaches_none_of_it(self):
        outsider = self.w.other_admin

        refused = outsider.put(f"/payroll/salaries/{self.w.staff_profile_id}", {"basic_salary": "1", "components": []})
        shapes.assert_error(self, refused, 403, "another school setting a salary")

    def test_a_bad_salary_is_refused_field_by_field(self):
        refused = self.w.admin.put(
            f"/payroll/salaries/{self.w.staff_profile_id}",
            {"basic_salary": "-5", "components": [{"type": "bonus", "name": "", "amount": "x"}]},
        )

        shapes.assert_validation_error(self, refused, "components.0.type", "PUT a bad salary")
