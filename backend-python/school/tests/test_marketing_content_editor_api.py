"""Editing the homepage, and publishing it (docs/marketing-content.md, slice 2).

Two things are being pinned here. The first is that only a Super Admin
can change the words on the front of the product - there is no school
context to fall back on, so the check is the whole of the protection.

The second is the gap between the draft and the page. Somebody rewrites
the hero over a morning; visitors keep reading the version that was
signed off until a deliberate act moves one to the other. Most of what
follows is about that line not blurring.
"""

from __future__ import annotations

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, marketing, tokens
from school.enums import UserRole
from school.models import AuditLog, MarketingContent
from school.views import marketing_content

DRAFT = "/api/v1/marketing-content/draft"
PUBLISH = "/api/v1/marketing-content/publish"
PUBLIC = "/api/v1/marketing-content"


def signed_in_as(role) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=role)))

    return client


class WhoMayEditThePage(TestCase):
    def setUp(self):
        cache.clear()

    def test_a_super_admin_may_read_the_draft(self):
        self.assertEqual(200, signed_in_as(UserRole.SUPER_ADMIN).get(DRAFT).status_code)

    def test_a_super_admin_may_save_and_publish(self):
        client = signed_in_as(UserRole.SUPER_ADMIN)

        self.assertEqual(200, client.put(DRAFT, {"document": {}}, format="json").status_code)
        self.assertEqual(200, client.post(PUBLISH).status_code)

    def test_nobody_else_may_read_it_save_it_or_publish_it(self):
        """A school administrator runs their own school; the words on the
        product's front page are not theirs to change."""
        for role in (
            UserRole.SCHOOL_ADMIN,
            UserRole.HOD,
            UserRole.TEACHER,
            UserRole.STAFF,
            UserRole.TRANSPORT_MANAGER,
            UserRole.ACCOUNTANT,
        ):
            client = signed_in_as(role)

            self.assertEqual(403, client.get(DRAFT).status_code, role)
            self.assertEqual(403, client.put(DRAFT, {"document": {}}, format="json").status_code, role)
            self.assertEqual(403, client.post(PUBLISH).status_code, role)

    def test_a_visitor_who_is_not_signed_in_may_not(self):
        """Reading the page is public; changing it is as far from public
        as anything in the product gets."""
        client = APIClient()

        self.assertEqual(401, client.get(DRAFT).status_code)
        self.assertEqual(401, client.put(DRAFT, {"document": {}}, format="json").status_code)
        self.assertEqual(401, client.post(PUBLISH).status_code)


class WhatTheEditorIsBuiltFrom(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SUPER_ADMIN)

    def test_the_form_comes_back_with_the_draft(self):
        """The editor draws itself from this rather than from a form kept
        in step with the page by hand."""
        sections = self.client.get(DRAFT).data["sections"]

        self.assertEqual([section.key for section in marketing.SECTIONS], [s["key"] for s in sections])

    def test_each_field_says_what_the_editor_needs_to_draw_it(self):
        fields = [field for section in self.client.get(DRAFT).data["sections"] for field in section["fields"]]

        self.assertEqual(sorted(marketing.keys()), sorted(f["key"] for f in fields))
        for field in fields:
            self.assertTrue(field["label"], field["key"])
            self.assertIsInstance(field["multiline"], bool)
            self.assertGreater(field["max_length"], 0)

    def test_an_untouched_page_opens_empty_rather_than_failing(self):
        """The state the product ships in: no row, nothing published."""
        body = self.client.get(DRAFT).data

        self.assertEqual({}, body["draft"])
        self.assertEqual({}, body["published"])
        self.assertIsNone(body["published_at"])
        self.assertFalse(body["has_unpublished_changes"])


class SavingADraft(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SUPER_ADMIN)

    def save(self, document):
        return self.client.put(DRAFT, {"document": document}, format="json")

    def test_it_keeps_what_was_typed(self):
        self.save({"hero.headline": "Run Your School Smarter"})

        self.assertEqual({"hero.headline": "Run Your School Smarter"}, self.client.get(DRAFT).data["draft"])

    def test_saving_a_draft_leaves_the_public_page_alone(self):
        """The whole point of the column. Half-written copy must not be
        on the homepage while somebody is still deciding."""
        self.save({"hero.headline": "Half a thought"})

        self.assertEqual({}, APIClient().get(PUBLIC).data["document"])

    def test_it_says_when_there_is_something_waiting_to_be_published(self):
        self.save({"hero.headline": "Not live yet"})

        self.assertTrue(self.client.get(DRAFT).data["has_unpublished_changes"])

    def test_a_draft_that_matches_the_page_is_not_waiting_for_anything(self):
        self.save({"hero.headline": "Live"})
        self.client.post(PUBLISH)

        self.assertFalse(self.client.get(DRAFT).data["has_unpublished_changes"])

    def test_saving_twice_replaces_rather_than_accumulates(self):
        """The editor sends the whole form, so the second save is the
        truth - a field removed from it was removed on purpose."""
        self.save({"hero.headline": "First", "cta.button": "Start"})
        self.save({"hero.headline": "Second"})

        self.assertEqual({"hero.headline": "Second"}, self.client.get(DRAFT).data["draft"])

    def test_it_does_not_make_a_second_row(self):
        """One page, one row. A second would make "the document" a
        question about ordering."""
        self.save({"hero.headline": "First"})
        self.save({"hero.headline": "Second"})

        self.assertEqual(1, MarketingContent.objects.count())

    def test_an_edit_opens_where_the_live_page_is_rather_than_blank(self):
        """Published once, never drafted since: the editor should show
        what the world is reading, not an empty form."""
        MarketingContent.objects.create(
            document={"hero.headline": "Live copy"},
            draft=None,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

        self.assertEqual({"hero.headline": "Live copy"}, self.client.get(DRAFT).data["draft"])


class WhatMayBeTyped(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SUPER_ADMIN)

    def save(self, document):
        return self.client.put(DRAFT, {"document": document}, format="json")

    def problems(self, response):
        return [str(problem) for problem in response.data["details"]["errors"]["document"]]

    def test_a_key_nobody_recognises_is_refused(self):
        """The column is loose JSON, so without this it would quietly
        collect whatever any client sent and nothing would read it back.
        """
        response = self.save({"hero.headline": "Fine", "hero.invented": "Nonsense"})

        self.assertEqual(422, response.status_code)
        self.assertIn('"hero.invented" is not something on the page.', self.problems(response))

    def test_nothing_is_saved_when_one_field_is_wrong(self):
        self.save({"hero.headline": "Fine", "hero.invented": "Nonsense"})

        self.assertEqual({}, self.client.get(DRAFT).data["draft"])

    def test_a_headline_too_long_for_its_slot_is_refused(self):
        """46px against a drawn mockup. Forty words would not wrap, it
        would wreck the section - refusing is kinder than publishing it
        and finding out."""
        response = self.save({"hero.headline": "x" * 91})

        self.assertEqual(422, response.status_code)
        self.assertIn("Headline must be 90 characters or fewer - it is 91.", self.problems(response))

    def test_a_headline_exactly_as_long_as_the_slot_is_fine(self):
        self.assertEqual(200, self.save({"hero.headline": "x" * 90}).status_code)

    def test_a_line_break_in_a_single_line_field_is_refused(self):
        response = self.save({"hero.headline": "Two\nlines"})

        self.assertEqual(422, response.status_code)
        self.assertIn("Headline is a single line.", self.problems(response))

    def test_a_line_break_is_kept_where_the_design_uses_one(self):
        """The phone and browser headings break across two lines by
        design, so a break typed there is the point."""
        self.assertEqual(200, self.save({"mobile.headline": "On the\nphone"}).status_code)
        self.assertEqual("On the\nphone", self.client.get(DRAFT).data["draft"]["mobile.headline"])

    def test_every_problem_is_reported_at_once(self):
        """Somebody who has rewritten six fields should not press Save six
        times to learn about each one."""
        response = self.save({"hero.headline": "x" * 200, "cta.button": "y" * 50, "nope.at.all": "z"})

        self.assertEqual(3, len(self.problems(response)))

    def test_a_cleared_field_goes_back_to_the_copy_that_ships(self):
        """Clearing a box means "I did not want to change this", not "the
        homepage should have a blank headline"."""
        self.save({"hero.headline": "Changed", "cta.button": "Changed"})
        self.save({"hero.headline": "", "cta.button": "   "})

        self.assertEqual({}, self.client.get(DRAFT).data["draft"])

    def test_surrounding_space_is_trimmed_rather_than_published(self):
        self.save({"hero.headline": "  Spaced out  "})

        self.assertEqual("Spaced out", self.client.get(DRAFT).data["draft"]["hero.headline"])

    def test_a_value_that_is_not_text_is_refused(self):
        response = self.save({"hero.headline": 42})

        self.assertEqual(422, response.status_code)
        self.assertIn("Headline must be text.", self.problems(response))

    def test_a_document_that_is_not_an_object_is_refused(self):
        self.assertEqual(422, self.client.put(DRAFT, {"document": "words"}, format="json").status_code)

    def test_markup_typed_into_a_box_is_stored_as_the_words_it_is(self):
        """Flutter draws these as text, not HTML, so a tag is only ever
        seen as the characters somebody typed. Pinned because the day the
        page gains a rich-text field, this test should be the one that
        starts the conversation."""
        self.save({"hero.headline": "<b>Bold</b>"})

        self.assertEqual("<b>Bold</b>", self.client.get(DRAFT).data["draft"]["hero.headline"])
        self.client.post(PUBLISH)

        self.assertEqual("<b>Bold</b>", APIClient().get(PUBLIC).data["document"]["hero.headline"])


class Publishing(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = factories.UserFactory(role=UserRole.SUPER_ADMIN)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))

    def save(self, document):
        return self.client.put(DRAFT, {"document": document}, format="json")

    def test_it_puts_the_draft_in_front_of_the_world(self):
        self.save({"hero.headline": "Run Your School Smarter"})

        self.client.post(PUBLISH)

        self.assertEqual(
            {"hero.headline": "Run Your School Smarter"}, APIClient().get(PUBLIC).data["document"]
        )

    def test_a_visitor_reading_the_old_page_sees_the_new_one(self):
        """The public answer is cached for an hour, so publishing has to
        forget it - otherwise the edit lands whenever the cache happens
        to expire."""
        APIClient().get(PUBLIC)
        self.save({"hero.headline": "New"})

        self.client.post(PUBLISH)

        self.assertEqual("New", APIClient().get(PUBLIC).data["document"]["hero.headline"])

    def test_it_records_who_published_and_when(self):
        self.save({"hero.headline": "New"})

        self.client.post(PUBLISH)

        row = MarketingContent.objects.get()
        self.assertEqual(self.admin.id, row.published_by_id)
        self.assertIsNotNone(row.published_at)

    def test_it_is_written_to_the_audit_trail(self):
        """"Who changed the front page, and when" is the first question
        anybody asks when the wording surprises them."""
        self.save({"hero.headline": "After"})

        self.client.post(PUBLISH)

        entry = AuditLog.objects.get(action="marketing_content.published")
        self.assertEqual(self.admin.id, entry.user_id)
        self.assertIsNone(entry.school_id)
        self.assertEqual({"hero.headline": "After"}, entry.new_values)

    def test_the_trail_keeps_what_the_page_said_before(self):
        self.save({"hero.headline": "Before"})
        self.client.post(PUBLISH)
        self.save({"hero.headline": "After"})

        self.client.post(PUBLISH)

        entries = AuditLog.objects.filter(action="marketing_content.published").order_by("id")
        self.assertEqual([{}, {"hero.headline": "Before"}], [entry.old_values for entry in entries])

    def test_publishing_with_nothing_changed_is_allowed_and_changes_nothing(self):
        """Pressing the button twice is a thing people do. The second
        press should be uneventful, not an error."""
        self.save({"hero.headline": "Same"})
        self.client.post(PUBLISH)

        self.assertEqual(200, self.client.post(PUBLISH).status_code)
        self.assertEqual({"hero.headline": "Same"}, APIClient().get(PUBLIC).data["document"])

    def test_publishing_an_empty_draft_puts_the_shipped_copy_back(self):
        """Clearing every box and publishing is how somebody undoes all of
        it - the page falls back to the copy in the client."""
        self.save({"hero.headline": "Changed"})
        self.client.post(PUBLISH)

        self.save({})
        self.client.post(PUBLISH)

        self.assertEqual({}, APIClient().get(PUBLIC).data["document"])

    def test_publishing_before_anything_was_ever_drafted_is_harmless(self):
        self.assertEqual(200, self.client.post(PUBLISH).status_code)
        self.assertEqual({}, APIClient().get(PUBLIC).data["document"])

    def test_the_draft_stays_readable_after_publishing(self):
        """Opening the editor again shows the live page, so the next edit
        starts from what is there rather than from nothing."""
        self.save({"hero.headline": "Live"})
        self.client.post(PUBLISH)

        self.assertEqual({"hero.headline": "Live"}, self.client.get(DRAFT).data["draft"])


class TwoAdminsAtOnce(TestCase):
    """Two people with the editor open is the one concurrency case this
    screen has, and there is exactly one row for them to share.

    No locking: whoever saves last wins, and the other's unsaved boxes are
    simply not in the document. That is the behaviour, not an accident, so
    it is pinned - the page is a handful of fields edited rarely by the
    few people who have the role, and a lock would cost more than it saves.
    """

    def setUp(self):
        cache.clear()
        self.first = signed_in_as(UserRole.SUPER_ADMIN)
        self.second = signed_in_as(UserRole.SUPER_ADMIN)

    def test_the_second_save_wins_and_the_first_is_not_lost_silently(self):
        self.first.put(DRAFT, {"document": {"hero.headline": "Mine"}}, format="json")
        self.second.put(DRAFT, {"document": {"hero.headline": "Theirs"}}, format="json")

        # The answer to a PUT carries the document as it now stands, so the
        # first editor's next save - or refresh - shows them what happened.
        self.assertEqual("Theirs", self.first.get(DRAFT).data["draft"]["hero.headline"])

    def test_publishing_publishes_the_row_not_whatever_one_browser_held(self):
        self.first.put(DRAFT, {"document": {"hero.headline": "Mine"}}, format="json")
        self.second.put(DRAFT, {"document": {"hero.headline": "Theirs"}}, format="json")

        self.first.post(PUBLISH)

        self.assertEqual("Theirs", APIClient().get(PUBLIC).data["document"]["hero.headline"])


class TheDeclarationAndTheClient(TestCase):
    """The keys live in two places - here, and in the client's defaults -
    because the page has to render its own copy with the backend down.

    So they have to agree, and nothing but a test can make them. A key
    only the client knows is a field nobody can edit; a key only this side
    knows is a box in the editor that changes nothing on the page.
    """

    DEFAULTS = "../frontend/lib/features/marketing/data/marketing_defaults.dart"

    def client_keys(self) -> set[str]:
        import pathlib
        import re

        source = (pathlib.Path(__file__).resolve().parents[2] / self.DEFAULTS).read_text(encoding="utf-8")
        # The words only - the repeating lists are keyed the same way
        # and are checked separately.
        source = source.split("const marketingListDefaults")[0]

        return set(re.findall(r"^\s*'([a-zA-Z]+\.[a-zA-Z]+)':", source, flags=re.MULTILINE))

    def client_lists(self) -> dict[str, list[dict]]:
        """The repeating lists the client ships, read out of its defaults.

        Parsed rather than imported, which is the price of the defaults
        living on the other side of the wire. A loose parse would make the
        drift test pass by finding nothing, so a guard below checks it
        found something.
        """
        import json
        import pathlib
        import re

        source = (pathlib.Path(__file__).resolve().parents[2] / self.DEFAULTS).read_text(encoding="utf-8")
        body = source.split("const marketingListDefaults")[1]
        lists: dict[str, list[dict]] = {}

        # Each list opens at its key and closes at a bracket on its own
        # indented line, so the source is cut between the two rather than
        # matched across newlines.
        for opening in re.finditer(r"'([a-zA-Z]+[.][a-zA-Z]+)': \[", body):
            block = body[opening.end():].split("  ],")[0]
            lists[opening.group(1)] = [
                json.loads("{" + re.sub(r"'([^']*)'", lambda m: json.dumps(m.group(1)), item) + "}")
                for item in re.findall(r"[{]([^{}]*)[}]", block)
            ]

        return lists

    def test_the_editor_offers_every_word_the_page_draws(self):
        self.assertEqual(self.client_keys(), marketing.keys())

    def test_the_editor_offers_every_list_the_page_draws(self):
        self.assertEqual(set(self.client_lists()), marketing.list_keys())

    def test_each_list_ships_the_fields_the_declaration_names(self):
        """An item key only one side knows is a box that edits nothing, or
        a word on the page nobody can reach.

        An optional box may be absent - a footer line ships without an
        address, which is what keeps it the plain text it is today.
        """
        declared = marketing.lists()

        for key, items in self.client_lists().items():
            every = {field.key for field in declared[key].fields}
            needed = {field.key for field in declared[key].fields if field.required}

            for position, item in enumerate(items, start=1):
                where = f"{key}, item {position}"
                self.assertEqual(set(), needed - set(item), where)
                self.assertEqual(set(), set(item) - every, where)

    def test_the_list_the_page_ships_fits_what_the_design_holds(self):
        """The editor starts from the shipped list, so a limit below it
        would open already over the line."""
        declared = marketing.lists()

        for key, items in self.client_lists().items():
            self.assertGreaterEqual(len(items), declared[key].min_items, key)
            self.assertLessEqual(len(items), declared[key].max_items, key)

    def test_every_icon_the_page_ships_is_on_the_picker(self):
        """Otherwise opening the editor and saving without touching
        anything would be refused."""
        offered = {choice.value for choice in marketing.FEATURE_ICONS}
        shipped = {item["icon"] for item in self.client_lists()["features.items"]}

        self.assertEqual(set(), shipped - offered)

    def test_the_declaration_found_the_client_file_at_all(self):
        """Guards the tests above: empty on both sides would pass."""
        self.assertGreater(len(self.client_keys()), 20)
        self.assertEqual(6, len(self.client_lists()))
        self.assertEqual(10, len(self.client_lists()["features.items"]))


class TheDraftDoesNotLeak(TestCase):
    def setUp(self):
        cache.clear()

    def test_an_unpublished_draft_is_not_visible_to_the_world(self):
        """The one way this feature could embarrass somebody: half-written
        copy reachable on the public endpoint."""
        MarketingContent.objects.create(
            document={"hero.headline": "Live"},
            draft={"hero.headline": "Still deciding"},
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )
        marketing_content.forget()

        body = APIClient().get(PUBLIC).data

        self.assertEqual({"hero.headline": "Live"}, body["document"])
        self.assertNotIn("draft", body)
