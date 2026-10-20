"""Finding a school among a hundred and fifty (docs/biometric.md).

The list had no search and no filter: it paged everything, ordered by name.
That is a list somebody scrolls rather than one somebody uses.

Two rules carry the weight:

- **Active first, then newest.** The two schools worth having at the top are
  the ones still running and the one onboarded this morning. Inactive schools
  sort below rather than disappearing - a list that silently omits them is how
  somebody concludes a school was deleted.
- **The map is narrowed by the same filters as the list.** A filtered list
  beside an unfiltered map is two answers to the same question.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import School

SCHOOLS = "/api/v1/schools"
LOCATIONS = "/api/v1/schools/locations"


class Browsing(TestCase):
    def setUp(self):
        cache.clear()
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        # Created oldest first, so "newest first" is not the insertion order
        # by accident.
        self.oldest = self.school("Abbey Road School", city="Pune", email="head@abbey.invalid")
        self.middle = self.school("Beacon Hill", city="Mumbai", registration_number="REG-7781")
        self.newest = self.school("Cedar Grove", city="Pune", email="office@cedar.invalid")
        self.closed = self.school("Zenith Academy", city="Delhi", status="inactive")

    def school(self, name: str, **overrides) -> School:
        made = factories.SchoolFactory(name=name, **overrides)
        # Distinct creation instants, in the order they were made here.
        made.created_at = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(days=made.id)
        made.save(update_fields=["created_at"])

        return made

    def client_as(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def names(self, **params) -> list[str]:
        response = self.client_as(self.root).get(SCHOOLS, params)

        self.assertEqual(200, response.status_code, response.data)

        return [row["name"] for row in response.data["data"]]


class WhatComesFirst(Browsing):
    def test_active_before_inactive(self):
        names = self.names()

        self.assertLess(names.index("Cedar Grove"), names.index("Zenith Academy"))
        self.assertEqual("Zenith Academy", names[-1])

    def test_newest_before_oldest_among_the_active(self):
        names = self.names()

        self.assertEqual(["Cedar Grove", "Beacon Hill", "Abbey Road School"], names[:3])

    def test_an_inactive_school_is_sorted_below_rather_than_hidden(self):
        # The one everybody gets wrong: a list that omits them is how
        # somebody concludes a school was deleted.
        self.assertIn("Zenith Academy", self.names())

    def test_reactivating_one_moves_it_up(self):
        self.closed.status = "active"
        self.closed.save()

        names = self.names()

        self.assertEqual("Zenith Academy", names[0])


class Searching(Browsing):
    def test_by_name(self):
        self.assertEqual(["Beacon Hill"], self.names(q="beacon"))

    def test_by_city(self):
        self.assertEqual({"Cedar Grove", "Abbey Road School"}, set(self.names(q="pune")))

    def test_by_email(self):
        self.assertEqual(["Cedar Grove"], self.names(q="office@cedar"))

    def test_by_registration_number(self):
        self.assertEqual(["Beacon Hill"], self.names(q="REG-7781"))

    def test_case_does_not_matter(self):
        self.assertEqual(self.names(q="BEACON"), self.names(q="beacon"))

    def test_part_of_a_word_is_enough(self):
        self.assertEqual(["Abbey Road School"], self.names(q="bbey"))

    def test_a_term_matching_nothing_is_an_empty_list_not_everything(self):
        self.assertEqual([], self.names(q="nowhere at all"))

    def test_a_blank_term_is_no_search(self):
        self.assertEqual(4, len(self.names(q="   ")))

    def test_a_percent_sign_is_a_character_somebody_typed(self):
        # Not a wildcard. Searching for "%" must not match every school -
        # see the ILike lookup, which deliberately does not escape and is
        # fed a term wrapped here.
        self.school("100% Attendance School")

        self.assertEqual(["100% Attendance School"], self.names(q="100%"))

    def test_an_inactive_school_is_still_findable(self):
        self.assertEqual(["Zenith Academy"], self.names(q="zenith"))


class Filtering(Browsing):
    def test_by_status(self):
        self.assertEqual(["Zenith Academy"], self.names(status="inactive"))
        self.assertEqual(3, len(self.names(status="active")))

    def test_with_a_search_at_the_same_time(self):
        self.school("Zenith Prep", city="Delhi")

        self.assertEqual(["Zenith Academy"], self.names(q="zenith", status="inactive"))

    def test_a_blank_status_is_no_filter(self):
        self.assertEqual(4, len(self.names(status="")))


class TheMapAgreesWithTheList(Browsing):
    def pins(self, **params) -> set[str]:
        response = self.client_as(self.root).get(LOCATIONS, params)

        self.assertEqual(200, response.status_code, response.data)

        return {row["name"] for row in response.data["placed"]} | {
            row["name"] for row in response.data["unplaced"]
        }

    def test_the_same_search_narrows_both(self):
        self.assertEqual({"Cedar Grove", "Abbey Road School"}, self.pins(q="pune"))

    def test_the_same_status_filter_narrows_both(self):
        self.assertEqual({"Zenith Academy"}, self.pins(status="inactive"))

    def test_unfiltered_they_hold_the_same_schools(self):
        self.assertEqual(set(self.names()), self.pins())


class WhoCanSeeWhat(Browsing):
    def test_a_search_cannot_reach_outside_the_actors_scope(self):
        """The filter narrows what somebody may see; it never widens it."""
        group = factories.SchoolFactory(name="Head Office Group")
        branch = factories.SchoolFactory(name="Branch One", parent_school=group)
        admin = factories.UserFactory(school=group, role=UserRole.GROUP_ADMIN)

        response = self.client_as(admin).get(SCHOOLS, {"q": "cedar"})

        self.assertEqual(200, response.status_code)
        self.assertEqual([], [row["name"] for row in response.data["data"]])

        theirs = self.client_as(admin).get(SCHOOLS, {"q": "branch"})

        self.assertEqual(["Branch One"], [row["name"] for row in theirs.data["data"]])
        self.assertEqual(branch.id, theirs.data["data"][0]["id"])
