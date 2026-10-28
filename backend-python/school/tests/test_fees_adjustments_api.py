"""Discounts and waivers over HTTP (docs/fees.md, F4): the discounts list with
its filters and pages, the form's validation, the statement's new fields, and
who may give, remove, read and waive. The rules themselves are
test_fees_adjustments.py, whose fixtures these share.
"""

import datetime as dt

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from school import factories
from school.enums import UserRole
from school.fees.dues import FeeDueService
from school.models import AuditLog, FeeConcession, FeeHead, ModuleSetting, RolePermission, StudentFeeDue

from .test_fees_adjustments import CONCESSIONS, DUES, AdjustmentsTestCase
from .test_fees_receipts_api import school_with_a_charged_student

STATEMENT = "/api/v1/fees/students"


class TheList(AdjustmentsTestCase):
    def setUp(self):
        super().setUp()
        self.bina = self.student("Bina", last_name="Rao", admission_number="ADM-77")
        FeeDueService.sync_student(self.bina, self.year)

        self.c1 = self.conceded("fixed", "500.00", reason="Sibling")
        self.c2 = self.conceded("percent", "10", head=None, student=self.bina, reason="Staff child")
        self.c3 = self.conceded("fixed", "100.00", reason="Scholarship")
        self.revoke(self.c3["id"])

    def listed(self, user=None, **params):
        response = self.as_user(user or self.accountant).get(CONCESSIONS, params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def ids(self, **params) -> list[int]:
        return [row["id"] for row in self.listed(**params)["data"]]

    def test_active_ones_newest_first_with_the_whole_discount_on_each_row(self):
        data = self.listed()

        self.assertEqual([self.c2["id"], self.c1["id"]], [row["id"] for row in data["data"]])
        self.assertEqual(
            {
                "id": self.c1["id"],
                "student": {"id": self.aarav.id, "name": self.aarav.name, "admission_number": "ADM-1",
                            "class_name": "Class 8"},
                "academic_year": {"id": self.year.id, "name": "2026-27"},
                "fee_head": {"id": self.tuition.id, "name": "Tuition"},
                "kind": "fixed",
                "value": "500.00",
                "reason": "Sibling",
                "created_by": {"id": self.accountant.id, "name": self.accountant.name},
                "created_at": data["data"][1]["created_at"],
                "revoked_at": None,
                "revoked_by": None,
                "currency_code": "INR",
                "dues_affected": 4,
            },
            data["data"][1],
        )
        self.assertIsNone(data["data"][0]["fee_head"])
        self.assertEqual(4, data["data"][0]["dues_affected"])

    def test_filters_and_the_revoked_ones(self):
        self.assertEqual([self.c3["id"], self.c1["id"]], self.ids(student_id=self.aarav.id, include_revoked=1))
        self.assertEqual([self.c1["id"]], self.ids(student_id=self.aarav.id))
        self.assertEqual(3, len(self.ids(academic_year_id=self.year.id, include_revoked="true")))

        revoked = next(row for row in self.listed(include_revoked=1)["data"] if row["id"] == self.c3["id"])
        self.assertEqual({"id": self.accountant.id, "name": self.accountant.name}, revoked["revoked_by"])
        self.assertIsNotNone(revoked["revoked_at"])
        self.assertEqual(0, revoked["dues_affected"])

    def test_pages(self):
        data = self.listed(per_page=1, page=2)

        self.assertEqual([self.c1["id"]], [row["id"] for row in data["data"]])

    def test_another_schools_year_or_student_is_invalid(self):
        _, other_year, other_student, _ = school_with_a_charged_student()

        for params, field in (({"student_id": other_student.id}, "student_id"),
                              ({"academic_year_id": other_year.id}, "academic_year_id")):
            with self.subTest(params=params):
                response = self.as_user(self.accountant).get(CONCESSIONS, params)
                self.assertEqual(422, response.status_code, response.data)
                self.assertIn(field, response.data["details"]["errors"])

    def test_the_number_of_queries_does_not_grow_with_the_discounts(self):
        def queries() -> int:
            with CaptureQueriesContext(connection) as captured:
                self.listed()
            return len(captured)

        few = queries()

        for _ in range(5):
            self.conceded("fixed", "1.00", student=self.bina)

        self.assertEqual(few, queries())
        self.assertLessEqual(few, 12)


class TheForm(AdjustmentsTestCase):
    def errors(self, **overrides) -> dict:
        body = {"student_id": self.aarav.id, "academic_year_id": self.year.id, "fee_head_id": self.tuition.id,
                "kind": "fixed", "value": "500.00", "reason": "Sibling", **overrides}
        response = self.as_user(self.accountant).post(CONCESSIONS, body, format="json")
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]

    def test_the_created_resource(self):
        data = self.conceded("percent", "12.50", head=None, reason="  Scholarship  ")

        self.assertEqual(("percent", "12.50", None, "Scholarship", 4),
                         (data["kind"], data["value"], data["fee_head"], data["reason"], data["dues_affected"]))

    def test_every_field_is_checked(self):
        other_school, other_year, other_student, _ = school_with_a_charged_student()
        their_head = FeeHead.objects.get(school=other_school, name="Tuition")
        retired = FeeHead.objects.create(school=self.school, name="Library", is_active=False)

        cases = [
            ({"student_id": None}, "student_id", "The student id field is required."),
            ({"student_id": other_student.id}, "student_id", "The selected student id is invalid."),
            ({"academic_year_id": None}, "academic_year_id", "The academic year id field is required."),
            ({"academic_year_id": other_year.id}, "academic_year_id", "The selected academic year id is invalid."),
            ({"fee_head_id": their_head.id}, "fee_head_id", "The selected fee head id is invalid."),
            ({"fee_head_id": retired.id}, "fee_head_id",
             "The Library fee type is retired. Bring it back before giving a discount on it."),
            ({"kind": None}, "kind", "The kind field is required."),
            ({"kind": "free"}, "kind", "The selected kind is invalid."),
            ({"value": None}, "value", "The value field is required."),
            ({"kind": "percent", "value": "100.01"}, "value", "A percentage can't be more than 100."),
            ({"reason": None}, "reason", "The reason field is required."),
            ({"reason": "ab"}, "reason", "The reason field must be at least 3 characters."),
            ({"reason": "x" * 256}, "reason", "The reason field must not be greater than 255 characters."),
        ]

        for overrides, field, message in cases:
            with self.subTest(overrides=overrides):
                self.assertEqual([message], self.errors(**overrides)[field])

        for value in ("0", "-5", "abc", "1.001"):
            with self.subTest(value=value):
                self.assertIn("value", self.errors(value=value))

        self.assertEqual(0, FeeConcession.objects.count())

    def test_a_hundred_percent_and_the_transport_head_are_allowed(self):
        self.conceded("percent", "100")
        self.conceded("fixed", "50.00", head="transport")

        self.assertEqual(2, FeeConcession.objects.count())

    def test_the_student_must_be_in_the_year(self):
        later = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                              start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))

        self.assertEqual(
            [f"{self.aarav.name} is not enrolled in 2027-28 and has no fees in it."],
            self.errors(academic_year_id=later.id)["student_id"],
        )

    def test_removing_twice_is_a_conflict_and_an_unknown_one_is_not_found(self):
        concession = self.conceded()
        self.assertEqual(200, self.revoke(concession["id"]).status_code)

        again = self.revoke(concession["id"])

        self.assertEqual(409, again.status_code)
        self.assertEqual(("FEE_CONCESSION_REVOKED", "This discount is already removed."),
                         (again.data["code"], again.data["message"]))
        self.assertEqual(404, self.revoke(999999).status_code)
        self.assertEqual(1, AuditLog.objects.filter(action="fee_concession.revoked").count())

    def test_the_removal_reason_is_optional_but_checked(self):
        concession = self.conceded()

        response = self.revoke(concession["id"], reason="ab")
        self.assertEqual(422, response.status_code)
        self.assertIsNone(FeeConcession.objects.get().revoked_at)

        response = self.as_user(self.accountant).delete(f"{CONCESSIONS}/{concession['id']}")
        self.assertEqual(200, response.status_code)
        self.assertIsNotNone(response.data["revoked_at"])

    def test_an_unknown_due_is_not_found(self):
        self.assertEqual(404, self.as_user(self.accountant).post(f"{DUES}/999999/waive", {"reason": "abc"},
                                                                 format="json").status_code)


class TheStatement(AdjustmentsTestCase):
    def test_each_due_and_the_totals_say_more_and_the_active_discounts_come_with_it(self):
        active = self.conceded("fixed", "100.00")
        revoked = self.conceded("fixed", "5.00")
        self.revoke(revoked["id"])
        self.fines_on(amount=50, grace=5)
        self.run_fines()
        self.waived(self.due("Tuition - July"), reason="Hardship")

        data = self.as_user(self.accountant).get(f"{STATEMENT}/{self.aarav.id}").data

        self.assertEqual([active["id"]], [row["id"] for row in data["concessions"]])
        self.assertEqual("Class 8", data["concessions"][0]["student"]["class_name"])
        april, july, fine = data["dues"][:3]
        self.assertEqual(("installment", None, None, None),
                         (april["kind"], april["fine_for_due_id"], april["waive_reason"], april["waived_at"]))
        self.assertEqual(("installment", "Hardship", "waived", "0.00"),
                         (july["kind"], july["waive_reason"], july["status"], july["balance"]))
        self.assertIsNotNone(july["waived_at"])
        self.assertEqual(("late_fine", april["id"], "Late fine - Tuition - April", "50.00", "0.00"),
                         (fine["kind"], fine["fine_for_due_id"], fine["label"], fine["amount"],
                          fine["discount_amount"]))
        self.assertEqual(
            {"charged": "4050.00", "discount": "400.00", "paid": "0.00", "balance": "2750.00",
             "overdue": "900.00", "waived": "900.00"},
            data["totals"],
        )


# -- who may do what ------------------------------------------------------------------


class WhoMay(AdjustmentsTestCase):
    def setUp(self):
        super().setUp()
        self.concession = self.conceded()
        self.april = self.due("Tuition - April")

    def reads(self, client) -> list:
        return [client.get(CONCESSIONS), client.get(f"{STATEMENT}/{self.aarav.id}")]

    def writes(self, client, student=None, concession_id=None, due=None) -> list:
        body = {"student_id": (student or self.aarav).id, "academic_year_id": self.year_of(student),
                "kind": "fixed", "value": "10.00", "reason": "Sibling"}

        return [
            client.post(CONCESSIONS, body, format="json"),
            client.delete(f"{CONCESSIONS}/{concession_id or self.concession['id']}"),
            client.post(f"{DUES}/{(due or self.april).id}/waive", {"reason": "Hardship"}, format="json"),
        ]

    def year_of(self, student) -> int:
        if student is None:
            return self.year.id

        return StudentFeeDue.objects.filter(student=student).values_list("academic_year_id", flat=True).first()

    def test_the_school_admin_and_the_accountant_may_do_everything(self):
        for user in (self.admin, self.accountant):
            with self.subTest(role=user.role):
                concession = self.conceded(user=user)
                due = StudentFeeDue.objects.filter(student=self.aarav, status="pending").first()

                for response in self.reads(self.as_user(user)):
                    self.assertEqual(200, response.status_code)

                created, revoked, waived = self.writes(self.as_user(user), concession_id=concession["id"], due=due)
                self.assertEqual((201, 200, 200), (created.status_code, revoked.status_code, waived.status_code))

    def test_a_super_admin_reads_every_school_and_changes_nothing(self):
        other_school, _, other_student, their_accountant = school_with_a_charged_student()
        theirs = self.conceded(student=other_student, user=their_accountant, head=None,
                               year=other_student.fee_dues.first().academic_year)
        client = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        for response in self.reads(client):
            self.assertEqual(200, response.status_code)

        every = {row["id"] for row in client.get(CONCESSIONS).data["data"]}
        self.assertEqual({self.concession["id"], theirs["id"]}, every)
        self.assertEqual([theirs["id"]],
                         [row["id"] for row in client.get(CONCESSIONS, {"school_id": other_school.id}).data["data"]])

        for response in self.writes(client):
            self.assertEqual(403, response.status_code)

        self.assertIsNone(FeeConcession.objects.get(pk=self.concession["id"]).revoked_at)
        self.assertEqual("pending", StudentFeeDue.objects.get(pk=self.april.id).status)

    def test_every_other_role_is_refused(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.DRIVER,
                     UserRole.BUS_ATTENDANT):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))

            for response in (*self.reads(client), *self.writes(client)):
                with self.subTest(role=role):
                    self.assertEqual(403, response.status_code)

        self.assertEqual(1, FeeConcession.objects.count())

    def test_nobody_signed_in_is_asked_to_sign_in(self):
        for response in (*self.reads(APIClient()), *self.writes(APIClient())):
            self.assertEqual(401, response.status_code)

    def test_a_school_with_fees_off_is_refused(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        for response in (*self.reads(self.as_user(self.accountant)), *self.writes(self.as_user(self.accountant))):
            self.assertEqual(403, response.status_code)
            self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_another_schools_discount_and_due_are_forbidden_and_their_student_is_invalid(self):
        _, _, other_student, their_accountant = school_with_a_charged_student()
        theirs = self.conceded(student=other_student, user=their_accountant, head=None,
                               year=other_student.fee_dues.first().academic_year)
        their_due = StudentFeeDue.objects.get(student=other_student)

        created, revoked, waived = self.writes(self.as_user(self.accountant), student=other_student,
                                               concession_id=theirs["id"], due=their_due)

        self.assertEqual((422, 403, 403), (created.status_code, revoked.status_code, waived.status_code))
        self.assertEqual(["The selected student id is invalid."], created.data["details"]["errors"]["student_id"])
        self.assertIsNone(FeeConcession.objects.get(pk=theirs["id"]).revoked_at)
        self.assertEqual("pending", StudentFeeDue.objects.get(pk=their_due.id).status)

    def test_a_group_admin_works_across_their_group_and_nowhere_else(self):
        _, _, branch_student, branch_accountant = school_with_a_charged_student(self.school, "Sunrise North")
        branch_year = branch_student.fee_dues.first().academic_year
        branch = self.conceded(student=branch_student, user=branch_accountant, head=None, year=branch_year)
        _, _, outside_student, outside_accountant = school_with_a_charged_student(name="Elsewhere")
        outside_year = outside_student.fee_dues.first().academic_year
        outside = self.conceded(student=outside_student, user=outside_accountant, head=None, year=outside_year)
        client = self.as_user(factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN))

        listed = {row["id"] for row in client.get(CONCESSIONS).data["data"]}
        self.assertEqual({self.concession["id"], branch["id"]}, listed)

        created, revoked, waived = self.writes(client, student=branch_student, concession_id=branch["id"],
                                               due=StudentFeeDue.objects.get(student=branch_student))
        self.assertEqual((201, 200, 200), (created.status_code, revoked.status_code, waived.status_code))

        created, revoked, waived = self.writes(client, student=outside_student, concession_id=outside["id"],
                                               due=StudentFeeDue.objects.get(student=outside_student))
        self.assertEqual((422, 403, 403), (created.status_code, revoked.status_code, waived.status_code))
        self.assertEqual(403, client.get(f"{STATEMENT}/{outside_student.id}").status_code)

    def test_a_widened_matrix_lets_staff_give_discounts(self):
        RolePermission.objects.create(role="STAFF", module="fees", level="manage")
        clerk = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        self.assertEqual(201, self.concede(user=clerk).status_code)

    def test_view_only_may_read_but_not_change(self):
        RolePermission.objects.create(role="TEACHER", module="fees", level="view")
        client = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual([200, 200], [response.status_code for response in self.reads(client)])
        self.assertEqual([403, 403, 403], [response.status_code for response in self.writes(client)])
