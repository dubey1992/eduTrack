"""Every school this actor may see, as pins (docs/maps.md, M1d).

Not a page of the schools list. A pin missing because it was on page four
is a school that looks like it does not exist, so this answers in one go -
with a cap, because a platform larger than one map of itself should be told
so rather than quietly shown the first five hundred.

The scoping is the schools list's own, which is the point: a Group Admin
sees their group on the map for exactly the reason they see it in the list.
"""

from __future__ import annotations

from django.db import connection
from django.test import TestCase
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import SchoolStatus, UserRole
from school.views import schools as schools_view

URL = "/api/v1/schools/locations"

PUNE = {"latitude": "18.5289000", "longitude": "73.8744000"}


def signed_in(user) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

    return client


class WhatComesBack(TestCase):
    def setUp(self):
        self.client = signed_in(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))

    def test_a_school_with_coordinates_is_a_pin(self):
        school = factories.SchoolFactory(name="Bright Future", **PUNE)

        body = self.client.get(URL).data

        self.assertEqual([school.id], [pin["id"] for pin in body["placed"]])
        self.assertEqual("Bright Future", body["placed"][0]["name"])

    def test_a_school_without_coordinates_is_listed_rather_than_dropped(self):
        """They are the ones somebody has to go and place. A map that
        silently omitted them would hide the work it exists to prompt."""
        school = factories.SchoolFactory(name="Not Placed Yet", latitude=None, longitude=None)

        body = self.client.get(URL).data

        self.assertEqual([], body["placed"])
        self.assertEqual([{"id": school.id, "name": "Not Placed Yet"}], body["unplaced"])

    def test_half_a_coordinate_is_not_a_pin(self):
        """The column pair is nullable separately, so a half-filled row is
        reachable however much the form refuses it. Half a coordinate
        points nowhere, so it counts as unplaced."""
        for half in ({"latitude": "18.5289000", "longitude": None}, {"latitude": None, "longitude": "73.8744000"}):
            with self.subTest(half=half):
                School = factories.SchoolFactory(**half)

                body = self.client.get(URL).data

                self.assertIn(School.id, [row["id"] for row in body["unplaced"]])
                self.assertNotIn(School.id, [row["id"] for row in body["placed"]])

    def test_coordinates_come_back_as_strings_with_every_place_kept(self):
        """A decimal(10,7) through a float loses the seventh place, which
        is about a centimetre - but the whole API agrees on strings, and a
        pin that disagreed would be the one row drawn from a float."""
        factories.SchoolFactory(latitude="18.5289123", longitude="73.8744567")

        pin = self.client.get(URL).data["placed"][0]

        self.assertEqual("18.5289123", pin["latitude"])
        self.assertEqual("73.8744567", pin["longitude"])

    def test_a_pin_says_whether_it_is_a_branch(self):
        """The map colours them differently, and it should not have to work
        it out from a parent id it was not given."""
        parent = factories.SchoolFactory(name="A Group", **PUNE)
        branch = factories.SchoolFactory(name="B Branch", parent_school=parent, **PUNE)

        pins = {pin["id"]: pin for pin in self.client.get(URL).data["placed"]}

        self.assertFalse(pins[parent.id]["is_branch"])
        self.assertTrue(pins[branch.id]["is_branch"])
        self.assertEqual(parent.id, pins[branch.id]["parent_school_id"])

    def test_a_switched_off_school_is_still_a_pin_and_says_so(self):
        """It is still somewhere, and leaving it off the map would make a
        deactivated school look like a missing one."""
        factories.SchoolFactory(status=SchoolStatus.INACTIVE, **PUNE)

        pin = self.client.get(URL).data["placed"][0]

        self.assertEqual(SchoolStatus.INACTIVE, pin["status"])

    def test_a_pin_carries_nothing_it_does_not_need(self):
        """The list endpoint is for reading a school. This is for drawing
        one, and every extra field is a row of data per pin."""
        factories.SchoolFactory(**PUNE)

        self.assertEqual(
            {"id", "name", "parent_school_id", "is_branch", "status", "city", "latitude", "longitude"},
            set(self.client.get(URL).data["placed"][0]),
        )

    def test_an_empty_platform_answers_with_nothing_rather_than_failing(self):
        body = self.client.get(URL).data

        self.assertEqual([], body["placed"])
        self.assertEqual([], body["unplaced"])
        self.assertFalse(body["more_than_shown"])


class WhenThereAreTooMany(TestCase):
    """A platform bigger than one map of itself is told so, rather than
    quietly shown the first few hundred."""

    def setUp(self):
        self.client = signed_in(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))

    def test_under_the_cap_nothing_is_held_back(self):
        for index in range(3):
            factories.SchoolFactory(name=f"School {index}", **PUNE)

        body = self.client.get(URL).data

        self.assertEqual(3, len(body["placed"]))
        self.assertFalse(body["more_than_shown"])

    def test_exactly_the_cap_is_not_more_than_the_cap(self):
        """The off-by-one that would make a full map claim it was
        incomplete."""
        with self.settings():
            schools_view.MAP_LIMIT = 3
            self.addCleanup(setattr, schools_view, "MAP_LIMIT", 500)

            for index in range(3):
                factories.SchoolFactory(name=f"School {index}", **PUNE)

            body = self.client.get(URL).data

        self.assertEqual(3, len(body["placed"]))
        self.assertFalse(body["more_than_shown"])

    def test_over_the_cap_says_so_and_draws_exactly_the_cap(self):
        schools_view.MAP_LIMIT = 3
        self.addCleanup(setattr, schools_view, "MAP_LIMIT", 500)

        for index in range(5):
            factories.SchoolFactory(name=f"School {index}", **PUNE)

        body = self.client.get(URL).data

        self.assertEqual(3, len(body["placed"]) + len(body["unplaced"]))
        self.assertTrue(body["more_than_shown"])

    def test_the_probe_row_is_never_one_of_the_answers(self):
        """One row past the cap is read to know there are more. Showing it
        would mean a map of 501 schools calling itself a map of 500."""
        schools_view.MAP_LIMIT = 2
        self.addCleanup(setattr, schools_view, "MAP_LIMIT", 500)

        for index in range(4):
            factories.SchoolFactory(name=f"School {index}", **PUNE)

        body = self.client.get(URL).data

        self.assertEqual(2, len(body["placed"]))

    def test_the_cap_counts_placed_and_unplaced_together(self):
        """Otherwise a platform of 500 unplaced schools would still read
        500 more rows looking for pins."""
        schools_view.MAP_LIMIT = 2
        self.addCleanup(setattr, schools_view, "MAP_LIMIT", 500)

        factories.SchoolFactory(name="A placed", **PUNE)
        factories.SchoolFactory(name="B unplaced", latitude=None, longitude=None)
        factories.SchoolFactory(name="C placed", **PUNE)

        body = self.client.get(URL).data

        self.assertEqual(2, len(body["placed"]) + len(body["unplaced"]))
        self.assertTrue(body["more_than_shown"])

    def test_a_bigger_platform_is_not_a_bigger_query(self):
        """The whole point of the probe row, and of not annotating: the
        work must not grow with the table. Counted as a difference rather
        than a number, because the three queries that authenticate the
        caller are not what this is about.
        """
        factories.SchoolFactory(name="School 0", **PUNE)
        with CaptureQueriesContext(connection) as small:
            self.client.get(URL)

        for index in range(1, 30):
            factories.SchoolFactory(name=f"School {index}", **PUNE)

        with CaptureQueriesContext(connection) as large:
            self.client.get(URL)

        self.assertEqual(len(small), len(large))

    def test_it_never_reads_more_rows_than_the_cap_and_one(self):
        schools_view.MAP_LIMIT = 2
        self.addCleanup(setattr, schools_view, "MAP_LIMIT", 500)

        for index in range(10):
            factories.SchoolFactory(name=f"School {index}", **PUNE)

        with CaptureQueriesContext(connection) as queries:
            self.client.get(URL)

        asked = [query["sql"] for query in queries.captured_queries if '"schools" ORDER BY' in query["sql"]]
        self.assertEqual(1, len(asked), asked)
        self.assertIn("LIMIT 3", asked[0])


class WhoSeesWhichSchools(TestCase):
    """The schools list's own scoping, which is the point: a Group Admin
    sees their group on the map for the reason they see it in the list."""

    def setUp(self):
        self.group = factories.SchoolFactory(name="A Group", **PUNE)
        self.branch = factories.SchoolFactory(name="B Branch", parent_school=self.group, **PUNE)
        self.stranger = factories.SchoolFactory(name="Z Elsewhere", **PUNE)

    def pins_for(self, user) -> set:
        body = signed_in(user).get(URL).data

        return {pin["id"] for pin in body["placed"]} | {row["id"] for row in body["unplaced"]}

    def test_a_super_admin_sees_every_school(self):
        admin = factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None)

        self.assertEqual({self.group.id, self.branch.id, self.stranger.id}, self.pins_for(admin))

    def test_a_group_admin_sees_their_group_and_not_another(self):
        admin = factories.UserFactory(role=UserRole.GROUP_ADMIN, school=self.group)

        self.assertEqual({self.group.id, self.branch.id}, self.pins_for(admin))

    def test_a_branchs_school_admin_sees_the_group_they_belong_to(self):
        admin = factories.UserFactory(role=UserRole.SCHOOL_ADMIN, school=self.branch)

        self.assertEqual({self.group.id, self.branch.id}, self.pins_for(admin))

    def test_a_standalone_school_admin_has_no_map_to_look_at(self):
        """They have one school and nothing to choose between, which is why
        the list refuses them too."""
        admin = factories.UserFactory(role=UserRole.SCHOOL_ADMIN, school=self.stranger)

        self.assertEqual(403, signed_in(admin).get(URL).status_code)

    def test_nobody_else_may_ask_at_all(self):
        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            admin = factories.UserFactory(role=role, school=self.group)

            self.assertEqual(403, signed_in(admin).get(URL).status_code, role)

    def test_a_visitor_who_is_not_signed_in_may_not(self):
        self.assertEqual(401, APIClient().get(URL).status_code)

    def test_another_groups_school_is_not_reachable_by_asking_differently(self):
        """There is no id in this request to change - which is the point of
        scoping the query rather than filtering the answer."""
        admin = factories.UserFactory(role=UserRole.GROUP_ADMIN, school=self.group)

        body = signed_in(admin).get(URL, {"school_id": self.stranger.id}).data

        self.assertNotIn(self.stranger.id, {pin["id"] for pin in body["placed"]})


class TheOrderPinsArriveIn(TestCase):
    def setUp(self):
        self.client = signed_in(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))

    def test_schools_are_named_in_the_same_order_as_the_list(self):
        """The unplaced ones are read down beside the map, and a list that
        reordered itself between visits is unusable."""
        for name in ("Charlie", "Alpha", "Bravo"):
            factories.SchoolFactory(name=name, latitude=None, longitude=None)

        body = self.client.get(URL).data

        self.assertEqual(["Alpha", "Bravo", "Charlie"], [row["name"] for row in body["unplaced"]])

    def test_two_schools_of_the_same_name_keep_a_fixed_order(self):
        first = factories.SchoolFactory(name="Same Name", latitude=None, longitude=None)
        second = factories.SchoolFactory(name="Same Name", latitude=None, longitude=None)

        body = self.client.get(URL).data

        self.assertEqual(sorted([first.id, second.id]), [row["id"] for row in body["unplaced"]])
