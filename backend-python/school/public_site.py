"""The public website as plain HTML files (docs/seo.md, S2).

The Flutter app paints its text on a canvas, which search engines cannot
read, and routes after a '#', which they ignore. So the public pages - the
homepage and every published Website Page - are written out here as real
HTML into the web root, and the app itself lives at /app/.

Nothing changes for whoever edits them. Homepage Content and Website Pages
stay the source of truth; publishing either rewrites these files at once.
A failure to write is logged and reported back to the editor, and never
undoes the publish.

    index.html               the homepage
    404.html                 page not found (the web server answers 404 with it)
    site/pages/<slug>.html   each published Website Page, served at /<slug>
    site/site.css, site.js   the pages' styles, and the old-link forwarder
    sitemap.xml, robots.txt  for crawlers
    favicon.png, og-image.png
    .htaccess                only from the build_public_site command (deploy)

`PUBLIC_SITE_DIR` names the web root. Unset - development and tests by
default - and nothing is written.
"""

from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass
from pathlib import Path

from django.conf import settings
from django.template.loader import render_to_string

from . import dates, site_markup
from .marketing_copy import Words

logger = logging.getLogger(__name__)

ASSETS = Path(__file__).resolve().parent / "public_site_assets"
PAGES_DIR = Path("site") / "pages"

# Where the app lives, under the same domain.
APP = "/app/"

# The homepage's own sections, by the names old links use (/features,
# ?section=features) and the anchors this page gives them.
SECTIONS = {
    "features": "features",
    "for-schools": "for-schools",
    "mobile-app": "mobile-app",
    "contact": "contact",
}

PAGE_WORD = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
OURS = re.compile(r"^https?://(www\.)?school365ai\.com(?P<path>/[^?#]*)?$")


def configured() -> bool:
    return bool(getattr(settings, "PUBLIC_SITE_DIR", ""))


def site_url() -> str:
    return getattr(settings, "PUBLIC_SITE_URL", "https://school365ai.com").rstrip("/")


def api_url() -> str:
    """Where the pages' forms send what visitors type."""
    return getattr(settings, "PUBLIC_API_URL", "https://api.school365ai.com/api/v1").rstrip("/")


@dataclass(frozen=True)
class PublicPage:
    slug: str
    title: str
    body: str
    published_at: object

    @property
    def path(self) -> str:
        return f"/{self.slug}"


def rebuild() -> str | None:
    """Rewrites the public pages, or says why it could not. Never raises:
    a publish has already happened, and a file that failed to write must
    not turn it into an error."""
    if not configured():
        return None

    try:
        build(Path(settings.PUBLIC_SITE_DIR))
    except Exception as error:  # noqa: BLE001 - reported, not swallowed
        logger.exception("The public website could not be written.")
        return f"The website pages could not be updated: {error}"

    return None


def build(root: Path, server_files: bool = False) -> list[str]:
    """Writes every public file under `root`; returns their paths."""
    from .views import marketing_content, site_pages

    document = marketing_content.published()
    pages = [
        PublicPage(page.slug, page.published_title, page.published_body, page.published_at)
        for page in site_pages.every_page()
        if page.is_live
    ]
    live = {page.slug for page in pages}
    written: list[str] = []

    def write(relative: Path | str, content: str | bytes) -> None:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_bytes(content.encode("utf-8") if isinstance(content, str) else content)
        os.replace(temporary, path)
        written.append(str(relative).replace(os.sep, "/"))

    words = Words(document)
    write("index.html", render_home(words, live))

    for page in pages:
        write(PAGES_DIR / f"{page.slug}.html", render_page(page, words, live))

    # A page unpublished or renamed stops answering at its old address.
    for stale in (root / PAGES_DIR).glob("*.html"):
        if stale.stem not in live:
            stale.unlink()

    write("404.html", render_not_found(words, live))
    write("sitemap.xml", render_sitemap(pages))
    write("robots.txt", render_robots())

    for name in ("site.css", "site.js"):
        write(Path("site") / name, (ASSETS / name).read_bytes())

    for name in ("favicon.png", "og-image.png"):
        write(name, (ASSETS / name).read_bytes())

    if server_files:
        write(".htaccess", (ASSETS / "htaccess").read_bytes())

    return written


# -- links ---------------------------------------------------------------------


def href(url: str | None, live: set[str]) -> str | None:
    """Where a link typed for the app's homepage goes on this one.

    The app's addresses were written for the app: `/login` is one of its
    screens, `/features` a section of its homepage. Here a screen is under
    /app/, a section is an anchor on this page, and a website page is its
    own plain address. Somewhere else entirely is left as it is.
    """
    if not url:
        return None

    address = url.strip()
    ours = OURS.match(address)

    if ours:
        address = ours.group("path") or "/"

    if not address.startswith("/"):
        return address

    if address == "/":
        return "/"

    word = address.strip("/")

    if word in SECTIONS:
        return f"/#{SECTIONS[word]}"

    if word in live:
        return f"/{word}"

    return APP + "#" + address


def leads_somewhere(url: str | None, live: set[str]) -> bool:
    """False for a link to a website page nobody has published - the same
    rule as the app's footer (docs/seo.md, S1)."""
    if not url:
        return True

    address = url.strip()
    ours = OURS.match(address)

    if ours:
        address = ours.group("path") or "/"
    elif not address.startswith("/") or "?" in address or "#" in address:
        return True

    word = address.strip("/")

    if "/" in word or not PAGE_WORD.match(word) or word in SECTIONS or word in ("login", "forgot-password"):
        return True

    return word in live


# -- pages ---------------------------------------------------------------------


def shared(words: Words, live: set[str]) -> dict:
    """What every page carries: the bar across the top and the footer."""
    columns = []

    for title_key, list_key in (
        ("footer.productTitle", "footer.productLinks"),
        ("footer.companyTitle", "footer.companyLinks"),
        ("footer.resourceTitle", "footer.resourceLinks"),
    ):
        links = [
            {"label": link.get("label", ""), "href": href(link.get("url"), live)}
            for link in words.list(list_key)
            if leads_somewhere(link.get("url"), live)
        ]
        columns.append({"title": words.text(title_key), "links": links})

    return {
        "site_url": site_url(),
        "app": APP,
        # The forms open on the page itself (forms.html); site.js sends them.
        "join_href": "#join-early-access",
        "demo_href": "#request-a-demo",
        "api_url": api_url(),
        "login_href": APP + "#/login",
        "about_href": "/about" if "about" in live else None,
        "nav": {
            "wordmark": words.text("nav.wordmark"),
            "tagline": words.text("nav.tagline"),
            "login": words.text("nav.login"),
            "join": words.text("nav.join"),
            "demo": words.text("nav.demo"),
        },
        "footer": {
            "wordmark": words.text("footer.wordmark"),
            "blurb": words.text("footer.blurb"),
            "copyright": words.text("footer.copyright"),
            "tagline": words.text("footer.tagline"),
            "columns": columns,
        },
    }


def render_home(words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/home.html",
        {
            **shared(words, live),
            "canonical": site_url() + "/",
            "title": "School365ai - School Management Software for Attendance, Fees and Transport",
            "description": (
                "School365ai is school management software for attendance, fees, school bus tracking, "
                "timetables, payroll, parent SMS and WhatsApp alerts, and reports - on the web and on Android."
            ),
            "hero": {
                "eyebrow": words.text("hero.eyebrow"),
                "headline": words.text("hero.headline"),
                "body": words.text("hero.body"),
                "join": words.text("hero.primaryButton"),
                "demo": words.text("hero.demoButton"),
                "trust": words.text("hero.trustLine"),
                "stats": words.list("hero.stats"),
            },
            "features": {
                "eyebrow": words.text("features.eyebrow"),
                "title": words.text("features.title"),
                "body": words.text("features.body"),
                "items": words.list("features.items"),
            },
            "mobile": {
                "eyebrow": words.text("mobile.eyebrow"),
                "headline": words.text("mobile.headline"),
                "body": words.text("mobile.body"),
            },
            "web": {
                "eyebrow": words.text("web.eyebrow"),
                "headline": words.text("web.headline"),
                "body": words.text("web.body"),
                "button": words.text("web.button"),
                "bullets": words.list("web.bullets"),
            },
            "cta": {
                "headline": words.text("cta.headline"),
                "body": words.text("cta.body"),
                "join": words.text("cta.button"),
                "demo": words.text("cta.demoButton"),
            },
        },
    )


def render_page(page: PublicPage, words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/page.html",
        {
            **shared(words, live),
            "canonical": site_url() + page.path,
            "title": f"{page.title} - School365ai",
            "description": summary(page.body),
            "page_title": page.title,
            "body_html": site_markup.to_html(page.body),
            "updated": dates.us(page.published_at) if page.published_at else None,
        },
    )


def render_not_found(words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/not_found.html",
        {**shared(words, live), "canonical": None, "title": "Page not found - School365ai", "description": ""},
    )


def render_sitemap(pages: list[PublicPage]) -> str:
    entries = [{"loc": site_url() + "/", "lastmod": None}]
    entries += [
        {"loc": site_url() + page.path, "lastmod": page.published_at.date().isoformat() if page.published_at else None}
        for page in pages
    ]

    return render_to_string("public_site/sitemap.xml", {"entries": entries})


def render_robots() -> str:
    return (
        "# school365ai.com (docs/seo.md). The app itself is not for search results.\n"
        "User-agent: *\n"
        "Disallow: /app/\n"
        f"\nSitemap: {site_url()}/sitemap.xml\n"
    )


def summary(body: str, limit: int = 155) -> str:
    """The first words of a page as plain text: its search snippet."""
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", body or "")
    text = re.sub(r"[*#>`]|^-{3,}$|^\s*[-*]\s+|^\s*\d+\.\s+", " ", text, flags=re.M)
    text = re.sub(r"\s+", " ", text).strip()

    if len(text) <= limit:
        return text

    return text[:limit].rsplit(" ", 1)[0].rstrip(",;:.") + "..."
