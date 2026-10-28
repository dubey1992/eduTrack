"""Reading what students owe over HTTP (docs/fees.md, F2): a student's fees
statement, the balances list, `students_count` on the fee list, the student
form's admission date, and who may read any of it. Charging itself is
test_fees_dues.py, whose fixtures these tests share.
"""

import datetime as dt
from unittest import mock

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from school import factories
from school.enums import FeeDueStatus, StudentStatus, UserRole
from school.models import AcademicYear, ModuleSetting, RolePermission, StudentFeeDue

from .test_fees_dues import ROUTE_A, TUITION_8, TUITION_9, DuesTestCase

STATEMENT = "/api/v1/fees/students"
BALANCES = "/api/v1/fees/balances"
STRUCTURES = "/api/v1/fees/structures"
STUDENTS = "/api/v1/students"


class StatementTestCase(DuesTestCase):
    def statement(self, student, user=None, **params):
        return self.as_user(user or self.accountant).get(f"{STATEMENT}/{student.id}", params)

    def balances(self, user=None, **params):
        params.setdefault("academic_year_id", self.year.id)

        return self.as_user(user or self.accountant).get(BALANCES, params)

    def errors(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]


# -- the statement --------------------------------------------------------------


class TheStatement(StatementTestCase):
    def test_a_statement_lists_every_due_cancelled_ones_too_with_totals_that_leave_them_out(self):
        aarav = self.student("Aarav", last_name="Shah", admission_number="ADM-1", roll_number="4")
        self.published(TUITION_8, school_class=self.class8)
        self.published(TUITION_9, school_class=self.class9)
        self.patch_student(aarav, {"class_section_id": self.section9.id})
        StudentFeeDue.objects.filter(student=aarav, label="Tuition - April").update(
            status=FeeDueStatus.PARTIAL, paid_amount="250.00"
        )

        response = self.statement(aarav)

        self.assertEqual(200, response.status_code, response.data)
        data = response.data
        self.assertEqual(
            {"id": aarav.id, "name": "Aarav Shah", "admission_number": "ADM-1", "class_name": "Class 9",
             "section_name": "A", "status": "active", "admission_date": "2026-04-01"},
            data["student"],
        )
        self.assertEqual({"id": self.year.id, "name": "2026-27"}, data["academic_year"])
        self.assertEqual("INR", data["currency_code"])
        self.assertEqual(
            [
                ("Tuition - April", "2026-04-10", "1000.00", "250.00", "750.00", "partial", True, None),
                ("Tuition - July", "2026-07-10", "1000.00", "0.00", "1000.00", "pending", True, None),
                # A cancelled due owes nothing (F4).
                ("Tuition - October", "2026-10-10", "1000.00", "0.00", "0.00", "cancelled", False,
                 "class_changed"),
                ("Tuition - Term 2", "2026-10-10", "1500.00", "0.00", "1500.00", "pending", False, None),
                ("Tuition - January", "2027-01-10", "1000.00", "0.00", "0.00", "cancelled", False,
                 "class_changed"),
                ("Tuition - Term 3", "2027-01-10", "1500.00", "0.00", "1500.00", "pending", False, None),
            ],
            [
                (row["label"], row["due_date"], row["amount"], row["paid_amount"], row["balance"], row["status"],
                 row["is_overdue"], row["cancelled_reason"])
                for row in data["dues"]
            ],
        )
        first = data["dues"][0]
        self.assertEqual({"id": self.tuition.id, "name": "Tuition"}, first["fee_head"])
        self.assertEqual("0.00", first["discount_amount"])
        self.assertIsInstance(first["id"], int)
        self.assertEqual(
            {"charged": "5000.00", "discount": "0.00", "paid": "250.00", "balance": "4750.00", "overdue": "1750.00",
             "waived": "0.00"},
            data["totals"],
        )

    def test_dues_on_the_same_day_are_ordered_by_fee_type(self):
        aarav = self.student()
        self.published(ROUTE_A, route=self.route_a)
        self.published(TUITION_8, school_class=self.class8)
        self.ride(aarav, self.route_a, self.stop_a)

        labels = [row["label"] for row in self.statement(aarav).data["dues"]]

        self.assertEqual(["Transport - Bus 1", "Tuition - April", "Tuition - July", "Transport - Bus 2",
                          "Tuition - October", "Tuition - January"], labels)

    def test_overdue_is_judged_by_the_schools_date_not_utc(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)

        # 10:00 UTC on 10 July is 15:30 the same day in Kolkata: July is due
        # today, not overdue.
        with mock.patch("django.utils.timezone.now",
                        return_value=dt.datetime(2026, 7, 10, 10, 0, tzinfo=dt.timezone.utc)):
            on_the_day = self.statement(aarav).data

        # 20:00 UTC is already 11 July in Kolkata - overdue there, though
        # still the 10th in UTC.
        with mock.patch("django.utils.timezone.now",
                        return_value=dt.datetime(2026, 7, 10, 20, 0, tzinfo=dt.timezone.utc)):
            next_morning = self.statement(aarav).data

        self.assertFalse(on_the_day["dues"][1]["is_overdue"])
        self.assertEqual("1000.00", on_the_day["totals"]["overdue"])
        self.assertTrue(next_morning["dues"][1]["is_overdue"])
        self.assertEqual("2000.00", next_morning["totals"]["overdue"])

    def test_a_student_with_nothing_charged_has_an_empty_statement(self):
        aarav = self.student(admission=None)

        data = self.statement(aarav).data

        self.assertEqual([], data["dues"])
        self.assertIsNone(data["student"]["admission_date"])
        self.assertEqual("INR", data["currency_code"])
        self.assertEqual({key: "0.00" for key in ("charged", "discount", "paid", "balance", "overdue", "waived")},
                         data["totals"])

    def test_the_year_defaults_to_the_current_one_then_the_latest_with_dues_then_the_latest(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)
        later = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                              start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))

        self.assertEqual(self.year.id, self.statement(aarav).data["academic_year"]["id"], "the current year")

        AcademicYear.objects.filter(pk=self.year.id).update(is_current=False)
        self.assertEqual(self.year.id, self.statement(aarav).data["academic_year"]["id"],
                         "no current year: the latest the student owes in, not the later empty one")

        StudentFeeDue.objects.filter(student=aarav).delete()
        self.assertEqual(later.id, self.statement(aarav).data["academic_year"]["id"], "else the latest")

        self.assertEqual(later.id, self.statement(aarav, academic_year_id=later.id).data["academic_year"]["id"])

    def test_a_year_of_another_school_or_nonsense_is_invalid_and_an_unknown_student_is_not_found(self):
        aarav = self.student()
        theirs = factories.AcademicYearFactory(school=factories.SchoolFactory())

        self.assertEqual(["The selected academic year id is invalid."],
                         self.errors(self.statement(aarav, academic_year_id=theirs.id))["academic_year_id"])
        self.assertIn("academic_year_id", self.errors(self.statement(aarav, academic_year_id="abc")))
        self.assertEqual(404, self.as_user(self.accountant).get(f"{STATEMENT}/999999").status_code)


# -- the balances list -----------------------------------------------------------


class TheBalancesList(StatementTestCase):
    def setUp(self):
        super().setUp()
        self.section8b = factories.ClassSectionFactory(school_class=self.class8, name="B")
        self.published(TUITION_8, school_class=self.class8)
        self.published(TUITION_9, school_class=self.class9)

        self.aarav = self.student("Aarav", last_name="Shah", admission_number="ADM-1", roll_number="2")
        self.bina = self.student("Bina", last_name="Iyer", admission_number="ADM-2", roll_number="1")
        self.chetan = self.student("Chetan", last_name="Das", section=self.section8b, admission_number="ADM-3",
                                   roll_number="1")
        self.divya = self.student("Divya", last_name="Rao", section=self.section9, admission_number="ADM-4",
                                  roll_number="1")
        self.sync_all()
        # Aarav has paid April in full, and half of July.
        StudentFeeDue.objects.filter(student=self.aarav, label="Tuition - April").update(
            status=FeeDueStatus.PAID, paid_amount="1000.00"
        )
        StudentFeeDue.objects.filter(student=self.aarav, label="Tuition - July").update(
            status=FeeDueStatus.PARTIAL, paid_amount="500.00"
        )
        # Esha left in May: owes April and July, nothing later.
        self.esha = self.student("Esha", last_name="Bose", admission_number="ADM-5", roll_number="3")
        self.sync_all()
        self.as_user(self.admin).patch(f"{STUDENTS}/{self.esha.id}/deactivate")
        # Farah left before anything was charged: not on the list.
        self.farah = self.student("Farah", admission_number="ADM-6", status=StudentStatus.INACTIVE)

    def sync_all(self):
        from school.fees.dues import FeeDueService

        FeeDueService.sync_many(list(self.year_students()), self.year)

    def year_students(self):
        from school.models import StudentEnrollment

        return StudentEnrollment.objects.filter(academic_year=self.year).values_list("student_id", flat=True)

    def rows(self, response) -> list[tuple]:
        self.assertEqual(200, response.status_code, response.data)

        return [
            (row["student"]["name"], row["charged"], row["paid"], row["balance"], row["overdue"], row["next_due_date"])
            for row in response.data["data"]
        ]

    def test_every_student_of_the_year_in_register_order_with_their_totals(self):
        response = self.balances()

        self.assertEqual(
            [
                # Class 8 A, by roll number: Bina (1), Aarav (2), Esha (3).
                ("Bina Iyer", "4000.00", "0.00", "4000.00", "2000.00", "2026-10-10"),
                ("Aarav Shah", "4000.00", "1500.00", "2500.00", "500.00", "2026-10-10"),
                ("Esha Bose", "2000.00", "0.00", "2000.00", "2000.00", None),
                # Class 8 B, then Class 9.
                ("Chetan Das", "4000.00", "0.00", "4000.00", "2000.00", "2026-10-10"),
                ("Divya Rao", "3000.00", "0.00", "3000.00", "0.00", "2026-10-10"),
            ],
            self.rows(response),
        )
        first = response.data["data"][0]
        self.assertEqual(
            {"id": self.bina.id, "name": "Bina Iyer", "admission_number": "ADM-2", "class_name": "Class 8",
             "section_name": "A", "status": "active"},
            first["student"],
        )
        self.assertEqual("INR", first["currency_code"])
        self.assertEqual(5, response.data["meta"]["total"])
        self.assertEqual("inactive", response.data["data"][2]["student"]["status"])

    def test_filters_by_class_section_owing_and_overdue(self):
        self.assertEqual(["Bina Iyer", "Aarav Shah", "Esha Bose", "Chetan Das"],
                         [row[0] for row in self.rows(self.balances(school_class_id=self.class8.id))])
        self.assertEqual(["Chetan Das"], [row[0] for row in self.rows(self.balances(class_section_id=self.section8b.id))])

        StudentFeeDue.objects.filter(student=self.divya).update(status=FeeDueStatus.PAID, paid_amount="1500.00")
        self.assertNotIn("Divya Rao", [row[0] for row in self.rows(self.balances(owing=1))])
        self.assertEqual(["Bina Iyer", "Aarav Shah", "Esha Bose", "Chetan Das"],
                         [row[0] for row in self.rows(self.balances(owing=1))])
        self.assertEqual(["Bina Iyer", "Aarav Shah", "Esha Bose", "Chetan Das"],
                         [row[0] for row in self.rows(self.balances(overdue=1))])
        self.assertEqual(5, len(self.rows(self.balances(owing=0, overdue=0))))

    def test_search_by_name_or_admission_number_without_regard_to_case(self):
        for term, expected in (("aarav", ["Aarav Shah"]), ("SHAH", ["Aarav Shah"]), ("aarav sh", ["Aarav Shah"]),
                               ("adm-4", ["Divya Rao"]), ("nobody", [])):
            with self.subTest(term=term):
                self.assertEqual(expected, [row[0] for row in self.rows(self.balances(search=term))])

    def test_pages(self):
        first = self.balances(per_page=2)
        second = self.balances(per_page=2, page=3)

        self.assertEqual(["Bina Iyer", "Aarav Shah"], [row[0] for row in self.rows(first)])
        self.assertEqual(["Divya Rao"], [row[0] for row in self.rows(second)])
        self.assertEqual((5, 3, 2), (first.data["meta"]["total"], first.data["meta"]["last_page"],
                                     first.data["meta"]["per_page"]))

    def test_the_number_of_queries_does_not_grow_with_the_students(self):
        def queries() -> int:
            with CaptureQueriesContext(connection) as captured:
                self.assertEqual(200, self.balances(per_page=100).status_code)

            return len(captured.captured_queries)

        few = queries()

        for index in range(10):
            self.student(f"Extra{index}", admission_number=f"ADM-X{index}")
        self.sync_all()

        self.assertEqual(few, queries())
        self.assertLessEqual(few, 12)

    def test_the_year_is_required_and_another_schools_ids_are_invalid(self):
        other = factories.SchoolFactory()
        other_year = factories.AcademicYearFactory(school=other)
        other_class = factories.SchoolClassFactory(academic_year=other_year)
        other_section = factories.ClassSectionFactory(school_class=other_class)

        self.assertEqual(["The academic year id field is required."],
                         self.errors(self.as_user(self.accountant).get(BALANCES))["academic_year_id"])
        self.assertIn("academic_year_id", self.errors(self.balances(academic_year_id=other_year.id)))
        errors = self.errors(self.balances(school_class_id=other_class.id, class_section_id=other_section.id))
        self.assertEqual(["The selected school class id is invalid."], errors["school_class_id"])
        self.assertEqual(["The selected class section id is invalid."], errors["class_section_id"])

    def test_the_fee_list_counts_the_students_each_fee_charges(self):
        data = self.as_user(self.accountant).get(STRUCTURES, {"academic_year_id": self.year.id}).data["data"]

        # Class 8: Aarav, Bina, Chetan, and Esha who still owes April and July.
        self.assertEqual([("Class 8", 4), ("Class 9", 1)],
                         [(row["school_class"]["name"], row["students_count"]) for row in data])


# -- who may read it ----------------------------------------------------------------


class WhoMayRead(StatementTestCase):
    def setUp(self):
        super().setUp()
        self.aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)

    def both(self, client, student=None):
        student = student or self.aarav

        return (
            client.get(f"{STATEMENT}/{student.id}"),
            client.get(BALANCES, {"academic_year_id": student.school_id == self.school.id and self.year.id
                                  or AcademicYear.objects.filter(school_id=student.school_id).first().id}),
        )

    def test_the_office_and_a_super_admin_may_read(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        for user in (self.admin, self.accountant, root):
            with self.subTest(role=user.role):
                for response in self.both(self.as_user(user)):
                    self.assertEqual(200, response.status_code, response.data)

    def test_every_other_role_is_refused(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.DRIVER,
                     UserRole.BUS_ATTENDANT):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))

            for response in self.both(client):
                with self.subTest(role=role):
                    self.assertEqual(403, response.status_code)
                    self.assertEqual("FORBIDDEN", response.data["code"])

    def test_a_widened_matrix_lets_a_teacher_read(self):
        RolePermission.objects.create(role="TEACHER", module="fees", level="view")
        client = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        for response in self.both(client):
            self.assertEqual(200, response.status_code)

    def test_nobody_signed_in_is_asked_to_sign_in(self):
        for response in self.both(APIClient()):
            self.assertEqual(401, response.status_code)

    def test_a_school_with_fees_off_is_refused(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        for response in self.both(self.as_user(self.accountant)):
            self.assertEqual(403, response.status_code)
            self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_another_schools_student_is_forbidden_and_their_year_is_invalid(self):
        other = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=other, module="fees")
        other_year = factories.AcademicYearFactory(school=other)
        theirs = factories.StudentFactory(
            school=other,
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=other_year)
            ),
        )

        statement, balances = self.both(self.as_user(self.admin), theirs)

        self.assertEqual(403, statement.status_code)
        self.assertEqual(422, balances.status_code)
        self.assertIn("academic_year_id", balances.data["details"]["errors"])

    def test_a_group_admin_reads_their_group_and_nowhere_else(self):
        branch = factories.SchoolFactory(parent_school=self.school, name="Sunrise North")
        factories.ModuleSettingFactory(school=branch, module="fees")
        branch_year = factories.AcademicYearFactory(school=branch)
        branch_student = factories.StudentFactory(
            school=branch,
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=branch_year)
            ),
        )
        outsider = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=outsider, module="fees")
        outside_year = factories.AcademicYearFactory(school=outsider)
        outside_student = factories.StudentFactory(
            school=outsider,
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=outside_year)
            ),
        )
        client = self.as_user(factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN))

        for response in (*self.both(client), *self.both(client, branch_student)):
            self.assertEqual(200, response.status_code, response.data)

        statement, balances = self.both(client, outside_student)
        self.assertEqual(403, statement.status_code)
        self.assertEqual(422, balances.status_code)


# -- the admission date on the student form ---------------------------------------


class TheAdmissionDate(StatementTestCase):
    def create(self, **fields):
        return self.as_user(self.admin).post(STUDENTS, {
            "class_section_id": self.section8.id, "admission_number": "ADM-99", "first_name": "Isha",
            "last_name": "Nair", "guardian_name": "Anil Nair", **fields,
        }, format="json")

    def test_it_is_optional_returned_and_cleared_with_null(self):
        created = self.create(admission_date="2026-06-15")
        self.assertEqual(201, created.status_code, created.data)
        self.assertEqual("2026-06-15", created.data["admission_date"])

        student_id = created.data["id"]
        self.assertEqual("2026-06-15", self.as_user(self.admin).get(f"{STUDENTS}/{student_id}").data["admission_date"])

        cleared = self.as_user(self.admin).patch(f"{STUDENTS}/{student_id}", {"admission_date": None}, format="json")
        self.assertEqual(200, cleared.status_code, cleared.data)
        self.assertIsNone(cleared.data["admission_date"])

    def test_it_must_be_a_date_from_1950_to_a_year_after_the_schools_today(self):
        # Today in Kolkata is 15 July 2026, so the latest is 15 July 2027.
        for value, message in (
            ("15/07/2026", "The admission date field must be a valid date."),
            ("2026-02-30", "The admission date field must be a valid date."),
            ("1949-12-31", "The admission date field must be a date after or equal to 1950-01-01."),
            ("2027-07-16", "The admission date field must be a date before or equal to 2027-07-15."),
        ):
            with self.subTest(value=value):
                self.assertEqual([message], self.errors(self.create(admission_date=value))["admission_date"])

        self.assertEqual(201, self.create(admission_date="2027-07-15").status_code)

    def test_an_edit_is_validated_the_same_way(self):
        aarav = self.student()

        response = self.as_user(self.admin).patch(f"{STUDENTS}/{aarav.id}", {"admission_date": "1900-01-01"},
                                                  format="json")

        self.assertEqual(["The admission date field must be a date after or equal to 1950-01-01."],
                         self.errors(response)["admission_date"])
        self.assertEqual(dt.date(2026, 4, 1), type(aarav).objects.get(pk=aarav.id).admission_date)
