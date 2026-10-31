"""The public website's own pages (docs/site-pages.md).

Two audiences, the same split as the homepage's words. Anybody may read a
published page at /pages/<slug> - it is what the website serves at
school365ai.com/<slug>, so it has to be readable by somebody who will never
sign in. Only a Super Admin may see drafts, write, publish or delete, under
/site-pages.

A page is a row, except for the three built-in ones, which exist before
anybody saves them (school/site_pages.py). Everything below works on a
`Page` - the row's columns, or the built-in's shipped text where there is
no row yet - so neither the public endpoint nor the editor has to care
which it is looking at.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass

from django.core.cache import cache
from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import serializers
from django.http import Http404, HttpResponse
from rest_framework.decorators import api_view, parser_classes, permission_classes, throttle_classes
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .. import audit, photos, public_site, site_pages
from ..enums import UserRole
from ..errors import PageBuiltIn, PageEmpty, PageLimitReached, PageNeedsSummary, PageNotFound
from ..models import SitePage
from ..policies import authorize
from ..requests import SitePageRequest
from ..throttling import SitePageThrottle

# Long, because a page changes when somebody publishes and not otherwise -
# and every change a visitor could see clears it rather than waiting it out.
CACHE_SECONDS = 60 * 60

# Cached in place of a page that is not there, so a script asking for
# made-up addresses is answered from the cache rather than the database.
MISSING = "missing"


@dataclass
class Page:
    """A page as it stands, whether or not it has a row yet."""

    slug: str
    title: str
    body: str
    published_title: str | None
    published_body: str | None
    published_at: dt.datetime | None
    updated_at: dt.datetime | None
    row: SitePage | None
    # A page, blog post or help article, and the details those carry - each
    # a draft and a published copy (docs/seo.md, S5).
    kind: str = site_pages.PAGE
    summary: str | None = None
    published_summary: str | None = None
    author: str | None = None
    published_author: str | None = None
    topic: str | None = None
    published_topic: str | None = None
    cover_path: str | None = None
    published_cover_path: str | None = None

    @property
    def details(self) -> tuple:
        return (self.summary, self.author, self.topic, self.cover_path)

    @property
    def published_details(self) -> tuple:
        return (self.published_summary, self.published_author, self.published_topic, self.published_cover_path)

    @property
    def built_in(self) -> bool:
        return self.slug in site_pages.BUILT_IN_SLUGS

    @property
    def is_live(self) -> bool:
        return self.published_title is not None and self.published_body is not None

    @property
    def has_unpublished_changes(self) -> bool:
        return not self.is_live or (self.title, self.body, *self.details) != (
            self.published_title, self.published_body, *self.published_details
        )


def from_row(row: SitePage) -> Page:
    return Page(
        slug=row.slug,
        title=row.title,
        body=row.body,
        published_title=row.published_title,
        published_body=row.published_body,
        published_at=row.published_at,
        updated_at=row.updated_at,
        row=row,
        kind=row.kind or site_pages.PAGE,
        summary=row.summary,
        published_summary=row.published_summary,
        author=row.author,
        published_author=row.published_author,
        topic=row.topic,
        published_topic=row.published_topic,
        cover_path=row.cover_path,
        published_cover_path=row.published_cover_path,
    )


def from_default(page: site_pages.BuiltIn) -> Page:
    """A built-in page nobody has saved: its shipped text, live or not."""
    live = page.live_by_default

    return Page(
        slug=page.slug,
        title=page.title,
        body=page.body,
        published_title=page.title if live else None,
        published_body=page.body if live else None,
        published_at=page.published_at if live else None,
        updated_at=None,
        row=None,
    )


def find(slug: str) -> Page | None:
    row = SitePage.objects.filter(slug=slug).first()

    if row is not None:
        return from_row(row)

    default = site_pages.built_in(slug)

    return from_default(default) if default is not None else None


def every_page() -> list[Page]:
    """The built-ins in their own order, then everybody else's by title."""
    rows = {row.slug: row for row in SitePage.objects.all()}
    pages = []

    for default in site_pages.BUILT_INS:
        row = rows.pop(default.slug, None)
        pages.append(from_row(row) if row is not None else from_default(default))

    custom = sorted(rows.values(), key=lambda row: (row.title.lower(), row.slug))

    return pages + [from_row(row) for row in custom]


def iso(value: dt.datetime | None) -> str | None:
    return None if value is None else value.isoformat()


def summary(page: Page) -> dict:
    return {
        "slug": page.slug,
        # The draft's title: what the Super Admin is working on.
        "title": page.title,
        "kind": page.kind,
        # Where visitors read it once it is live: /about, /blog/x, /help/y.
        "path": site_pages.path_of(page.kind, page.slug),
        "built_in": page.built_in,
        "is_live": page.is_live,
        "published_at": iso(page.published_at),
        "has_unpublished_changes": page.has_unpublished_changes,
        "updated_at": iso(page.updated_at),
    }


def resource(page: Page) -> dict:
    return {
        **summary(page),
        "body": page.body,
        "summary": page.summary,
        "author": page.author,
        "topic": page.topic,
        "has_cover": page.cover_path is not None,
        "published_title": page.published_title if page.is_live else None,
        "published_body": page.published_body if page.is_live else None,
    }


# -- the public side ----------------------------------------------------------


@api_view(["GET"])
@permission_classes([AllowAny])
@throttle_classes([SitePageThrottle])
def public(request, slug: str) -> Response:
    """The published version of one page, and nothing of its draft."""
    page = published(slug)

    if page is None:
        raise PageNotFound()

    return Response({"page": page})


def published(slug: str) -> dict | None:
    """What visitors read at this address, or None.

    Cached per address, the absence included. An address that could never
    be a page is turned away before the cache, so nobody can fill it with
    keys by asking for nonsense.
    """
    if len(slug) > site_pages.SLUG_MAX or not site_pages.SLUG_PATTERN.match(slug):
        return None

    cached = cache.get(cache_key(slug))

    if cached == MISSING:
        return None

    if cached is not None:
        return cached

    page = find(slug)
    answer = None

    if page is not None and page.is_live:
        answer = {
            "slug": page.slug,
            "title": page.published_title,
            "body": page.published_body,
            "published_at": iso(page.published_at),
        }

    cache.set(cache_key(slug), MISSING if answer is None else answer, CACHE_SECONDS)

    return answer


def cache_key(slug: str) -> str:
    return f"site-page:{slug}"


LIVE_SLUGS_KEY = "site-pages:live"


def live_slugs() -> list[str]:
    """Every address a visitor can read a page at, cached like the pages.

    The homepage hides footer links to the rest (docs/seo.md, S1): a link
    to "page not available" is a dead link to a visitor and to a crawler.
    """
    cached = cache.get(LIVE_SLUGS_KEY)

    if cached is not None:
        return cached

    live = [page for page in every_page() if page.is_live]
    slugs = [page.slug for page in live if page.kind == site_pages.PAGE]
    # /blog and /help are pages too, once there is a post or an article.
    for kind, index in ((site_pages.POST, "blog"), (site_pages.HELP, "help")):
        if any(page.kind == kind for page in live):
            slugs.append(index)
    cache.set(LIVE_SLUGS_KEY, slugs, CACHE_SECONDS)

    return slugs


def forget(*slugs: str) -> None:
    """Called whenever what visitors would see at an address changes."""
    for slug in slugs:
        cache.delete(cache_key(slug))

    cache.delete(LIVE_SLUGS_KEY)


# -- the Super Admin's side ---------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    """Every page, or a new one.

    Not paginated: there are at most site_pages.MAX_PAGES of them, and the
    editor shows them all in one list.
    """
    authorize(request.user.role == UserRole.SUPER_ADMIN)

    if request.method == "GET":
        return Response({"data": [summary(page) for page in every_page()]})

    if page_count() >= site_pages.MAX_PAGES:
        raise PageLimitReached(site_pages.MAX_PAGES)

    form = SitePageRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    now = timezone.now()

    try:
        with transaction.atomic():
            # A draft only: nothing is in front of visitors until somebody
            # publishes it.
            row = SitePage.objects.create(
                slug=data["slug"],
                title=data["title"],
                body=data.get("body", ""),
                kind=data["kind"],
                summary=data.get("summary"),
                author=data.get("author"),
                topic=data.get("topic"),
                created_by_id=request.user.id,
                created_at=now,
                updated_at=now,
            )
    except IntegrityError:
        # Two people taking the same address at the same moment; the
        # unique key caught what the request's check could not.
        raise serializers.ValidationError({"slug": ["That address is already used by another page."]})

    # A visitor may have asked for this address before it existed.
    forget(row.slug)

    audit.record(
        action="site_page.created",
        module="settings",
        entity_type="site_page",
        entity_id=row.pk,
        school_id=None,
        new={"slug": row.slug, "kind": row.kind, "title": row.title, "body": row.body},
    )

    return Response(resource(from_row(row)), status=201)


def page_count() -> int:
    """Every page there is, counting a built-in nobody has saved yet."""
    saved_built_ins = SitePage.objects.filter(slug__in=site_pages.BUILT_IN_SLUGS).count()

    return SitePage.objects.count() + len(site_pages.BUILT_IN_SLUGS) - saved_built_ins


@api_view(["GET", "PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, slug: str) -> Response:
    authorize(request.user.role == UserRole.SUPER_ADMIN)

    page = find(slug)

    if page is None:
        raise NotFound()

    if request.method == "PUT":
        page = save_draft(request, page)
    elif request.method == "DELETE":
        delete(page)
        return Response(status=204)

    return Response(resource(page))


def save_draft(request, page: Page) -> Page:
    """Saves the draft and, for a custom page, its address.

    The public page does not change: a draft is invisible until it is
    published. A new address is the exception, effective at once - the old
    one stops answering and the new one starts.
    """
    form = SitePageRequest(data=request.data, current=page.slug, kind=page.kind)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    row = page.row or materialise(page.slug, request.user)
    old_slug = row.slug

    row.title = data["title"]
    row.body = data.get("body", row.body)
    row.slug = data.get("slug", row.slug)
    for detail in ("summary", "author", "topic"):
        if detail in data:
            setattr(row, detail, data[detail])
    row.updated_at = timezone.now()

    try:
        with transaction.atomic():
            row.save(update_fields=["slug", "title", "body", "summary", "author", "topic", "updated_at"])
    except IntegrityError:
        raise serializers.ValidationError({"slug": ["That address is already used by another page."]})

    if row.slug != old_slug:
        forget(old_slug, row.slug)
        # A published page moves to its new address at once.
        public_site.rebuild()

        audit.record(
            action="site_page.renamed",
            module="settings",
            entity_type="site_page",
            entity_id=row.pk,
            school_id=None,
            old={"slug": old_slug},
            new={"slug": row.slug},
        )

    return from_row(row)


def materialise(slug: str, user) -> SitePage:
    """The row for a built-in page nobody has saved yet.

    Seeded with what visitors already read, so saving a draft of the
    privacy policy does not change the privacy policy - only publishing
    does.
    """
    default = from_default(site_pages.built_in(slug))
    now = timezone.now()

    try:
        with transaction.atomic():
            return SitePage.objects.create(
                slug=slug,
                title=default.title,
                body=default.body,
                published_title=default.published_title,
                published_body=default.published_body,
                published_at=default.published_at,
                created_by_id=user.id,
                created_at=now,
                updated_at=now,
            )
    except IntegrityError:
        # Somebody else saved it first; theirs is the row now.
        return SitePage.objects.get(slug=slug)


def delete(page: Page) -> None:
    if page.built_in:
        raise PageBuiltIn()

    row = page.row
    old = {
        "slug": row.slug,
        "title": row.title,
        "body": row.body,
        "published_title": row.published_title,
        "published_body": row.published_body,
        "published_at": row.published_at,
    }
    pk = row.pk

    row.delete()
    forget(page.slug)
    public_site.rebuild()

    for path in {row.cover_path, row.published_cover_path} - {None}:
        photos.remove(path)

    audit.record(
        action="site_page.deleted",
        module="settings",
        entity_type="site_page",
        entity_id=pk,
        school_id=None,
        old=old,
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def publish(request, slug: str) -> Response:
    """Puts the draft in front of visitors.

    One explicit act, audited with the text before and after: "who changed
    the privacy policy, and when" is a question with legal weight.
    """
    authorize(request.user.role == UserRole.SUPER_ADMIN)

    page = find(slug)

    if page is None:
        raise NotFound()

    if not page.body.strip():
        raise PageEmpty()

    row = page.row or materialise(page.slug, request.user)
    before = {"title": row.published_title, "body": row.published_body}
    now = timezone.now()

    if row.kind in (site_pages.POST, site_pages.HELP) and not (row.summary or "").strip():
        raise PageNeedsSummary()

    replaced_cover = row.published_cover_path

    row.published_title = row.title
    row.published_body = row.body
    row.published_summary = row.summary
    row.published_author = row.author
    row.published_topic = row.topic
    row.published_cover_path = row.cover_path
    row.published_at = now
    row.published_by_id = request.user.id
    row.updated_at = now
    row.save(update_fields=[
        "published_title", "published_body", "published_summary", "published_author", "published_topic",
        "published_cover_path", "published_at", "published_by", "updated_at",
    ])

    # A cover the post no longer shows, and that is not its draft either.
    if replaced_cover and replaced_cover not in (row.cover_path, row.published_cover_path):
        photos.remove(replaced_cover)
    forget(row.slug)
    website_problem = public_site.rebuild()

    audit.record(
        action="site_page.published",
        module="settings",
        entity_type="site_page",
        entity_id=row.pk,
        school_id=None,
        old=before,
        new={"title": row.title, "body": row.body},
    )

    # Null, or why the plain-HTML page could not be written (docs/seo.md):
    # the publish itself stands either way.
    return Response({**resource(from_row(row)), "website_problem": website_problem})


# -- a blog post's cover image (docs/seo.md, S5) ------------------------------------

# A cover is a share picture as well as a header, and those are 1200 x 630.
COVER_SIDE = 1600
COVER_BYTES = 5 * 1024 * 1024
COVER_FOLDER = "site-covers"


@api_view(["GET", "POST", "DELETE"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser, JSONParser])
def cover(request, slug: str):
    """A post's draft cover: the Super Admin's preview of it, a new one, or
    none. Like the text, a new cover reaches visitors when it is published."""
    authorize(request.user.role == UserRole.SUPER_ADMIN)

    page = find(slug)

    if page is None:
        raise NotFound()

    if request.method == "GET":
        stored = photos.read(page.cover_path)

        if stored is None:
            raise Http404

        data, content_type = stored
        response = HttpResponse(data, content_type=content_type)
        response["Cache-Control"] = "private, no-cache"

        return response

    if page.kind != site_pages.POST:
        raise ValidationError({"cover": ["Only a blog post has a cover image."]})

    row = page.row or materialise(page.slug, request.user)
    old = row.cover_path

    if request.method == "DELETE":
        row.cover_path = None
    else:
        try:
            data, extension = photos.prepare(
                request.FILES.get("cover"), max_side=COVER_SIDE, max_bytes=COVER_BYTES, noun="cover image"
            )
        except photos.PhotoRejected as rejected:
            raise ValidationError({"cover": [str(rejected)]})

        row.cover_path = photos.store(data, extension, folder=COVER_FOLDER)

    row.updated_at = timezone.now()
    row.save(update_fields=["cover_path", "updated_at"])

    # The old draft cover goes, unless visitors are still looking at it.
    if old and old != row.published_cover_path:
        photos.remove(old)

    audit.record(
        action="site_page.cover_changed" if request.method == "POST" else "site_page.cover_removed",
        module="settings",
        entity_type="site_page",
        entity_id=row.pk,
        school_id=None,
        new={"slug": row.slug},
    )

    return Response(resource(from_row(row)))

