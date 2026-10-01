"""The repeating parts of the homepage (docs/marketing-content.md, slice 3).

The feature cards, the figures under the hero, the ticked list beside the
dashboard, and the footer's three columns. They live in the same document
as the words, because they are published as one.

The rule that shapes most of this: an item's fields may not be blank.
A page-level box left empty falls back to the copy that ships, which is a
sensible thing to mean. A card with no title is a hole in a grid.
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

STAT = {"value": "500+", "label": "Schools"}
CARD = {"icon": marketing.FEATURE_ICONS[0].value, "title": "Attendance", "body": "Who came in today"}


def super_admin() -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=UserRole.SUPER_ADMIN)))

    return client


class WhatTheEditorIsToldAboutLists(TestCase):
    def setUp(self):
        cache.clear()
        self.client = super_admin()

    def sections(self) -> dict:
        return {section["key"]: section for section in self.client.get(DRAFT).data["sections"]}

    def test_every_list_is_declared_with_its_section(self):
        sections = self.sections()

        self.assertEqual(["hero.stats"], [declared["key"] for declared in sections["hero"]["lists"]])
        self.assertEqual(["features.items"], [declared["key"] for declared in sections["features"]["lists"]])
        self.assertEqual(
            ["footer.productLinks", "footer.companyLinks", "footer.resourceLinks"],
            [declared["key"] for declared in sections["footer"]["lists"]],
        )

    def test_a_section_with_no_list_says_so_rather_than_leaving_it_out(self):
        self.assertEqual([], self.sections()["nav"]["lists"])

    def test_a_list_says_how_many_items_the_design_holds(self):
        stats = self.sections()["hero"]["lists"][0]

        self.assertEqual(1, stats["min_items"])
        self.assertEqual(5, stats["max_items"])

    def test_the_icon_is_a_picker_and_everything_else_is_a_box(self):
        """Free text lets somebody type a character the font has no glyph
        for, and the card shows an empty box where an icon belongs."""
        cards = self.sections()["features"]["lists"][0]
        by_key = {field["key"]: field for field in cards["fields"]}

        self.assertEqual(len(marketing.FEATURE_ICONS), len(by_key["icon"]["choices"]))
        self.assertEqual([], by_key["title"]["choices"])

    def test_each_choice_carries_the_character_and_a_name_for_it(self):
        icon = self.sections()["features"]["lists"][0]["fields"][0]

        for choice in icon["choices"]:
            self.assertTrue(choice["value"], choice)
            self.assertTrue(choice["label"], choice)


class SavingAList(TestCase):
    def setUp(self):
        cache.clear()
        self.client = super_admin()

    def save(self, document):
        return self.client.put(DRAFT, {"document": document}, format="json")

    def problems(self, response):
        return [str(problem) for problem in response.data["details"]["errors"]["document"]]

    def test_it_keeps_the_items_in_the_order_they_were_given(self):
        first = {"value": "1", "label": "One"}
        second = {"value": "2", "label": "Two"}

        self.save({"hero.stats": [first, second]})

        self.assertEqual([first, second], self.client.get(DRAFT).data["draft"]["hero.stats"])

    def test_reordering_is_just_another_save(self):
        first = {"value": "1", "label": "One"}
        second = {"value": "2", "label": "Two"}
        self.save({"hero.stats": [first, second]})

        self.save({"hero.stats": [second, first]})

        self.assertEqual([second, first], self.client.get(DRAFT).data["draft"]["hero.stats"])

    def test_words_and_lists_live_in_one_document(self):
        self.save({"hero.headline": "New", "hero.stats": [STAT]})

        draft = self.client.get(DRAFT).data["draft"]
        self.assertEqual("New", draft["hero.headline"])
        self.assertEqual([STAT], draft["hero.stats"])

    def test_a_list_left_out_is_the_one_the_page_ships_with(self):
        """Nothing is stored for it, the same as a cleared box - the client
        draws its own."""
        self.save({"hero.stats": [STAT]})

        self.save({"hero.headline": "Only words now"})

        self.assertNotIn("hero.stats", self.client.get(DRAFT).data["draft"])

    def test_surrounding_space_is_trimmed(self):
        self.save({"hero.stats": [{"value": "  500+  ", "label": " Schools "}]})

        self.assertEqual(
            [{"value": "500+", "label": "Schools"}], self.client.get(DRAFT).data["draft"]["hero.stats"]
        )

    def test_a_published_list_reaches_the_public_page(self):
        self.save({"features.items": [CARD]})

        self.client.post(PUBLISH)

        self.assertEqual([CARD], APIClient().get(PUBLIC).data["document"]["features.items"])

    def test_an_unpublished_list_does_not(self):
        self.save({"features.items": [CARD]})

        self.assertEqual({}, APIClient().get(PUBLIC).data["document"])


class WhatAListMayHold(TestCase):
    def setUp(self):
        cache.clear()
        self.client = super_admin()

    def save(self, document):
        return self.client.put(DRAFT, {"document": document}, format="json")

    def problems(self, response):
        return [str(problem) for problem in response.data["details"]["errors"]["document"]]

    def test_more_than_the_design_holds_is_refused(self):
        """Five figures sit across the width of the hero; a sixth wraps on
        to a row of its own at a fifth of the width and looks wrong."""
        response = self.save({"hero.stats": [STAT] * 6})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero holds 5 at most - there are 6.", self.problems(response))

    def test_exactly_as_many_as_it_holds_is_fine(self):
        self.assertEqual(200, self.save({"hero.stats": [STAT] * 5}).status_code)

    def test_an_empty_list_is_refused_rather_than_quietly_meaning_the_shipped_one(self):
        """Leaving the key out means "use the one that ships". Sending an
        empty list is somebody having removed every item, and the layout has
        no sensible answer for that."""
        response = self.save({"hero.stats": []})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero needs at least 1 entry.", self.problems(response))

    def test_a_blank_field_in_an_item_is_refused(self):
        response = self.save({"hero.stats": [{"value": "500+", "label": "   "}]})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero, figure 1 needs a what it is.", self.problems(response))

    def test_a_missing_field_in_an_item_is_refused(self):
        response = self.save({"hero.stats": [{"value": "500+"}]})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero, figure 1 needs a what it is.", self.problems(response))

    def test_the_item_that_is_wrong_is_named_by_its_position(self):
        """Somebody looking at nine cards needs to know which one."""
        response = self.save({"features.items": [CARD, CARD, {**CARD, "title": ""}]})

        self.assertIn("The feature cards, card 3 needs a title.", self.problems(response))

    def test_a_field_nobody_recognises_inside_an_item_is_refused(self):
        response = self.save({"hero.stats": [{**STAT, "colour": "red"}]})

        self.assertEqual(422, response.status_code)
        self.assertIn(
            'The figures under the hero, figure 1: "colour" is not something on the page.',
            self.problems(response),
        )

    def test_an_item_that_is_not_an_object_is_refused(self):
        response = self.save({"hero.stats": ["500+"]})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero, figure 1 is not filled in.", self.problems(response))

    def test_a_value_too_long_for_its_slot_is_refused(self):
        response = self.save({"hero.stats": [{"value": "x" * 17, "label": "Schools"}]})

        self.assertEqual(422, response.status_code)
        self.assertIn(
            "The figures under the hero, figure 1: figure must be 16 characters or fewer - it is 17.",
            self.problems(response),
        )

    def test_a_line_break_inside_an_item_is_refused(self):
        response = self.save({"hero.stats": [{"value": "500+", "label": "Two\nlines"}]})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero, figure 1: what it is is a single line.", self.problems(response))

    def test_something_that_is_not_a_list_at_all_is_refused(self):
        response = self.save({"hero.stats": "500+"})

        self.assertEqual(422, response.status_code)
        self.assertIn("The figures under the hero must be a list.", self.problems(response))

    def test_nothing_is_saved_when_one_item_is_wrong(self):
        self.save({"hero.stats": [STAT, {"value": "", "label": ""}]})

        self.assertEqual({}, self.client.get(DRAFT).data["draft"])

    def test_every_problem_in_a_list_is_reported_at_once(self):
        response = self.save({"features.items": [{**CARD, "title": ""}, {**CARD, "body": ""}]})

        self.assertEqual(2, len(self.problems(response)))


class TheIconsAreAFixedSet(TestCase):
    def setUp(self):
        cache.clear()
        self.client = super_admin()

    def save(self, document):
        return self.client.put(DRAFT, {"document": document}, format="json")

    def test_every_icon_on_the_picker_is_accepted(self):
        for choice in marketing.FEATURE_ICONS:
            response = self.save({"features.items": [{**CARD, "icon": choice.value}]})

            self.assertEqual(200, response.status_code, choice.label)

    def test_a_character_that_is_not_on_it_is_refused(self):
        """Free text lets somebody paste a glyph the font has no room for,
        and the card draws an empty box where the icon belongs."""
        response = self.save({"features.items": [{**CARD, "icon": "☃"}]})

        self.assertEqual(422, response.status_code)
        self.assertIn(
            "The feature cards, card 1: that is not one of the icons to choose from.",
            [str(problem) for problem in response.data["details"]["errors"]["document"]],
        )

    def test_the_set_has_no_repeats(self):
        """Two entries drawing the same character would be two ways to say
        the same thing on a picker."""
        values = [choice.value for choice in marketing.FEATURE_ICONS]

        self.assertEqual(len(values), len(set(values)))


class WhoMayChangeTheLists(TestCase):
    def setUp(self):
        cache.clear()

    def test_nobody_but_a_super_admin_may(self):
        for role in (UserRole.SCHOOL_ADMIN, UserRole.HOD, UserRole.TEACHER, UserRole.ACCOUNTANT):
            client = APIClient()
            client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=role)))

            response = client.put(DRAFT, {"document": {"hero.stats": [STAT]}}, format="json")

            self.assertEqual(403, response.status_code, role)

    def test_a_visitor_who_is_not_signed_in_may_not(self):
        response = APIClient().put(DRAFT, {"document": {"hero.stats": [STAT]}}, format="json")

        self.assertEqual(401, response.status_code)
