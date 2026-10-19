"""Google Maps, through the server key only (docs/maps.md, M1).

Three calls, all made here and never from a browser: address search while an
administrator types, the details of the place they picked, and a label for a
point they clicked on the map. The browser draws maps with its own key; this
key does the asking, so it can stay on the server behind the school's scope
and a rate limit, and so its answers can be cached.

**Nothing here logs the key**, and nothing returns it. A failure comes back
as a sentence an administrator can read, the way the messaging gateways do.

Field masks are not an optimisation - Places (New) refuses a request without
one, and every field named is a field Google charges for. Only what the
picker draws is asked for.
"""

from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings

from .http import ProviderError, get, post

AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete"
PLACE_URL = "https://places.googleapis.com/v1/places/{place_id}"
GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"

# What the location picker draws, and nothing else.
PLACE_FIELDS = "id,displayName,formattedAddress,location"


@dataclass(frozen=True)
class Suggestion:
    place_id: str
    label: str
    detail: str


@dataclass(frozen=True)
class Place:
    place_id: str
    label: str
    address: str
    latitude: float
    longitude: float


class MapsUnavailable(Exception):
    """No key is configured, or Google refused. The message is safe to show
    an administrator and never contains the key."""


def configured() -> bool:
    return bool(server_key())


def server_key() -> str:
    return (settings.GOOGLE_MAPS_SERVER_KEY or "").strip()


def _headers(field_mask: str | None = None) -> dict:
    headers = {"X-Goog-Api-Key": server_key()}

    if field_mask:
        headers["X-Goog-FieldMask"] = field_mask

    return headers


def _checked(answer: dict) -> dict:
    """Google's refusals explain themselves in the body; its outages do not."""
    status = answer.get("_status", 0)

    if 200 <= status < 300:
        return answer

    error = answer.get("error") or {}
    said = error.get("message") or answer.get("error_message") or f"Google answered {status}."

    raise MapsUnavailable(f"Google Maps: {said}"[:255])


def _call(make):
    if not configured():
        raise MapsUnavailable("No Google Maps key is set up on the server.")

    try:
        return _checked(make())
    except ProviderError as error:
        raise MapsUnavailable(str(error)[:255]) from error


def autocomplete(query: str, *, near: tuple[float, float] | None = None, region: str | None = None) -> list[Suggestion]:
    """What somebody typing an address might mean.

    [near] biases the results towards the school, which is most of what makes
    this usable: "Station Road" means a different road in every city.
    """
    body: dict = {"input": query}

    if region:
        body["regionCode"] = region

    if near is not None:
        body["locationBias"] = {
            "circle": {"center": {"latitude": near[0], "longitude": near[1]}, "radius": 50_000.0}
        }

    answer = _call(lambda: post(AUTOCOMPLETE_URL, body=body, headers=_headers()))

    return [
        Suggestion(
            place_id=place["placeId"],
            label=(place.get("structuredFormat", {}).get("mainText", {}).get("text") or "").strip(),
            detail=(place.get("structuredFormat", {}).get("secondaryText", {}).get("text") or "").strip(),
        )
        for suggestion in answer.get("suggestions", [])
        if isinstance(suggestion, dict) and (place := suggestion.get("placePrediction")) and place.get("placeId")
    ]


def place(place_id: str) -> Place:
    """Where the thing they picked actually is."""
    answer = _call(lambda: get(PLACE_URL.format(place_id=place_id), headers=_headers(PLACE_FIELDS)))
    location = answer.get("location") or {}

    if "latitude" not in location or "longitude" not in location:
        raise MapsUnavailable("Google Maps did not say where that place is.")

    return Place(
        place_id=answer.get("id") or place_id,
        label=(answer.get("displayName") or {}).get("text") or "",
        address=answer.get("formattedAddress") or "",
        latitude=float(location["latitude"]),
        longitude=float(location["longitude"]),
    )


def reverse_geocode(latitude: float, longitude: float) -> str:
    """A label for a point somebody clicked.

    An empty answer is not a failure: the sea has no address, and the picker
    is happy to let somebody name the pin themselves.
    """
    answer = _call(
        lambda: get(GEOCODE_URL, params={"latlng": f"{latitude},{longitude}", "key": server_key()})
    )

    # Geocoding is the old-style API: it answers 200 and says ZERO_RESULTS.
    if answer.get("status") not in ("OK", "ZERO_RESULTS"):
        raise MapsUnavailable(f"Google Maps: {answer.get('error_message') or answer.get('status')}"[:255])

    results = answer.get("results") or []

    return (results[0].get("formatted_address") or "") if results else ""
