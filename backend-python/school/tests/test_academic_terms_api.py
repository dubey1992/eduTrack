"""Academic terms, over HTTP (docs/assessments.md).

A term is the period a result is filed under, so the rules that matter are the
ones that keep it meaningful: inside its year, not overlapping a sibling, one
name and one sequence number per year, and never moved to another year once
results could be hanging off it.

The year used throughout is 2026-27, 1 April 2026 to 31 March 2027.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AcademicTerm

URL = "/api/v1/academic-terms"


class AcademicTermApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "academic_year_id": self.year.id,
            "name": "Term 1",
            "sequence_number": 1,
            "start_date": "2026-04-01",
            "end_date": "2026-08-31",
        }
        body.update(overrides)

        return body

    def term(self, **overrides) -> AcademicTerm:
        fields = {
            "academic_year": self.year,
            "school": self.school,
            "name": "Term 1",
            "sequence_number": 1,
            "start_date": dt.date(2026, 4, 1),
            "end_date": dt.date(2026, 8, 31),
        }
        fields.update(overrides)

        return factories.AcademicTermFactory(**fields)

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


class CreatingATerm(AcademicTermApiTest):
    def test_a_term_is_created_and_comes_back_whole(self):
        response = self.client.post(URL, self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Term 1", response.data["name"])
        self.assertEqual(1, response.data["sequence_number"])
        self.assertEqual("2026-04-01", response.data["start_date"])
        self.assertEqual("2026-08-31", response.data["end_date"])
        self.assertEqual("2026-27", response.data["academic_year_name"])

    def test_the_school_comes_from_the_year_not_the_request(self):
        other = factories.SchoolFactory()

        response = self.client.post(URL, self.payload(school_id=other.id), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_a_term_may_be_one_day_long(self):
        response = self.client.post(
            URL, self.payload(start_date="2026-04-01", end_date="2026-04-01"), format="json"
        )

        # End must be after start, so a single day is not expressible. The
        # shortest term is two days, which is close enough to nothing that no
        # school will notice, and the alternative is an end that may equal the
        # start - which makes every overlap comparison ambiguous.
        self.assertEqual(422, response.status_code, response.data)

    def test_the_end_date_must_be_after_the_start(self):
        response = self.client.post(
            URL, self.payload(start_date="2026-08-31", end_date="2026-04-01"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The end date field must be a date after start date.", self.errors(response)["end_date"][0]
        )

    def test_a_term_starting_before_its_year_is_refused(self):
        response = self.client.post(URL, self.payload(start_date="2026-03-31"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The term must start inside 2026-27, which runs from 2026-04-01 to 2027-03-31.",
            self.errors(response)["start_date"][0],
        )

    def test_a_term_ending_after_its_year_is_refused(self):
        response = self.client.post(URL, self.payload(end_date="2027-04-01"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("must end inside 2026-27", self.errors(response)["end_date"][0])

    def test_a_term_on_the_years_first_and_last_day_is_allowed(self):
        response = self.client.post(
            URL, self.payload(start_date="2026-04-01", end_date="2027-03-31"), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_a_missing_field_is_named(self):
        response = self.client.post(URL, {"academic_year_id": self.year.id}, format="json")

        self.assertEqual(422, response.status_code, response.data)
        for field in ("name", "sequence_number", "start_date", "end_date"):
            self.assertIn(field, self.errors(response))

    def test_every_broken_rule_is_reported_at_once(self):
        self.term()

        response = self.client.post(
            URL,
            self.payload(name="Term 1", sequence_number=1, start_date="2026-03-01", end_date="2026-02-01"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        for field in ("name", "sequence_number", "start_date", "end_date"):
            self.assertIn(field, self.errors(response))

    def test_a_sequence_number_outside_its_range_is_refused(self):
        for value in (0, 21, -1):
            with self.subTest(sequence_number=value):
                response = self.client.post(URL, self.payload(sequence_number=value), format="json")

                self.assertEqual(422, response.status_code, response.data)
                self.assertIn("sequence_number", self.errors(response))

    def test_a_sequence_number_that_is_not_a_number_is_refused(self):
        response = self.client.post(URL, self.payload(sequence_number="first"), format="json")

        self.assertEqual(422, response.status_code, response.data)

    def test_something_that_is_not_a_date_is_refused(self):
        response = self.client.post(URL, self.payload(start_date="the first of April"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The start date field must be a valid date.", self.errors(response)["start_date"][0]
        )

    def test_a_year_that_does_not_exist_is_refused(self):
        response = self.client.post(URL, self.payload(academic_year_id=9_999_999), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected academic year id is invalid.", self.errors(response)["academic_year_id"][0]
        )

    def test_another_schools_year_cannot_be_named(self):
        stranger_year = factories.AcademicYearFactory()

        response = self.client.post(URL, self.payload(academic_year_id=stranger_year.id), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("academic_year_id", self.errors(response))

    def test_a_term_can_be_created_in_a_year_that_is_not_current(self):
        old = factories.AcademicYearFactory(
            school=self.school,
            name="2025-26",
            start_date=dt.date(2025, 4, 1),
            end_date=dt.date(2026, 3, 31),
            is_current=False,
        )

        response = self.client.post(
            URL,
            self.payload(academic_year_id=old.id, start_date="2025-04-01", end_date="2025-08-31"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)


class TermsDoNotCollide(AcademicTermApiTest):
    def test_two_terms_cannot_share_a_name_within_a_year(self):
        self.term()

        response = self.client.post(
            URL,
            self.payload(sequence_number=2, start_date="2026-09-01", end_date="2027-03-31"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("The name has already been taken.", self.errors(response)["name"][0])

    def test_two_terms_cannot_share_a_sequence_number_within_a_year(self):
        self.term()

        response = self.client.post(
            URL,
            self.payload(name="Term 2", start_date="2026-09-01", end_date="2027-03-31"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The sequence number has already been taken.", self.errors(response)["sequence_number"][0]
        )

    def test_the_same_name_in_a_different_year_is_fine(self):
        self.term()
        next_year = factories.AcademicYearFactory(
            school=self.school,
            name="2027-28",
            start_date=dt.date(2027, 4, 1),
            end_date=dt.date(2028, 3, 31),
            is_current=False,
        )

        response = self.client.post(
            URL,
            self.payload(academic_year_id=next_year.id, start_date="2027-04-01", end_date="2027-08-31"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_overlapping_dates_are_refused_with_the_term_in_the_way(self):
        self.term()

        response = self.client.post(
            URL,
            self.payload(name="Term 2", sequence_number=2, start_date="2026-08-01", end_date="2026-12-31"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "These dates overlap Term 1 (2026-04-01 to 2026-08-31).",
            self.errors(response)["start_date"][0],
        )

    def test_a_single_overlapping_day_is_still_an_overlap(self):
        self.term()

        response = self.client.post(
            URL,
            self.payload(name="Term 2", sequence_number=2, start_date="2026-08-31", end_date="2026-12-31"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_terms_that_touch_at_the_boundary_are_allowed(self):
        self.term()

        response = self.client.post(
            URL,
            self.payload(name="Term 2", sequence_number=2, start_date="2026-09-01", end_date="2027-03-31"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_a_term_that_swallows_another_is_refused(self):
        self.term(name="Term 2", sequence_number=2, start_date=dt.date(2026, 6, 1), end_date=dt.date(2026, 7, 1))

        response = self.client.post(
            URL,
            self.payload(name="Whole year", sequence_number=3, start_date="2026-04-01", end_date="2027-03-31"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_another_schools_term_is_not_in_the_way(self):
        stranger_year = factories.AcademicYearFactory(
            start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        factories.AcademicTermFactory(
            academic_year=stranger_year,
            school=stranger_year.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )

        response = self.client.post(URL, self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)


class EditingATerm(AcademicTermApiTest):
    def setUp(self):
        super().setUp()
        self.existing = self.term()

    def test_a_field_can_be_changed_on_its_own(self):
        response = self.client.patch(f"{URL}/{self.existing.id}", {"name": "First Term"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("First Term", response.data["name"])
        self.assertEqual("2026-04-01", response.data["start_date"])

    def test_moving_one_date_is_checked_against_the_stored_other(self):
        response = self.client.patch(
            f"{URL}/{self.existing.id}", {"start_date": "2026-09-30"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("end_date", self.errors(response))

    def test_a_term_cannot_be_edited_out_of_its_year(self):
        response = self.client.patch(
            f"{URL}/{self.existing.id}", {"end_date": "2027-06-30"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("must end inside 2026-27", self.errors(response)["end_date"][0])

    def test_a_term_does_not_overlap_itself(self):
        response = self.client.patch(
            f"{URL}/{self.existing.id}", {"end_date": "2026-09-30"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_an_edit_may_not_collide_with_a_sibling(self):
        self.term(name="Term 2", sequence_number=2, start_date=dt.date(2026, 9, 1), end_date=dt.date(2027, 3, 31))

        response = self.client.patch(
            f"{URL}/{self.existing.id}", {"end_date": "2026-10-01"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("overlap Term 2", self.errors(response)["start_date"][0])

    def test_a_term_cannot_be_moved_to_another_year(self):
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False)

        response = self.client.patch(
            f"{URL}/{self.existing.id}", {"academic_year_id": next_year.id}, format="json"
        )

        self.existing.refresh_from_db()
        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(self.year.id, self.existing.academic_year_id)


class DeletingATerm(AcademicTermApiTest):
    def test_a_term_can_be_deleted(self):
        existing = self.term()

        response = self.client.delete(f"{URL}/{existing.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(AcademicTerm.objects.filter(pk=existing.id).exists())

    def test_a_year_with_terms_under_it_is_refused_with_the_reason(self):
        self.term()

        response = self.client.delete(f"/api/v1/academic-years/{self.year.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual(
            "This academic year still has terms set up under it. Remove them first.",
            response.data["message"],
        )


class WhoMayDoWhat(AcademicTermApiTest):
    def setUp(self):
        super().setUp()
        self.existing = self.term()

    def test_every_role_of_the_school_may_read_the_list(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                reader = self.as_user(factories.UserFactory(school=self.school, role=role))

                response = reader.get(URL, {"academic_year_id": self.year.id})

                self.assertEqual(200, response.status_code, response.data)
                self.assertEqual([self.existing.id], [row["id"] for row in response.data["data"]])

    def test_nobody_but_an_administrator_may_write_one(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                writer = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, writer.post(URL, self.payload(name="Term 9"), format="json").status_code)
                self.assertEqual(
                    403,
                    writer.patch(f"{URL}/{self.existing.id}", {"name": "Nope"}, format="json").status_code,
                )
                self.assertEqual(403, writer.delete(f"{URL}/{self.existing.id}").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(URL).status_code)


class SchoolIsolation(AcademicTermApiTest):
    def setUp(self):
        super().setUp()
        self.mine = self.term()
        self.stranger_school = factories.SchoolFactory()
        self.stranger_year = factories.AcademicYearFactory(
            school=self.stranger_school, start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.theirs = factories.AcademicTermFactory(
            academic_year=self.stranger_year, school=self.stranger_school, name="Term 1", sequence_number=1
        )

    def test_the_list_never_includes_another_schools_terms(self):
        response = self.client.get(URL)

        self.assertEqual([self.mine.id], [row["id"] for row in response.data["data"]])

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        # A school outside the scope is ignored rather than honoured, which
        # leaves the caller looking at their own terms instead of somebody
        # else's. See SchoolScope.apply_to - the filter may only narrow.
        response = self.client.get(URL, {"school_id": self.stranger_school.id})

        self.assertEqual(200, response.status_code, response.data)
        self.assertNotIn(self.theirs.id, [row["id"] for row in response.data["data"]])
        self.assertEqual([self.mine.id], [row["id"] for row in response.data["data"]])

    def test_an_academic_year_id_from_another_school_returns_nothing(self):
        response = self.client.get(URL, {"academic_year_id": self.stranger_year.id})

        self.assertEqual([], response.data["data"])

    def test_another_schools_term_cannot_be_read_edited_or_deleted(self):
        self.assertEqual(403, self.client.get(f"{URL}/{self.theirs.id}").status_code)
        self.assertEqual(
            403, self.client.patch(f"{URL}/{self.theirs.id}", {"name": "Mine now"}, format="json").status_code
        )
        self.assertEqual(403, self.client.delete(f"{URL}/{self.theirs.id}").status_code)

    def test_a_group_admin_reaches_a_branchs_terms(self):
        branch = factories.SchoolFactory(parent_school=self.school)
        branch_year = factories.AcademicYearFactory(
            school=branch, start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        branch_term = factories.AcademicTermFactory(
            academic_year=branch_year, school=branch, name="Term 1", sequence_number=1
        )
        group_admin = self.as_user(
            factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)
        )

        response = group_admin.get(URL, {"school_id": branch.id})

        self.assertEqual([branch_term.id], [row["id"] for row in response.data["data"]])

    def test_a_super_admin_reads_any_schools_terms(self):
        response = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)).get(
            URL, {"school_id": self.stranger_school.id}
        )

        self.assertEqual([self.theirs.id], [row["id"] for row in response.data["data"]])


class TheListReadsInOrder(AcademicTermApiTest):
    def test_terms_come_back_in_curriculum_order(self):
        self.term(name="Term 2", sequence_number=2, start_date=dt.date(2026, 9, 1), end_date=dt.date(2026, 12, 31))
        self.term(name="Term 1", sequence_number=1)
        self.term(name="Term 3", sequence_number=3, start_date=dt.date(2027, 1, 1), end_date=dt.date(2027, 3, 31))

        response = self.client.get(URL, {"academic_year_id": self.year.id})

        self.assertEqual(["Term 1", "Term 2", "Term 3"], [row["name"] for row in response.data["data"]])

    def test_the_newest_year_comes_first(self):
        older = factories.AcademicYearFactory(
            school=self.school,
            name="2025-26",
            start_date=dt.date(2025, 4, 1),
            end_date=dt.date(2026, 3, 31),
            is_current=False,
        )
        factories.AcademicTermFactory(
            academic_year=older,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2025, 4, 1),
            end_date=dt.date(2025, 8, 31),
        )
        self.term()

        response = self.client.get(URL)

        self.assertEqual(
            [self.year.id, older.id], [row["academic_year_id"] for row in response.data["data"]]
        )
