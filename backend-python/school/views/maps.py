"""Looking things up on Google's maps (docs/maps.md, M1).

The browser draws maps with its own key; everything that *asks Google a
question* happens here, with the server key. Three reasons it is worth the
extra hop rather than calling Google from the app:

- The server key never leaves the server, so it cannot be lifted out of a
  built web app and spent by somebody else.
- Google charges per call, so the answers are cached and the caller is rate
  limited. Somebody holding a key down in a search box is one call per
  distinct query per day, not one per keystroke per person.
- The scope rules that apply everywhere else apply here too.

`GET maps/config` is the exception: it hands out the *browser* key, which is
published inside the app the moment a map draws. Any signed-in user may have
it, because the app they are signed in to already carries it. What protects
it is the referrer and package restrictions set on it in Google Cloud.
"""

from __future__ import annotations

import hashlib

from django.conf import settings
from django.core.cache import cache
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..enums import UserRole
from ..errors import InvalidCoordinate, MapsUnavailable
from ..gateways import google_maps
from ..policies import authorize
from ..throttling import MapsLookupThrottle

# Google's answer for a given question does not change through the day, and
# the same administrator searching the same road twice is the common case.
CACHE_SECONDS = 60 * 60 * 24

# Asking Google about one or two characters costs the same as asking about a
# road name and tells nobody anything.
MINIMUM_QUERY = 3


def may_look_up(actor) -> bool:
    """Who may spend a call on Google.

    The two jobs that need it are placing a school on the map and placing a
    route's stops, so: the administrators who do the first, and whoever may
    change transport at their school for the second. A teacher looking at a
    trip sees the map, but never needs to ask Google anything.
    """
    if actor.role in (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN):
        return True

    return actor.role == UserRole.TRANSPORT_MANAGER


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def config(request) -> Response:
    """What the app needs to draw a map, or that it cannot.

    `available` false is not an error: every map falls back to the list
    screen beside it, and saying so plainly is how the app knows to.
    """
    key = (settings.GOOGLE_MAPS_BROWSER_KEY or "").strip()

    return Response({"available": bool(key), "browser_key": key})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
@throttle_classes([MapsLookupThrottle])
def autocomplete(request) -> Response:
    """What somebody typing an address might mean."""
    authorize(may_look_up(request.user))

    query = (request.query_params.get("q") or "").strip()

    if len(query) < MINIMUM_QUERY:
        return Response({"suggestions": []})

    near = _near(request)
    key = _cache_key("autocomplete", settings.GOOGLE_MAPS_REGION, near, query.lower())
    cached = cache.get(key)

    if cached is not None:
        return Response({"suggestions": cached})

    suggestions = [
        {"place_id": found.place_id, "label": found.label, "detail": found.detail}
        for found in _asked(
            lambda: google_maps.autocomplete(query, near=near, region=settings.GOOGLE_MAPS_REGION or None)
        )
    ]
    cache.set(key, suggestions, CACHE_SECONDS)

    return Response({"suggestions": suggestions})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
@throttle_classes([MapsLookupThrottle])
def place(request, place_id: str) -> Response:
    """Where the thing they picked actually is."""
    authorize(may_look_up(request.user))

    key = _cache_key("place", place_id)
    cached = cache.get(key)

    if cached is not None:
        return Response(cached)

    found = _asked(lambda: google_maps.place(place_id))
    answer = {
        "place_id": found.place_id,
        "label": found.label,
        "address": found.address,
        "latitude": found.latitude,
        "longitude": found.longitude,
    }
    cache.set(key, answer, CACHE_SECONDS)

    return Response(answer)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
@throttle_classes([MapsLookupThrottle])
def reverse_geocode(request) -> Response:
    """A label for a point somebody clicked on the map."""
    authorize(may_look_up(request.user))

    latitude = _coordinate(request, "lat", limit=90)
    longitude = _coordinate(request, "lng", limit=180)

    # Rounded for the cache key: two clicks a metre apart are the same place,
    # and without this a dragged pin is a call per pixel.
    key = _cache_key("reverse", round(latitude, 4), round(longitude, 4))
    cached = cache.get(key)

    if cached is not None:
        return Response({"address": cached})

    address = _asked(lambda: google_maps.reverse_geocode(latitude, longitude))
    cache.set(key, address, CACHE_SECONDS)

    return Response({"address": address})


def _cache_key(*parts) -> str:
    """A key safe for any cache backend.

    What is being keyed is somebody's typing: it has spaces in it, which
    memcached refuses, and no length anybody controls. Hashing is not for
    secrecy - the answer is cached in the clear - it is so that what a
    person types cannot decide the shape of a key.
    """
    joined = "|".join(str(part) for part in parts)

    return "maps:" + hashlib.sha256(joined.encode()).hexdigest()


def _asked(ask):
    """Turns a gateway failure into the envelope the app already understands.

    503 rather than 500: nothing here is broken, Google is unreachable or
    unconfigured, and the app's answer to both is to fall back to typing the
    numbers in by hand.
    """
    try:
        return ask()
    except google_maps.MapsUnavailable as error:
        raise MapsUnavailable(str(error)) from error


def _near(request) -> tuple[float, float] | None:
    """Biasing search towards the school is most of what makes it usable:
    "Station Road" means a different road in every city."""
    if "near_lat" not in request.query_params or "near_lng" not in request.query_params:
        return None

    return (_coordinate(request, "near_lat", limit=90), _coordinate(request, "near_lng", limit=180))


def _coordinate(request, name: str, *, limit: float) -> float:
    raw = request.query_params.get(name)

    try:
        value = float(raw)
    except (TypeError, ValueError):
        raise InvalidCoordinate(f"{name} must be a number.") from None

    if not -limit <= value <= limit:
        raise InvalidCoordinate(f"{name} must be between -{limit} and {limit}.")

    return value
