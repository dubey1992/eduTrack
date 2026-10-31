"""The help centre's first articles and the blog's first drafts
(docs/seo.md, S5).

They live as Markdown files in backend/database/content/site-pages and are
inserted once by a Laravel migration, past every rule the editor applies.
So the files are checked here against those same rules - an address the
editor would refuse, or a link that goes nowhere, is caught before it is
inserted where nobody would notice.
"""

from __future__ import annotations

import re
from pathlib import Path

from django.test import SimpleTestCase

from school import site_pages

CONTENT = Path(__file__).resolve().parents[3] / "backend" / "database" / "content" / "site-pages"
FRONT = re.compile(r"\A---\n(.*?)\n---\n(.*)\Z", re.S)


def read(path: Path) -> tuple[dict, str]:
    """The same reading as the migration's: `key: value` lines, then the text."""
    match = FRONT.match(path.read_text(encoding="utf-8").replace("\r\n", "\n"))
    assert match, f"{path.name} has no front matter"
    meta = {}
    for line in match.group(1).split("\n"):
        if ":" in line:
            key, value = line.split(":", 1)
            meta[key.strip()] = value.strip()

    return meta, match.group(2).strip()


class TheStarterContent(SimpleTestCase):
    def setUp(self):
        self.files = sorted(CONTENT.glob("*.md"))

    def test_there_are_help_articles_and_draft_posts(self):
        kinds = [read(path)[0].get("kind") for path in self.files]

        self.assertGreaterEqual(kinds.count("help"), 12)
        self.assertEqual(3, kinds.count("post"))

    def test_each_file_passes_the_editors_own_rules(self):
        slugs = set()

        for path in self.files:
            meta, body = read(path)
            with self.subTest(file=path.name):
                self.assertIn(meta.get("kind"), (site_pages.POST, site_pages.HELP))
                self.assertEqual(path.stem, meta.get("slug"))
                self.assertIsNone(site_pages.slug_problem(meta["slug"]))
                self.assertNotIn(meta["slug"], slugs)
                slugs.add(meta["slug"])
                self.assertTrue(0 < len(meta.get("title", "")) <= site_pages.MAX_TITLE)
                self.assertTrue(0 < len(meta.get("summary", "")) <= site_pages.MAX_SUMMARY)
                self.assertTrue(body)
                self.assertLessEqual(len(body), site_pages.MAX_BODY)
                self.assertEqual([], site_pages.link_problems(body))

                if meta["kind"] == site_pages.HELP:
                    self.assertIn(meta.get("topic"), site_pages.TOPIC_NAMES)
                    self.assertNotIn("author", meta)
                else:
                    self.assertTrue(meta.get("author"))
                    self.assertNotIn("topic", meta)

    def test_no_slug_is_taken_by_a_built_in_page(self):
        for path in self.files:
            with self.subTest(file=path.name):
                self.assertNotIn(read(path)[0]["slug"], site_pages.BUILT_IN_SLUGS)

    def test_links_between_articles_lead_to_articles_that_exist(self):
        help_slugs = {read(path)[0]["slug"] for path in self.files if read(path)[0]["kind"] == site_pages.HELP}
        pages = set(site_pages.BUILT_IN_SLUGS)

        for path in self.files:
            body = read(path)[1]
            for address in re.findall(r"\]\((/[^)]*)\)", body):
                with self.subTest(file=path.name, address=address):
                    if address.startswith("/help/"):
                        self.assertIn(address[len("/help/"):], help_slugs)
                    else:
                        self.assertIn(address.strip("/"), pages)

    def test_the_text_starts_below_the_title_and_uses_only_the_supported_marks(self):
        for path in self.files:
            body = read(path)[1]
            with self.subTest(file=path.name):
                # The title is the page's own heading; the text never repeats it.
                self.assertFalse(re.search(r"^# ", body, re.M))
                for unsupported in ("<", "![", "```", "|---"):
                    self.assertNotIn(unsupported, body)

    def test_nothing_is_promised_that_the_product_does_not_do(self):
        for path in self.files:
            text = read(path)[1].lower()
            with self.subTest(file=path.name):
                for claim in ("parent app", "student app", "ai-powered", "artificial intelligence", "payment gateway",
                              "app store", "ios app", "hall ticket"):
                    self.assertNotIn(claim, text)
