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
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from ..models import MarketingContent
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
    document = (row.document if row else None) or {}

    cache.set(CACHE_KEY, document, CACHE_SECONDS)

    return document


def forget() -> None:
    """Called when the document changes, so the next visitor sees it."""
    cache.delete(CACHE_KEY)
