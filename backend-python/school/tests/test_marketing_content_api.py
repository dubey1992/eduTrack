"""The public homepage's words (docs/marketing-content.md, slice 1).

The one endpoint in the product that anybody may read without signing in,
so most of what is pinned here is that it stays that way - and that it
answers sensibly when there is nothing to say, which is the state it will
be in on the day a school first sees the page.
"""

from __future__ import annotations

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import MarketingContent
from school.views import marketing_content

URL = "/api/v1/marketing-content"


class ReadingThePage(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def write(self, document) -> MarketingContent:
        row = MarketingContent.objects.create(
            document=document, created_at=timezone.now(), updated_at=timezone.now()
        )
        marketing_content.forget()

        return row

    def test_a_visitor_with_no_account_may_read_it(self):
        """The page is served to anybody who types the address, so its
        words have to be readable by anybody too."""
        response = self.client.get(URL)

        self.assertEqual(200, response.status_code)

    def test_an_empty_table_answers_with_nothing_rather_than_failing(self):
        """The state the product is in until somebody edits the page, and
        the client renders its own copy from it."""
        response = self.client.get(URL)

        self.assertEqual({"document": {}}, response.data)

    def test_it_returns_what_somebody_changed(self):
        self.write({"hero.headline": "Run Your School Smarter"})

        self.assertEqual({"hero.headline": "Run Your School Smarter"}, self.client.get(URL).data["document"])

    def test_a_null_document_reads_as_nothing_changed(self):
        self.write(None)

        self.assertEqual({}, self.client.get(URL).data["document"])

    def test_it_carries_only_what_was_changed_not_the_whole_page(self):
        """The page's own copy lives in the client. Storing the whole page
        here would mean a homepage that goes blank when an API call does.
        """
        self.write({"hero.headline": "One line"})

        self.assertEqual(["hero.headline"], list(self.client.get(URL).data["document"]))

    def test_signing_in_changes_nothing_about_what_is_returned(self):
        self.write({"hero.headline": "One line"})
        admin = factories.UserFactory(role=UserRole.SUPER_ADMIN)
        signed_in = APIClient()
        signed_in.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(admin))

        self.assertEqual(self.client.get(URL).data, signed_in.get(URL).data)

    def test_only_reading_is_allowed(self):
        """Editing happens at /marketing-content/draft, behind the Super
        Admin check. Nothing may write through the public path, signed in
        or not - see test_marketing_content_editor_api.
        """
        for method in (self.client.post, self.client.put, self.client.patch, self.client.delete):
            self.assertEqual(405, method(URL).status_code)


class TheCache(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def test_the_answer_is_cached_rather_than_read_per_visitor(self):
        MarketingContent.objects.create(
            document={"hero.headline": "First"}, created_at=timezone.now(), updated_at=timezone.now()
        )
        marketing_content.forget()

        self.client.get(URL)

        with self.assertNumQueries(0):
            self.assertEqual({"hero.headline": "First"}, self.client.get(URL).data["document"])

    def test_an_empty_table_is_cached_too(self):
        """Otherwise the commonest state of all - nobody has edited the
        page - is the one that queries on every visit."""
        self.client.get(URL)

        with self.assertNumQueries(0):
            self.assertEqual({}, self.client.get(URL).data["document"])

    def test_forgetting_it_is_what_lets_an_edit_be_seen(self):
        row = MarketingContent.objects.create(
            document={"hero.headline": "First"}, created_at=timezone.now(), updated_at=timezone.now()
        )
        marketing_content.forget()
        self.client.get(URL)

        row.document = {"hero.headline": "Second"}
        row.save()

        self.assertEqual("First", self.client.get(URL).data["document"]["hero.headline"], "still cached")

        marketing_content.forget()

        self.assertEqual("Second", self.client.get(URL).data["document"]["hero.headline"])
