"""Payroll over HTTP: salaries, a month's run, payslips, and who may do any of
it. The rules are docs/payroll.md; the arithmetic alone is
test_payroll_calculator.py.

September 2026 throughout: 22 weekdays, less a school holiday on the 15th -
21 working days. The clock is the 30th.
"""

import datetime as dt
from decimal import Decimal
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, queue, tokens
from school.enums import UserRole
from school.models import AuditLog, Holiday, PayrollRun, Payslip, QueuedJob, SalaryProfile, StaffAttendance

NOW = dt.datetime(2026, 9, 30, 12, 0, tzinfo=dt.timezone.utc)


class PayrollTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.school = factories.SchoolFactory(name="Sunrise Public School", timezone="UTC", currency_code="INR")
        Holiday.objects.create(school=self.school, name="Founders Day", type="school_event",
                               start_date="2026-09-15", end_date="2026-09-15", created_at=NOW, updated_at=NOW)
        self.science = factories.DepartmentFactory(school=self.school, name="Science")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT, first_name="Meena", last_name="Iyer")
        self.accountant_profile = factories.StaffProfileFactory(
            user=self.accountant, employee_id="ACC-1", joining_date=dt.date(2026, 9, 16), designation="Accountant",
        )

        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER, first_name="Rahul", last_name="Verma")
        self.teacher_profile = factories.StaffProfileFactory(
            user=self.teacher, employee_id="TCH-1", department=self.science, designation="Senior Teacher",
            joining_date=dt.date(2026, 4, 1),
        )
        self.clerk = factories.UserFactory(school=self.school, role=UserRole.STAFF)
        self.clerk_profile = factories.StaffProfileFactory(user=self.clerk, employee_id="STF-1")

    # -- helpers ------------------------------------------------------------

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def mark(self, profile, day: str, status: str):
        StaffAttendance.objects.create(school=self.school, staff_profile=profile, attendance_date=day, status=status,
                                       created_at=NOW, updated_at=NOW)

    def set_salaries(self):
        teacher = factories.SalaryProfileFactory(staff_profile=self.teacher_profile, basic_salary="30000.00")
        factories.SalaryComponentFactory(salary_profile=teacher, type="earning", name="HRA", amount="6000.00")
        factories.SalaryComponentFactory(salary_profile=teacher, type="deduction", name="PF", amount="1800.00", sort_order=1)
        factories.SalaryProfileFactory(staff_profile=self.accountant_profile, basic_salary="25000.00")

    def generate(self, client=None, **overrides):
        return (client or self.as_user(self.accountant)).post(
            "/api/v1/payroll/runs", {"year": 2026, "month": 9, **overrides}, format="json"
        )

    def draft(self):
        self.set_salaries()
        self.mark(self.teacher_profile, "2026-09-07", "absent")
        self.mark(self.teacher_profile, "2026-09-08", "half_day")
        self.mark(self.teacher_profile, "2026-09-09", "leave")
        self.mark(self.teacher_profile, "2026-09-10", "present")
        response = self.generate()
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def payslip_of(self, run_id, profile):
        return Payslip.objects.get(payroll_run_id=run_id, staff_profile=profile)

    def finalize(self, run_id):
        response = self.as_user(self.accountant).post(f"/api/v1/payroll/runs/{run_id}/finalize")
        self.assertEqual(200, response.status_code, response.data)

        return response.data


class Salaries(PayrollTestCase):
    def payload(self, **overrides):
        return {
            "basic_salary": "30000.00",
            "components": [
                {"type": "earning", "name": "HRA", "amount": "6000.00"},
                {"type": "deduction", "name": "PF", "amount": "1800.00"},
            ],
            **overrides,
        }

    def test_an_accountant_sets_a_salary_in_the_schools_currency(self):
        response = self.as_user(self.accountant).put(
            f"/api/v1/payroll/salaries/{self.teacher_profile.id}", self.payload(), format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        salary = response.data["salary"]
        self.assertEqual(
            ("30000.00", "INR", "6000.00", "1800.00", "36000.00", "34200.00"),
            (salary["basic_salary"], salary["currency_code"], salary["total_earnings"], salary["total_deductions"],
             salary["gross_monthly"], salary["net_monthly"]),
        )
        self.assertEqual([("earning", "HRA"), ("deduction", "PF")], [(c["type"], c["name"]) for c in salary["components"]])

    def test_saving_again_replaces_the_components_and_both_versions_are_audited(self):
        client = self.as_user(self.accountant)
        client.put(f"/api/v1/payroll/salaries/{self.teacher_profile.id}", self.payload(), format="json")
        client.put(
            f"/api/v1/payroll/salaries/{self.teacher_profile.id}",
            self.payload(basic_salary="32000.00", components=[{"type": "earning", "name": "DA", "amount": "500"}]),
            format="json",
        )

        salary = SalaryProfile.objects.get(staff_profile=self.teacher_profile)
        self.assertEqual(["DA"], [c.name for c in salary.components.all()])

        entries = list(AuditLog.objects.filter(action="salary.saved").order_by("id"))
        self.assertEqual(2, len(entries))
        self.assertIsNone(entries[0].old_values)
        self.assertEqual("30000.00", entries[1].old_values["basic_salary"])
        self.assertEqual("32000.00", entries[1].new_values["basic_salary"])
        self.assertEqual((self.accountant.id, self.school.id, "payroll", "127.0.0.1"),
                         (entries[1].user_id, entries[1].school_id, entries[1].module, entries[1].ip))

    def test_every_problem_with_a_salary_is_reported_at_once(self):
        response = self.as_user(self.accountant).put(
            f"/api/v1/payroll/salaries/{self.teacher_profile.id}",
            {
                "basic_salary": "-1",
                "components": [
                    {"type": "bonus", "name": "", "amount": "1.001"},
                    {"type": "earning", "name": "HRA", "amount": "10"},
                    {"type": "earning", "name": "hra", "amount": ""},
                    {"type": "deduction", "name": "Loan", "amount": "99999999999"},
                ],
            },
            format="json",
        )

        self.assertEqual(422, response.status_code)
        errors = response.data["details"]["errors"]
        self.assertEqual(
            {"basic_salary", "components.0.type", "components.0.name", "components.0.amount",
             "components.2.name", "components.2.amount", "components.3.amount"},
            set(errors),
        )
        self.assertEqual(['"hra" appears twice as an earning.'], errors["components.2.name"])

    def test_the_salary_list_shows_who_is_missing_one_and_never_the_admins_placeholder(self):
        factories.StaffProfileFactory(user=self.admin, employee_id="ADMIN-1")
        factories.SalaryProfileFactory(staff_profile=self.teacher_profile)

        client = self.as_user(self.accountant)
        everyone = client.get("/api/v1/payroll/salaries").data["data"]
        missing = client.get("/api/v1/payroll/salaries", {"salary": "missing"}).data["data"]

        self.assertEqual(["ACC-1", "STF-1", "TCH-1"], [row["employee_id"] for row in everyone])
        self.assertEqual(["ACC-1", "STF-1"], [row["employee_id"] for row in missing])

    def test_another_schools_staff_are_out_of_reach(self):
        other = factories.SchoolFactory()
        stranger = factories.StaffProfileFactory(user=factories.UserFactory(school=other, role=UserRole.TEACHER))
        client = self.as_user(self.accountant)

        self.assertEqual(403, client.get(f"/api/v1/payroll/salaries/{stranger.id}").status_code)
        self.assertEqual(403, client.put(f"/api/v1/payroll/salaries/{stranger.id}", self.payload(), format="json").status_code)
        rows = client.get("/api/v1/payroll/salaries", {"school_id": other.id}).data["data"]
        self.assertNotIn(stranger.id, [row["staff_profile_id"] for row in rows])


class GeneratingARun(PayrollTestCase):
    def test_pay_is_pro_rated_by_paid_days_over_working_days(self):
        run = self.draft()

        self.assertEqual(("draft", 21, 2, "INR"), (run["status"], run["working_days"], run["employees"], run["currency_code"]))
        slip = self.as_user(self.accountant).get(
            f"/api/v1/payroll/payslips/{self.payslip_of(run['id'], self.teacher_profile).id}"
        ).data

        self.assertEqual((21.0, 19.5, 1.0, 1, 17), (slip["working_days"], slip["paid_days"], slip["absent_days"], slip["half_days"], slip["unmarked_days"]))
        self.assertEqual(
            [("earning", "basic", "Basic salary", "30000.00", "27857.14"),
             ("earning", "component", "HRA", "6000.00", "5571.43"),
             ("deduction", "component", "PF", "1800.00", "1671.43")],
            [(l["type"], l["source"], l["name"], l["full_amount"], l["amount"]) for l in slip["lines"]],
        )
        self.assertEqual(("33428.57", "1671.43", "31757.14", "0.00"), (slip["gross_earnings"], slip["total_deductions"], slip["net_pay"], slip["shortfall"]))
        self.assertEqual(("Rahul Verma", "TCH-1", "Senior Teacher", "Science"), (slip["employee_name"], slip["employee_code"], slip["designation"], slip["department_name"]))

    def test_days_before_joining_are_unpaid(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.accountant_profile)

        # Joined on the 16th: 11 of the 21 working days, all unmarked.
        self.assertEqual((Decimal("11.0"), Decimal("13095.24")), (slip.paid_days, slip.net_pay))

    def test_nobody_is_dropped_without_saying_why(self):
        run = self.draft()
        moved = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        profile = factories.StaffProfileFactory(user=moved, employee_id="TCH-2")
        factories.SalaryProfileFactory(staff_profile=profile, currency_code="USD")

        detail = self.as_user(self.accountant).get(f"/api/v1/payroll/runs/{run['id']}").data

        self.assertEqual(
            {("STF-1", "No salary has been set."),
             ("TCH-2", "The salary is in USD but the school now uses INR. Save the salary again.")},
            {(row["employee_id"], row["reason"]) for row in detail["missing_salaries"]},
        )

    def test_an_inactive_employee_and_the_admins_placeholder_are_not_paid(self):
        self.set_salaries()
        self.teacher.status = "inactive"
        self.teacher.save()
        factories.SalaryProfileFactory(staff_profile=factories.StaffProfileFactory(user=self.admin, employee_id="ADM-1"))

        run = self.generate().data

        self.assertEqual(["ACC-1"], list(Payslip.objects.filter(payroll_run_id=run["id"]).values_list("employee_code", flat=True)))

    def test_one_run_per_month_and_never_a_month_that_has_not_started(self):
        self.draft()

        again = self.generate()
        future = self.generate(month=10)

        self.assertEqual((409, "PAYROLL_RUN_EXISTS"), (again.status_code, again.data["code"]))
        self.assertEqual("A payroll run for September 2026 already exists.", again.data["message"])
        self.assertEqual(422, future.status_code)
        self.assertEqual(["Payroll cannot be run for a month that has not started."], future.data["details"]["errors"]["month"])

    def test_the_month_must_be_a_month(self):
        response = self.generate(year=1999, month=13)

        self.assertEqual({"year", "month"}, set(response.data["details"]["errors"]))

    def test_a_month_that_is_all_holidays_pays_in_full(self):
        self.set_salaries()
        Holiday.objects.all().delete()
        Holiday.objects.create(school=self.school, name="Vacation", type="vacation", start_date="2026-08-01",
                               end_date="2026-08-31", created_at=NOW, updated_at=NOW)

        run = self.generate(month=8).data
        slip = self.payslip_of(run["id"], self.teacher_profile)

        self.assertEqual((0, Decimal("34200.00")), (run["working_days"], slip.net_pay))

    def test_an_accountant_cannot_generate_for_another_school(self):
        other = factories.SchoolFactory(timezone="UTC")

        response = self.generate(school_id=other.id)

        # Pinned to their own school, as every write is for a one-school actor.
        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])
        self.assertFalse(PayrollRun.objects.filter(school=other).exists())

    def test_generating_is_audited(self):
        run = self.draft()

        entry = AuditLog.objects.get(action="payroll_run.generated")
        self.assertEqual((run["id"], "payroll_run", 2), (entry.entity_id, entry.entity_type, entry.new_values["employees"]))


class ADraft(PayrollTestCase):
    def test_an_adjustment_is_added_whole_and_changes_the_totals(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        client = self.as_user(self.accountant)

        bonus = client.post(f"/api/v1/payroll/payslips/{slip.id}/adjustments",
                            {"type": "earning", "name": "Exam duty", "amount": "1500.00", "note": "Board exams"}, format="json")
        advance = client.post(f"/api/v1/payroll/payslips/{slip.id}/adjustments",
                              {"type": "deduction", "name": "Advance recovery", "amount": "2000.00", "note": "August advance"}, format="json")

        self.assertEqual(201, bonus.status_code, bonus.data)
        self.assertEqual(("34928.57", "3671.43", "31257.14"),
                         (advance.data["gross_earnings"], advance.data["total_deductions"], advance.data["net_pay"]))
        line = advance.data["lines"][-1]
        self.assertEqual((True, None, "2000.00", "August advance"), (line["is_adjustment"], line["full_amount"], line["amount"], line["note"]))

        removed = client.delete(f"/api/v1/payroll/payslips/{slip.id}/adjustments/{line['id']}")
        # The advance comes off; the bonus stays.
        self.assertEqual("33257.14", removed.data["net_pay"])
        self.assertEqual(
            ["payslip.adjustment_added", "payslip.adjustment_added", "payslip.adjustment_removed"],
            list(AuditLog.objects.filter(entity_type="payslip").order_by("id").values_list("action", flat=True)),
        )

    def test_an_adjustment_needs_a_type_a_name_a_positive_amount_and_a_reason(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        response = self.as_user(self.accountant).post(
            f"/api/v1/payroll/payslips/{slip.id}/adjustments", {"type": "gift", "amount": "0"}, format="json"
        )

        self.assertEqual({"type", "name", "amount", "note"}, set(response.data["details"]["errors"]))

    def test_the_salary_lines_themselves_cannot_be_removed(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        basic = slip.lines.get(source="basic")

        response = self.as_user(self.accountant).delete(f"/api/v1/payroll/payslips/{slip.id}/adjustments/{basic.id}")

        self.assertEqual(404, response.status_code)

    def test_regenerating_picks_up_new_salaries_and_marks_and_keeps_adjustments(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        client = self.as_user(self.accountant)
        client.post(f"/api/v1/payroll/payslips/{slip.id}/adjustments",
                    {"type": "earning", "name": "Exam duty", "amount": "1500.00", "note": "Board exams"}, format="json")
        StaffAttendance.objects.filter(staff_profile=self.teacher_profile).delete()
        factories.SalaryProfileFactory(staff_profile=self.clerk_profile, basic_salary="15000.00")
        self.accountant.status = "inactive"
        self.accountant.save()

        detail = self.as_user(self.admin).post(f"/api/v1/payroll/runs/{run['id']}/regenerate").data

        slip.refresh_from_db()
        self.assertEqual((2, []), (detail["employees"], detail["missing_salaries"]))
        self.assertEqual({"TCH-1", "STF-1"}, set(Payslip.objects.filter(payroll_run_id=run["id"]).values_list("employee_code", flat=True)))
        # A full month now, plus the adjustment that survived.
        self.assertEqual((Decimal("21.0"), Decimal("35700.00")), (slip.paid_days, slip.net_pay))

    def test_a_draft_can_be_deleted(self):
        run = self.draft()

        response = self.as_user(self.accountant).delete(f"/api/v1/payroll/runs/{run['id']}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(PayrollRun.objects.exists())
        self.assertFalse(Payslip.objects.exists())
        self.assertTrue(AuditLog.objects.filter(action="payroll_run.deleted", entity_id=run["id"]).exists())

    def test_deductions_beyond_earnings_leave_nothing_to_pay_and_record_the_shortfall(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        response = self.as_user(self.accountant).post(
            f"/api/v1/payroll/payslips/{slip.id}/adjustments",
            {"type": "deduction", "name": "Loan", "amount": "40000.00", "note": "Full recovery"}, format="json",
        )

        self.assertEqual(("0.00", "8242.86"), (response.data["net_pay"], response.data["shortfall"]))


class FinalizingAndPaying(PayrollTestCase):
    def pay(self, path, **overrides):
        return self.as_user(self.accountant).post(
            path, {"paid_on": "2026-09-30", "payment_mode": "bank_transfer", "payment_reference": "NEFT-1", **overrides},
            format="json",
        )

    def test_finalizing_locks_the_run_and_queues_each_employees_payslip(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)
        client = self.as_user(self.accountant)

        final = self.finalize(run["id"])

        self.assertEqual(("finalized", "Meena Iyer"), (final["status"], final["finalized_by_name"]))
        self.assertEqual(2, QueuedJob.objects.filter(name="payslip_email").count())
        for response in (
            client.post(f"/api/v1/payroll/runs/{run['id']}/regenerate"),
            client.delete(f"/api/v1/payroll/runs/{run['id']}"),
            client.post(f"/api/v1/payroll/runs/{run['id']}/finalize"),
            client.post(f"/api/v1/payroll/payslips/{slip.id}/adjustments",
                        {"type": "earning", "name": "Late", "amount": "1", "note": "x"}, format="json"),
        ):
            self.assertEqual((409, "PAYROLL_RUN_LOCKED"), (response.status_code, response.data["code"]))

    def test_a_later_salary_change_never_rewrites_a_finalized_payslip(self):
        run = self.draft()
        self.finalize(run["id"])
        SalaryProfile.objects.filter(staff_profile=self.teacher_profile).update(basic_salary="90000.00")

        self.assertEqual(Decimal("31757.14"), self.payslip_of(run["id"], self.teacher_profile).net_pay)

    def test_a_run_with_nobody_on_it_is_not_finalized(self):
        run = self.generate().data

        response = self.as_user(self.accountant).post(f"/api/v1/payroll/runs/{run['id']}/finalize")

        self.assertEqual((409, "PAYROLL_RUN_EMPTY"), (response.status_code, response.data["code"]))

    def test_nobody_is_paid_against_a_draft(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        for response in (self.pay(f"/api/v1/payroll/payslips/{slip.id}/pay"), self.pay(f"/api/v1/payroll/runs/{run['id']}/pay")):
            self.assertEqual((409, "PAYROLL_RUN_NOT_FINALIZED"), (response.status_code, response.data["code"]))

    def test_paying_each_payslip_settles_the_run(self):
        run = self.draft()
        self.finalize(run["id"])
        teacher = self.payslip_of(run["id"], self.teacher_profile)
        accountant = self.payslip_of(run["id"], self.accountant_profile)

        first = self.pay(f"/api/v1/payroll/payslips/{teacher.id}/pay")
        again = self.pay(f"/api/v1/payroll/payslips/{teacher.id}/pay")
        self.assertEqual("finalized", PayrollRun.objects.get(pk=run["id"]).status)
        self.pay(f"/api/v1/payroll/payslips/{accountant.id}/pay", payment_mode="cash", payment_reference="")

        self.assertEqual((200, "paid", "2026-09-30", "bank_transfer", "NEFT-1"),
                         (first.status_code, first.data["status"], first.data["paid_on"], first.data["payment_mode"], first.data["payment_reference"]))
        self.assertEqual((409, "PAYSLIP_ALREADY_PAID"), (again.status_code, again.data["code"]))
        settled = PayrollRun.objects.get(pk=run["id"])
        self.assertEqual("paid", settled.status)
        self.assertIsNotNone(settled.paid_at)
        self.assertEqual(1, AuditLog.objects.filter(action="payroll_run.paid").count())

    def test_paying_the_whole_run_at_once(self):
        run = self.draft()
        self.finalize(run["id"])

        response = self.pay(f"/api/v1/payroll/runs/{run['id']}/pay")

        self.assertEqual(("paid", 2, 0), (response.data["status"], response.data["paid_count"], response.data["unpaid_count"]))
        self.assertEqual(2, AuditLog.objects.filter(action="payslip.paid").count())

    def test_a_payment_date_cannot_be_in_the_future_and_the_mode_must_be_known(self):
        run = self.draft()
        self.finalize(run["id"])

        response = self.pay(f"/api/v1/payroll/runs/{run['id']}/pay", paid_on="2026-10-01", payment_mode="barter")

        self.assertEqual({"paid_on", "payment_mode"}, set(response.data["details"]["errors"]))

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_each_employee_is_emailed_their_own_payslip(self):
        run = self.draft()
        self.finalize(run["id"])

        result = queue.work()

        self.assertEqual({"done": 2, "failed": 0}, result)
        self.assertEqual(sorted([[self.teacher.email], [self.accountant.email]]), sorted(message.to for message in mail.outbox))
        self.assertTrue(all(message.attachments[0][0].endswith("-2026-09.pdf") for message in mail.outbox))
        self.assertIsNotNone(self.payslip_of(run["id"], self.teacher_profile).emailed_at)

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_a_draft_payslip_is_never_emailed(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        response = self.as_user(self.accountant).post(f"/api/v1/payroll/payslips/{slip.id}/email")
        queue.push("payslip_email", {"payslip_id": slip.id})
        queue.work()

        self.assertEqual(409, response.status_code)
        self.assertEqual([], mail.outbox)


class PayslipDocument(PayrollTestCase):
    def test_the_pdf_downloads_and_says_what_it_pays(self):
        from school.payroll import payslips

        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        response = self.as_user(self.accountant).get(f"/api/v1/payroll/payslips/{slip.id}/pdf")
        html = payslips.document(slip)

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertIn(f'filename="PSL-{slip.id:06d}-2026-09.pdf"', response["Content-Disposition"])
        self.assertTrue(response.content.startswith(b"%PDF"))
        for text in ("DRAFT", "Rahul Verma", "INR 31,757.14", "INR 27,857.14", "(of INR 30,000.00)", "Payslip for September 2026"):
            self.assertIn(text, html)

    def test_names_are_escaped(self):
        from school.payroll import payslips

        self.teacher.first_name = "<b>Rahul</b>"
        self.teacher.save()
        run = self.draft()

        self.assertIn("&lt;b&gt;Rahul&lt;/b&gt;", payslips.document(self.payslip_of(run["id"], self.teacher_profile)))


class WhoMayDoWhat(PayrollTestCase):
    def test_school_and_group_admins_manage_payroll_too(self):
        self.set_salaries()
        group_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)

        self.assertEqual(201, self.generate(client=self.as_user(self.admin)).status_code)
        run_id = PayrollRun.objects.get().id
        self.assertEqual(200, self.as_user(group_admin).post(f"/api/v1/payroll/runs/{run_id}/finalize").status_code)

    def test_a_super_admin_reads_every_schools_payroll_and_changes_none_of_it(self):
        run = self.draft()
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))
        slip = self.payslip_of(run["id"], self.teacher_profile)

        self.assertEqual(200, root.get("/api/v1/payroll/runs", {"school_id": self.school.id}).status_code)
        self.assertEqual(200, root.get(f"/api/v1/payroll/runs/{run['id']}").status_code)
        self.assertEqual(200, root.get(f"/api/v1/payroll/payslips/{slip.id}").status_code)
        self.assertEqual(200, root.get("/api/v1/payroll/salaries").status_code)
        for response in (
            root.post("/api/v1/payroll/runs", {"year": 2026, "month": 8, "school_id": self.school.id}, format="json"),
            root.post(f"/api/v1/payroll/runs/{run['id']}/finalize"),
            root.put(f"/api/v1/payroll/salaries/{self.teacher_profile.id}", {"basic_salary": "1", "components": []}, format="json"),
            root.post(f"/api/v1/payroll/payslips/{slip.id}/adjustments", {"type": "earning", "name": "x", "amount": "1", "note": "x"}, format="json"),
        ):
            self.assertEqual(403, response.status_code)

    def test_other_roles_have_no_payroll_access(self):
        run = self.draft()
        slip = self.payslip_of(run["id"], self.teacher_profile)

        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))
            with self.subTest(role=role):
                self.assertEqual(403, client.get("/api/v1/payroll/runs").status_code)
                self.assertEqual(403, client.get("/api/v1/payroll/salaries").status_code)
                self.assertEqual(403, client.get(f"/api/v1/payroll/runs/{run['id']}").status_code)
                self.assertEqual(403, client.get(f"/api/v1/payroll/payslips/{slip.id}").status_code)
                self.assertEqual(403, self.generate(client=client).status_code)

    def test_another_schools_accountant_reaches_nothing(self):
        run = self.draft()
        other = factories.SchoolFactory(timezone="UTC")
        stranger = self.as_user(factories.UserFactory(school=other, role=UserRole.ACCOUNTANT))
        slip = self.payslip_of(run["id"], self.teacher_profile)

        self.assertEqual([], stranger.get("/api/v1/payroll/runs", {"school_id": self.school.id}).data["data"])
        for response in (
            stranger.get(f"/api/v1/payroll/runs/{run['id']}"),
            stranger.post(f"/api/v1/payroll/runs/{run['id']}/finalize"),
            stranger.delete(f"/api/v1/payroll/runs/{run['id']}"),
            stranger.get(f"/api/v1/payroll/payslips/{slip.id}"),
            stranger.get(f"/api/v1/payroll/payslips/{slip.id}/pdf"),
        ):
            self.assertEqual(403, response.status_code)

    def test_an_employee_reads_only_their_own_payslips_and_only_once_final(self):
        run = self.draft()
        mine = self.payslip_of(run["id"], self.teacher_profile)
        theirs = self.payslip_of(run["id"], self.accountant_profile)
        client = self.as_user(self.teacher)

        self.assertEqual([], client.get("/api/v1/payroll/my-payslips").data["data"])
        self.assertEqual(403, client.get(f"/api/v1/payroll/payslips/{mine.id}").status_code)

        self.finalize(run["id"])

        listed = client.get("/api/v1/payroll/my-payslips").data["data"]
        self.assertEqual([(mine.id, "31757.14", "September 2026")], [(row["id"], row["net_pay"], row["period_label"]) for row in listed])
        self.assertEqual(200, client.get(f"/api/v1/payroll/payslips/{mine.id}").status_code)
        self.assertEqual(200, client.get(f"/api/v1/payroll/payslips/{mine.id}/pdf").status_code)
        self.assertEqual(403, client.get(f"/api/v1/payroll/payslips/{theirs.id}").status_code)
        self.assertEqual(403, client.post(f"/api/v1/payroll/payslips/{mine.id}/pay", {}, format="json").status_code)

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get("/api/v1/payroll/my-payslips").status_code)


class AccountantDashboard(PayrollTestCase):
    def test_payroll_leads_the_accountants_dashboard(self):
        client = self.as_user(self.accountant)

        before = {card["key"]: card for card in client.get("/api/v1/dashboard").data["cards"]}
        self.assertEqual(("Not started", "September 2026"), (before["payroll"]["value"], before["payroll"]["hint"]))
        self.assertEqual(("3", "warning"), (before["salaries"]["value"], before["salaries"]["tone"]))

        run = self.draft()
        self.finalize(run["id"])
        data = client.get("/api/v1/dashboard").data
        after = {card["key"]: card for card in data["cards"]}

        self.assertEqual(("Finalized", "1", "2"), (after["payroll"]["value"], after["salaries"]["value"], after["unpaid"]["value"]))
        self.assertEqual({"leave", "inbox"} <= set(after), True)
        self.assertEqual(["salaries", "unpaid"], [note["key"] for note in data["attention"]])
