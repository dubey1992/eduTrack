"""The classic printed payslip (asked for 2026-11-21, beside the classic fee
receipt and report card): the layout a school chooses under Module Settings
-> Payroll -> Payslip layout, what it prints, and that no other school's
payslips change.

The same September 2026 run as test_payroll_api.py: Rahul Verma, basic
30,000 with HRA 6,000 and PF 1,800, one absent day and a half day.

Set PAYSLIP_SAMPLES to a folder to have the PDFs written there.
"""

import os

from school import factories, pdf_design
from school.models import ModuleSetting
from school.payroll import payslip_classic, payslips

from . import test_payroll_api
from .test_payroll_api import PayrollTestCase

MODULE_SETTINGS = "/api/v1/settings/modules/payroll"


class ClassicPayslipTestCase(PayrollTestCase):
    def classic(self, school=None):
        ModuleSetting.objects.update_or_create(
            school=school or self.school, module="payroll",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {"payslip_style": "classic"}},
        )

    def html(self, slip, name: str | None = None) -> str:
        html = payslip_classic.document(slip)
        self.assertEqual(0, pdf_design.style_errors(html), "xhtml2pdf dropped a cell's styles")
        folder = os.environ.get("PAYSLIP_SAMPLES")

        if folder and name:
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, f"{name}.pdf"), "wb") as handle:
                handle.write(pdf_design.render(html, name))
            with open(os.path.join(folder, f"{name}.html"), "w", encoding="utf-8") as handle:
                handle.write(html)

        return html


class TheLayout(ClassicPayslipTestCase):
    def test_a_draft_prints_as_a_salary_slip_with_the_draft_box(self):
        run = self.draft()
        html = self.html(self.payslip_of(run["id"], self.teacher_profile), "classic-draft")

        for text in ("Salary Slip", self.school.name.upper(), "Pay Period : SEPTEMBER 2026", "09/01/2026 to 09/30/2026",
                     "DRAFT", "RAHUL VERMA", "Working Days", "Paid Days", ">21<", ">19.5<",
                     "Earnings", "Rate", "Deductions", "Gross Earnings", "Total Deductions", "Net Pay",
                     "Net Pay In Words", "Only", "DRAFT - NOT PAID", "Employee Signature", "Authorised Signatory",
                     "Powered by School365ai"):
            self.assertIn(text, html)
        # Black on white: none of the standard payslip's blue band.
        self.assertNotIn("PAYSLIP", html.replace("Payslip", ""))

    def test_a_pro_rated_line_shows_the_full_month_as_its_rate(self):
        run = self.draft()
        html = self.html(self.payslip_of(run["id"], self.teacher_profile))

        self.assertIn("30,000.00", html)
        self.assertIn("27,857.14", html)
        self.assertIn("HRA", html)
        self.assertIn("PF", html)

    def test_a_paid_payslip_says_how_and_carries_no_draft_box(self):
        run = self.draft()
        self.finalize(run["id"])
        slip = self.payslip_of(run["id"], self.teacher_profile)
        test_payroll_api.FinalizingAndPaying.pay(self, f"/api/v1/payroll/payslips/{slip.id}/pay")

        html = self.html(self.payslip_of(run["id"], self.teacher_profile), "classic-paid")

        self.assertIn("PAID ON 09/30/2026 - BANK TRANSFER - NEFT-1", html)
        self.assertNotIn("DRAFT", html)

    def test_details_it_does_not_have_are_left_out(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        slip.department_name = None
        slip.designation = ""
        slip.save(update_fields=["department_name", "designation"])

        html = self.html(self.payslip_of(run["id"], self.teacher_profile))

        self.assertNotIn(">Department<", html)
        self.assertNotIn(">Designation<", html)
        self.assertNotIn("None", html)

    def test_deductions_beyond_earnings_are_said_not_hidden(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        slip.shortfall = "1250.00"
        slip.save(update_fields=["shortfall"])

        html = self.html(self.payslip_of(run["id"], self.teacher_profile))

        self.assertIn("Deductions beyond earnings, not taken this month", html)
        self.assertIn("1,250.00", html)


class TheSchoolsChoice(ClassicPayslipTestCase):
    def test_standard_until_the_school_chooses(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        self.assertIn("PAYSLIP", payslips.document_for(slip))
        self.assertNotIn("Salary Slip", payslips.document_for(slip))

    def test_once_chosen_the_download_is_the_classic_one(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        self.classic()

        self.assertIn("Salary Slip", payslips.document_for(slip))
        response = self.as_user(self.accountant).get(f"/api/v1/payroll/payslips/{slip.id}/pdf")
        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF"))

    def test_another_schools_choice_does_not_reach_this_one(self):
        run = self.draft()
        self.classic(school=factories.SchoolFactory())

        self.assertNotIn("Salary Slip", payslips.document_for(self.payslip_of(run["id"], self.teacher_profile)))

    def test_the_setting_is_offered_as_a_choice(self):
        response = self.as_user(self.admin).get("/api/v1/settings/modules")

        payroll = next(row for row in response.data if row["module"] == "payroll")
        schema = {row["key"]: row for row in payroll["settings_schema"]}["payslip_style"]
        self.assertEqual("choice", schema["type"])
        self.assertEqual(
            [{"value": "standard", "label": "Standard"}, {"value": "classic", "label": "Classic printed"}],
            schema["choices"],
        )

    def test_the_admin_chooses_classic(self):
        response = self.as_user(self.admin).put(MODULE_SETTINGS, {"settings": {"payslip_style": "classic"}}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("classic", response.data["settings"]["payslip_style"])

    def test_a_value_that_is_not_one_of_the_choices_is_refused(self):
        response = self.as_user(self.admin).put(MODULE_SETTINGS, {"settings": {"payslip_style": "fancy"}}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("Payslip layout must be one of: Standard, Classic printed.", str(response.data))

    def test_an_accountant_may_not_change_the_layout(self):
        response = self.as_user(self.accountant).put(
            MODULE_SETTINGS, {"settings": {"payslip_style": "classic"}}, format="json"
        )

        self.assertEqual(403, response.status_code)
