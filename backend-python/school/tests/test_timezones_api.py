"""The timezone picker's list.

The list has to be PHP's, not Python's. Comparing the two backends live found
Django offering 598 zones where Laravel offers 419 - all of Laravel's, plus
179 backward-compatibility aliases (`Asia/Calcutta`, `America/Buenos_Aires`,
`US/Eastern`) that PHP's list leaves out.

That is not a cosmetic duplicate in a dropdown. A school set to
`Asia/Calcutta` through Django would be read by Laravel through `SchoolClock`,
which checks the name against PHP's list, fail, and **fall back to UTC** -
moving every attendance date for that school by five and a half hours. So the
list is generated from PHP and committed (`school/zones.py`), and these tests
guard both halves: the aliases are absent, and the real zones are present.
"""

from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens


class TimezoneTest(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory()))

    def zones(self, query: str = ""):
        return self.client.get("/api/v1/timezones" + query).data["data"]


class TheList(TimezoneTest):
    def test_it_comes_back_whole_rather_than_paginated(self):
        # A few hundred entries, identical for every user. Paginating it would
        # make the picker fetch six pages to show one dropdown.
        response = self.client.get("/api/v1/timezones")

        self.assertEqual(200, response.status_code)
        self.assertIn("data", response.data)
        self.assertNotIn("meta", response.data)
        self.assertGreater(len(response.data["data"]), 100)

    def test_every_entry_carries_what_the_picker_reads(self):
        for zone in self.zones()[:20]:
            self.assertEqual({"name", "region", "offset_minutes", "label"}, set(zone))
            self.assertIsInstance(zone["offset_minutes"], int)

    def test_the_zones_the_product_actually_uses_are_there(self):
        names = {zone["name"] for zone in self.zones()}

        for name in ("Asia/Kolkata", "Africa/Lagos", "America/New_York", "Europe/London", "UTC"):
            self.assertIn(name, names)

    def test_it_is_php_s_list_and_not_python_s(self):
        # The difference that would otherwise move a school's calendar. See
        # this module's docstring and school/zones.py.
        names = {zone["name"] for zone in self.zones()}

        self.assertEqual(419, len(names))

        for alias in ("Asia/Calcutta", "America/Buenos_Aires", "US/Eastern", "Africa/Asmera"):
            self.assertNotIn(alias, names, "a backward-compatibility alias PHP does not accept")

    def test_a_zone_php_rejects_cannot_be_set_on_a_school(self):
        # The list and the validator have to agree, or the picker offers what
        # the form refuses - or worse, the form accepts what the picker never
        # offered.
        from school.enums import UserRole

        root = APIClient()
        root.credentials(
            HTTP_AUTHORIZATION="Bearer "
            + tokens.issue(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))
        )

        response = root.post(
            "/api/v1/schools",
            {
                "name": "Legacy Zone High",
                "email": "legacy@example.invalid",
                "phone": "+91 9000000000",
                "address": "1 Road",
                "city": "Kolkata",
                "state": "WB",
                "country": "India",
                "postal_code": "700001",
                "currency_code": "INR",
                "timezone": "Asia/Calcutta",
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The timezone field must be a valid timezone.",
            response.data["details"]["errors"]["timezone"][0],
        )

    def test_it_is_ordered_west_to_east(self):
        offsets = [zone["offset_minutes"] for zone in self.zones()]

        self.assertEqual(sorted(offsets), offsets)

    def test_a_half_hour_offset_is_labelled_the_way_people_write_it(self):
        kolkata = next(zone for zone in self.zones() if zone["name"] == "Asia/Kolkata")

        self.assertEqual(330, kolkata["offset_minutes"])
        self.assertEqual("Asia/Kolkata (GMT+05:30)", kolkata["label"])
        self.assertEqual("Asia", kolkata["region"])

    def test_a_zone_west_of_greenwich_is_labelled_with_a_minus(self):
        new_york = next(zone for zone in self.zones() if zone["name"] == "America/New_York")

        self.assertLess(new_york["offset_minutes"], 0)
        self.assertTrue(new_york["label"].startswith("America/New_York (GMT-0"))

    def test_a_zone_with_no_region_is_filed_under_other(self):
        utc = next(zone for zone in self.zones() if zone["name"] == "UTC")

        self.assertEqual("Other", utc["region"])


class Narrowing(TimezoneTest):
    def test_a_search_term_narrows_the_list(self):
        narrowed = self.zones("?q=kolkata")

        self.assertEqual(["Asia/Kolkata"], [zone["name"] for zone in narrowed])

    def test_the_search_ignores_case(self):
        self.assertEqual(self.zones("?q=KOLKATA"), self.zones("?q=kolkata"))

    def test_a_term_matching_nothing_is_an_empty_list_not_an_error(self):
        self.assertEqual([], self.zones("?q=mars"))

    def test_a_blank_term_is_no_filter(self):
        self.assertEqual(len(self.zones()), len(self.zones("?q=")))


class WhoMayRead(TimezoneTest):
    def test_any_signed_in_user_may_read_it(self):
        # Reference data, not tenant data - and every role that can see a
        # date needs to know which zone it is in.
        from school.enums import UserRole

        for role in (UserRole.SUPER_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.TEACHER):
            with self.subTest(role=role):
                client = APIClient()
                client.credentials(
                    HTTP_AUTHORIZATION="Bearer "
                    + tokens.issue(factories.UserFactory(role=role))
                )

                self.assertEqual(200, client.get("/api/v1/timezones").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/timezones").status_code)
