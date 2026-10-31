"""A new school's setup guide (docs/onboarding.md, slice O4).

Six steps, each done because the school has the thing - never because
somebody ticked it - and the guide's closed state remembered for the whole
school. Plus the common departments in one step.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import StudentStatus, UserRole
from school.models import AuditLog, Department, School


class GuideTest(TestCase):
    url = "/api/v1/setup-guide"

    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def steps(self) -> dict:
        response = self.client.get(self.url)
        self.assertEqual(200, response.status_code, response.data)

        return {step["key"]: step for step in response.data["steps"]}


class TheSteps(GuideTest):
    def test_a_new_school_has_six_steps_none_done_in_dependency_order(self):
        response = self.client.get(self.url)

        self.assertEqual(
            ["academic_year", "departments", "classes", "subjects", "staff", "students"],
            [step["key"] for step in response.data["steps"]],
        )
        self.assertEqual((0, 6, False), (response.data["done"], response.data["total"], response.data["closed"]))
        self.assertEqual(self.school.name, response.data["school_name"])

    def test_the_admin_who_runs_the_school_is_not_counted_as_staff(self):
        self.assertFalse(self.steps()["staff"]["done"])

    def test_a_step_that_depends_on_another_says_which(self):
        steps = self.steps()

        self.assertIn("academic year first", steps["classes"]["blocked_by"])
        self.assertIn("department first", steps["subjects"]["blocked_by"])
        self.assertIn("classes and sections first", steps["students"]["blocked_by"])

    def test_each_step_is_done_by_the_data_itself(self):
        year = factories.AcademicYearFactory(school=self.school, name="2026-27", is_current=True)
        department = factories.DepartmentFactory(school=self.school)
        school_class = factories.SchoolClassFactory(school=self.school, academic_year=year, name="Class 1", level=1)
        section = factories.ClassSectionFactory(school_class=school_class)
        factories.SubjectFactory(school=self.school, department=department)
        factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.StudentFactory(school=self.school, class_section=section)

        response = self.client.get(self.url)

        self.assertEqual(6, response.data["done"])
        steps = {step["key"]: step for step in response.data["steps"]}
        self.assertEqual("2026-27 is the current year", steps["academic_year"]["summary"])
        self.assertEqual("1 class, 1 section", steps["classes"]["summary"])
        self.assertIsNone(steps["students"]["blocked_by"])

    def test_classes_count_only_in_the_current_year(self):
        old = factories.AcademicYearFactory(school=self.school, name="Last year", is_current=False)
        old_class = factories.SchoolClassFactory(school=self.school, academic_year=old)
        factories.ClassSectionFactory(school_class=old_class)
        factories.AcademicYearFactory(school=self.school, name="This year", is_current=True)

        self.assertFalse(self.steps()["classes"]["done"])

    def test_students_who_left_do_not_count(self):
        factories.StudentFactory(school=self.school, status=StudentStatus.INACTIVE)

        self.assertFalse(self.steps()["students"]["done"])

    def test_another_schools_records_never_count(self):
        other = factories.SchoolFactory()
        factories.AcademicYearFactory(school=other, is_current=True)
        factories.DepartmentFactory(school=other)

        steps = self.steps()

        self.assertFalse(steps["academic_year"]["done"])
        self.assertFalse(steps["departments"]["done"])


class OpenOrClosed(GuideTest):
    def test_closing_hides_it_for_every_admin_of_the_school_and_is_audited(self):
        before = AuditLog.objects.count()

        response = self.client.post(f"{self.url}/close")

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(response.data["closed"])
        other_admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN, is_sub_admin=True)
        self.assertTrue(self.as_user(other_admin).get(self.url).data["closed"])
        self.assertEqual(before + 1, AuditLog.objects.count())

    def test_closing_twice_changes_nothing_the_second_time(self):
        self.client.post(f"{self.url}/close")
        closed_at = School.objects.get(pk=self.school.id).setup_guide_closed_at
        before = AuditLog.objects.count()

        self.client.post(f"{self.url}/close")

        self.assertEqual(closed_at, School.objects.get(pk=self.school.id).setup_guide_closed_at)
        self.assertEqual(before, AuditLog.objects.count())

    def test_reopening_brings_it_back(self):
        self.client.post(f"{self.url}/close")

        response = self.client.post(f"{self.url}/reopen")

        self.assertFalse(response.data["closed"])
        self.assertIsNone(School.objects.get(pk=self.school.id).setup_guide_closed_at)

    def test_one_schools_choice_does_not_touch_another(self):
        other = factories.SchoolFactory()
        self.client.post(f"{self.url}/close")

        self.assertIsNone(School.objects.get(pk=other.id).setup_guide_closed_at)


class WhoMay(GuideTest):
    def test_only_a_school_admin_has_a_guide(self):
        for role in (UserRole.TEACHER, UserRole.ACCOUNTANT, UserRole.HOD):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, client.get(self.url).status_code)
                self.assertEqual(403, client.post(f"{self.url}/close").status_code)

        self.assertIsNone(School.objects.get(pk=self.school.id).setup_guide_closed_at)

    def test_a_super_admin_has_no_school_to_set_up_here(self):
        root = self.as_user(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))

        self.assertEqual(403, root.get(self.url).status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(self.url).status_code)


class QuickDepartments(GuideTest):
    url = "/api/v1/departments/quick-setup"

    def test_it_offers_the_common_departments(self):
        response = self.client.get(self.url)

        self.assertEqual(200, response.status_code, response.data)
        names = [row["name"] for row in response.data["departments"]]
        self.assertIn("Science", names)
        self.assertTrue(next(row for row in response.data["departments"] if row["name"] == "Primary")["selected"])

    def test_the_chosen_ones_are_created_and_existing_ones_skipped(self):
        factories.DepartmentFactory(school=self.school, name="science")

        response = self.client.post(self.url, {"names": ["Primary", "Science", "Primary", " Arts "]}, format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual({"created": ["Primary", "Arts"], "skipped": ["Science"]}, response.data)
        self.assertEqual(
            ["Arts", "Primary", "science"],
            sorted(Department.objects.filter(school=self.school).values_list("name", flat=True)),
        )

    def test_nothing_chosen_is_refused(self):
        response = self.client.post(self.url, {"names": []}, format="json")

        self.assertEqual(422, response.status_code, response.data)

    def test_the_client_school_id_is_not_trusted(self):
        other = factories.SchoolFactory()

        self.client.post(self.url, {"names": ["Primary"], "school_id": other.id}, format="json")

        self.assertFalse(Department.objects.filter(school=other).exists())

    def test_a_teacher_may_not(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, teacher.post(self.url, {"names": ["Primary"]}, format="json").status_code)
        self.assertFalse(Department.objects.exists())
