"""The words on the public homepage (docs/marketing-content.md).

Public on purpose, and the only endpoint in the product that is. The
homepage is served to anybody who types the address, so the words on it
have to be readable by anybody too - there is nothing here that is not
already on the page.

What comes back is only what somebody has *changed*. The page's own copy
lives in the client as its defaults, so an empty table, a failed request
and a backend that is down all render exactly the page that ships. A
marketing homepage that goes blank because an API call did would be worse
than one nobody can edit.
"""

from __future__ import annotations

from django.core.cache import cache
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .. import audit, marketing
from ..enums import SchoolStatus, StudentStatus, UserRole
from ..models import MarketingContent, School, Student
from ..policies import authorize
from ..requests import UpdateMarketingContentRequest
from ..throttling import MarketingContentThrottle

CACHE_KEY = "marketing-content"

# Long, because the document changes when somebody publishes and not
# otherwise - and publishing clears this rather than waiting it out.
CACHE_SECONDS = 60 * 60


@api_view(["GET"])
@permission_classes([AllowAny])
@throttle_classes([MarketingContentThrottle])
def content(request) -> Response:
    return Response({"document": published()})


def published() -> dict:
    """What has been changed, or nothing at all.

    Cached because every visitor to the homepage asks for it, and the
    answer is the same for all of them until somebody edits the page.
    """
    cached = cache.get(CACHE_KEY)

    if cached is not None:
        return cached

    row = MarketingContent.objects.order_by("id").first()
    document = marketing.resolve((row.document if row else None) or {}, figures())

    cache.set(CACHE_KEY, document, CACHE_SECONDS)

    return document


def figures() -> dict[str, int]:
    """What the platform can say about itself today.

    Two counts, both cheap, both cached with the document that uses them -
    so a busy homepage asks nothing of the database, and a school signing
    up shows on the front page within the hour rather than at once. For a
    marketing figure that is close enough, and it is the difference
    between two queries an hour and two per visitor.

    A branch counts as a school. The word on the page is "schools", and
    four buildings running the product are four schools by any ordinary
    reading - whatever they are on an invoice.

    Students of a school that has been switched off are nobody's students.
    """
    active_schools = School.objects.filter(status=SchoolStatus.ACTIVE)

    return {
        marketing.SCHOOLS: active_schools.count(),
        marketing.STUDENTS: Student.objects.filter(
            status=StudentStatus.ACTIVE, school__in=active_schools
        ).count(),
    }


def forget() -> None:
    """Called when the document changes, so the next visitor sees it."""
    cache.delete(CACHE_KEY)


# -- the Super Admin's side ---------------------------------------------------


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def draft(request) -> Response:
    """What the page could say, and what it says now.

    The declaration comes back with it so the editor is built from one
    description of the page rather than a form kept in step by hand.
    """
    authorize(request.user.role == UserRole.SUPER_ADMIN)

    row = MarketingContent.objects.order_by("id").first()

    if request.method == "PUT":
        form = UpdateMarketingContentRequest(data=request.data)
        form.is_valid(raise_exception=True)
        row = save_draft(row, form.validated_data["document"])

    return Response(
        {
            "sections": marketing.resource(),
            # What a live figure would say if it were published now, so the
            # editor can show it and the preview can draw it. The page
            # itself is never told which figures are live.
            "figures": figures(),
            "draft": draft_of(row),
            "published": (row.document if row else None) or {},
            "published_at": None if row is None or row.published_at is None else row.published_at.isoformat(),
            "has_unpublished_changes": draft_of(row) != ((row.document if row else None) or {}),
        }
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def publish(request) -> Response:
    """Puts the draft in front of the world.

    One explicit act, audited: "who changed the front page, and when" is
    the first question anybody asks when the wording surprises them.
    """
    authorize(request.user.role == UserRole.SUPER_ADMIN)

    row = MarketingContent.objects.order_by("id").first()
    wanted = draft_of(row)
    now = timezone.now()

    if row is None:
        row = MarketingContent.objects.create(draft=wanted, created_at=now, updated_at=now)

    before = (row.document or {})

    MarketingContent.objects.filter(pk=row.pk).update(
        document=wanted, published_at=now, published_by_id=request.user.id, updated_at=now
    )
    forget()

    audit.record(
        action="marketing_content.published",
        module="settings",
        entity_type="marketing_content",
        entity_id=row.pk,
        school_id=None,
        old=before,
        new=wanted,
    )

    return Response({"published": wanted, "published_at": now.isoformat()})


def draft_of(row) -> dict:
    """What is being worked on.

    A row that has been published but never drafted since reads back as
    the published document, so opening the editor shows the live page
    rather than an empty form.
    """
    if row is None:
        return {}

    if row.draft is not None:
        return row.draft

    return row.document or {}


def save_draft(row, document: dict):
    now = timezone.now()

    if row is None:
        return MarketingContent.objects.create(draft=document, created_at=now, updated_at=now)

    MarketingContent.objects.filter(pk=row.pk).update(draft=document, updated_at=now)
    row.refresh_from_db()

    return row
