"""Departments and subjects, over HTTP.

The rule these two share and that carries the risk: a department may only be
headed, and a subject only led, by somebody who teaches at *that* school.
Getting it wrong would let an admin attach a colleague from another school to
their own records - a leak dressed up as a dropdown.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Department, Subject


class AcademicConfigTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client


class Departments(AcademicConfigTest):
    def payload(self, **overrides) -> dict:
        body = {"school_id": self.school.id, "name": "Science"}
        body.update(overrides)

        return body

    def test_a_department_is_created_and_comes_back_whole(self):
        response = self.client.post("/api/v1/departments", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Science", response.data["name"])
        self.assertEqual(self.school.name, response.data["school_name"])
        self.assertIsNone(response.data["hod_user_id"])
        self.assertIsNone(response.data["hod_name"])

    def test_a_teacher_can_be_made_head_of_it(self):
        response = self.client.post(
            "/api/v1/departments", self.payload(hod_user_id=self.teacher.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.teacher.id, response.data["hod_user_id"])
        self.assertEqual(self.teacher.name, response.data["hod_name"])

    def test_an_hod_can_be_made_head_of_it(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)

        response = self.client.post(
            "/api/v1/departments", self.payload(hod_user_id=hod.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_somebody_who_does_not_teach_cannot_head_it(self):
        # Leading a department is a teaching role. An admin who also teaches
        # has a TEACHER or HOD account for that.
        staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        response = self.client.post(
            "/api/v1/departments", self.payload(hod_user_id=staff.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected hod user id is invalid.",
            response.data["details"]["errors"]["hod_user_id"][0],
        )

    def test_a_teacher_from_another_school_cannot_head_it(self):
        outsider = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.TEACHER)

        response = self.client.post(
            "/api/v1/departments", self.payload(hod_user_id=outsider.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("hod_user_id", response.data["details"]["errors"])

    def test_the_name_is_unique_within_the_school(self):
        self.client.post("/api/v1/departments", self.payload(), format="json")

        response = self.client.post("/api/v1/departments", self.payload(), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The name has already been taken.", response.data["details"]["errors"]["name"][0]
        )

    def test_another_school_may_have_a_department_of_the_same_name(self):
        self.client.post("/api/v1/departments", self.payload(), format="json")

        elsewhere = factories.SchoolFactory()
        other_admin = self.as_user(
            factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)
        )

        response = other_admin.post(
            "/api/v1/departments", {"school_id": elsewhere.id, "name": "Science"}, format="json"
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_keeping_its_own_name_is_not_a_duplicate(self):
        created = self.client.post("/api/v1/departments", self.payload(), format="json")

        response = self.client.patch(
            f"/api/v1/departments/{created.data['id']}",
            {"name": "Science", "hod_user_id": self.teacher.id},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_an_empty_department_can_be_deleted(self):
        created = self.client.post("/api/v1/departments", self.payload(), format="json")

        response = self.client.delete(f"/api/v1/departments/{created.data['id']}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(Department.objects.filter(pk=created.data["id"]).exists())

    def test_a_department_with_subjects_is_refused_with_the_reason(self):
        department = factories.DepartmentFactory(school=self.school)
        Subject.objects.create(
            school_id=self.school.id,
            department_id=department.id,
            code="SCI",
            name="Science",
            min_class_level=1,
            max_class_level=12,
        )

        response = self.client.delete(f"/api/v1/departments/{department.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("HAS_DEPENDENT_RECORDS", response.data["code"])
        self.assertEqual(
            "This department still has subjects assigned to it. "
            "Reassign or remove them first.",
            response.data["message"],
        )
        self.assertTrue(Department.objects.filter(pk=department.id).exists())

    def test_a_teacher_may_read_but_not_write(self):
        department = factories.DepartmentFactory(school=self.school)
        teacher = self.as_user(self.teacher)

        self.assertEqual(200, teacher.get("/api/v1/departments").status_code)
        self.assertEqual(200, teacher.get(f"/api/v1/departments/{department.id}").status_code)
        self.assertEqual(
            403, teacher.post("/api/v1/departments", self.payload(), format="json").status_code
        )
        self.assertEqual(403, teacher.delete(f"/api/v1/departments/{department.id}").status_code)


class Subjects(AcademicConfigTest):
    def setUp(self):
        super().setUp()
        self.department = factories.DepartmentFactory(school=self.school)

    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "department_id": self.department.id,
            "code": "SCI",
            "name": "Science",
            "min_class_level": 1,
            "max_class_level": 12,
        }
        body.update(overrides)

        return body

    def test_a_subject_is_created_and_comes_back_whole(self):
        response = self.client.post("/api/v1/subjects", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("SCI", response.data["code"])
        self.assertEqual(self.department.name, response.data["department_name"])
        self.assertEqual(self.school.name, response.data["school_name"])
        self.assertIsNone(response.data["lead_teacher_name"])

    def test_a_teacher_can_lead_it(self):
        response = self.client.post(
            "/api/v1/subjects", self.payload(lead_teacher_id=self.teacher.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.teacher.name, response.data["lead_teacher_name"])

    def test_a_teacher_from_another_school_cannot_lead_it(self):
        outsider = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.TEACHER)

        response = self.client.post(
            "/api/v1/subjects", self.payload(lead_teacher_id=outsider.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("lead_teacher_id", response.data["details"]["errors"])

    def test_a_department_from_another_school_is_refused(self):
        elsewhere = factories.DepartmentFactory(school=factories.SchoolFactory())

        response = self.client.post(
            "/api/v1/subjects", self.payload(department_id=elsewhere.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected department id is invalid.",
            response.data["details"]["errors"]["department_id"][0],
        )

    def test_the_code_is_unique_within_the_school(self):
        self.client.post("/api/v1/subjects", self.payload(), format="json")

        response = self.client.post(
            "/api/v1/subjects", self.payload(name="Science Again"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The code has already been taken.", response.data["details"]["errors"]["code"][0]
        )

    def test_the_class_level_range_has_to_make_sense(self):
        response = self.client.post(
            "/api/v1/subjects",
            self.payload(min_class_level=8, max_class_level=3),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The max class level must be at or above the min class level.",
            response.data["details"]["errors"]["max_class_level"][0],
        )

    def test_a_class_level_outside_the_school_years_is_refused(self):
        too_high = self.client.post(
            "/api/v1/subjects", self.payload(max_class_level=13), format="json"
        )
        too_low = self.client.post(
            "/api/v1/subjects", self.payload(min_class_level=-1), format="json"
        )

        self.assertEqual(
            "The max class level field must not be greater than 12.",
            too_high.data["details"]["errors"]["max_class_level"][0],
        )
        self.assertEqual(
            "The min class level field must be at least 0.",
            too_low.data["details"]["errors"]["min_class_level"][0],
        )

    def test_raising_only_the_minimum_is_checked_against_the_stored_maximum(self):
        # Sending one bound alone would otherwise invert the range silently.
        created = self.client.post(
            "/api/v1/subjects", self.payload(min_class_level=1, max_class_level=5), format="json"
        )

        response = self.client.patch(
            f"/api/v1/subjects/{created.data['id']}", {"min_class_level": 9}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("max_class_level", response.data["details"]["errors"])

    def test_the_list_filters_by_department(self):
        other_department = factories.DepartmentFactory(school=self.school)
        mine = self.client.post("/api/v1/subjects", self.payload(), format="json")
        self.client.post(
            "/api/v1/subjects",
            self.payload(code="ART", department_id=other_department.id),
            format="json",
        )

        response = self.client.get(f"/api/v1/subjects?department_id={self.department.id}")

        self.assertEqual([mine.data["id"]], [row["id"] for row in response.data["data"]])

    def test_a_subject_can_be_deleted(self):
        created = self.client.post("/api/v1/subjects", self.payload(), format="json")

        response = self.client.delete(f"/api/v1/subjects/{created.data['id']}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(Subject.objects.filter(pk=created.data["id"]).exists())

    def test_a_teacher_may_read_but_not_write(self):
        created = self.client.post("/api/v1/subjects", self.payload(), format="json")
        teacher = self.as_user(self.teacher)

        self.assertEqual(200, teacher.get("/api/v1/subjects").status_code)
        self.assertEqual(
            403, teacher.post("/api/v1/subjects", self.payload(code="X"), format="json").status_code
        )
        self.assertEqual(403, teacher.delete(f"/api/v1/subjects/{created.data['id']}").status_code)


class SchoolIsolation(AcademicConfigTest):
    def setUp(self):
        super().setUp()
        self.mine = factories.DepartmentFactory(school=self.school, name="Mine")

        self.outside_school = factories.SchoolFactory()
        self.outsider = self.as_user(
            factories.UserFactory(school=self.outside_school, role=UserRole.SCHOOL_ADMIN)
        )

    def test_an_admin_cannot_read_another_schools_department(self):
        self.assertEqual(403, self.outsider.get(f"/api/v1/departments/{self.mine.id}").status_code)

    def test_an_admin_cannot_edit_another_schools_department(self):
        response = self.outsider.patch(
            f"/api/v1/departments/{self.mine.id}", {"name": "Stolen"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_an_admin_cannot_delete_another_schools_department(self):
        self.assertEqual(
            403, self.outsider.delete(f"/api/v1/departments/{self.mine.id}").status_code
        )
        self.assertTrue(Department.objects.filter(pk=self.mine.id).exists())

    def test_the_list_never_includes_another_schools_departments(self):
        response = self.outsider.get("/api/v1/departments?per_page=100")

        self.assertEqual(
            [], [row for row in response.data["data"] if row["school_id"] == self.school.id]
        )

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        response = self.outsider.get(
            f"/api/v1/departments?school_id={self.school.id}&per_page=100"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [], [row for row in response.data["data"] if row["school_id"] == self.school.id]
        )

    def test_a_new_department_lands_in_the_actors_school_whatever_was_asked_for(self):
        response = self.client.post(
            "/api/v1/departments",
            {"school_id": self.outside_school.id, "name": "Sneaky"},
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/departments").status_code)
        self.assertEqual(401, APIClient().get("/api/v1/subjects").status_code)
