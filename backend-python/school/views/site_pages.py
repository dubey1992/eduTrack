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
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.exceptions import NotFound
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .. import audit, site_pages
from ..enums import UserRole
from ..errors import PageBuiltIn, PageEmpty, PageLimitReached, PageNotFound
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

    @property
    def built_in(self) -> bool:
        return self.slug in site_pages.BUILT_IN_SLUGS

    @property
    def is_live(self) -> bool:
        return self.published_title is not None and self.published_body is not None

    @property
    def has_unpublished_changes(self) -> bool:
        return not self.is_live or (self.title, self.body) != (self.published_title, self.published_body)


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

    slugs = [page.slug for page in every_page() if page.is_live]
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
        new={"slug": row.slug, "title": row.title, "body": row.body},
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
    form = SitePageRequest(data=request.data, current=page.slug)
    form.is_valid(raise_exception=True)
    data = form.validated_data
    row = page.row or materialise(page.slug, request.user)
    old_slug = row.slug

    row.title = data["title"]
    row.body = data.get("body", row.body)
    row.slug = data.get("slug", row.slug)
    row.updated_at = timezone.now()

    try:
        with transaction.atomic():
            row.save(update_fields=["slug", "title", "body", "updated_at"])
    except IntegrityError:
        raise serializers.ValidationError({"slug": ["That address is already used by another page."]})

    if row.slug != old_slug:
        forget(old_slug, row.slug)

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

    row.published_title = row.title
    row.published_body = row.body
    row.published_at = now
    row.published_by_id = request.user.id
    row.updated_at = now
    row.save(update_fields=["published_title", "published_body", "published_at", "published_by", "updated_at"])
    forget(row.slug)

    audit.record(
        action="site_page.published",
        module="settings",
        entity_type="site_page",
        entity_id=row.pk,
        school_id=None,
        old=before,
        new={"title": row.title, "body": row.body},
    )

    return Response(resource(from_row(row)))
