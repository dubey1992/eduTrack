"""The public website as plain HTML (docs/seo.md, S2).

Search engines cannot read the Flutter app's canvas, so the homepage and
every published Website Page are written out as HTML into the web root, and
rewritten whenever either is published. These cover what is written, the
links in it, the page-text conversion, and the publish hooks.
"""

from __future__ import annotations

import ast
import io
import re
import tempfile
from pathlib import Path
from unittest import mock

from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, marketing_copy, public_site, site_markup, tokens
from school.enums import UserRole
from school.models import MarketingContent

DART_DEFAULTS = Path(__file__).resolve().parents[3] / "frontend" / "lib" / "features" / "marketing" / "data" / "marketing_defaults.dart"


def dart_map(source: str, name: str):
    """A const map literal from the Dart file, read as Python: the two
    languages write these strings and maps the same way."""
    start = source.index("{", source.index(">", source.index(f"const {name} =")))
    depth = 0

    for end in range(start, len(source)):
        depth += {"{": 1, "}": -1}.get(source[end], 0)
        if depth == 0:
            break

    return ast.literal_eval(re.sub(r"^\s*//.*$", "", source[start : end + 1], flags=re.M))


class TheCopyMatchesTheApps(SimpleTestCase):
    def test_the_server_says_exactly_what_the_app_says(self):
        source = DART_DEFAULTS.read_text(encoding="utf-8")

        self.assertEqual(dart_map(source, "marketingDefaults"), marketing_copy.TEXT)
        self.assertEqual(dart_map(source, "marketingListDefaults"), marketing_copy.LISTS)

    def test_a_blank_override_or_an_empty_list_means_the_default(self):
        words = marketing_copy.Words({"hero.headline": "  ", "features.items": [], "hero.body": "Ours."})

        self.assertEqual(marketing_copy.TEXT["hero.headline"], words.text("hero.headline"))
        self.assertEqual(marketing_copy.LISTS["features.items"], words.list("features.items"))
        self.assertEqual("Ours.", words.text("hero.body"))


class PageText(SimpleTestCase):
    def test_headings_lists_dividers_and_paragraphs(self):
        html = site_markup.to_html(
            "# Who we are\nA team.\nIn Pune.\n\n- one\n* two\n\n1. first\n2. second\n---\n### Small"
        )

        self.assertEqual(
            "<h2>Who we are</h2>\n<p>A team.<br>\nIn Pune.</p>\n<ul><li>one</li><li>two</li></ul>\n"
            "<ol><li>first</li><li>second</li></ol>\n<hr>\n<h4>Small</h4>",
            html,
        )

    def test_bold_and_links(self):
        html = site_markup.inline("**Read** the [privacy policy](/privacy) or [mail us](mailto:a@b.co)")

        self.assertEqual(
            '<strong>Read</strong> the <a href="/privacy">privacy policy</a> or <a href="mailto:a@b.co">mail us</a>',
            html,
        )

    def test_another_site_opens_in_a_new_tab_and_ours_does_not(self):
        self.assertIn('rel="noopener" target="_blank"', site_markup.inline("[x](https://example.com)"))
        self.assertNotIn("target", site_markup.inline("[x](https://school365ai.com/about)"))

    def test_typed_markup_is_only_ever_words(self):
        html = site_markup.to_html('<script>alert(1)</script> & "quotes"')

        self.assertEqual("<p>&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quotes&quot;</p>", html)

    def test_a_link_that_would_not_pass_now_is_left_as_its_words(self):
        self.assertEqual("click", site_markup.inline("[click](javascript:void)"))

    def test_a_quote_in_an_address_cannot_break_out_of_it(self):
        html = site_markup.inline('[x](https://example.com/a"onmouseover="b)')

        self.assertNotIn('"onmouseover', html)


class Links(SimpleTestCase):
    LIVE = {"about", "privacy"}

    def test_each_kind_of_address_goes_where_it_belongs_here(self):
        cases = {
            "/login": "/app/#/login",
            "https://school365ai.com/features": "/#features",
            "/contact": "/#contact",
            "/about": "/about",
            "https://www.school365ai.com/privacy": "/privacy",
            "https://school365ai.com/": "/",
            "https://example.com/x": "https://example.com/x",
            "mailto:hello@school365ai.com": "mailto:hello@school365ai.com",
        }

        for url, expected in cases.items():
            with self.subTest(url=url):
                self.assertEqual(expected, public_site.href(url, self.LIVE))

    def test_a_link_to_an_unpublished_page_leads_nowhere_and_the_rest_do(self):
        self.assertFalse(public_site.leads_somewhere("https://school365ai.com/careers", self.LIVE))
        self.assertFalse(public_site.leads_somewhere("/terms", self.LIVE))

        for url in ("/about", "/login", "https://school365ai.com/features", "https://example.com/careers", None):
            with self.subTest(url=url):
                self.assertTrue(public_site.leads_somewhere(url, self.LIVE))

    def test_a_search_snippet_is_plain_words_cut_at_a_word(self):
        body = "# Hello\nWe run **schools** - see [our page](/about).\n" + "word " * 60

        snippet = public_site.summary(body)

        self.assertTrue(snippet.startswith("Hello We run schools - see our page."))
        self.assertLessEqual(len(snippet), 158)
        self.assertTrue(snippet.endswith("..."))


class Building(TestCase):
    def setUp(self):
        cache.clear()
        self.root = Path(tempfile.mkdtemp())

    def build(self, server_files=False):
        return public_site.build(self.root, server_files=server_files)

    def read(self, name: str) -> str:
        return (self.root / name).read_text(encoding="utf-8")

    def test_every_file_is_written(self):
        written = self.build()

        for name in ("index.html", "404.html", "sitemap.xml", "robots.txt", "site/site.css", "site/site.js",
                     "favicon.png", "og-image.png", "site/pages/about.html", "site/pages/privacy.html"):
            with self.subTest(name=name):
                self.assertIn(name, written)
                self.assertTrue((self.root / name).exists())

        self.assertNotIn(".htaccess", written)
        self.assertFalse((self.root / "site/pages/terms.html").exists())

    def test_the_htaccess_only_from_the_deploy_command(self):
        self.assertIn(".htaccess", self.build(server_files=True))
        self.assertIn("ErrorDocument 404 /404.html", self.read(".htaccess"))

    def test_the_homepage_is_readable_text_with_what_was_published(self):
        MarketingContent.objects.create(document={"hero.headline": "Schools, <run> better"})

        self.build()
        home = self.read("index.html")

        self.assertIn("<h1>Schools, &lt;run&gt; better</h1>", home)
        self.assertIn("Powerful Features for Modern Schools", home)
        self.assertIn('<link rel="canonical" href="https://school365ai.com/">', home)
        self.assertIn('<script src="/site/site.js"></script>', home)
        self.assertNotIn("<script>", home)

    def test_its_buttons_open_the_app_and_dead_footer_links_are_left_out(self):
        self.build()
        home = self.read("index.html")

        # The two forms open on the page itself, never in the app.
        self.assertIn('href="#request-a-demo"', home)
        self.assertIn('href="#join-early-access"', home)
        self.assertNotIn("?open=", home)
        self.assertIn('<dialog class="form-dialog" id="request-a-demo"', home)
        self.assertIn('<dialog class="form-dialog" id="join-early-access"', home)
        self.assertIn('data-api="https://api.school365ai.com/api/v1"', home)
        self.assertIn('href="/app/#/login"', home)
        self.assertIn(">About Us</a>", home)
        self.assertNotIn("Careers", home)
        self.assertNotIn("Help Center", home)
        # Promises the plain page does not make: a newsletter that stores
        # nothing, and a video that does not exist.
        self.assertNotIn("Stay Updated", home)
        self.assertNotIn("Watch Video", home)

    def test_every_page_carries_the_forms_with_the_fields_the_api_wants(self):
        self.build()

        for name in ("index.html", "site/pages/about.html", "404.html"):
            with self.subTest(name=name):
                page = self.read(name)
                self.assertIn('data-endpoint="/demo-requests"', page)
                self.assertIn('data-endpoint="/early-access"', page)

        home = self.read("index.html")
        for field in ("contact_name", "school_name", "email", "phone", "country", "preferred_date", "preferred_time"):
            self.assertIn(f'id="demo-{field}"', home)
        for field in ("school_name", "contact_name", "email", "phone", "city", "country", "current_software"):
            self.assertIn(f'id="join-{field}"', home)

    def test_the_homepage_names_the_two_apps_that_exist(self):
        self.build()
        home = self.read("index.html")

        self.assertIn("<h3>School365ai</h3>", home)
        self.assertIn("<h3>School365ai Driver</h3>", home)
        self.assertNotIn("parents, teachers, students", home)

    def test_the_web_root_lets_the_forms_reach_the_api_and_sends_www_away(self):
        htaccess = (public_site.ASSETS / "htaccess").read_text(encoding="utf-8")

        self.assertIn("connect-src 'self' https://api.school365ai.com;", htaccess)
        self.assertIn("RewriteCond %{HTTP_HOST} ^www\.(.+)$ [NC]", htaccess)

    def test_a_page_reads_its_published_text_not_its_draft(self):
        self.build()
        privacy = self.read("site/pages/privacy.html")

        self.assertIn("<h1>Privacy Policy</h1>", privacy)
        self.assertIn('<link rel="canonical" href="https://school365ai.com/privacy">', privacy)
        self.assertIn("<title>Privacy Policy - School365ai</title>", privacy)

    def test_a_page_no_longer_published_stops_answering(self):
        (self.root / "site/pages").mkdir(parents=True)
        (self.root / "site/pages/old-news.html").write_text("gone")

        self.build()

        self.assertFalse((self.root / "site/pages/old-news.html").exists())

    def test_the_sitemap_lists_the_homepage_and_each_page_and_robots_points_at_it(self):
        self.build()
        sitemap = self.read("sitemap.xml")

        self.assertIn("<loc>https://school365ai.com/</loc>", sitemap)
        self.assertIn("<loc>https://school365ai.com/about</loc>", sitemap)
        self.assertNotIn("/terms", sitemap)
        self.assertIn("Disallow: /app/", self.read("robots.txt"))
        self.assertIn("Sitemap: https://school365ai.com/sitemap.xml", self.read("robots.txt"))

    def test_the_not_found_page_is_never_indexed(self):
        self.build()

        self.assertIn('<meta name="robots" content="noindex">', self.read("404.html"))


class Publishing(TestCase):
    """Publishing rewrites the files at once; failing to never undoes it."""

    def setUp(self):
        cache.clear()
        self.root = Path(tempfile.mkdtemp())
        self.settings_override = override_settings(PUBLIC_SITE_DIR=str(self.root))
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))
        )

    def test_publishing_a_page_writes_it_and_deleting_it_takes_it_away(self):
        self.client.post("/api/v1/site-pages", {"slug": "careers", "title": "Careers", "body": "Join us."}, format="json")

        response = self.client.post("/api/v1/site-pages/careers/publish")

        self.assertEqual(200, response.status_code)
        self.assertIsNone(response.data["website_problem"])
        self.assertIn("Join us.", (self.root / "site/pages/careers.html").read_text(encoding="utf-8"))

        self.client.delete("/api/v1/site-pages/careers")

        self.assertFalse((self.root / "site/pages/careers.html").exists())

    def test_publishing_the_homepage_rewrites_it(self):
        self.client.put("/api/v1/marketing-content/draft", {"document": {"hero.headline": "A new headline"}}, format="json")

        response = self.client.post("/api/v1/marketing-content/publish")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIn("A new headline", (self.root / "index.html").read_text(encoding="utf-8"))

    def test_a_failure_to_write_is_reported_and_the_publish_still_stands(self):
        self.client.post("/api/v1/site-pages", {"slug": "careers", "title": "Careers", "body": "Join us."}, format="json")

        with mock.patch("school.public_site.build", side_effect=OSError("disk full")):
            response = self.client.post("/api/v1/site-pages/careers/publish")

        self.assertEqual(200, response.status_code)
        self.assertEqual("The website pages could not be updated: disk full", response.data["website_problem"])
        self.assertTrue(response.data["is_live"])

    @override_settings(PUBLIC_SITE_DIR="")
    def test_nothing_is_written_where_no_directory_is_set(self):
        self.assertIsNone(public_site.rebuild())
        self.assertEqual([], list(self.root.iterdir()))


class TheCommand(TestCase):
    def test_it_writes_the_site_and_its_htaccess(self):
        root = Path(tempfile.mkdtemp())

        call_command("build_public_site", "--to", str(root), stdout=io.StringIO())

        self.assertTrue((root / "index.html").exists())
        self.assertTrue((root / ".htaccess").exists())

    @override_settings(PUBLIC_SITE_DIR="")
    def test_with_nowhere_to_write_it_refuses_unless_asked_to_skip(self):
        with self.assertRaises(CommandError):
            call_command("build_public_site", stdout=io.StringIO())

        out = io.StringIO()
        call_command("build_public_site", "--if-configured", stdout=out)

        self.assertIn("not written", out.getvalue())
