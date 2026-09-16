"""Academic years, over HTTP.

Two rules carry the risk. Exactly one year is current per school, and setting
one has to clear the rest atomically - a school with two current years makes
every downstream screen pick an arbitrary one. And a year with classes under
it cannot be deleted, because deleting it would orphan them.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AcademicYear


class AcademicYearApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "name": "2026-27",
            "start_date": "2026-04-01",
            "end_date": "2027-03-31",
        }
        body.update(overrides)

        return body


class CreatingAYear(AcademicYearApiTest):
    def test_a_year_is_created_and_comes_back_whole(self):
        response = self.client.post("/api/v1/academic-years", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("2026-27", response.data["name"])
        self.assertEqual("2026-04-01", response.data["start_date"])
        self.assertEqual("2027-03-31", response.data["end_date"])
        self.assertEqual(self.school.name, response.data["school_name"])

    def test_is_current_is_false_and_never_null_when_omitted(self):
        # The column is NOT NULL with a default of false. Answering null for
        # it would break a client reading it as a boolean - on the backend's
        # own contract. Found originally by the contract suite, which omits
        # the field where the Flutter client always sends it.
        response = self.client.post("/api/v1/academic-years", self.payload(), format="json")

        self.assertIs(False, response.data["is_current"])

    def test_a_year_can_be_created_as_the_current_one(self):
        response = self.client.post(
            "/api/v1/academic-years", self.payload(is_current=True), format="json"
        )

        self.assertIs(True, response.data["is_current"])

    def test_the_end_date_must_be_after_the_start(self):
        response = self.client.post(
            "/api/v1/academic-years",
            self.payload(start_date="2027-03-31", end_date="2026-04-01"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The end date field must be a date after start date.",
            response.data["details"]["errors"]["end_date"][0],
        )

    def test_the_two_dates_cannot_be_the_same_day(self):
        response = self.client.post(
            "/api/v1/academic-years",
            self.payload(start_date="2026-04-01", end_date="2026-04-01"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_something_that_is_not_a_date_is_refused(self):
        response = self.client.post(
            "/api/v1/academic-years", self.payload(start_date="last April"), format="json"
        )

        self.assertEqual(
            "The start date field must be a valid date.",
            response.data["details"]["errors"]["start_date"][0],
        )

    def test_missing_fields_are_named(self):
        response = self.client.post("/api/v1/academic-years", {}, format="json")

        self.assertEqual(422, response.status_code, response.data)
        for field in ("name", "start_date", "end_date"):
            self.assertIn(field, response.data["details"]["errors"])

    def test_a_teacher_may_not_create_one(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        response = teacher.post("/api/v1/academic-years", self.payload(), format="json")

        self.assertEqual(403, response.status_code, response.data)


class OnlyOneYearIsCurrent(AcademicYearApiTest):
    def setUp(self):
        super().setUp()
        self.first = factories.AcademicYearFactory(
            school=self.school, name="2025-26", is_current=True
        )
        self.second = factories.AcademicYearFactory(
            school=self.school, name="2026-27", is_current=False
        )

    def current_names(self, school=None):
        return sorted(
            AcademicYear.objects.filter(
                school=school or self.school, is_current=True
            ).values_list("name", flat=True)
        )

    def test_setting_one_current_clears_the_others(self):
        response = self.client.patch(f"/api/v1/academic-years/{self.second.id}/set-current")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIs(True, response.data["is_current"])
        self.assertEqual(["2026-27"], self.current_names())

    def test_creating_a_current_year_clears_the_others(self):
        self.client.post(
            "/api/v1/academic-years",
            self.payload(name="2027-28", is_current=True),
            format="json",
        )

        self.assertEqual(["2027-28"], self.current_names())

    def test_another_schools_current_year_is_left_alone(self):
        # The clearing is per school. A group admin setting the current year
        # at one branch must not reset every other branch's calendar.
        elsewhere = factories.SchoolFactory()
        theirs = factories.AcademicYearFactory(
            school=elsewhere, name="Theirs", is_current=True
        )

        self.client.patch(f"/api/v1/academic-years/{self.second.id}/set-current")

        theirs.refresh_from_db()
        self.assertTrue(theirs.is_current)

    def test_editing_a_year_cannot_make_it_current(self):
        # It goes through the dedicated action, so the clearing of the others
        # cannot be skipped.
        self.client.patch(
            f"/api/v1/academic-years/{self.second.id}", {"is_current": True}, format="json"
        )

        self.second.refresh_from_db()
        self.assertFalse(self.second.is_current)
        self.assertEqual(["2025-26"], self.current_names())

    def test_a_teacher_may_not_set_the_current_year(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        response = teacher.patch(f"/api/v1/academic-years/{self.second.id}/set-current")

        self.assertEqual(403, response.status_code, response.data)


class EditingAYear(AcademicYearApiTest):
    def setUp(self):
        super().setUp()
        self.year = factories.AcademicYearFactory(school=self.school, name="2026-27")

    def test_a_field_can_be_changed_on_its_own(self):
        response = self.client.patch(
            f"/api/v1/academic-years/{self.year.id}", {"name": "2026-2027"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("2026-2027", response.data["name"])

    def test_moving_one_date_is_checked_against_the_stored_other(self):
        # Sending only an end date that lands before the stored start would
        # otherwise invert the year silently.
        response = self.client.patch(
            f"/api/v1/academic-years/{self.year.id}",
            {"end_date": "2020-01-01"},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The end date must be after the start date.",
            response.data["details"]["errors"]["end_date"][0],
        )

    def test_a_year_cannot_be_moved_to_another_school(self):
        elsewhere = factories.SchoolFactory()

        self.client.patch(
            f"/api/v1/academic-years/{self.year.id}",
            {"school_id": elsewhere.id},
            format="json",
        )

        self.year.refresh_from_db()
        self.assertEqual(self.school.id, self.year.school_id)


class DeletingAYear(AcademicYearApiTest):
    def setUp(self):
        super().setUp()
        self.year = factories.AcademicYearFactory(school=self.school)

    def test_an_empty_year_can_be_deleted(self):
        response = self.client.delete(f"/api/v1/academic-years/{self.year.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(AcademicYear.objects.filter(pk=self.year.id).exists())

    def test_a_year_with_classes_under_it_is_refused_with_the_reason(self):
        # Deleting it would orphan them, and "cannot delete" without a reason
        # sends somebody hunting.
        factories.SchoolClassFactory(academic_year=self.year, school=self.school)

        response = self.client.delete(f"/api/v1/academic-years/{self.year.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("HAS_DEPENDENT_RECORDS", response.data["code"])
        self.assertEqual(
            "This academic year still has classes set up under it. Remove them first.",
            response.data["message"],
        )
        self.assertTrue(AcademicYear.objects.filter(pk=self.year.id).exists())

    def test_a_teacher_may_not_delete_one(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        response = teacher.delete(f"/api/v1/academic-years/{self.year.id}")

        self.assertEqual(403, response.status_code, response.data)
        self.assertTrue(AcademicYear.objects.filter(pk=self.year.id).exists())


class SchoolIsolation(AcademicYearApiTest):
    def setUp(self):
        super().setUp()
        self.mine = factories.AcademicYearFactory(school=self.school, name="Mine")

        self.outside_school = factories.SchoolFactory()
        self.theirs = factories.AcademicYearFactory(school=self.outside_school, name="Theirs")
        self.outsider = self.as_user(
            factories.UserFactory(school=self.outside_school, role=UserRole.SCHOOL_ADMIN)
        )

    def test_an_admin_cannot_read_another_schools_year(self):
        self.assertEqual(403, self.outsider.get(f"/api/v1/academic-years/{self.mine.id}").status_code)

    def test_an_admin_cannot_edit_another_schools_year(self):
        response = self.outsider.patch(
            f"/api/v1/academic-years/{self.mine.id}", {"name": "Stolen"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_an_admin_cannot_delete_another_schools_year(self):
        response = self.outsider.delete(f"/api/v1/academic-years/{self.mine.id}")

        self.assertEqual(403, response.status_code, response.data)
        self.assertTrue(AcademicYear.objects.filter(pk=self.mine.id).exists())

    def test_the_list_never_includes_another_schools_years(self):
        response = self.outsider.get("/api/v1/academic-years?per_page=100")

        self.assertEqual(["Theirs"], [row["name"] for row in response.data["data"]])

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        response = self.outsider.get(
            f"/api/v1/academic-years?school_id={self.school.id}&per_page=100"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [], [row for row in response.data["data"] if row["school_id"] == self.school.id]
        )

    def test_a_new_year_lands_in_the_actors_school_whatever_was_asked_for(self):
        response = self.client.post(
            "/api/v1/academic-years",
            self.payload(school_id=self.outside_school.id, name="Sneaky"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_every_role_may_read_the_list(self):
        # An academic year is the filter almost every other screen hangs off,
        # so a teacher who cannot list them cannot use attendance either.
        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(200, client.get("/api/v1/academic-years").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/academic-years").status_code)
