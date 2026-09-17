"""The list envelope.

`meta.links` is here because the first cross-backend diff of `/schools` found
it missing: this module claims to reproduce Laravel's envelope, and a claim
like that is either true or it is a trap for whoever relies on it next.

The window algorithm is ported from `Illuminate\\Pagination\\UrlWindow`. The
short-list case is also compared against the live Laravel instance by hand;
the elision cases below are asserted against the algorithm as the framework
source defines it, because producing fourteen pages of real records to compare
would mean creating a thousand rows to check a field no client reads.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.pagination import LaravelPagination, resolve_page, resolve_per_page

from .test_scope import section_in


class TheWindow(TestCase):
    """Which page numbers a paginator offers. None stands for an ellipsis."""

    def window(self, current, last):
        return LaravelPagination.window(current, last)

    def test_a_short_list_offers_every_page(self):
        self.assertEqual([1], self.window(1, 1))
        self.assertEqual([1, 2, 3], self.window(2, 3))

    def test_thirteen_pages_still_fit(self):
        # The threshold is `<`, not `<=`: at exactly fourteen the slider
        # starts. Both sides of that boundary, because an off-by-one here
        # would be invisible until somebody had a big enough school.
        self.assertEqual(list(range(1, 14)), self.window(1, 13))
        self.assertNotEqual(list(range(1, 15)), self.window(1, 14))

    def test_near_the_beginning_shows_the_start_then_the_end(self):
        # first = pages 1..(window + onEachSide) = 1..10, then an ellipsis,
        # then the last two.
        self.assertEqual(
            list(range(1, 11)) + [None, 19, 20],
            self.window(1, 20),
        )

    def test_near_the_end_shows_the_start_then_the_end(self):
        # first = [1, 2], ellipsis, then last - (window + onEachSide - 1) to
        # the end: 11..20.
        self.assertEqual(
            [1, 2, None] + list(range(11, 21)),
            self.window(20, 20),
        )

    def test_in_the_middle_shows_both_caps_and_a_slider(self):
        self.assertEqual(
            [1, 2, None, 12, 13, 14, 15, 16, 17, 18, None, 29, 30],
            self.window(15, 30),
        )

    def test_the_current_page_is_always_offered(self):
        # Whichever page you are on, the window has to contain it - otherwise
        # the control renders with nothing highlighted and the reader cannot
        # tell where they are.
        for last in (1, 5, 13, 14, 20, 30, 100):
            candidates = {1, 2, last // 2, last - 1, last}

            for current in sorted(page for page in candidates if 1 <= page <= last):
                with self.subTest(current=current, last=last):
                    self.assertIn(current, self.window(current, last))


class TheLinks(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.section = section_in(self.school)

        for index in range(3):
            factories.StudentFactory(
                school=self.school,
                class_section=self.section,
                admission_number=f"ADM-{index}",
                first_name=f"Student{index}",
            )

        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION="Bearer "
            + tokens.issue(factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN))
        )

    def links(self, query: str = ""):
        return self.client.get("/api/v1/students" + query).data["meta"]["links"]

    def test_the_first_and_last_entries_are_previous_and_next(self):
        links = self.links("?per_page=1")

        self.assertEqual("&laquo; Previous", links[0]["label"])
        self.assertEqual("Next &raquo;", links[-1]["label"])

    def test_previous_is_dead_on_the_first_page(self):
        links = self.links("?per_page=1")

        self.assertIsNone(links[0]["url"])
        self.assertIsNone(links[0]["page"])
        self.assertFalse(links[0]["active"])

    def test_next_is_dead_on_the_last_page(self):
        links = self.links("?per_page=1&page=3")

        self.assertIsNone(links[-1]["url"])
        self.assertIsNone(links[-1]["page"])

    def test_the_current_page_is_the_active_one_and_only_it(self):
        links = self.links("?per_page=1&page=2")
        active = [link for link in links if link["active"]]

        self.assertEqual(1, len(active))
        self.assertEqual("2", active[0]["label"])
        self.assertEqual(2, active[0]["page"])

    def test_every_page_is_offered_with_a_url(self):
        links = self.links("?per_page=1")
        pages = [link for link in links if link.get("page") and link["label"].isdigit()]

        self.assertEqual(["1", "2", "3"], [link["label"] for link in pages])
        for link in pages:
            self.assertIn("?page=" + link["label"], link["url"])

    def test_a_single_page_still_has_previous_and_next(self):
        links = self.links()

        self.assertEqual(3, len(links), "previous, page 1, next")
        self.assertIsNone(links[0]["url"])
        self.assertIsNone(links[-1]["url"])


class ThePageSize(TestCase):
    def test_it_falls_back_rather_than_refusing(self):
        # Laravel turns "abc" into 0 and its own `> 0` check then rejects it.
        # A list endpoint answering 422 because of a junk page size would be
        # new behaviour.
        self.assertEqual(20, resolve_per_page("abc"))
        self.assertEqual(20, resolve_per_page(None))
        self.assertEqual(20, resolve_per_page(0))
        self.assertEqual(20, resolve_per_page(-5))

    def test_it_is_capped(self):
        self.assertEqual(100, resolve_per_page(5000))
        self.assertEqual(50, resolve_per_page(50))


class PageNumberTest(TestCase):
    """What counts as a page number - PHP's FILTER_VALIDATE_INT, then >= 1."""

    def test_a_plain_number_is_that_page(self):
        self.assertEqual(3, resolve_page("3"))

    def test_whitespace_and_a_plus_sign_are_tolerated(self):
        self.assertEqual(2, resolve_page(" 2"))
        self.assertEqual(2, resolve_page("+2"))

    def test_anything_else_is_the_first_page_rather_than_an_error(self):
        for junk in (None, "", "abc", "0", "-2", "2.5", "1e1", "02"):
            self.assertEqual(1, resolve_page(junk), junk)


class PastTheEnd(TestCase):
    """Laravel answers a page that does not exist with an empty page, not 404."""

    setUp = TheLinks.setUp

    def test_a_page_past_the_end_is_empty_rather_than_not_found(self):
        response = self.client.get("/api/v1/students?per_page=2&page=9")

        self.assertEqual(200, response.status_code)
        self.assertEqual([], response.data["data"])
        self.assertEqual(9, response.data["meta"]["current_page"])
        self.assertEqual(2, response.data["meta"]["last_page"])
        self.assertIsNone(response.data["meta"]["from"])
        self.assertIsNone(response.data["meta"]["to"])
        self.assertTrue(response.data["links"]["prev"].endswith("?page=8"))
        self.assertIsNone(response.data["links"]["next"])

    def test_junk_zero_and_negative_pages_are_the_first_page(self):
        for junk in ("abc", "0", "-2", "2.5"):
            response = self.client.get(f"/api/v1/students?per_page=2&page={junk}")

            with self.subTest(page=junk):
                self.assertEqual(200, response.status_code)
                self.assertEqual(1, response.data["meta"]["current_page"])
                self.assertEqual(2, len(response.data["data"]))

    def test_the_last_real_page_still_counts_its_rows(self):
        response = self.client.get("/api/v1/students?per_page=2&page=2")

        self.assertEqual((3, 3), (response.data["meta"]["from"], response.data["meta"]["to"]))
