"""Search engines and the API (docs/seo.md, S1).

The API host is never crawled or indexed, and the homepage learns which
website pages exist so its footer never links to one that does not.
"""

from __future__ import annotations

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, module_pages, tokens
from school.enums import UserRole

HOMEPAGE = "/api/v1/marketing-content"


class TheApiIsNeverIndexed(TestCase):
    def test_robots_txt_asks_crawlers_to_fetch_nothing(self):
        response = APIClient().get("/robots.txt")

        self.assertEqual(200, response.status_code)
        self.assertEqual("text/plain", response["Content-Type"].split(";")[0])
        self.assertEqual("User-agent: *\nDisallow: /\n", response.content.decode())

    def test_every_answer_says_noindex_found_or_refused(self):
        for path in (HOMEPAGE, "/api/v1/students", "/api/v1/no-such-thing"):
            with self.subTest(path=path):
                self.assertEqual("noindex, nofollow", APIClient().get(path)["X-Robots-Tag"])


class TheHomepageKnowsWhichPagesExist(TestCase):
    def setUp(self):
        cache.clear()
        self.root = APIClient()
        self.root.credentials(
            HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))
        )

    def pages(self) -> list[str]:
        return APIClient().get(HOMEPAGE).data["pages"]

    def test_the_built_in_pages_live_from_the_start_and_not_the_terms(self):
        modules = [module.slug for module in module_pages.MODULES]

        self.assertEqual(["about", "privacy", "contact", *modules], self.pages())

    def test_a_page_appears_once_published_and_not_before(self):
        self.pages()  # cached before the page exists, as a busy homepage would be
        self.root.post("/api/v1/site-pages", {"slug": "careers", "title": "Careers", "body": "Join us."}, format="json")

        self.assertNotIn("careers", self.pages())

        self.root.post("/api/v1/site-pages/careers/publish")

        self.assertIn("careers", self.pages())

    def test_a_deleted_page_leaves_the_list(self):
        self.root.post("/api/v1/site-pages", {"slug": "news", "title": "Blog", "body": "News."}, format="json")
        self.root.post("/api/v1/site-pages/news/publish")
        self.assertIn("news", self.pages())

        self.root.delete("/api/v1/site-pages/news")

        self.assertNotIn("news", self.pages())
