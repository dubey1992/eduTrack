"""Footer lines that go somewhere (docs/marketing-content.md, slice 5).

Each of the footer's three columns is a list of lines, and a line may now
carry an address. One with an address becomes a link; one without stays
the plain text it has always been, which is what every line ships as.

**The address list is a list of what is allowed, not of what is banned.**
The page is served to the open web, and `javascript:` in an address would
run that script in a visitor's browser with the Super Admin's typing as
its source. Anything not named is refused, so a scheme nobody thought
about cannot slip through.
"""

from __future__ import annotations

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, marketing, tokens
from school.enums import UserRole

DRAFT = "/api/v1/marketing-content/draft"
PUBLISH = "/api/v1/marketing-content/publish"
PUBLIC = "/api/v1/marketing-content"
COLUMN = "footer.productLinks"


def super_admin() -> APIClient:
    client = APIClient()
    client.credentials(
        HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))
    )

    return client


class WhichAddressesAreAllowed(TestCase):
    """[marketing.url_problem] on its own - the gate everything else sits
    behind."""

    def allowed(self, url):
        self.assertIsNone(marketing.url_problem(url), url)

    def refused(self, url):
        self.assertIsNotNone(marketing.url_problem(url), url)

    def test_somewhere_else_on_the_web(self):
        for url in ("https://example.com", "http://example.com/terms", "https://example.com/a?b=c#d"):
            self.allowed(url)

    def test_a_page_of_this_site(self):
        for url in ("/login", "/", "/transport/routes"):
            self.allowed(url)

    def test_an_address_the_device_handles(self):
        for url in ("mailto:hello@example.com", "tel:+15551234567"):
            self.allowed(url)

    def test_script_is_refused(self):
        """The one that matters. A link whose address is script would run
        it in the visitor's browser, from the open web."""
        for url in (
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "java\tscript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "vbscript:msgbox(1)",
        ):
            self.refused(url)

    def test_a_bare_domain_is_refused_because_it_is_ambiguous(self):
        """"example.com" could be a site or a page of this one, and
        guessing wrong sends visitors somewhere nobody meant."""
        self.refused("example.com")
        self.refused("www.example.com")

    def test_a_scheme_with_nothing_after_it_is_refused(self):
        self.refused("https://")
        self.refused("mailto:")

    def test_a_page_of_this_site_cannot_have_a_space_in_it(self):
        self.refused("/my page")

    def test_a_scheme_nobody_thought_about_is_refused_by_default(self):
        for url in ("ftp://example.com", "file:///etc/passwd", "chrome://settings", "intent://evil"):
            self.refused(url)


class SavingALineWithAnAddress(TestCase):
    def setUp(self):
        cache.clear()
        self.client = super_admin()

    def save(self, links):
        return self.client.put(DRAFT, {"document": {COLUMN: links}}, format="json")

    def problems(self, response):
        return [str(problem) for problem in response.data["details"]["errors"]["document"]]

    def test_a_line_may_be_given_an_address(self):
        self.save([{"label": "Privacy Policy", "url": "https://example.com/privacy"}])

        self.assertEqual(
            [{"label": "Privacy Policy", "url": "https://example.com/privacy"}],
            self.client.get(DRAFT).data["draft"][COLUMN],
        )

    def test_a_line_without_one_stays_the_plain_text_it_is(self):
        """What every line ships as, and what the whole column was before
        this. Leaving the box empty must stay an ordinary thing to do."""
        self.save([{"label": "Careers"}])

        self.assertEqual([{"label": "Careers"}], self.client.get(DRAFT).data["draft"][COLUMN])

    def test_an_emptied_address_is_removed_rather_than_stored_blank(self):
        self.save([{"label": "Careers", "url": "https://example.com/jobs"}])

        self.save([{"label": "Careers", "url": "   "}])

        self.assertEqual([{"label": "Careers"}], self.client.get(DRAFT).data["draft"][COLUMN])

    def test_a_line_still_needs_its_wording(self):
        """The address is optional; the words on the page are not."""
        response = self.save([{"label": "", "url": "https://example.com"}])

        self.assertEqual(422, response.status_code)
        self.assertIn("First column, line 1 needs a line.", self.problems(response))

    def test_an_address_that_is_not_allowed_is_refused_with_the_reason(self):
        response = self.save([{"label": "Careers", "url": "javascript:alert(1)"}])

        self.assertEqual(422, response.status_code)
        self.assertIn(
            "First column, line 1: an address has to start with https://, http://, "
            "a / for a page of this site, or mailto: or tel:.",
            self.problems(response),
        )

    def test_nothing_is_saved_when_one_address_is_refused(self):
        self.save([{"label": "Careers", "url": "https://example.com/jobs"}, {"label": "Blog", "url": "javascript:1"}])

        self.assertEqual({}, self.client.get(DRAFT).data["draft"])

    def test_a_very_long_address_is_refused(self):
        response = self.save([{"label": "Careers", "url": "https://example.com/" + "x" * 200}])

        self.assertEqual(422, response.status_code)

    def test_the_line_that_is_wrong_is_named_by_its_position(self):
        response = self.save(
            [{"label": "One"}, {"label": "Two"}, {"label": "Three", "url": "nonsense"}]
        )

        self.assertIn("First column, line 3", " ".join(self.problems(response)))

    def test_all_three_columns_take_addresses(self):
        for column in ("footer.productLinks", "footer.companyLinks", "footer.resourceLinks"):
            response = self.client.put(
                DRAFT,
                {"document": {column: [{"label": "Terms", "url": "/terms"}]}},
                format="json",
            )

            self.assertEqual(200, response.status_code, column)

    def test_the_editor_is_told_the_address_box_is_optional(self):
        sections = {section["key"]: section for section in self.client.get(DRAFT).data["sections"]}
        fields = {field["key"]: field for field in sections["footer"]["lists"][0]["fields"]}

        self.assertFalse(fields["url"]["required"])
        self.assertTrue(fields["label"]["required"])


class WhatReachesTheOpenWeb(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = super_admin()

    def test_a_published_address_reaches_the_page(self):
        self.admin.put(
            DRAFT,
            {"document": {COLUMN: [{"label": "Privacy Policy", "url": "https://example.com/privacy"}]}},
            format="json",
        )

        self.admin.post(PUBLISH)

        links = APIClient().get(PUBLIC).data["document"][COLUMN]
        self.assertEqual("https://example.com/privacy", links[0]["url"])

    def test_an_address_that_was_never_allowed_cannot_be_on_the_page(self):
        """The validator is the only way into the document, so this is the
        whole of the protection - pinned so it stays that way."""
        response = self.admin.put(
            DRAFT,
            {"document": {COLUMN: [{"label": "Careers", "url": "javascript:alert(1)"}]}},
            format="json",
        )
        self.assertEqual(422, response.status_code)

        self.admin.post(PUBLISH)

        self.assertEqual({}, APIClient().get(PUBLIC).data["document"])
