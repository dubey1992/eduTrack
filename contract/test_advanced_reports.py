"""Advanced reporting (Phase 20) - served by the Python backend only.

Laravel was frozen before Phase 20 (docs/python-migration.md), so against it
these are skipped rather than failed. Against Django they check the three new
reports' shapes, that every report - old and new - comes back as a PDF, and
that the previous-period comparison is there when asked for and absent when
not, so the Phase 18 reports still answer exactly as Laravel's do.
"""

from __future__ import annotations

import unittest

import coverage
import world

RANGE = {"from": "2026-09-07", "to": "2026-09-09"}
NEW_REPORTS = ("payroll-summary", "leave-usage", "syllabus-progress")
PHASE_18_REPORTS = ("student-attendance", "staff-attendance", "teaching-coverage", "transport-usage")


class AdvancedReports(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/reports/payroll-summary", **RANGE)
        if probe.status == 404:
            raise unittest.SkipTest("advanced reporting is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert AdvancedReports.WORLD is not None
        return AdvancedReports.WORLD

    def test_each_new_report_answers_with_a_range_rows_and_totals(self):
        for report in NEW_REPORTS:
            with self.subTest(report=report):
                response = self.w.admin.get(f"/reports/{report}", **RANGE)

                self.assertEqual(200, response.status, f"GET /reports/{report}\n{response!r}")
                self.assertEqual({"from", "to", "working_days"}, set(response.body["range"]))
                self.assertIsInstance(response.body["rows"], list)
                self.assertIsInstance(response.body["totals"], dict)

    def test_payroll_totals_are_a_list_per_currency(self):
        totals = self.w.admin.get("/reports/payroll-summary", **RANGE).body["totals"]

        self.assertIsInstance(totals["by_currency"], list)

    def test_every_report_comes_back_as_a_pdf(self):
        for report in (*PHASE_18_REPORTS, *NEW_REPORTS):
            with self.subTest(report=report):
                response = self.w.admin.get(f"/reports/{report}", format="pdf", **RANGE)

                self.assertEqual(200, response.status, f"GET /reports/{report}?format=pdf\n{response!r}")
                self.assertEqual("application/pdf", response.headers.get("content-type"))

    def test_the_comparison_is_there_only_when_asked_for(self):
        compared = self.w.admin.get("/reports/student-attendance", compare=1, **RANGE)
        plain = self.w.admin.get("/reports/student-attendance", **RANGE)

        self.assertEqual({"range", "totals"}, set(compared.body["comparison"]))
        self.assertNotIn("comparison", plain.body)

    def test_another_schools_admin_reports_on_their_own_school(self):
        # A school named in the request is ignored for anybody but the Super
        # Admin: the other admin gets their own school's staff, never ours.
        ours = self.w.admin.get("/reports/leave-usage", **RANGE).body["rows"]
        response = self.w.other_admin.get("/reports/leave-usage", school_id=self.w.school_id, **RANGE)

        self.assertEqual(200, response.status, f"{response!r}")
        self.assertIn(self.w.staff_profile_id, [row["staff_profile_id"] for row in ours])
        self.assertNotIn(self.w.staff_profile_id, [row["staff_profile_id"] for row in response.body["rows"]])
