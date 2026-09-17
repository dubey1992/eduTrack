"""Teachers and staff, over HTTP.

The rule this module exists to enforce: **the login and the employment record
are created together, or neither is.** A login with no profile is invisible to
Attendance and Leave; a profile with no login is somebody on a roster who
cannot sign in. Both halves are asserted, including that a failure leaves
neither behind.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, hashing, tokens
from school.enums import UserRole, UserStatus
from school.models import StaffProfile, User


class StaffApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.department = factories.DepartmentFactory(school=self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "first_name": "Rahul",
            "last_name": "Verma",
            "email": "rahul@example.invalid",
            "password": "AGoodPassword2026",
            "role": UserRole.TEACHER,
            "employee_id": "EMP-0001",
            "department_id": self.department.id,
            "designation": "Teacher",
            "joining_date": "2026-04-01",
        }
        body.update(overrides)

        return body


class AddingAnEmployee(StaffApiTest):
    def test_the_login_and_the_profile_are_created_together(self):
        response = self.client.post("/api/v1/staff", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)

        profile = StaffProfile.objects.get(pk=response.data["id"])
        user = User.objects.get(pk=profile.user_id)

        self.assertEqual("EMP-0001", profile.employee_id)
        self.assertEqual(UserRole.TEACHER, user.role)
        self.assertEqual(profile.school_id, user.school_id, "both agree about the school")

    def test_the_response_carries_both_halves(self):
        response = self.client.post("/api/v1/staff", self.payload(), format="json")

        self.assertEqual("Rahul Verma", response.data["name"])
        self.assertEqual("rahul@example.invalid", response.data["email"])
        self.assertEqual("TEACHER", response.data["role"])
        self.assertEqual("active", response.data["status"])
        self.assertEqual(self.department.name, response.data["department_name"])
        self.assertEqual(self.school.name, response.data["school_name"])
        self.assertEqual([], response.data["class_teacher_of"])

    def test_the_new_employee_can_sign_in(self):
        self.client.post("/api/v1/staff", self.payload(), format="json")

        response = APIClient().post(
            "/api/v1/auth/login",
            {"email": "rahul@example.invalid", "password": "AGoodPassword2026"},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_the_password_is_hashed_and_never_returned(self):
        response = self.client.post("/api/v1/staff", self.payload(), format="json")

        self.assertNotIn("password", response.data)

        user = User.objects.get(pk=response.data["user_id"])
        self.assertTrue(hashing.check("AGoodPassword2026", user.password))

    def test_a_failure_leaves_neither_half_behind(self):
        # The transaction is the point. A duplicate employee id is caught in
        # validation, but the same atomicity is what protects a database error
        # halfway through.
        factories.StaffProfileFactory(
            school=self.school,
            employee_id="EMP-0001",
            user=factories.UserFactory(school=self.school, role=UserRole.TEACHER),
        )

        response = self.client.post("/api/v1/staff", self.payload(), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The employee id has already been taken.",
            response.data["details"]["errors"]["employee_id"][0],
        )
        self.assertFalse(User.objects.filter(email="rahul@example.invalid").exists())

    def test_an_employee_id_may_repeat_in_another_school(self):
        self.client.post("/api/v1/staff", self.payload(), format="json")

        elsewhere = factories.SchoolFactory()
        other_admin = self.as_user(
            factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)
        )

        response = other_admin.post(
            "/api/v1/staff",
            self.payload(
                school_id=elsewhere.id,
                email="someone.else@example.invalid",
                department_id=factories.DepartmentFactory(school=elsewhere).id,
            ),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_an_email_is_unique_across_the_platform(self):
        # Unlike an employee id: an address is how somebody signs in, and two
        # accounts cannot share one.
        self.client.post("/api/v1/staff", self.payload(), format="json")

        response = self.client.post(
            "/api/v1/staff", self.payload(employee_id="EMP-0002"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("email", response.data["details"]["errors"])

    def test_this_screen_never_creates_an_admin(self):
        # Admin accounts go through /users, which derives the admin tier from
        # who is doing the creating rather than from a field.
        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.SUPER_ADMIN):
            with self.subTest(role=role):
                response = self.client.post(
                    "/api/v1/staff", self.payload(role=role), format="json"
                )

                self.assertEqual(422, response.status_code, role)
                self.assertIn("role", response.data["details"]["errors"])

    def test_every_operational_role_can_be_added(self):
        for index, role in enumerate(
            (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.ACCOUNTANT)
        ):
            with self.subTest(role=role):
                response = self.client.post(
                    "/api/v1/staff",
                    self.payload(
                        role=role,
                        email=f"person{index}@example.invalid",
                        employee_id=f"EMP-10{index}",
                    ),
                    format="json",
                )

                self.assertEqual(201, response.status_code, response.data)

    def test_a_department_from_another_school_is_refused(self):
        elsewhere = factories.DepartmentFactory(school=factories.SchoolFactory())

        response = self.client.post(
            "/api/v1/staff", self.payload(department_id=elsewhere.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("department_id", response.data["details"]["errors"])

    def test_an_employee_need_not_have_a_department(self):
        response = self.client.post(
            "/api/v1/staff", self.payload(department_id=None), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(response.data["department_id"])
        self.assertIsNone(response.data["department_name"])


class TheRoster(StaffApiTest):
    def setUp(self):
        super().setUp()
        self.teacher = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER, first_name="Priya", last_name="Nair"
        )
        self.profile = factories.StaffProfileFactory(
            school=self.school, user=self.teacher, employee_id="EMP-0100"
        )

    def test_the_placeholder_profile_of_an_admin_is_not_on_it(self):
        # A School Admin account gets a minimal profile so it can use Leave
        # and Staff Attendance. It is not an employment record and does not
        # belong on the Teachers & Staff roster.
        self.client.post(
            "/api/v1/users",
            {
                "first_name": "Another",
                "last_name": "Admin",
                "email": "another.admin@example.invalid",
                "password": "AGoodPassword2026",
                "role": UserRole.SCHOOL_ADMIN,
                "school_id": self.school.id,
            },
            format="json",
        )

        response = self.client.get("/api/v1/staff?per_page=100")

        self.assertEqual(
            ["EMP-0100"], [row["employee_id"] for row in response.data["data"]]
        )

    def test_it_filters_by_role_department_and_status(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        factories.StaffProfileFactory(
            school=self.school, user=hod, employee_id="EMP-0200", department=self.department
        )

        by_role = self.client.get(f"/api/v1/staff?role={UserRole.HOD}&per_page=100")
        by_department = self.client.get(
            f"/api/v1/staff?department_id={self.department.id}&per_page=100"
        )

        self.assertEqual(["EMP-0200"], [r["employee_id"] for r in by_role.data["data"]])
        self.assertEqual(["EMP-0200"], [r["employee_id"] for r in by_department.data["data"]])

    def test_the_search_ignores_case_and_looks_at_the_email_too(self):
        for term in ("priya", "PRIYA", "nair", self.teacher.email[:6].upper()):
            with self.subTest(term=term):
                response = self.client.get(f"/api/v1/staff?search={term}&per_page=100")

                self.assertIn(
                    "EMP-0100", [r["employee_id"] for r in response.data["data"]], term
                )

    def test_it_shows_the_classes_somebody_is_class_teacher_of(self):
        year = factories.AcademicYearFactory(school=self.school)
        school_class = factories.SchoolClassFactory(
            academic_year=year, school=self.school, name="Grade 8"
        )
        section = factories.ClassSectionFactory(school_class=school_class, name="A")
        section.class_teacher_id = self.teacher.id
        section.save()

        response = self.client.get(f"/api/v1/staff/{self.profile.id}")

        self.assertEqual(["Grade 8 A"], response.data["class_teacher_of"])


class EditingAnEmployee(StaffApiTest):
    def setUp(self):
        super().setUp()
        self.profile = factories.StaffProfileFactory(
            school=self.school,
            user=factories.UserFactory(school=self.school, role=UserRole.TEACHER),
            employee_id="EMP-0100",
        )

    def test_the_employment_record_can_be_changed(self):
        response = self.client.patch(
            f"/api/v1/staff/{self.profile.id}",
            {"designation": "Senior Teacher", "department_id": self.department.id},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Senior Teacher", response.data["designation"])
        self.assertEqual(self.department.name, response.data["department_name"])

    def test_the_login_behind_it_is_not_edited_here(self):
        # Name, email and role go through /users, so the admin hierarchy is
        # enforced in one place rather than two.
        before = self.profile.user.first_name

        self.client.patch(
            f"/api/v1/staff/{self.profile.id}",
            {"first_name": "Renamed", "role": UserRole.HOD},
            format="json",
        )

        self.profile.user.refresh_from_db()
        self.assertEqual(before, self.profile.user.first_name)
        self.assertEqual(UserRole.TEACHER, self.profile.user.role)

    def test_taking_another_employees_id_is_refused(self):
        factories.StaffProfileFactory(
            school=self.school,
            user=factories.UserFactory(school=self.school, role=UserRole.TEACHER),
            employee_id="EMP-0200",
        )

        response = self.client.patch(
            f"/api/v1/staff/{self.profile.id}", {"employee_id": "EMP-0200"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("employee_id", response.data["details"]["errors"])

    def test_keeping_its_own_id_is_not_a_duplicate(self):
        response = self.client.patch(
            f"/api/v1/staff/{self.profile.id}",
            {"employee_id": "EMP-0100", "designation": "Head of Year"},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)


class WhoMaySeeTheRoster(StaffApiTest):
    """Admins only, even to read - a teacher does not browse their colleagues'
    joining dates and addresses."""

    def setUp(self):
        super().setUp()
        self.profile = factories.StaffProfileFactory(
            school=self.school,
            user=factories.UserFactory(school=self.school, role=UserRole.TEACHER),
            employee_id="EMP-0100",
        )

    def test_operational_roles_are_refused(self):
        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, client.get("/api/v1/staff").status_code)
                self.assertEqual(403, client.get(f"/api/v1/staff/{self.profile.id}").status_code)
                self.assertEqual(
                    403, client.post("/api/v1/staff", self.payload(), format="json").status_code
                )

    def test_an_admin_from_another_school_reaches_nothing(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(403, outsider.get(f"/api/v1/staff/{self.profile.id}").status_code)
        self.assertEqual(
            403,
            outsider.patch(
                f"/api/v1/staff/{self.profile.id}", {"designation": "Stolen"}, format="json"
            ).status_code,
        )

    def test_the_list_never_includes_another_schools_employees(self):
        outsider_school = factories.SchoolFactory()
        outsider = self.as_user(
            factories.UserFactory(school=outsider_school, role=UserRole.SCHOOL_ADMIN)
        )

        response = outsider.get("/api/v1/staff?per_page=100")

        self.assertEqual(
            [], [row for row in response.data["data"] if row["school_id"] == self.school.id]
        )

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        response = outsider.get(f"/api/v1/staff?school_id={self.school.id}&per_page=100")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [], [row for row in response.data["data"] if row["school_id"] == self.school.id]
        )

    def test_a_new_employee_lands_in_the_actors_school_whatever_was_asked_for(self):
        elsewhere = factories.SchoolFactory()

        response = self.client.post(
            "/api/v1/staff",
            self.payload(school_id=elsewhere.id, department_id=None),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/staff").status_code)


class ADeactivatedEmployee(StaffApiTest):
    def test_they_stay_on_the_roster_and_stop_being_able_to_sign_in(self):
        # There is no delete. Somebody who has left keeps their attendance,
        # their leave and their name on last year's timetable.
        created = self.client.post("/api/v1/staff", self.payload(), format="json").data

        self.client.patch(f"/api/v1/users/{created['user_id']}/deactivate")

        listed = self.client.get("/api/v1/staff?status=inactive&per_page=100")

        self.assertEqual([created["id"]], [row["id"] for row in listed.data["data"]])
        self.assertEqual(
            UserStatus.INACTIVE, User.objects.get(pk=created["user_id"]).status
        )
