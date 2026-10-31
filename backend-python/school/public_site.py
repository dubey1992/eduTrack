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
    site/blog/index.html     the blog, served at /blog; each post at /blog/<slug>
    site/help/index.html     the help centre, at /help; each article at /help/<slug>
    site/covers/...          the published blog posts' cover images
    site/site.css, site.js   the pages' styles, and the old-link forwarder
    site/hero-app.jpg        the homepage's screenshot of the app
    sitemap.xml, robots.txt  for crawlers
    favicon.png, og-image.png
    .htaccess                only from the build_public_site command (deploy)

`PUBLIC_SITE_DIR` names the web root. Unset - development and tests by
default - and nothing is written.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from dataclasses import dataclass, replace
from pathlib import Path

from django.conf import settings
from django.template.loader import render_to_string
from django.utils.safestring import mark_safe

from . import dates, photos, site_markup
from . import site_pages as kinds
from .marketing_copy import Words

logger = logging.getLogger(__name__)

ASSETS = Path(__file__).resolve().parent / "public_site_assets"
PAGES_DIR = Path("site") / "pages"
BLOG_DIR = Path("site") / "blog"
HELP_DIR = Path("site") / "help"
COVERS_DIR = Path("site") / "covers"

# Where the app lives, under the same domain.
APP = "/app/"

# The homepage's own sections, by the names old links use (/features,
# ?section=features) and the anchors this page gives them.
SECTIONS = {
    "features": "features",
    "for-schools": "for-schools",
    "mobile-app": "mobile-app",
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
    # Set on a page about one part of the product (school/module_pages.py).
    blurb: str | None = None
    # A page, blog post or help article, and what those carry (docs/seo.md, S5).
    kind: str = kinds.PAGE
    summary: str | None = None
    author: str | None = None
    topic: str | None = None
    # A published post's cover, in the private media storage; and where the
    # build put its public copy.
    cover_path: str | None = None
    cover_url: str | None = None

    @property
    def path(self) -> str:
        return kinds.path_of(self.kind, self.slug)

    @property
    def date(self) -> str | None:
        return dates.us(self.published_at) if self.published_at else None

    @property
    def topic_name(self) -> str:
        return kinds.TOPIC_NAMES.get(self.topic or "", "")


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
    published = [
        PublicPage(
            page.slug, page.published_title, page.published_body, page.published_at, blurb_of(page.slug),
            kind=page.kind, summary=page.published_summary, author=page.published_author,
            topic=page.published_topic, cover_path=page.published_cover_path,
        )
        for page in site_pages.every_page()
        if page.is_live
    ]
    pages = [page for page in published if page.kind == kinds.PAGE]
    # Newest first: a blog is read from the top.
    posts = sorted((page for page in published if page.kind == kinds.POST), key=newest_first)
    articles = [page for page in published if page.kind == kinds.HELP]
    modules = [page for page in pages if page.blurb]
    live = {page.slug for page in pages} | ({"blog"} if posts else set()) | ({"help"} if articles else set())
    written: list[str] = []

    def write(relative: Path | str, content: str | bytes) -> None:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_bytes(content.encode("utf-8") if isinstance(content, str) else content)
        os.replace(temporary, path)
        written.append(str(relative).replace(os.sep, "/"))

    words = Words(document)
    write("index.html", render_home(words, live, modules))

    for page in pages:
        write(PAGES_DIR / f"{page.slug}.html", render_page(page, words, live, modules))

    # A page unpublished or renamed stops answering at its old address.
    for stale in (root / PAGES_DIR).glob("*.html"):
        if stale.stem not in live:
            stale.unlink()

    # -- the blog (docs/seo.md, S5) --
    covers = set()
    with_covers = []
    for post in posts:
        stored = photos.read(post.cover_path) if post.cover_path else None
        if stored is not None:
            data, content_type = stored
            # Named by what is in it, so a new cover is a new address and no
            # browser keeps showing the old one.
            extension = "png" if content_type == "image/png" else "jpg"
            name = f"{post.slug}-{hashlib.sha256(data).hexdigest()[:12]}.{extension}"
            write(COVERS_DIR / name, data)
            covers.add(name)
            post = replace(post, cover_url=f"/{COVERS_DIR.as_posix()}/{name}")
        with_covers.append(post)
    posts = with_covers

    for post in posts:
        write(BLOG_DIR / f"{post.slug}.html", render_post(post, posts, words, live))
    if posts:
        write(BLOG_DIR / "index.html", render_blog(posts, words, live))

    # -- the help centre --
    for article in articles:
        write(HELP_DIR / f"{article.slug}.html", render_article(article, articles, words, live))
    if articles:
        write(HELP_DIR / "index.html", render_help(articles, words, live))

    keep = {
        BLOG_DIR: {f"{post.slug}.html" for post in posts} | ({"index.html"} if posts else set()),
        HELP_DIR: {f"{article.slug}.html" for article in articles} | ({"index.html"} if articles else set()),
        COVERS_DIR: covers,
    }
    for folder, names in keep.items():
        for stale in (root / folder).glob("*"):
            if stale.is_file() and stale.name not in names:
                stale.unlink()

    write("404.html", render_not_found(words, live))
    write("sitemap.xml", render_sitemap(pages, posts, articles))
    write("robots.txt", render_robots())

    for name in ("site.css", "site.js", "hero-app.jpg"):
        write(Path("site") / name, (ASSETS / name).read_bytes())

    for name in ("favicon.png", "og-image.png", "logo.png"):
        write(name, (ASSETS / name).read_bytes())

    if server_files:
        write(".htaccess", (ASSETS / "htaccess").read_bytes())

    return written


def newest_first(page: PublicPage):
    return -(page.published_at.timestamp() if page.published_at else 0), page.title.lower()


def blurb_of(slug: str) -> str | None:
    """The card line of a module page (school/module_pages.py), or None."""
    from . import site_pages as built_ins

    page = built_ins.built_in(slug)

    return page.blurb if page is not None else None


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


def render_home(words: Words, live: set[str], modules: list[PublicPage]) -> str:
    return render_to_string(
        "public_site/home.html",
        {
            **shared(words, live),
            "modules": modules,
            "structured_data": structured([*about_us(), product()]),
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


def render_page(page: PublicPage, words: Words, live: set[str], modules: list[PublicPage]) -> str:
    return render_to_string(
        "public_site/page.html",
        {
            **shared(words, live),
            # A module page invites a demo and points at the other parts.
            "is_module": bool(page.blurb),
            "structured_data": structured(
                [breadcrumbs(page), *([faq(pairs)] if (pairs := faq_pairs(page.body)) else [])]
            ),
            "other_modules": [module for module in modules if module.slug != page.slug],
            "canonical": site_url() + page.path,
            "title": f"{page.title} - School365ai",
            "description": summary(page.body),
            "page_title": page.title,
            "body_html": site_markup.to_html(page.body),
            "updated": dates.us(page.published_at) if page.published_at else None,
        },
    )


def render_blog(posts: list[PublicPage], words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/blog_index.html",
        {
            **shared(words, live),
            "canonical": site_url() + "/blog",
            "title": "Blog - School365ai",
            "description": "Ideas and practical advice on running a school: attendance, fees, school transport, "
                           "teaching and keeping families informed.",
            "posts": posts,
            "structured_data": structured([
                {"@type": "Blog", "name": "School365ai Blog", "url": site_url() + "/blog"},
            ]),
        },
    )


def render_post(post: PublicPage, posts: list[PublicPage], words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/post.html",
        {
            **shared(words, live),
            "canonical": site_url() + post.path,
            "title": f"{post.title} - School365ai",
            "description": post.summary or summary(post.body),
            "og_image": site_url() + post.cover_url if post.cover_url else None,
            "og_type": "article",
            "post": post,
            "body_html": site_markup.to_html(post.body),
            "more": [other for other in posts if other.slug != post.slug][:3],
            "structured_data": structured([
                breadcrumbs(post, ("Blog", "/blog")),
                article_data(post, "BlogPosting"),
            ]),
        },
    )


def render_help(articles: list[PublicPage], words: Words, live: set[str]) -> str:
    topics = [
        {"key": key, "name": name, "articles": sorted(
            (article for article in articles if article.topic == key), key=lambda article: article.title.lower()
        )}
        for key, name in kinds.HELP_TOPICS
    ]

    return render_to_string(
        "public_site/help_index.html",
        {
            **shared(words, live),
            "canonical": site_url() + "/help",
            "title": "Help Centre - School365ai",
            "description": "Step-by-step help with School365ai: setting up a school, attendance, fees, "
                           "school transport, teaching reports, the staff and Driver apps, and more.",
            "topics": [topic for topic in topics if topic["articles"]],
        },
    )


def render_article(article: PublicPage, articles: list[PublicPage], words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/help_article.html",
        {
            **shared(words, live),
            "canonical": site_url() + article.path,
            "title": f"{article.title} - School365ai Help",
            "description": article.summary or summary(article.body),
            "article": article,
            "body_html": site_markup.to_html(article.body),
            "related": sorted(
                (other for other in articles if other.topic == article.topic and other.slug != article.slug),
                key=lambda other: other.title.lower(),
            ),
            "structured_data": structured([
                breadcrumbs(article, ("Help Centre", "/help")),
                article_data(article, "Article"),
            ]),
        },
    )


def render_not_found(words: Words, live: set[str]) -> str:
    return render_to_string(
        "public_site/not_found.html",
        {**shared(words, live), "canonical": None, "title": "Page not found - School365ai", "description": ""},
    )


# -- structured data (docs/seo.md, S4) -----------------------------------------
#
# schema.org descriptions search engines read beside the page: who publishes
# the site, what the product is, where a page sits, and a page's questions
# and answers. Only what is true and on the page - no ratings, reviews or
# prices, because there are none to report.


def structured(blocks: list[dict]) -> list[str]:
    """Each block as JSON for a <script type="application/ld+json">.

    `<` is escaped, so nothing typed into a page - a question with "</script>"
    in it - can end the block early.
    """
    return [
        mark_safe(json.dumps({"@context": "https://schema.org", **block}, ensure_ascii=False).replace("<", "\\u003c"))
        for block in blocks
    ]


def about_us() -> list[dict]:
    return [
        {
            "@type": "Organization",
            "name": "School365ai",
            "legalName": kinds.OFFICE[0],
            "url": site_url() + "/",
            "logo": site_url() + "/logo.png",
            "email": kinds.SUPPORT_EMAIL,
            "telephone": kinds.SUPPORT_PHONE,
            "address": {
                "@type": "PostalAddress",
                "streetAddress": kinds.OFFICE[1],
                "addressLocality": "Gurgaon",
                "addressRegion": "Haryana",
                "postalCode": "122002",
                "addressCountry": "IN",
            },
            "contactPoint": {
                "@type": "ContactPoint",
                "contactType": "customer support",
                "telephone": kinds.SUPPORT_PHONE,
                "email": kinds.SUPPORT_EMAIL,
                "availableLanguage": "English",
            },
        },
        {"@type": "WebSite", "name": "School365ai", "url": site_url() + "/"},
    ]


def product() -> dict:
    return {
        "@type": "SoftwareApplication",
        "name": "School365ai",
        "url": site_url() + "/",
        "applicationCategory": "BusinessApplication",
        "applicationSubCategory": "School management software",
        "operatingSystem": "Web, Android",
        "description": (
            "School management software for attendance, fees, school bus tracking, timetables, "
            "teaching reports, payroll, parent alerts and reports."
        ),
        "publisher": {"@type": "Organization", "name": "School365ai", "url": site_url() + "/"},
    }


def breadcrumbs(page: PublicPage, *between: tuple[str, str]) -> dict:
    """Home, then [between] (name, path), then the page itself."""
    trail = [("Home", "/"), *between, (page.title, page.path)]

    return {
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": n, "name": name, "item": site_url() + path}
            for n, (name, path) in enumerate(trail, start=1)
        ],
    }


def article_data(page: PublicPage, kind: str) -> dict:
    """A blog post as a BlogPosting, a help article as an Article."""
    publisher = {
        "@type": "Organization",
        "name": "School365ai",
        "logo": {"@type": "ImageObject", "url": site_url() + "/logo.png"},
    }
    data = {
        "@type": kind,
        "headline": page.title,
        "description": page.summary or summary(page.body),
        "mainEntityOfPage": site_url() + page.path,
        "publisher": publisher,
        "image": site_url() + (page.cover_url or "/og-image.png"),
    }

    if page.published_at:
        data["datePublished"] = page.published_at.isoformat()

    if page.author:
        # The team is the organisation; anybody else is a person.
        data["author"] = (
            {"@type": "Organization", "name": page.author, "url": site_url() + "/"}
            if page.author == kinds.DEFAULT_AUTHOR
            else {"@type": "Person", "name": page.author}
        )
    else:
        data["author"] = {"@type": "Organization", "name": "School365ai", "url": site_url() + "/"}

    return data


def faq(pairs: list[tuple[str, str]]) -> dict:
    return {
        "@type": "FAQPage",
        "mainEntity": [
            {"@type": "Question", "name": question, "acceptedAnswer": {"@type": "Answer", "text": answer}}
            for question, answer in pairs
        ],
    }


FAQ_HEADING = re.compile(r"^##\s+(frequently asked questions|faqs?|questions)\s*$", re.IGNORECASE)


def faq_pairs(body: str) -> list[tuple[str, str]]:
    """The questions and answers in a page's "## Frequently asked questions"
    section: each `### question`, with the plain text of what follows it up
    to the next heading as its answer. A question with no answer is left
    out - structured data must match what the page says."""
    pairs: list[tuple[str, str]] = []
    in_section = False
    question: str | None = None
    answer: list[str] = []

    def close():
        if question and " ".join(answer).strip():
            pairs.append((plain(question), plain(" ".join(answer))))

    for line in (body or "").replace("\r\n", "\n").split("\n"):
        stripped = line.strip()

        if stripped.startswith("## ") or stripped.startswith("# "):
            close()
            question, answer = None, []
            in_section = bool(FAQ_HEADING.match(stripped))
            continue

        if not in_section:
            continue

        if stripped.startswith("### "):
            close()
            question, answer = stripped[4:].strip(), []
        elif question is not None and stripped:
            answer.append(stripped)

    close()

    return pairs


def plain(text: str) -> str:
    """Page-text marks taken off: link words kept, bold marks gone."""
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = text.replace("**", "")

    return re.sub(r"\s+", " ", text).strip()


def render_sitemap(pages: list[PublicPage], posts=(), articles=()) -> str:
    def entry(path: str, page: PublicPage | None = None) -> dict:
        published = page.published_at if page else None
        return {"loc": site_url() + path, "lastmod": published.date().isoformat() if published else None}

    entries = [entry("/")]
    entries += [entry(page.path, page) for page in pages]

    if posts:
        entries.append(entry("/blog", posts[0]))
        entries += [entry(post.path, post) for post in posts]

    if articles:
        entries.append(entry("/help"))
        entries += [entry(article.path, article) for article in articles]

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
