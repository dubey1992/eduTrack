"""Live platform figures in the hero (docs/marketing-content.md, slice 4).

A figure under the hero is either what the Super Admin typed or a count of
something real. The choice is per figure, so a platform with three schools
can keep "500+ (Target)" on the board and swap one over when the real
number is worth showing - without a deploy.

The rule everything here turns on: **a count of nothing falls back to the
typed figure.** A front page saying "0 Schools" helps nobody, and the
typed value is already sitting there saying "500+ (Target)".
"""

from __future__ import annotations

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, marketing, tokens
from school.enums import SchoolStatus, StudentStatus, UserRole
from school.models import MarketingContent
from school.views import marketing_content

DRAFT = "/api/v1/marketing-content/draft"
PUBLISH = "/api/v1/marketing-content/publish"
PUBLIC = "/api/v1/marketing-content"


def typed(value: str, label: str) -> dict:
    return {"source": marketing.TYPED, "value": value, "label": label}


def live(source: str, fallback: str, label: str) -> dict:
    return {"source": source, "value": fallback, "label": label}


class CountingThePlatform(TestCase):
    def setUp(self):
        cache.clear()

    def test_an_empty_platform_counts_nothing(self):
        self.assertEqual({marketing.SCHOOLS: 0, marketing.STUDENTS: 0}, marketing_content.figures())

    def test_it_counts_the_schools_using_the_product(self):
        factories.SchoolFactory()
        factories.SchoolFactory()

        self.assertEqual(2, marketing_content.figures()[marketing.SCHOOLS])

    def test_a_school_that_was_switched_off_is_not_counted(self):
        factories.SchoolFactory()
        factories.SchoolFactory(status=SchoolStatus.INACTIVE)

        self.assertEqual(1, marketing_content.figures()[marketing.SCHOOLS])

    def test_a_branch_counts_as_a_school(self):
        """The word on the page is "schools", and four buildings running
        the product are four schools by any ordinary reading - whatever
        they are on an invoice."""
        parent = factories.SchoolFactory()
        factories.SchoolFactory(parent_school=parent)

        self.assertEqual(2, marketing_content.figures()[marketing.SCHOOLS])

    def test_it_counts_the_students_on_the_platform(self):
        school = factories.SchoolFactory()
        factories.StudentFactory(school=school)
        factories.StudentFactory(school=school)

        self.assertEqual(2, marketing_content.figures()[marketing.STUDENTS])

    def test_a_student_who_has_left_is_not_counted(self):
        school = factories.SchoolFactory()
        factories.StudentFactory(school=school)
        factories.StudentFactory(school=school, status=StudentStatus.INACTIVE)

        self.assertEqual(1, marketing_content.figures()[marketing.STUDENTS])

    def test_students_of_a_school_that_was_switched_off_are_nobodys_students(self):
        off = factories.SchoolFactory(status=SchoolStatus.INACTIVE)
        factories.StudentFactory(school=off)

        self.assertEqual(0, marketing_content.figures()[marketing.STUDENTS])


class PuttingTheCountsIntoThePage(TestCase):
    """[marketing.resolve] on its own - the rule the page, the preview and
    the editor's hint all follow."""

    def test_a_typed_figure_is_left_alone(self):
        document = {marketing.STATS: [typed("500+", "Schools")]}

        self.assertEqual(document, marketing.resolve(document, {marketing.SCHOOLS: 12}))

    def test_a_live_figure_is_replaced_by_the_count(self):
        document = {marketing.STATS: [live(marketing.SCHOOLS, "500+", "Schools")]}

        resolved = marketing.resolve(document, {marketing.SCHOOLS: 12})

        self.assertEqual("12", resolved[marketing.STATS][0]["value"])

    def test_a_big_count_is_grouped_so_it_can_be_read(self):
        document = {marketing.STATS: [live(marketing.STUDENTS, "1M+", "Students")]}

        resolved = marketing.resolve(document, {marketing.STUDENTS: 1248})

        self.assertEqual("1,248", resolved[marketing.STATS][0]["value"])

    def test_a_count_of_nothing_falls_back_to_what_was_typed(self):
        """A front page saying "0 Schools" helps nobody."""
        document = {marketing.STATS: [live(marketing.SCHOOLS, "500+", "Schools")]}

        resolved = marketing.resolve(document, {marketing.SCHOOLS: 0})

        self.assertEqual("500+", resolved[marketing.STATS][0]["value"])

    def test_the_label_and_the_source_are_untouched(self):
        document = {marketing.STATS: [live(marketing.SCHOOLS, "500+", "Schools")]}

        resolved = marketing.resolve(document, {marketing.SCHOOLS: 12})[marketing.STATS][0]

        self.assertEqual("Schools", resolved["label"])
        self.assertEqual(marketing.SCHOOLS, resolved["source"])

    def test_the_rest_of_the_document_comes_through_unchanged(self):
        document = {"hero.headline": "Keep me", marketing.STATS: [typed("500+", "Schools")]}

        self.assertEqual("Keep me", marketing.resolve(document, {})[("hero.headline")])

    def test_a_document_with_no_figures_is_handed_back_as_it_came(self):
        for document in ({}, {"hero.headline": "Only words"}, {marketing.STATS: "nonsense"}):
            self.assertEqual(document, marketing.resolve(document, {marketing.SCHOOLS: 12}))

    def test_an_item_that_is_not_an_object_is_left_where_it_is(self):
        """Nothing stores a shape like this, but resolving is also what the
        preview runs over whatever is on screen."""
        document = {marketing.STATS: ["nonsense"]}

        self.assertEqual(document, marketing.resolve(document, {marketing.SCHOOLS: 12}))


class WhatAVisitorSees(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.admin = APIClient()
        self.admin.credentials(
            HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))
        )

    def publish(self, stats):
        self.admin.put(DRAFT, {"document": {marketing.STATS: stats}}, format="json")
        self.admin.post(PUBLISH)

    def stats(self):
        return self.client.get(PUBLIC).data["document"][marketing.STATS]

    def test_the_page_is_handed_the_count_rather_than_told_to_work_it_out(self):
        """A visitor's browser never counts anything, and the page is never
        told which figures are live."""
        factories.SchoolFactory()
        factories.SchoolFactory()
        self.publish([live(marketing.SCHOOLS, "500+", "Schools")])
        marketing_content.forget()

        self.assertEqual("2", self.stats()[0]["value"])

    def test_a_typed_figure_reaches_the_page_as_it_was_typed(self):
        factories.SchoolFactory()
        self.publish([typed("500+", "Schools")])
        marketing_content.forget()

        self.assertEqual("500+", self.stats()[0]["value"])

    def test_switching_a_figure_back_to_typed_stops_the_counting(self):
        factories.SchoolFactory()
        self.publish([live(marketing.SCHOOLS, "500+", "Schools")])
        marketing_content.forget()
        self.assertEqual("1", self.stats()[0]["value"])

        self.publish([typed("500+", "Schools")])

        self.assertEqual("500+", self.stats()[0]["value"])

    def test_counting_happens_once_an_hour_rather_than_once_a_visitor(self):
        """The figure is cached with the document that uses it, so a busy
        homepage asks nothing of the database."""
        factories.SchoolFactory()
        self.publish([live(marketing.SCHOOLS, "500+", "Schools")])
        marketing_content.forget()
        self.client.get(PUBLIC)

        with self.assertNumQueries(0):
            self.assertEqual("1", self.stats()[0]["value"])

    def test_a_school_signing_up_shows_within_the_hour_not_at_once(self):
        """The trade this makes, pinned so it is a decision rather than a
        surprise. Publishing clears the cache; nothing else does."""
        factories.SchoolFactory()
        self.publish([live(marketing.SCHOOLS, "500+", "Schools")])
        marketing_content.forget()
        self.assertEqual("1", self.stats()[0]["value"])

        factories.SchoolFactory()

        self.assertEqual("1", self.stats()[0]["value"], "still the cached count")

        marketing_content.forget()

        self.assertEqual("2", self.stats()[0]["value"])

    def test_an_empty_platform_shows_the_target_rather_than_a_zero(self):
        self.publish([live(marketing.SCHOOLS, "500+", "Schools (Target)")])
        marketing_content.forget()

        self.assertEqual("500+", self.stats()[0]["value"])

    def test_what_is_stored_is_the_choice_not_the_number(self):
        """Otherwise publishing would freeze the count into the document
        and the figure would stop being live."""
        factories.SchoolFactory()
        self.publish([live(marketing.SCHOOLS, "500+", "Schools")])

        stored = MarketingContent.objects.get().document[marketing.STATS][0]

        self.assertEqual("500+", stored["value"])
        self.assertEqual(marketing.SCHOOLS, stored["source"])


class WhatTheEditorIsTold(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))
        )

    def test_it_is_told_what_each_live_figure_would_say_today(self):
        """So the Super Admin can see the real number before deciding to
        put it on the front page."""
        factories.SchoolFactory()

        self.assertEqual({marketing.SCHOOLS: 1, marketing.STUDENTS: 0}, self.client.get(DRAFT).data["figures"])

    def test_the_sources_are_offered_as_a_picker(self):
        sections = {section["key"]: section for section in self.client.get(DRAFT).data["sections"]}
        source = sections["hero"]["lists"][0]["fields"][0]

        self.assertEqual(
            [choice.value for choice in marketing.STAT_SOURCES],
            [choice["value"] for choice in source["choices"]],
        )

    def test_typing_it_yourself_is_the_first_choice(self):
        """A newly added figure gets the first one, and a platform with
        three schools would rather say "500+ (Target)" than "3"."""
        self.assertEqual(marketing.TYPED, marketing.STAT_SOURCES[0].value)

    def test_a_source_nobody_recognises_is_refused(self):
        response = self.client.put(
            DRAFT,
            {"document": {marketing.STATS: [live("teachers", "500+", "Teachers")]}},
            format="json",
        )

        self.assertEqual(422, response.status_code)

    def test_a_live_figure_still_needs_a_typed_one_to_fall_back_to(self):
        response = self.client.put(
            DRAFT,
            {"document": {marketing.STATS: [{"source": marketing.SCHOOLS, "value": "", "label": "Schools"}]}},
            format="json",
        )

        self.assertEqual(422, response.status_code)
        self.assertIn(
            "The figures under the hero, figure 1 needs a figure.",
            [str(problem) for problem in response.data["details"]["errors"]["document"]],
        )


class NobodyElseMaySeeTheCounts(TestCase):
    def setUp(self):
        cache.clear()

    def test_the_public_page_is_handed_figures_not_counts_to_run(self):
        """The counts are platform-wide numbers; the public endpoint hands
        over only the figures somebody chose to publish."""
        factories.SchoolFactory()
        MarketingContent.objects.create(
            document={}, created_at=timezone.now(), updated_at=timezone.now()
        )
        marketing_content.forget()

        body = APIClient().get(PUBLIC).data

        self.assertNotIn("figures", body)

    def test_a_school_administrator_may_not_read_the_counts(self):
        client = APIClient()
        client.credentials(
            HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=UserRole.SCHOOL_ADMIN))
        )

        self.assertEqual(403, client.get(DRAFT).status_code)
