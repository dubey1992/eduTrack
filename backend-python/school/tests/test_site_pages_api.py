"""The website's own pages: About Us, the privacy policy, the terms, and
whatever else the Super Admin adds (docs/site-pages.md).

Three things are pinned here. Only a Super Admin writes, publishes or
deletes - there is no school to fall back on, so the role check is the
whole of the protection. The draft never leaks: visitors read what was
published until somebody publishes again. And the built-in pages always
exist, keep their addresses, and cannot be deleted.
"""

from __future__ import annotations

from django.core.cache import cache
from django.test import SimpleTestCase, TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, module_pages, site_pages, tokens
from school.enums import UserRole
from school.models import AuditLog, SitePage
from school.views import site_pages as site_pages_view

ADMIN = "/api/v1/site-pages"


def public(slug: str) -> str:
    return f"/api/v1/pages/{slug}"


def detail(slug: str) -> str:
    return f"{ADMIN}/{slug}"


def publish_url(slug: str) -> str:
    return f"{ADMIN}/{slug}/publish"


def signed_in_as(role) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=role)))

    return client


EVERYONE_ELSE = [role for role in UserRole if role != UserRole.SUPER_ADMIN]


class WhoMayDoWhat(TestCase):
    def setUp(self):
        cache.clear()
        SitePage.objects.create(
            slug="careers", title="Careers", body="Join us.", created_at=timezone.now(), updated_at=timezone.now()
        )

    def test_a_super_admin_may_do_everything(self):
        client = signed_in_as(UserRole.SUPER_ADMIN)

        self.assertEqual(200, client.get(ADMIN).status_code)
        self.assertEqual(
            201, client.post(ADMIN, {"slug": "help", "title": "Help", "body": "Ask."}, format="json").status_code
        )
        self.assertEqual(200, client.get(detail("help")).status_code)
        self.assertEqual(200, client.put(detail("help"), {"title": "Help", "body": "Ask us."}, format="json").status_code)
        self.assertEqual(200, client.post(publish_url("help")).status_code)
        self.assertEqual(204, client.delete(detail("help")).status_code)

    def test_nobody_else_may_touch_the_editor(self):
        """A school administrator runs their own school; the product's own
        website is not theirs to change - nor a Group Admin's."""
        self.assertIn(UserRole.GROUP_ADMIN, EVERYONE_ELSE)

        for role in EVERYONE_ELSE:
            client = signed_in_as(role)

            self.assertEqual(403, client.get(ADMIN).status_code, role)
            self.assertEqual(403, client.post(ADMIN, {"slug": "x-y", "title": "X"}, format="json").status_code, role)
            self.assertEqual(403, client.get(detail("careers")).status_code, role)
            self.assertEqual(403, client.put(detail("careers"), {"title": "Mine"}, format="json").status_code, role)
            self.assertEqual(403, client.delete(detail("careers")).status_code, role)
            self.assertEqual(403, client.post(publish_url("careers")).status_code, role)

        self.assertEqual("Careers", SitePage.objects.get(slug="careers").title)
        self.assertFalse(SitePage.objects.filter(slug="x-y").exists())

    def test_refused_even_for_an_address_that_does_not_exist(self):
        """Asked before looking, so the answer does not say which pages exist."""
        self.assertEqual(403, signed_in_as(UserRole.SCHOOL_ADMIN).get(detail("nothing-here")).status_code)

    def test_a_visitor_who_is_not_signed_in_may_not(self):
        client = APIClient()

        self.assertEqual(401, client.get(ADMIN).status_code)
        self.assertEqual(401, client.post(ADMIN, {"slug": "x-y", "title": "X"}, format="json").status_code)
        self.assertEqual(401, client.get(detail("careers")).status_code)
        self.assertEqual(401, client.put(detail("careers"), {"title": "Mine"}, format="json").status_code)
        self.assertEqual(401, client.delete(detail("careers")).status_code)
        self.assertEqual(401, client.post(publish_url("careers")).status_code)

    def test_anybody_may_read_a_published_page(self):
        self.assertEqual(200, APIClient().get(public("privacy")).status_code)

        for role in EVERYONE_ELSE:
            self.assertEqual(200, signed_in_as(role).get(public("privacy")).status_code, role)

    def test_the_public_address_only_reads(self):
        client = signed_in_as(UserRole.SUPER_ADMIN)

        for method in (client.post, client.put, client.patch, client.delete):
            self.assertEqual(405, method(public("about")).status_code)


class TheBuiltInPagesByDefault(TestCase):
    """The state the product ships in: an empty table."""

    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def test_about_us_is_live_with_no_date(self):
        response = self.client.get(public("about"))

        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {"slug": "about", "title": "About Us", "body": site_pages.ABOUT_BODY, "published_at": None},
            response.data["page"],
        )

    def test_the_privacy_policy_is_live_with_its_own_date(self):
        page = self.client.get(public("privacy")).data["page"]

        self.assertEqual("Privacy Policy", page["title"])
        self.assertEqual("2026-10-26T00:00:00+00:00", page["published_at"])
        self.assertIn("Bus positions are deleted after 30 days.", page["body"])

    def test_the_terms_are_not_live_until_somebody_fills_them_in(self):
        """Their text has blanks only the operator can fill in."""
        response = self.client.get(public("terms"))

        self.assertEqual(404, response.status_code)
        self.assertEqual("PAGE_NOT_FOUND", response.data["code"])
        self.assertEqual("This page is not available.", response.data["message"])

    def test_the_shipped_text_passes_its_own_validation(self):
        for page in site_pages.BUILT_INS:
            self.assertEqual([], site_pages.link_problems(page.body), page.slug)
            self.assertLessEqual(len(page.body), site_pages.MAX_BODY)

    def test_the_terms_keep_their_blanks_and_link_to_the_privacy_page(self):
        self.assertIn("[COMPANY LEGAL NAME]", site_pages.TERMS_BODY)
        self.assertIn("[Privacy Policy](/privacy)", site_pages.TERMS_BODY)
        self.assertNotIn("Last updated", site_pages.TERMS_BODY)

    def test_the_editor_lists_them_first_and_in_order(self):
        SitePage.objects.create(slug="zeta", title="alpha page", body="", created_at=timezone.now(), updated_at=timezone.now())
        SitePage.objects.create(slug="alpha", title="Zeta page", body="", created_at=timezone.now(), updated_at=timezone.now())

        data = signed_in_as(UserRole.SUPER_ADMIN).get(ADMIN).data["data"]

        modules = [module.slug for module in module_pages.MODULES]
        built_ins = 3 + len(modules)

        self.assertEqual(["about", "privacy", "terms", *modules, "zeta", "alpha"], [page["slug"] for page in data])
        self.assertEqual(
            {"slug", "title", "built_in", "is_live", "published_at", "has_unpublished_changes", "updated_at"},
            set(data[0]),
        )
        self.assertEqual([True] * built_ins + [False, False], [page["built_in"] for page in data])
        # The terms wait for their blanks; every module page is live from the start.
        self.assertEqual([True, True, False] + [True] * len(modules) + [False, False], [page["is_live"] for page in data])
        self.assertEqual(
            [False, False, True] + [False] * len(modules) + [True, True], [page["has_unpublished_changes"] for page in data]
        )

    def test_a_built_in_page_opens_in_the_editor_without_a_row(self):
        page = signed_in_as(UserRole.SUPER_ADMIN).get(detail("terms")).data

        self.assertEqual("Terms of Use", page["title"])
        self.assertEqual(site_pages.TERMS_BODY, page["body"])
        self.assertIsNone(page["published_title"])
        self.assertIsNone(page["published_body"])
        self.assertIsNone(page["updated_at"])
        self.assertFalse(SitePage.objects.exists())


class CreatingAPage(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = factories.UserFactory(role=UserRole.SUPER_ADMIN)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))

    def create(self, **payload):
        return self.client.post(ADMIN, payload, format="json")

    def errors(self, response, field):
        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("VALIDATION_ERROR", response.data["code"])

        return response.data["details"]["errors"][field]

    def test_a_new_page_is_a_draft_nobody_can_read_yet(self):
        response = self.create(slug="help-center", title="Help Center", body="Ask us anything.")

        self.assertEqual(201, response.status_code)
        self.assertEqual("help-center", response.data["slug"])
        self.assertEqual("Ask us anything.", response.data["body"])
        self.assertFalse(response.data["is_live"])
        self.assertFalse(response.data["built_in"])
        self.assertTrue(response.data["has_unpublished_changes"])
        self.assertIsNone(response.data["published_title"])
        self.assertEqual(self.admin.id, SitePage.objects.get(slug="help-center").created_by_id)
        self.assertEqual(404, APIClient().get(public("help-center")).status_code)

    def test_the_body_may_be_left_out_or_empty(self):
        self.assertEqual("", self.create(slug="later", title="Later").data["body"])
        self.assertEqual(201, self.create(slug="later-too", title="Later", body="").status_code)

    def test_it_is_written_to_the_audit_trail(self):
        self.create(slug="careers", title="Careers", body="Join us.")

        entry = AuditLog.objects.get(action="site_page.created")
        self.assertEqual(self.admin.id, entry.user_id)
        self.assertIsNone(entry.school_id)
        self.assertEqual("settings", entry.module)
        self.assertEqual("site_page", entry.entity_type)
        self.assertEqual(SitePage.objects.get(slug="careers").pk, entry.entity_id)
        self.assertEqual({"slug": "careers", "title": "Careers", "body": "Join us."}, entry.new_values)

    def test_an_address_asked_for_before_it_existed_is_not_stuck_as_missing(self):
        """The 404 is cached; creating and publishing must clear it."""
        self.assertEqual(404, APIClient().get(public("careers")).status_code)

        self.create(slug="careers", title="Careers", body="Join us.")
        self.client.post(publish_url("careers"))

        self.assertEqual(200, APIClient().get(public("careers")).status_code)

    def test_the_title_is_required_and_capped(self):
        self.assertEqual(["The title field is required."], self.errors(self.create(slug="ok-page", title="  "), "title"))
        self.assertEqual(
            ["The title field must not be greater than 120 characters."],
            self.errors(self.create(slug="ok-page", title="x" * 121), "title"),
        )

    def test_the_title_is_trimmed(self):
        self.assertEqual("Careers", self.create(slug="careers", title="  Careers  ").data["title"])

    def test_the_address_is_required(self):
        self.assertEqual(["The slug field is required."], self.errors(self.create(title="No address"), "slug"))

    def test_an_address_must_be_lowercase_words_and_single_hyphens(self):
        for slug in ("Help", "help center", "help--center", "-help", "help-", "help_center", "help/center", "hélp"):
            self.assertEqual(
                ["Use lowercase letters, numbers and single hyphens, e.g. help-center."],
                self.errors(self.create(slug=slug, title="Help"), "slug"),
                slug,
            )

    def test_an_address_must_be_two_to_sixty_characters(self):
        self.assertEqual(
            ["An address must be 2 to 60 characters long."], self.errors(self.create(slug="a", title="A"), "slug")
        )
        self.assertEqual(
            ["An address must be 2 to 60 characters long."],
            self.errors(self.create(slug="a" * 61, title="A"), "slug"),
        )
        self.assertEqual(201, self.create(slug="a" * 60, title="A").status_code)
        self.assertEqual(201, self.create(slug="ab", title="A").status_code)

    def test_an_address_the_app_already_uses_is_reserved(self):
        for slug in ("login", "dashboard", "api", "pages", "contact", "site-pages", "404"):
            self.assertEqual(
                ["That address is reserved by the app. Choose another."],
                self.errors(self.create(slug=slug, title="Mine"), "slug"),
                slug,
            )

    def test_an_address_another_page_has_is_taken(self):
        self.create(slug="careers", title="Careers")

        self.assertEqual(
            ["That address is already used by another page."],
            self.errors(self.create(slug="careers", title="Again"), "slug"),
        )

    def test_a_built_in_page_s_address_is_taken_even_without_a_row(self):
        for slug in site_pages.BUILT_IN_SLUGS:
            self.assertEqual(
                ["That address is already used by another page."],
                self.errors(self.create(slug=slug, title="Mine"), "slug"),
                slug,
            )

    def test_every_problem_comes_back_at_once(self):
        response = self.create(slug="Bad Slug", title="", body="[a](javascript:alert(1)) [b](ftp://x)")

        errors = response.data["details"]["errors"]
        self.assertEqual({"slug", "title", "body"}, set(errors))
        self.assertEqual(2, len(errors["body"]))

    def test_a_script_link_is_refused_naming_the_link(self):
        errors = self.errors(self.create(slug="bad", title="Bad", body="Hello [Click here](javascript:alert(1))"), "body")

        self.assertEqual(
            [
                'The link "Click here" can\'t be used: an address has to start with https://, http://, '
                "a / for a page of this site, or mailto: or tel:."
            ],
            errors,
        )

    def test_ordinary_links_are_accepted(self):
        body = (
            "[web](https://example.com) [plain](http://example.com) [mail](mailto:hello@example.com) "
            "[phone](tel:+15551234) [page](/privacy) [home](/)"
        )

        self.assertEqual(201, self.create(slug="links", title="Links", body=body).status_code)

    def test_an_empty_or_spaced_link_is_refused(self):
        errors = self.errors(self.create(slug="bad", title="Bad", body="[nothing]() [space](/a b)"), "body")

        self.assertEqual(1, len(errors), "an address with a space is not a link at all")

    def test_the_text_is_capped(self):
        errors = self.errors(self.create(slug="long", title="Long", body="x" * (site_pages.MAX_BODY + 1)), "body")

        self.assertEqual(["The page text must be 100,000 characters or fewer - it is 100,001."], errors)
        self.assertEqual(201, self.create(slug="long", title="Long", body="x" * site_pages.MAX_BODY).status_code)

    def test_fifty_pages_is_the_limit_built_ins_included(self):
        now = timezone.now()
        SitePage.objects.bulk_create(
            SitePage(slug=f"page-{n}", title=f"Page {n}", body="", created_at=now, updated_at=now) for n in range(site_pages.MAX_PAGES - len(site_pages.BUILT_IN_SLUGS))
        )

        response = self.create(slug="one-more", title="One more")

        self.assertEqual(409, response.status_code)
        self.assertEqual("PAGE_LIMIT_REACHED", response.data["code"])
        self.assertEqual(
            "There can be at most 50 website pages. Delete one you no longer need first.", response.data["message"]
        )

    def test_a_saved_built_in_is_not_counted_twice(self):
        now = timezone.now()
        SitePage.objects.bulk_create(
            SitePage(slug=f"page-{n}", title=f"Page {n}", body="", created_at=now, updated_at=now) for n in range(site_pages.MAX_PAGES - len(site_pages.BUILT_IN_SLUGS) - 1)
        )
        self.client.put(detail("about"), {"title": "About Us", "body": "Us."}, format="json")

        self.assertEqual(201, self.create(slug="the-fiftieth", title="Fiftieth").status_code)
        self.assertEqual(409, self.create(slug="the-fifty-first", title="Too many").status_code)


class SavingAndPublishing(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = factories.UserFactory(role=UserRole.SUPER_ADMIN)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))

    def save(self, page, **payload):
        return self.client.put(detail(page), payload, format="json")

    def test_a_draft_edit_is_not_visible_until_published(self):
        self.assertEqual(200, APIClient().get(public("privacy")).status_code)

        response = self.save("privacy", title="Privacy", body="A new policy.")

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.data["has_unpublished_changes"])
        self.assertTrue(response.data["is_live"])
        self.assertEqual(site_pages.PRIVACY_BODY, response.data["published_body"])
        page = APIClient().get(public("privacy")).data["page"]
        self.assertEqual("Privacy Policy", page["title"])
        self.assertEqual(site_pages.PRIVACY_BODY, page["body"])
        self.assertEqual("2026-10-26T00:00:00+00:00", page["published_at"])

    def test_publishing_puts_the_draft_live_at_once(self):
        """Cached for an hour - and publishing clears it."""
        APIClient().get(public("privacy"))
        self.save("privacy", title="Privacy", body="A new policy.")

        response = self.client.post(publish_url("privacy"))

        self.assertEqual(200, response.status_code)
        self.assertFalse(response.data["has_unpublished_changes"])
        page = APIClient().get(public("privacy")).data["page"]
        self.assertEqual({"Privacy", "A new policy."}, {page["title"], page["body"]})
        self.assertNotEqual("2026-10-26T00:00:00+00:00", page["published_at"])

    def test_publishing_makes_the_terms_live(self):
        self.assertEqual(404, APIClient().get(public("terms")).status_code)

        self.save("terms", title="Terms of Use", body="Filled in.")
        self.client.post(publish_url("terms"))

        page = APIClient().get(public("terms")).data["page"]
        self.assertEqual("Filled in.", page["body"])
        row = SitePage.objects.get(slug="terms")
        self.assertEqual(self.admin.id, row.published_by_id)

    def test_a_built_in_may_be_published_without_a_save_first(self):
        response = self.client.post(publish_url("terms"))

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.data["is_live"])
        self.assertEqual(site_pages.TERMS_BODY, APIClient().get(public("terms")).data["page"]["body"])

    def test_saving_an_unsaved_built_in_keeps_the_public_page(self):
        self.save("about", title="About", body="Draft.")

        row = SitePage.objects.get(slug="about")
        self.assertEqual("About Us", row.published_title)
        self.assertEqual(site_pages.ABOUT_BODY, row.published_body)
        self.assertEqual("About Us", APIClient().get(public("about")).data["page"]["title"])

    def test_saving_the_terms_does_not_make_them_live(self):
        self.save("terms", title="Terms of Use", body="Half filled in.")

        self.assertEqual(404, APIClient().get(public("terms")).status_code)

    def test_saving_twice_makes_one_row(self):
        self.save("about", title="One", body="1")
        self.save("about", title="Two", body="2")

        self.assertEqual(1, SitePage.objects.filter(slug="about").count())
        self.assertEqual("Two", self.client.get(detail("about")).data["title"])

    def test_a_save_without_the_body_keeps_it(self):
        self.save("about", title="About", body="Kept.")

        self.assertEqual("Kept.", self.save("about", title="About again").data["body"])

    def test_a_built_in_page_cannot_be_renamed(self):
        response = self.save("about", slug="about-us", title="About Us", body="x")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["The address of a built-in page cannot be changed."], response.data["details"]["errors"]["slug"]
        )
        self.assertFalse(SitePage.objects.filter(slug="about-us").exists())

    def test_a_built_in_page_may_send_its_own_address(self):
        self.assertEqual(200, self.save("about", slug="about", title="About Us", body="x").status_code)

    def test_publishing_an_empty_page_is_refused(self):
        self.client.post(ADMIN, {"slug": "empty", "title": "Empty", "body": "  \n "}, format="json")

        response = self.client.post(publish_url("empty"))

        self.assertEqual(409, response.status_code)
        self.assertEqual("PAGE_EMPTY", response.data["code"])
        self.assertEqual("Write something on this page before publishing it.", response.data["message"])
        self.assertEqual(404, APIClient().get(public("empty")).status_code)

    def test_publishing_is_written_to_the_audit_trail_with_before_and_after(self):
        self.save("privacy", title="Privacy", body="New.")
        self.client.post(publish_url("privacy"))

        entry = AuditLog.objects.get(action="site_page.published")
        self.assertEqual(self.admin.id, entry.user_id)
        self.assertIsNone(entry.school_id)
        self.assertEqual("site_page", entry.entity_type)
        self.assertEqual(SitePage.objects.get(slug="privacy").pk, entry.entity_id)
        self.assertEqual({"title": "Privacy Policy", "body": site_pages.PRIVACY_BODY}, entry.old_values)
        self.assertEqual({"title": "Privacy", "body": "New."}, entry.new_values)

    def test_unknown_pages_are_not_found_in_the_editor(self):
        self.assertEqual(404, self.client.get(detail("nothing")).status_code)
        self.assertEqual("NOT_FOUND", self.client.get(detail("nothing")).data["code"])
        self.assertEqual(404, self.save("nothing", title="X").status_code)
        self.assertEqual(404, self.client.delete(detail("nothing")).status_code)
        self.assertEqual(404, self.client.post(publish_url("nothing")).status_code)

    def test_the_resource_carries_what_the_editor_needs(self):
        page = self.client.get(detail("privacy")).data

        self.assertEqual(
            {
                "slug", "title", "built_in", "is_live", "published_at", "has_unpublished_changes", "updated_at",
                "body", "published_title", "published_body",
            },
            set(page),
        )


class RenamingAndDeleting(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = factories.UserFactory(role=UserRole.SUPER_ADMIN)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))
        self.client.post(ADMIN, {"slug": "careers", "title": "Careers", "body": "Join us."}, format="json")
        self.client.post(publish_url("careers"))

    def test_a_rename_moves_the_public_page_at_once(self):
        self.assertEqual(200, APIClient().get(public("careers")).status_code)
        APIClient().get(public("jobs"))  # a cached 404 that must not survive

        response = self.client.put(detail("careers"), {"slug": "jobs", "title": "Careers", "body": "Join us."}, format="json")

        self.assertEqual(200, response.status_code)
        self.assertEqual("jobs", response.data["slug"])
        self.assertEqual(404, APIClient().get(public("careers")).status_code)
        self.assertEqual("Join us.", APIClient().get(public("jobs")).data["page"]["body"])

    def test_a_rename_is_audited(self):
        self.client.put(detail("careers"), {"slug": "jobs", "title": "Careers"}, format="json")

        entry = AuditLog.objects.get(action="site_page.renamed")
        self.assertEqual({"slug": "careers"}, entry.old_values)
        self.assertEqual({"slug": "jobs"}, entry.new_values)

    def test_a_save_that_keeps_the_address_is_not_a_rename(self):
        self.client.put(detail("careers"), {"slug": "careers", "title": "Careers!"}, format="json")

        self.assertFalse(AuditLog.objects.filter(action="site_page.renamed").exists())

    def test_a_rename_onto_a_taken_or_reserved_address_is_refused(self):
        self.client.post(ADMIN, {"slug": "jobs", "title": "Jobs"}, format="json")

        for slug, message in (
            ("jobs", "That address is already used by another page."),
            ("privacy", "That address is already used by another page."),
            ("login", "That address is reserved by the app. Choose another."),
            ("Jobs!", "Use lowercase letters, numbers and single hyphens, e.g. help-center."),
        ):
            response = self.client.put(detail("careers"), {"slug": slug, "title": "Careers"}, format="json")

            self.assertEqual(422, response.status_code, slug)
            self.assertEqual([message], response.data["details"]["errors"]["slug"], slug)

    def test_deleting_a_page_takes_it_off_the_site_at_once(self):
        self.assertEqual(200, APIClient().get(public("careers")).status_code)

        self.assertEqual(204, self.client.delete(detail("careers")).status_code)

        self.assertEqual(404, APIClient().get(public("careers")).status_code)
        self.assertFalse(SitePage.objects.filter(slug="careers").exists())

    def test_deleting_is_audited_with_what_was_there(self):
        pk = SitePage.objects.get(slug="careers").pk

        self.client.delete(detail("careers"))

        entry = AuditLog.objects.get(action="site_page.deleted")
        self.assertEqual(pk, entry.entity_id)
        self.assertEqual("Join us.", entry.old_values["published_body"])
        self.assertEqual("careers", entry.old_values["slug"])

    def test_a_built_in_page_cannot_be_deleted(self):
        for slug in site_pages.BUILT_IN_SLUGS:
            response = self.client.delete(detail(slug))

            self.assertEqual(409, response.status_code, slug)
            self.assertEqual("PAGE_BUILT_IN", response.data["code"])
            self.assertEqual("Built-in pages can be edited but not deleted.", response.data["message"])

        self.client.put(detail("about"), {"title": "About", "body": "Saved."}, format="json")
        self.assertEqual(409, self.client.delete(detail("about")).status_code, "a saved one neither")
        self.assertTrue(SitePage.objects.filter(slug="about").exists())


class ThePublicCache(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def test_a_page_is_read_once_and_then_from_the_cache(self):
        self.client.get(public("privacy"))

        with self.assertNumQueries(0):
            self.assertEqual(200, self.client.get(public("privacy")).status_code)

    def test_a_missing_page_is_cached_too(self):
        self.client.get(public("no-such-page"))

        with self.assertNumQueries(0):
            self.assertEqual(404, self.client.get(public("no-such-page")).status_code)

    def test_an_address_that_could_never_be_a_page_asks_nobody(self):
        with self.assertNumQueries(0):
            response = self.client.get(public("NOT_A_SLUG"))

        self.assertEqual(404, response.status_code)
        self.assertEqual("PAGE_NOT_FOUND", response.data["code"])

    def test_a_change_behind_its_back_waits_for_the_cache(self):
        """Which is why every endpoint that changes what visitors read
        clears it - see the tests above."""
        now = timezone.now()
        row = SitePage.objects.create(
            slug="news", title="News", body="Old", published_title="News", published_body="Old",
            published_at=now, created_at=now, updated_at=now,
        )
        self.client.get(public("news"))

        row.published_body = "New"
        row.save()

        self.assertEqual("Old", self.client.get(public("news")).data["page"]["body"], "still cached")
        site_pages_view.forget("news")
        self.assertEqual("New", self.client.get(public("news")).data["page"]["body"])


class ThePrivacyPolicyKeepsItsPromises(TestCase):
    """Carried over from the Flutter screen's test when the text moved here
    (docs/driver-app.md, D6.1). These are the promises the apps actually
    keep - if one stops being true, the page is a lie, and this is where
    that gets noticed."""

    PROMISES = (
        "does not ask for background location",
        "Sharing starts when a trip starts",
        "deleted after 30 days",
        "phone number itself is never recorded",
        "Google Maps.",
        "Google Fonts.",
        "Hosting.",
        "compared with the school's pin and then thrown away",
        "never anybody's marks",
        "Firebase delivers them",
    )

    def setUp(self):
        cache.clear()

    def check(self, body: str) -> None:
        for promise in self.PROMISES:
            self.assertIn(promise, body, promise)

        self.assertIn("\n## What the School365ai app collects\n", body)

    def test_the_shipped_text_keeps_them(self):
        self.check(site_pages.PRIVACY_BODY)
        self.assertEqual("2026-10-26T00:00:00+00:00", site_pages.built_in("privacy").published_at.isoformat())

    def test_the_public_page_keeps_them_with_no_row(self):
        self.assertFalse(SitePage.objects.exists())

        page = APIClient().get(public("privacy")).data["page"]

        self.check(page["body"])
        self.assertEqual("2026-10-26T00:00:00+00:00", page["published_at"])


class TheRules(SimpleTestCase):
    """The parts of school/site_pages.py that need no database."""

    def test_slug_problems(self):
        self.assertIsNone(site_pages.slug_problem("help-center"))
        self.assertIsNone(site_pages.slug_problem("faq2"))
        self.assertIsNotNone(site_pages.slug_problem("help--center"))
        self.assertIsNotNone(site_pages.slug_problem("x"))
        self.assertEqual(
            "That address is reserved by the app. Choose another.", site_pages.slug_problem("canvaskit")
        )

    def test_no_built_in_address_is_reserved(self):
        self.assertFalse(set(site_pages.BUILT_IN_SLUGS) & site_pages.RESERVED_SLUGS)

    def test_link_problems_name_every_bad_link(self):
        problems = site_pages.link_problems("[a](javascript:x) fine [b](https://ok.example) [c](data:text/html,x)")

        self.assertEqual(2, len(problems))
        self.assertTrue(problems[0].startswith('The link "a" can\'t be used: '))
        self.assertTrue(problems[1].startswith('The link "c" can\'t be used: '))

    def test_link_problems_reuse_the_homepage_rule(self):
        self.assertEqual(
            ['The link "x" can\'t be used: that address has nothing after the ://.'],
            site_pages.link_problems("[x](https://)"),
        )

    def test_text_without_links_has_no_problems(self):
        self.assertEqual([], site_pages.link_problems("# Heading\n\n- **bold** item\n1. one\n---\n[not a link] (x)"))
