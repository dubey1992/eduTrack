"""The blog and the help centre (docs/seo.md, S5).

Both are kinds of Website Page: a blog post (/blog/<slug>) with a summary,
an author and a cover image, and a help article (/help/<slug>) with a
summary and a topic. Each detail is a draft until published, like the text.
"""

from __future__ import annotations

import io
import json
import re
import tempfile
from pathlib import Path

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from school import factories, public_site, site_pages, tokens
from school.enums import UserRole
from school.models import AuditLog, SitePage

ADMIN = "/api/v1/site-pages"
MEDIA = tempfile.mkdtemp()


def png(width=40, height=30) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", (width, height), (37, 99, 235)).save(out, format="PNG")
    return out.getvalue()


def signed_in_as(role) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(school=None, role=role)))
    return client


@override_settings(MEDIA_ROOT=MEDIA)
class BlogAndHelpTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SUPER_ADMIN)

    def create(self, **body):
        return self.client.post(ADMIN, body, format="json")

    def post(self, slug="first-post", **extra):
        body = {"slug": slug, "title": "First post", "body": "Hello.", "kind": "post", "summary": "A first post.",
                **extra}
        return self.create(**body)

    def article(self, slug="take-the-register", **extra):
        body = {"slug": slug, "title": "Take the register", "body": "Steps.", "kind": "help",
                "summary": "How to take it.", "topic": "attendance", **extra}
        return self.create(**body)

    def publish(self, slug):
        return self.client.post(f"{ADMIN}/{slug}/publish")


class Creating(BlogAndHelpTestCase):
    def test_a_post_reads_at_blog_and_signs_off_as_the_team(self):
        response = self.post()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("post", "/blog/first-post", "School365ai Team", None),
                         (response.data["kind"], response.data["path"], response.data["author"],
                          response.data["topic"]))

    def test_a_post_may_name_its_own_author(self):
        self.assertEqual("Priya Nair", self.post(author="Priya Nair").data["author"])

    def test_a_help_article_needs_a_topic_from_the_list(self):
        self.assertEqual("/help/take-the-register", self.article().data["path"])

        for topic in (None, "", "gardening"):
            with self.subTest(topic=topic):
                response = self.article(slug=f"other-{len(str(topic))}", topic=topic)
                self.assertEqual(
                    {"topic": ["Choose the help centre topic this article belongs under."]},
                    response.data["details"]["errors"],
                )

    def test_a_plain_page_carries_no_author_or_topic(self):
        response = self.create(slug="careers", title="Careers", body="Join.", author="X", topic="fees")

        self.assertEqual(("page", "/careers", None, None),
                         (response.data["kind"], response.data["path"], response.data["author"],
                          response.data["topic"]))

    def test_an_unknown_kind_is_refused(self):
        response = self.create(slug="odd", title="Odd", body="x", kind="newsletter")

        self.assertEqual(["A page is a page, a blog post or a help article."], response.data["details"]["errors"]["kind"])

    def test_the_blog_and_help_addresses_are_kept_for_themselves(self):
        for slug in ("blog", "help"):
            with self.subTest(slug=slug):
                self.assertEqual(422, self.create(slug=slug, title="T", body="x").status_code)

    def test_a_kind_never_changes_once_created(self):
        self.post()

        self.client.put(f"{ADMIN}/first-post", {"title": "First post", "body": "Hello.", "kind": "help"}, format="json")

        self.assertEqual("post", SitePage.objects.get(slug="first-post").kind)


class Publishing(BlogAndHelpTestCase):
    def test_a_post_or_article_needs_a_summary_before_it_goes_live(self):
        self.post(summary="")

        response = self.publish("first-post")

        self.assertEqual((409, "PAGE_NEEDS_SUMMARY"), (response.status_code, response.data["code"]))

    def test_its_details_are_a_draft_until_published(self):
        self.post()
        self.publish("first-post")
        self.client.put(f"{ADMIN}/first-post", {"title": "First post", "body": "Hello.", "summary": "Changed."},
                        format="json")

        row = SitePage.objects.get(slug="first-post")
        self.assertEqual(("Changed.", "A first post."), (row.summary, row.published_summary))
        self.assertTrue(self.client.get(f"{ADMIN}/first-post").data["has_unpublished_changes"])

        self.publish("first-post")

        self.assertEqual("Changed.", SitePage.objects.get(slug="first-post").published_summary)

    def test_the_footer_links_to_the_blog_and_help_once_there_is_something_in_them(self):
        pages = lambda: APIClient().get("/api/v1/marketing-content").data["pages"]  # noqa: E731

        self.assertNotIn("blog", pages())
        self.post()
        self.article()
        self.assertNotIn("blog", pages())

        self.publish("first-post")
        self.publish("take-the-register")

        self.assertIn("blog", pages())
        self.assertIn("help", pages())
        self.assertNotIn("first-post", pages())


class Covers(BlogAndHelpTestCase):
    def upload(self, slug="first-post", data=None, name="cover.png"):
        return self.client.post(
            f"{ADMIN}/{slug}/cover",
            {"cover": SimpleUploadedFile(name, data if data is not None else png(), content_type="image/png")},
            format="multipart",
        )

    def test_a_post_takes_a_cover_that_the_editor_can_see(self):
        self.post()

        response = self.upload()

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(response.data["has_cover"])
        preview = self.client.get(f"{ADMIN}/first-post/cover")
        self.assertEqual(("image/png", "private, no-cache"), (preview["Content-Type"], preview["Cache-Control"]))
        self.assertTrue(AuditLog.objects.filter(action="site_page.cover_changed").exists())

    def test_a_large_cover_is_scaled_and_re_encoded(self):
        self.post()
        self.upload(data=png(3200, 1680))

        stored = Image.open(io.BytesIO(self.client.get(f"{ADMIN}/first-post/cover").content))

        self.assertEqual((1600, 840), stored.size)

    def test_only_an_image_is_kept(self):
        self.post()

        response = self.upload(data=b"<script>alert(1)</script>", name="cover.png")

        self.assertEqual(["The cover image must be a JPEG or PNG image."], response.data["details"]["errors"]["cover"])

    def test_only_a_post_has_a_cover(self):
        self.article()

        response = self.upload(slug="take-the-register")

        self.assertEqual(["Only a blog post has a cover image."], response.data["details"]["errors"]["cover"])

    def test_a_new_draft_cover_waits_for_publishing_and_keeps_the_live_one_meanwhile(self):
        self.post()
        self.upload()
        self.publish("first-post")
        live = SitePage.objects.get(slug="first-post").published_cover_path

        self.upload(data=png(50, 50))

        row = SitePage.objects.get(slug="first-post")
        self.assertEqual(live, row.published_cover_path)
        self.assertNotEqual(live, row.cover_path)
        self.assertTrue((Path(MEDIA) / live).exists())

        self.publish("first-post")

        self.assertFalse((Path(MEDIA) / live).exists())

    def test_removing_a_cover(self):
        self.post()
        self.upload()

        response = self.client.delete(f"{ADMIN}/first-post/cover")

        self.assertFalse(response.data["has_cover"])
        self.assertEqual(404, self.client.get(f"{ADMIN}/first-post/cover").status_code)

    def test_nobody_else_touches_a_cover(self):
        self.post()

        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.TEACHER):
            with self.subTest(role=role):
                self.assertEqual(403, signed_in_as(role).get(f"{ADMIN}/first-post/cover").status_code)
        self.assertEqual(401, APIClient().get(f"{ADMIN}/first-post/cover").status_code)


LD_JSON = re.compile(r'<script type="application/ld\+json">(.*?)</script>', re.S)


class ThePublicSite(BlogAndHelpTestCase):
    def setUp(self):
        super().setUp()
        self.root = Path(tempfile.mkdtemp())

    def build(self):
        public_site.build(self.root, server_files=True)

    def read(self, name: str) -> str:
        return (self.root / name).read_text(encoding="utf-8")

    def blocks(self, name: str) -> dict:
        return {block["@type"]: block for block in (json.loads(raw) for raw in LD_JSON.findall(self.read(name)))}

    def test_a_post_with_its_cover_byline_and_structured_data(self):
        self.post(author="Priya Nair")
        self.client.post(f"{ADMIN}/first-post/cover",
                         {"cover": SimpleUploadedFile("c.png", png(), content_type="image/png")}, format="multipart")
        self.publish("first-post")
        self.build()

        page = self.read("site/blog/first-post.html")
        cover = next((self.root / "site/covers").glob("first-post-*.png"))
        self.assertIn(f'src="/site/covers/{cover.name}"', page)
        self.assertIn(f'<meta property="og:image" content="https://school365ai.com/site/covers/{cover.name}">', page)
        self.assertIn("By Priya Nair", page)
        posting = self.blocks("site/blog/first-post.html")["BlogPosting"]
        self.assertEqual(("First post", {"@type": "Person", "name": "Priya Nair"}),
                         (posting["headline"], posting["author"]))
        self.assertIn('<link rel="canonical" href="https://school365ai.com/blog/first-post">', page)

    def test_the_blog_lists_posts_newest_first_and_drafts_never(self):
        self.post("older")
        self.publish("older")
        self.post("newer")
        self.publish("newer")
        self.post("unpublished")
        SitePage.objects.filter(slug="older").update(published_at="2026-01-01T00:00:00Z")
        self.build()

        blog = self.read("site/blog/index.html")
        self.assertLess(blog.index('href="/blog/newer"'), blog.index('href="/blog/older"'))
        self.assertNotIn("unpublished", blog)
        self.assertFalse((self.root / "site/blog/unpublished.html").exists())

    def test_the_help_centre_groups_articles_by_topic(self):
        self.article()
        self.article(slug="record-a-payment", title="Record a payment", topic="fees")
        self.publish("take-the-register")
        self.publish("record-a-payment")
        self.build()

        help_home = self.read("site/help/index.html")
        self.assertLess(help_home.index('id="attendance"'), help_home.index('id="fees"'))
        self.assertNotIn('id="transport"', help_home)
        article = self.read("site/help/take-the-register.html")
        self.assertIn('<a href="/help#attendance">Attendance</a>', article)
        crumbs = self.blocks("site/help/take-the-register.html")["BreadcrumbList"]["itemListElement"]
        self.assertEqual(["Home", "Help Centre", "Take the register"], [item["name"] for item in crumbs])

    def test_the_sitemap_and_the_web_server_know_both(self):
        self.post()
        self.article()
        self.publish("first-post")
        self.publish("take-the-register")
        self.build()

        sitemap = self.read("sitemap.xml")
        for loc in ("/blog", "/blog/first-post", "/help", "/help/take-the-register"):
            self.assertIn(f"<loc>https://school365ai.com{loc}</loc>", sitemap)
        htaccess = self.read(".htaccess")
        self.assertIn("RewriteRule ^(blog|help)/?$ /site/$1/index.html [L]", htaccess)

    def test_a_deleted_post_and_its_cover_leave_the_site(self):
        self.post()
        self.client.post(f"{ADMIN}/first-post/cover",
                         {"cover": SimpleUploadedFile("c.png", png(), content_type="image/png")}, format="multipart")
        self.publish("first-post")
        self.build()
        self.assertTrue((self.root / "site/blog/index.html").exists())

        self.client.delete(f"{ADMIN}/first-post")
        self.build()

        self.assertFalse((self.root / "site/blog/first-post.html").exists())
        self.assertFalse((self.root / "site/blog/index.html").exists())
        self.assertEqual([], list((self.root / "site/covers").glob("*")))
