"""Receipts over HTTP (docs/fees.md, F3): the list with its filters, search and
pages, and who may record, read, print, cancel and email a receipt. The
payment rules themselves are test_fees_receipts.py, whose fixtures these
share.
"""

import datetime as dt

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from school import factories
from school.enums import UserRole
from school.fees.dues import FeeDueService
from school.models import FeeHead, FeeInstallment, FeeReceipt, FeeStructure, ModuleSetting

from .test_fees_receipts import RECEIPTS, ReceiptsTestCase


def school_with_a_charged_student(parent=None, name="Other School"):
    """Another school with fees on, a 2026-27 year, one student owing 1,000
    and an accountant."""
    school = factories.SchoolFactory(name=name, parent_school=parent, currency_code="INR", timezone="Asia/Kolkata")
    factories.ModuleSettingFactory(school=school, module="fees")
    year = factories.AcademicYearFactory(
        school=school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31), is_current=True,
    )
    school_class = factories.SchoolClassFactory(academic_year=year, name="Class 8", level=8)
    section = factories.ClassSectionFactory(school_class=school_class)
    student = factories.StudentFactory(school=school, class_section=section, admission_date=dt.date(2026, 4, 1))
    factories.StudentEnrollmentFactory(student=student, school=school, academic_year=year,
                                       school_class=school_class, class_section=section)
    head = FeeHead.objects.create(school=school, name="Tuition")
    structure = FeeStructure.objects.create(
        school=school, academic_year=year, school_class=school_class, fee_head=head, amount="1000.00",
        currency_code="INR", frequency="yearly", status="published",
    )
    FeeInstallment.objects.create(fee_structure=structure, sequence=1, label="Year", due_date=dt.date(2026, 4, 10),
                                  amount="1000.00")
    FeeDueService.sync_student(student, year)
    accountant = factories.UserFactory(school=school, role=UserRole.ACCOUNTANT)

    return school, year, student, accountant


# -- the list -------------------------------------------------------------------------


class TheList(ReceiptsTestCase):
    def setUp(self):
        super().setUp()
        self.bina = self.student("Bina", last_name="Rao", admission_number="ADM-77")
        FeeDueService.sync_student(self.bina, self.year)

        self.r1 = self.paid(amount="100.00", receipt_date="2026-07-01")
        self.r2 = self.paid(self.bina, amount="200.00", receipt_date="2026-07-10", payment_mode="upi")
        self.r3 = self.paid(amount="300.00", receipt_date="2026-07-10", payment_mode="cheque", reference="12")
        self.cancel(self.r1["id"])

    def listed(self, user=None, **params):
        response = self.as_user(user or self.accountant).get(RECEIPTS, params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def numbers(self, **params) -> list[str]:
        return [row["receipt_number"] for row in self.listed(**params)["data"]]

    def test_newest_first_with_the_whole_receipt_on_each_row(self):
        data = self.listed()

        self.assertEqual(["RCPT-2026-27-00003", "RCPT-2026-27-00002", "RCPT-2026-27-00001"],
                         [row["receipt_number"] for row in data["data"]])
        self.assertEqual(3, data["meta"]["total"] if "meta" in data else data["total"])
        row = data["data"][0]
        self.assertEqual("Class 8", row["student"]["class_name"])
        self.assertEqual(1, len(row["allocations"]))
        self.assertEqual("cancelled", data["data"][2]["status"])

    def test_filters(self):
        self.assertEqual(["RCPT-2026-27-00003", "RCPT-2026-27-00001"], self.numbers(student_id=self.aarav.id))
        self.assertEqual(["RCPT-2026-27-00002"], self.numbers(payment_mode="upi"))
        self.assertEqual(["RCPT-2026-27-00001"], self.numbers(status="cancelled"))
        self.assertEqual(["RCPT-2026-27-00003", "RCPT-2026-27-00002"], self.numbers(**{"from": "2026-07-05"}))
        self.assertEqual(["RCPT-2026-27-00001"], self.numbers(to="2026-07-05"))
        self.assertEqual(3, len(self.numbers(academic_year_id=self.year.id)))

    def test_search_by_number_name_or_admission_number_without_regard_to_case(self):
        self.assertEqual(["RCPT-2026-27-00002"], self.numbers(search="rcpt-2026-27-00002"))
        self.assertEqual(["RCPT-2026-27-00002"], self.numbers(search="bina rao"))
        self.assertEqual(["RCPT-2026-27-00002"], self.numbers(search="adm-77"))
        self.assertEqual(["RCPT-2026-27-00003", "RCPT-2026-27-00001"], self.numbers(search="SHAH"))

    def test_pages(self):
        data = self.listed(per_page=2, page=2)

        self.assertEqual(["RCPT-2026-27-00001"], [row["receipt_number"] for row in data["data"]])

    def test_bad_filters_are_named(self):
        other_school, other_year, other_student, _ = school_with_a_charged_student()

        for params, field in (
            ({"payment_mode": "barter"}, "payment_mode"),
            ({"status": "lost"}, "status"),
            ({"from": "yesterday"}, "from"),
            ({"from": "2026-07-10", "to": "2026-07-01"}, "to"),
            ({"student_id": other_student.id}, "student_id"),
            ({"academic_year_id": other_year.id}, "academic_year_id"),
        ):
            with self.subTest(params=params):
                response = self.as_user(self.accountant).get(RECEIPTS, params)
                self.assertEqual(422, response.status_code, response.data)
                self.assertIn(field, response.data["details"]["errors"])

    def test_the_number_of_queries_does_not_grow_with_the_receipts(self):
        def queries() -> int:
            with CaptureQueriesContext(connection) as captured:
                self.listed()
            return len(captured)

        few = queries()

        for _ in range(6):
            self.paid(self.bina, amount="10.00")

        self.assertEqual(few, queries())
        self.assertLessEqual(few, 16)


# -- who may do what ------------------------------------------------------------------


class WhoMay(ReceiptsTestCase):
    def setUp(self):
        super().setUp()
        self.receipt = self.paid(amount="100.00")
        self.aarav.guardian_email = "meera@example.com"
        self.aarav.save(update_fields=["guardian_email"])

    def reads(self, client, receipt_id=None) -> list:
        receipt_id = receipt_id or self.receipt["id"]

        return [
            client.get(RECEIPTS),
            client.get(f"{RECEIPTS}/{receipt_id}"),
            client.get(f"{RECEIPTS}/{receipt_id}/pdf"),
        ]

    def writes(self, client, receipt_id=None, student=None) -> list:
        receipt_id = receipt_id or self.receipt["id"]
        body = {"student_id": (student or self.aarav).id, "receipt_date": "2026-07-15", "amount": "10.00",
                "payment_mode": "cash"}

        return [
            client.post(RECEIPTS, body, format="json"),
            client.post(f"{RECEIPTS}/{receipt_id}/email"),
            client.post(f"{RECEIPTS}/{receipt_id}/cancel", {"reason": "Wrong student"}, format="json"),
        ]

    def test_the_school_admin_and_the_accountant_may_do_everything(self):
        for user in (self.admin, self.accountant):
            with self.subTest(role=user.role):
                receipt = self.paid(amount="10.00", user=user)

                for response in self.reads(self.as_user(user), receipt["id"]):
                    self.assertEqual(200, response.status_code)

                created, emailed, cancelled = self.writes(self.as_user(user), receipt["id"])
                self.assertEqual((201, 202, 200),
                                 (created.status_code, emailed.status_code, cancelled.status_code))

    def test_a_super_admin_reads_every_school_and_changes_nothing(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        client = self.as_user(root)

        for response in self.reads(client):
            self.assertEqual(200, response.status_code)

        for response in self.writes(client):
            self.assertEqual(403, response.status_code)

        self.assertEqual("valid", FeeReceipt.objects.get(pk=self.receipt["id"]).status)

    def test_a_super_admin_lists_every_school_with_fees_on_or_the_one_named(self):
        other_school, _, other_student, their_accountant = school_with_a_charged_student()
        theirs = self.paid(other_student, amount="50.00", user=their_accountant)
        client = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        every = {row["id"] for row in client.get(RECEIPTS).data["data"]}
        named = {row["id"] for row in client.get(RECEIPTS, {"school_id": other_school.id}).data["data"]}

        self.assertEqual({self.receipt["id"], theirs["id"]}, every)
        self.assertEqual({theirs["id"]}, named)

    def test_every_other_role_is_refused(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.DRIVER,
                     UserRole.BUS_ATTENDANT):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))

            for response in (*self.reads(client), *self.writes(client)):
                with self.subTest(role=role):
                    self.assertEqual(403, response.status_code)

    def test_nobody_signed_in_is_asked_to_sign_in(self):
        for response in (*self.reads(APIClient()), *self.writes(APIClient())):
            self.assertEqual(401, response.status_code)

    def test_a_school_with_fees_off_is_refused(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        for response in (*self.reads(self.as_user(self.accountant)), *self.writes(self.as_user(self.accountant))):
            self.assertEqual(403, response.status_code)
            self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_another_schools_receipt_is_forbidden_and_their_student_is_invalid(self):
        _, _, other_student, their_accountant = school_with_a_charged_student()
        theirs = self.paid(other_student, amount="50.00", user=their_accountant)
        client = self.as_user(self.accountant)

        _, one, pdf = self.reads(client, theirs["id"])
        created, emailed, cancelled = self.writes(client, theirs["id"], student=other_student)

        self.assertEqual((403, 403, 403, 403), (one.status_code, pdf.status_code, emailed.status_code,
                                                cancelled.status_code))
        self.assertEqual(422, created.status_code)
        self.assertEqual(["The selected student id is invalid."], created.data["details"]["errors"]["student_id"])
        self.assertEqual("valid", FeeReceipt.objects.get(pk=theirs["id"]).status)

    def test_an_unknown_receipt_is_not_found(self):
        client = self.as_user(self.accountant)

        for response in (client.get(f"{RECEIPTS}/999999"), client.get(f"{RECEIPTS}/999999/pdf"),
                         client.post(f"{RECEIPTS}/999999/cancel", {"reason": "abc"}, format="json"),
                         client.post(f"{RECEIPTS}/999999/email")):
            self.assertEqual(404, response.status_code)

    def test_a_group_admin_works_across_their_group_and_nowhere_else(self):
        _, _, branch_student, branch_accountant = school_with_a_charged_student(self.school, "Sunrise North")
        branch_receipt = self.paid(branch_student, amount="50.00", user=branch_accountant)
        _, _, outside_student, outside_accountant = school_with_a_charged_student(name="Elsewhere")
        outside_receipt = self.paid(outside_student, amount="50.00", user=outside_accountant)
        client = self.as_user(factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN))

        for response in (*self.reads(client), *self.reads(client, branch_receipt["id"])):
            self.assertEqual(200, response.status_code, getattr(response, "data", None))

        listed = {row["id"] for row in client.get(RECEIPTS).data["data"]}
        self.assertIn(branch_receipt["id"], listed)
        self.assertNotIn(outside_receipt["id"], listed)

        created, _, cancelled = self.writes(client, branch_receipt["id"], student=branch_student)
        self.assertEqual((201, 200), (created.status_code, cancelled.status_code))

        _, one, pdf = self.reads(client, outside_receipt["id"])
        created, emailed, cancelled = self.writes(client, outside_receipt["id"], student=outside_student)
        self.assertEqual((403, 403, 403, 403), (one.status_code, pdf.status_code, emailed.status_code,
                                                cancelled.status_code))
        self.assertEqual(422, created.status_code)

    def test_a_widened_matrix_lets_staff_collect(self):
        from school.models import RolePermission

        RolePermission.objects.create(role="STAFF", module="fees", level="manage")
        clerk = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        self.assertEqual(201, self.pay(amount="10.00", user=clerk).status_code)
