"""Schools, over HTTP.

Two things carry most of the risk here. Onboarding is a platform action, so
every write has to be refused to everyone but a Super Admin. And the parent
rule keeps a group exactly one level deep - the cheapest thing to get right
and the dearest to fix, because unpicking a three-deep tree in production
means deciding what somebody's records belonged to all along.
"""

from django.core import mail
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, hashing, queue, tokens
from school.enums import UserRole
from school.models import EarlyAccessRequest, School, StaffProfile, User


def a_payload(**overrides) -> dict:
    body = {
        "name": "Greenfield Academy",
        "email": "head@greenfield.invalid",
        "phone": "+234 8000000000",
        "address": "1 Test Road",
        "city": "Lagos",
        "state": "Lagos",
        "country": "Nigeria",
        "postal_code": "100001",
        "currency_code": "NGN",
        "timezone": "Africa/Lagos",
    }
    body.update(overrides)

    return body


class SchoolApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))
        self.school = factories.SchoolFactory(name="Standalone High")

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client


class Onboarding(SchoolApiTest):
    def test_a_super_admin_creates_a_school(self):
        response = self.root.post("/api/v1/schools", a_payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Greenfield Academy", response.data["name"])
        self.assertEqual("active", response.data["status"])
        self.assertIsNone(response.data["parent_school_id"])
        self.assertEqual("NGN", response.data["currency_code"])

    def test_a_coordinate_survives_to_the_seventh_decimal(self):
        # Money and coordinates are the two places a float would be wrong, and
        # the wrongness would not show up until somebody looked at a map.
        response = self.root.post(
            "/api/v1/schools",
            a_payload(latitude="28.6139123", longitude="77.2090456"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("28.6139123", response.data["latitude"])
        self.assertEqual("77.2090456", response.data["longitude"])

    def test_half_a_coordinate_is_refused(self):
        # Half a coordinate points nowhere.
        without_latitude = self.root.post(
            "/api/v1/schools", a_payload(longitude="77.2090456"), format="json"
        )
        without_longitude = self.root.post(
            "/api/v1/schools", a_payload(latitude="28.6139123"), format="json"
        )

        self.assertEqual(422, without_latitude.status_code, without_latitude.data)
        self.assertEqual(
            "Enter a latitude as well, or clear the longitude.",
            without_latitude.data["details"]["errors"]["latitude"][0],
        )
        self.assertEqual(
            "Enter a longitude as well, or clear the latitude.",
            without_longitude.data["details"]["errors"]["longitude"][0],
        )

    def test_a_coordinate_off_the_planet_is_refused(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(latitude="91", longitude="0"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The latitude field must be between -90 and 90.",
            response.data["details"]["errors"]["latitude"][0],
        )

    def test_a_duplicate_email_is_refused(self):
        self.root.post("/api/v1/schools", a_payload(), format="json")

        response = self.root.post("/api/v1/schools", a_payload(name="Another"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The email has already been taken.",
            response.data["details"]["errors"]["email"][0],
        )

    def test_a_currency_must_be_three_upper_case_letters(self):
        # Fixed at creation and copied onto every payment, so a guess here
        # would put a guess in a ledger.
        response = self.root.post("/api/v1/schools", a_payload(currency_code="ngn"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The currency code field format is invalid.",
            response.data["details"]["errors"]["currency_code"][0],
        )

    def test_a_timezone_must_be_one_that_exists(self):
        # This decides what "today" means for everything the school records.
        response = self.root.post(
            "/api/v1/schools", a_payload(timezone="Mars/Olympus"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The timezone field must be a valid timezone.",
            response.data["details"]["errors"]["timezone"][0],
        )

    def test_a_phone_must_carry_a_dial_code(self):
        response = self.root.post("/api/v1/schools", a_payload(phone="8000000000"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("phone", response.data["details"]["errors"])

    def test_a_logo_must_be_a_url(self):
        response = self.root.post("/api/v1/schools", a_payload(logo_url="nonsense"), format="json")

        self.assertEqual(
            "The logo url field must be a valid URL.",
            response.data["details"]["errors"]["logo_url"][0],
        )

    def test_missing_fields_are_named(self):
        response = self.root.post("/api/v1/schools", {}, format="json")

        self.assertEqual(422, response.status_code, response.data)
        errors = response.data["details"]["errors"]

        for field in ("name", "email", "phone", "city", "currency_code", "timezone"):
            self.assertIn(field, errors)

        self.assertEqual("The name field is required.", errors["name"][0])


class OnboardingFromASignup(SchoolApiTest):
    def test_creating_a_school_closes_the_signup_request(self):
        # "Converted" has to be true rather than remembered: a list that says
        # converted with no school behind it is worse than one saying nothing.
        from django.utils.timezone import now

        enquiry = EarlyAccessRequest.objects.create(
            school_name="Greenfield Academy",
            contact_name="Nneka Okafor",
            email="head@greenfield.invalid",
            phone="+234 8000000000",
            city="Lagos",
            country="Nigeria",
            status="new",
            created_at=now(),
            updated_at=now(),
        )

        response = self.root.post(
            "/api/v1/schools", a_payload(early_access_request_id=enquiry.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)

        enquiry.refresh_from_db()
        self.assertEqual("converted", enquiry.status)
        self.assertEqual(response.data["id"], enquiry.converted_school_id)
        self.assertIsNotNone(enquiry.reviewed_at)

    def test_a_signup_request_that_does_not_exist_is_refused(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(early_access_request_id=999999), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("early_access_request_id", response.data["details"]["errors"])
        self.assertFalse(School.objects.filter(name="Greenfield Academy").exists())


class GroupsAreOneLevelDeep(SchoolApiTest):
    def setUp(self):
        super().setUp()
        self.group = factories.SchoolFactory(name="St Mary's Group")
        self.north = factories.SchoolFactory(name="St Mary's North", parent_school=self.group)

    def test_a_branch_can_be_created_under_a_parent(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(parent_school_id=self.group.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.group.id, response.data["parent_school_id"])

    def test_a_branch_of_a_branch_is_refused(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(parent_school_id=self.north.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            '"St Mary\'s North" is itself a branch. A group is one level deep: pick its parent instead.',
            response.data["details"]["errors"]["parent_school_id"][0],
        )

    def test_a_school_cannot_become_a_branch_of_itself(self):
        response = self.root.patch(
            f"/api/v1/schools/{self.group.id}",
            {"parent_school_id": self.group.id},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "A school cannot be a branch of itself.",
            response.data["details"]["errors"]["parent_school_id"][0],
        )

    def test_a_parent_cannot_become_a_branch_while_it_has_branches(self):
        response = self.root.patch(
            f"/api/v1/schools/{self.group.id}",
            {"parent_school_id": self.school.id},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            '"St Mary\'s Group" has branches of its own, so it cannot become a branch of another school.',
            response.data["details"]["errors"]["parent_school_id"][0],
        )

    def test_a_parent_that_does_not_exist_is_refused(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(parent_school_id=999999), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("parent_school_id", response.data["details"]["errors"])


class ReadingTheList(SchoolApiTest):
    def setUp(self):
        super().setUp()
        self.group = factories.SchoolFactory(name="St Mary's Group")
        self.north = factories.SchoolFactory(name="St Mary's North", parent_school=self.group)
        self.south = factories.SchoolFactory(name="St Mary's South", parent_school=self.group)

    def test_a_super_admin_sees_every_school(self):
        response = self.root.get("/api/v1/schools")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(4, response.data["meta"]["total"])

    def test_the_list_carries_the_branch_count_and_the_parent_name(self):
        response = self.root.get("/api/v1/schools?per_page=50")

        by_id = {row["id"]: row for row in response.data["data"]}

        self.assertEqual(2, by_id[self.group.id]["branch_count"])
        self.assertEqual(0, by_id[self.school.id]["branch_count"])
        self.assertEqual("St Mary's Group", by_id[self.north.id]["parent_school_name"])
        self.assertIsNone(by_id[self.school.id]["parent_school_name"])

    def test_a_branch_admin_sees_their_group_and_nothing_else(self):
        admin = self.as_user(factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN))

        response = admin.get("/api/v1/schools?per_page=50")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            {self.group.id, self.north.id, self.south.id},
            {row["id"] for row in response.data["data"]},
        )

    def test_an_admin_of_a_standalone_school_has_nothing_to_pick_from(self):
        # Refused rather than shown a list of one: the branch picker only
        # exists for an admin who actually has branches.
        admin = self.as_user(factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN))

        self.assertEqual(403, admin.get("/api/v1/schools").status_code)

    def test_a_teacher_may_not_list_schools(self):
        teacher = self.as_user(factories.UserFactory(school=self.north, role=UserRole.TEACHER))

        self.assertEqual(403, teacher.get("/api/v1/schools").status_code)


class ReadingOne(SchoolApiTest):
    def setUp(self):
        super().setUp()
        self.group = factories.SchoolFactory(name="Group")
        self.north = factories.SchoolFactory(name="North", parent_school=self.group)
        self.outsider = factories.SchoolFactory(name="Unrelated High")

    def test_a_super_admin_reads_any_school(self):
        response = self.root.get(f"/api/v1/schools/{self.north.id}")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Group", response.data["parent_school_name"])

    def test_a_branch_admin_reads_their_sister_and_their_parent(self):
        admin = self.as_user(factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN))

        self.assertEqual(200, admin.get(f"/api/v1/schools/{self.group.id}").status_code)
        self.assertEqual(200, admin.get(f"/api/v1/schools/{self.north.id}").status_code)

    def test_a_branch_admin_cannot_read_a_school_outside_the_group(self):
        admin = self.as_user(factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN))

        self.assertEqual(403, admin.get(f"/api/v1/schools/{self.outsider.id}").status_code)

    def test_a_missing_school_is_404_in_the_standard_envelope(self):
        response = self.root.get("/api/v1/schools/99999999")

        self.assertEqual(404, response.status_code, response.data)
        self.assertEqual("NOT_FOUND", response.data["code"])


class EditingAndStatus(SchoolApiTest):
    def test_a_super_admin_edits_a_school(self):
        response = self.root.patch(
            f"/api/v1/schools/{self.school.id}", {"name": "Renamed High"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Renamed High", response.data["name"])

    def test_the_fields_not_sent_are_left_alone(self):
        before = self.school.city

        self.root.patch(f"/api/v1/schools/{self.school.id}", {"name": "Renamed"}, format="json")

        self.school.refresh_from_db()
        self.assertEqual(before, self.school.city)

    def test_keeping_your_own_email_is_not_a_duplicate(self):
        response = self.root.patch(
            f"/api/v1/schools/{self.school.id}",
            {"email": self.school.email, "name": "Renamed"},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_a_school_can_be_deactivated_and_reinstated(self):
        deactivated = self.root.patch(f"/api/v1/schools/{self.school.id}/deactivate")
        self.assertEqual(200, deactivated.status_code, deactivated.data)
        self.assertEqual("inactive", deactivated.data["status"])

        activated = self.root.patch(f"/api/v1/schools/{self.school.id}/activate")
        self.assertEqual("active", activated.data["status"])

    def test_deactivating_keeps_the_record(self):
        self.root.patch(f"/api/v1/schools/{self.school.id}/deactivate")

        self.assertTrue(School.objects.filter(pk=self.school.id).exists())


class OnlyThePlatformManagesSchools(SchoolApiTest):
    """Onboarding a school and recording payments are platform actions. A
    school admin runs their school; they do not run the platform."""

    def setUp(self):
        super().setUp()
        self.group = factories.SchoolFactory(name="Group")
        self.north = factories.SchoolFactory(name="North", parent_school=self.group)

    def clients(self):
        return {
            "standalone admin": factories.UserFactory(
                school=self.school, role=UserRole.SCHOOL_ADMIN
            ),
            "group admin": factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN),
            "branch admin": factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN),
            "teacher": factories.UserFactory(school=self.north, role=UserRole.TEACHER),
        }

    def test_nobody_but_a_super_admin_creates_a_school(self):
        for who, user in self.clients().items():
            with self.subTest(who=who):
                response = self.as_user(user).post("/api/v1/schools", a_payload(), format="json")

                self.assertEqual(403, response.status_code, who)

    def test_nobody_but_a_super_admin_edits_a_school(self):
        for who, user in self.clients().items():
            with self.subTest(who=who):
                response = self.as_user(user).patch(
                    f"/api/v1/schools/{self.north.id}", {"name": "Stolen"}, format="json"
                )

                self.assertEqual(403, response.status_code, who)

        self.north.refresh_from_db()
        self.assertEqual("North", self.north.name)

    def test_nobody_but_a_super_admin_deactivates_a_school(self):
        for who, user in self.clients().items():
            with self.subTest(who=who):
                response = self.as_user(user).patch(f"/api/v1/schools/{self.north.id}/deactivate")

                self.assertEqual(403, response.status_code, who)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/schools").status_code)


class TheFirstSchoolAdmin(SchoolApiTest):
    """Add School can create the school's first School Admin in the same
    save, so a new school is never left with nobody who can sign in."""

    def with_admin(self, **overrides) -> dict:
        return a_payload(admin_first_name="Ada", admin_last_name="Obi", **overrides)

    def test_the_admin_is_created_with_the_school_and_emailed_a_link(self):
        response = self.root.post("/api/v1/schools", self.with_admin(), format="json")
        queue.work()

        self.assertEqual(201, response.status_code, response.data)
        admin = User.objects.get(email="head@greenfield.invalid")

        self.assertEqual((UserRole.SCHOOL_ADMIN, response.data["id"]), (admin.role, admin.school_id))
        self.assertFalse(admin.is_sub_admin, "created by the platform, so the head of the school")
        self.assertTrue(StaffProfile.objects.filter(user_id=admin.id).exists())
        self.assertEqual(1, len(mail.outbox))
        self.assertEqual(["head@greenfield.invalid"], mail.outbox[0].to)
        self.assertIn("Set your password", mail.outbox[0].subject)

    def test_the_admin_may_have_an_email_of_their_own(self):
        response = self.root.post(
            "/api/v1/schools", self.with_admin(admin_email="Ada.Obi@Greenfield.invalid"), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(User.objects.filter(email="ada.obi@greenfield.invalid").exists())
        self.assertFalse(User.objects.filter(email="head@greenfield.invalid").exists())

    def test_a_password_given_is_used_and_no_email_is_sent(self):
        response = self.root.post(
            "/api/v1/schools", self.with_admin(admin_password="AGoodPassword2026"), format="json"
        )
        queue.work()

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(hashing.check("AGoodPassword2026", User.objects.get(email="head@greenfield.invalid").password))
        self.assertEqual([], mail.outbox)

    def test_without_admin_fields_only_the_school_is_created(self):
        response = self.root.post("/api/v1/schools", a_payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertFalse(User.objects.filter(email="head@greenfield.invalid").exists())

    def test_the_admin_needs_both_names(self):
        response = self.root.post("/api/v1/schools", a_payload(admin_email="ada@greenfield.invalid"), format="json")

        self.assertEqual(422, response.status_code)
        errors = response.data["details"]["errors"]
        self.assertIn("admin_first_name", errors)
        self.assertIn("admin_last_name", errors)
        self.assertFalse(School.objects.filter(name="Greenfield Academy").exists(), "neither is created")

    def test_an_email_already_signing_in_is_refused_and_nothing_is_created(self):
        factories.UserFactory(email="head@greenfield.invalid", school=self.school, role=UserRole.TEACHER)

        response = self.root.post("/api/v1/schools", self.with_admin(), format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("already signs in", response.data["details"]["errors"]["admin_email"][0])
        self.assertFalse(School.objects.filter(name="Greenfield Academy").exists())

    def test_a_malformed_admin_email_is_refused(self):
        response = self.root.post("/api/v1/schools", self.with_admin(admin_email="not-an-email"), format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("admin_email", response.data["details"]["errors"])

    def test_a_weak_admin_password_is_refused(self):
        response = self.root.post("/api/v1/schools", self.with_admin(admin_password="short1"), format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("admin_password", response.data["details"]["errors"])

    def test_school_and_admin_errors_are_reported_together(self):
        factories.SchoolFactory(email="head@greenfield.invalid")

        response = self.root.post("/api/v1/schools", a_payload(admin_first_name="Ada"), format="json")

        self.assertEqual(422, response.status_code)
        errors = response.data["details"]["errors"]
        self.assertIn("email", errors)
        self.assertIn("admin_last_name", errors)

    def test_nobody_but_a_super_admin_creates_one(self):
        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.TEACHER):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))
            response = client.post("/api/v1/schools", self.with_admin(), format="json")

            self.assertEqual(403, response.status_code, role)

        self.assertFalse(User.objects.filter(email="head@greenfield.invalid").exists())
