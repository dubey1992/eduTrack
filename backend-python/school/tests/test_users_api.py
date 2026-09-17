"""Admin accounts, over HTTP.

The hierarchy is the part worth testing hardest, because it is the one rule
here that is not simply "same school or not". `is_sub_admin` splits one role
into two tiers: the head of a school manages the Sub Admins beneath them, a
Sub Admin manages no admin account at all, and nobody manages another head.
Every arm of that has an ALLOW and a DENY below.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, hashing, tokens
from school.enums import UserRole, UserStatus
from school.models import PersonalAccessToken, StaffProfile, User


class UserApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.head = factories.UserFactory(
            school=self.school, role=UserRole.SCHOOL_ADMIN, is_sub_admin=False
        )

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "first_name": "Priya",
            "last_name": "Nair",
            "email": "priya@example.invalid",
            "password": "AGoodPassword2026",
            "role": UserRole.SCHOOL_ADMIN,
            "school_id": self.school.id,
        }
        body.update(overrides)

        return body


class Onboarding(UserApiTest):
    def test_a_super_admin_creates_a_school_admin(self):
        response = self.as_user(self.root).post("/api/v1/users", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("SCHOOL_ADMIN", response.data["role"])
        self.assertEqual(self.school.id, response.data["school_id"])
        self.assertFalse(response.data["is_sub_admin"], "created by the platform, so a head")

    def test_an_admin_creating_an_admin_makes_a_sub_admin(self):
        # The tier comes from who is creating, never from the request.
        response = self.as_user(self.head).post(
            "/api/v1/users", self.payload(school_id=None), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(response.data["is_sub_admin"])

    def test_the_password_is_stored_hashed_and_never_returned(self):
        response = self.as_user(self.root).post("/api/v1/users", self.payload(), format="json")

        self.assertNotIn("password", response.data)

        created = User.objects.get(pk=response.data["id"])
        self.assertNotEqual("AGoodPassword2026", created.password)
        self.assertTrue(hashing.check("AGoodPassword2026", created.password))

    def test_a_new_admin_can_sign_in_with_the_password_that_was_set(self):
        self.as_user(self.root).post("/api/v1/users", self.payload(), format="json")

        response = APIClient().post(
            "/api/v1/auth/login",
            {"email": "priya@example.invalid", "password": "AGoodPassword2026"},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_an_admin_account_gets_a_minimal_staff_profile(self):
        # Without one they cannot use Staff Leave or Staff Attendance, which
        # both key off an employment record.
        response = self.as_user(self.root).post("/api/v1/users", self.payload(), format="json")

        profile = StaffProfile.objects.get(user_id=response.data["id"])

        self.assertEqual(f"ADMIN-{response.data['id']}", profile.employee_id)
        self.assertEqual("School Admin", profile.designation)
        self.assertIsNone(profile.department_id)

    def test_a_sub_admins_profile_says_so(self):
        response = self.as_user(self.head).post(
            "/api/v1/users", self.payload(school_id=None), format="json"
        )

        self.assertEqual(
            "Sub Admin", StaffProfile.objects.get(user_id=response.data["id"]).designation
        )

    def test_the_email_is_stored_lowercase(self):
        # The column is lowercase, so a lookup in the user's own
        # capitalisation would report a good password as wrong.
        response = self.as_user(self.root).post(
            "/api/v1/users", self.payload(email="Priya@Example.Invalid"), format="json"
        )

        self.assertEqual("priya@example.invalid", response.data["email"])

    def test_a_duplicate_email_is_refused_whatever_its_case(self):
        self.as_user(self.root).post("/api/v1/users", self.payload(), format="json")

        response = self.as_user(self.root).post(
            "/api/v1/users", self.payload(email="PRIYA@example.invalid"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The email has already been taken.", response.data["details"]["errors"]["email"][0]
        )

    def test_a_short_password_is_refused(self):
        response = self.as_user(self.root).post(
            "/api/v1/users", self.payload(password="short"), format="json"
        )

        self.assertEqual(
            "The password field must be at least 8 characters.",
            response.data["details"]["errors"]["password"][0],
        )


class WhichRolesThisScreenCreates(UserApiTest):
    def test_a_super_admin_may_create_a_group_admin(self):
        group = factories.SchoolFactory()
        factories.SchoolFactory(parent_school=group)

        response = self.as_user(self.root).post(
            "/api/v1/users",
            self.payload(role=UserRole.GROUP_ADMIN, school_id=group.id),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_a_group_admin_must_sit_at_the_parent_not_a_branch(self):
        # Attaching one to a branch would be claiming the branch is the group.
        group = factories.SchoolFactory()
        branch = factories.SchoolFactory(name="North", parent_school=group)

        response = self.as_user(self.root).post(
            "/api/v1/users",
            self.payload(role=UserRole.GROUP_ADMIN, school_id=branch.id),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            '"North" is a branch. A Group Admin belongs to the school the branches sit under.',
            response.data["details"]["errors"]["school_id"][0],
        )

    def test_an_admin_may_not_create_a_group_admin(self):
        response = self.as_user(self.head).post(
            "/api/v1/users",
            self.payload(role=UserRole.GROUP_ADMIN, school_id=None),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("role", response.data["details"]["errors"])

    def test_operational_roles_are_not_created_here(self):
        # They go through Teachers & Staff, which creates the employment
        # record alongside the login. One made here would be invisible to
        # Attendance and Leave.
        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                response = self.as_user(self.root).post(
                    "/api/v1/users", self.payload(role=role), format="json"
                )

                self.assertEqual(422, response.status_code, role)
                self.assertIn("role", response.data["details"]["errors"])

    def test_a_role_that_does_not_exist_is_refused(self):
        response = self.as_user(self.root).post(
            "/api/v1/users", self.payload(role="EMPEROR"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)


class TheAdminHierarchy(UserApiTest):
    def setUp(self):
        super().setUp()
        self.sub = factories.UserFactory(
            school=self.school, role=UserRole.SCHOOL_ADMIN, is_sub_admin=True
        )
        self.other_head = factories.UserFactory(
            school=self.school, role=UserRole.SCHOOL_ADMIN, is_sub_admin=False
        )
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

    def test_a_head_manages_a_sub_admin(self):
        response = self.as_user(self.head).patch(
            f"/api/v1/users/{self.sub.id}", {"first_name": "Renamed"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_a_head_does_not_manage_another_head(self):
        response = self.as_user(self.head).patch(
            f"/api/v1/users/{self.other_head.id}", {"first_name": "Renamed"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_a_sub_admin_manages_no_admin_account_at_all(self):
        for target, who in ((self.head, "a head"), (self.other_head, "another head")):
            with self.subTest(who=who):
                response = self.as_user(self.sub).patch(
                    f"/api/v1/users/{target.id}", {"first_name": "Renamed"}, format="json"
                )

                self.assertEqual(403, response.status_code, who)

    def test_a_sub_admin_does_not_manage_another_sub_admin(self):
        another_sub = factories.UserFactory(
            school=self.school, role=UserRole.SCHOOL_ADMIN, is_sub_admin=True
        )

        response = self.as_user(self.sub).patch(
            f"/api/v1/users/{another_sub.id}", {"first_name": "Renamed"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_any_admin_manages_a_non_admin_in_their_school(self):
        for actor, who in ((self.head, "head"), (self.sub, "sub admin")):
            with self.subTest(who=who):
                response = self.as_user(actor).patch(
                    f"/api/v1/users/{self.teacher.id}", {"first_name": "Renamed"}, format="json"
                )

                self.assertEqual(200, response.status_code, who)

    def test_a_sub_admin_may_not_create_an_account(self):
        response = self.as_user(self.sub).post(
            "/api/v1/users", self.payload(school_id=None), format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_a_school_admin_may_only_assign_operational_roles(self):
        response = self.as_user(self.head).patch(
            f"/api/v1/users/{self.teacher.id}", {"role": UserRole.SCHOOL_ADMIN}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "A school admin can only assign the HOD, Teacher, Staff, Transport Manager or Accountant role.",
            response.data["details"]["errors"]["role"][0],
        )

    def test_a_super_admin_may_assign_any_role(self):
        response = self.as_user(self.root).patch(
            f"/api/v1/users/{self.teacher.id}", {"role": UserRole.HOD}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("HOD", response.data["role"])


class DeactivatingAnAccount(UserApiTest):
    def setUp(self):
        super().setUp()
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

    def test_deactivating_signs_them_out_everywhere(self):
        # Without this the account is switched off but whatever browser it was
        # open in keeps working.
        their_client = self.as_user(self.teacher)
        self.assertEqual(200, their_client.get("/api/v1/me").status_code)

        response = self.as_user(self.head).patch(f"/api/v1/users/{self.teacher.id}/deactivate")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("inactive", response.data["status"])
        self.assertEqual(401, their_client.get("/api/v1/me").status_code)
        self.assertEqual(
            0, PersonalAccessToken.objects.filter(tokenable_id=self.teacher.id).count()
        )

    def test_an_account_can_be_reinstated(self):
        self.as_user(self.head).patch(f"/api/v1/users/{self.teacher.id}/deactivate")

        response = self.as_user(self.head).patch(f"/api/v1/users/{self.teacher.id}/activate")

        self.assertEqual("active", response.data["status"])

    def test_nobody_deactivates_their_own_account(self):
        # The one mistake that locks you out of fixing it.
        for actor, who in ((self.root, "super admin"), (self.head, "school admin")):
            with self.subTest(who=who):
                response = self.as_user(actor).patch(f"/api/v1/users/{actor.id}/deactivate")

                self.assertEqual(403, response.status_code, who)

                actor.refresh_from_db()
                self.assertEqual(UserStatus.ACTIVE, actor.status)


class SchoolIsolation(UserApiTest):
    def setUp(self):
        super().setUp()
        self.outside_school = factories.SchoolFactory()
        self.outsider = factories.UserFactory(
            school=self.outside_school, role=UserRole.TEACHER
        )

    def test_an_admin_cannot_read_a_user_from_another_school(self):
        response = self.as_user(self.head).get(f"/api/v1/users/{self.outsider.id}")

        self.assertEqual(403, response.status_code, response.data)

    def test_an_admin_cannot_edit_a_user_from_another_school(self):
        response = self.as_user(self.head).patch(
            f"/api/v1/users/{self.outsider.id}", {"first_name": "Stolen"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)
        self.outsider.refresh_from_db()
        self.assertNotEqual("Stolen", self.outsider.first_name)

    def test_the_list_never_includes_another_schools_users(self):
        response = self.as_user(self.head).get("/api/v1/users?per_page=100")

        self.assertEqual(
            [],
            [row for row in response.data["data"] if row["school_id"] == self.outside_school.id],
        )

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        response = self.as_user(self.head).get(
            f"/api/v1/users?school_id={self.outside_school.id}&per_page=100"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [],
            [row for row in response.data["data"] if row["school_id"] == self.outside_school.id],
        )

    def test_a_new_account_lands_in_the_actors_school_whatever_was_asked_for(self):
        response = self.as_user(self.head).post(
            "/api/v1/users", self.payload(school_id=self.outside_school.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_a_teacher_may_not_list_users(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.as_user(teacher).get("/api/v1/users").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/users").status_code)


class TheList(UserApiTest):
    def test_it_filters_by_role_and_by_several_roles(self):
        factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.UserFactory(school=self.school, role=UserRole.HOD)
        factories.UserFactory(school=self.school, role=UserRole.STAFF)

        client = self.as_user(self.root)

        one = client.get(f"/api/v1/users?role={UserRole.TEACHER}&per_page=100")
        several = client.get("/api/v1/users?roles=TEACHER,HOD&per_page=100")

        self.assertEqual(["TEACHER"], sorted({row["role"] for row in one.data["data"]}))
        self.assertEqual(["HOD", "TEACHER"], sorted({row["role"] for row in several.data["data"]}))

    def test_it_filters_by_status(self):
        gone = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER, status=UserStatus.INACTIVE
        )

        response = self.as_user(self.root).get("/api/v1/users?status=inactive&per_page=100")

        self.assertEqual([gone.id], [row["id"] for row in response.data["data"]])

    def test_manages_branches_is_only_computed_for_the_reader(self):
        # It costs a query, and a paginated list would pay it per row for
        # something no row needs.
        response = self.as_user(self.root).get("/api/v1/users?per_page=100")

        mine = [row for row in response.data["data"] if row["id"] == self.root.id]
        others = [row for row in response.data["data"] if row["id"] != self.root.id]

        self.assertIn("manages_branches", mine[0])
        for row in others:
            self.assertNotIn("manages_branches", row)
