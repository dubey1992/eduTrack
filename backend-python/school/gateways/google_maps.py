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
ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"

# What the location picker draws, and nothing else.
PLACE_FIELDS = "id,displayName,formattedAddress,location"

# The drawn line, the totals, and each leg - which is all a route map and an
# arrival estimate need. Asking for the turn-by-turn steps as well would
# multiply the size of every answer for text nobody reads.
ROUTE_FIELDS = (
    "routes.polyline.encodedPolyline,routes.distanceMeters,routes.duration,"
    "routes.legs.distanceMeters,routes.legs.duration"
)

# Google refuses more than this many intermediate points in one call. A
# route with more stops is computed in pieces and joined.
MAX_WAYPOINTS = 25


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


@dataclass(frozen=True)
class Leg:
    distance_m: int
    duration_s: int


@dataclass(frozen=True)
class Route:
    """A road path through a list of points, in the order given."""

    polyline: str
    distance_m: int
    duration_s: int
    legs: tuple[Leg, ...]


def route(points: list[tuple[float, float]]) -> Route:
    """The road through [points], in order.

    Driving, and with no departure time: a route's stop times are the
    school's own, and a live-traffic estimate would be a different number
    every time anybody looked at the map, for a line that does not move.

    More points than Google takes in one call are computed in pieces and
    joined. The pieces overlap at a point - each one ends where the next
    begins - so the legs line up end to end and nothing is counted twice.
    """
    if len(points) < 2:
        raise MapsUnavailable("A route needs at least two places to join up.")

    polylines, distance, duration, legs = [], 0, 0, []

    for piece in _pieces(points):
        answer = _call(lambda piece=piece: post(ROUTES_URL, body=_body(piece), headers=_headers(ROUTE_FIELDS)))
        found = (answer.get("routes") or [None])[0]

        if not found:
            raise MapsUnavailable("Google Maps could not find a road between those places.")

        polylines.append((found.get("polyline") or {}).get("encodedPolyline") or "")
        distance += int(found.get("distanceMeters") or 0)
        duration += _seconds(found.get("duration"))
        legs.extend(
            Leg(distance_m=int(leg.get("distanceMeters") or 0), duration_s=_seconds(leg.get("duration")))
            for leg in found.get("legs") or []
        )

    return Route(
        polyline=_joined(polylines),
        distance_m=distance,
        duration_s=duration,
        legs=tuple(legs),
    )


def _pieces(points: list[tuple[float, float]]):
    """Splits a long route into calls Google will accept.

    Each piece starts where the last one ended, so the joined line has no
    gap in it and the legs are the legs of the whole route.
    """
    step = MAX_WAYPOINTS + 1

    for start in range(0, len(points) - 1, step):
        yield points[start : start + step + 1]


def _body(points: list[tuple[float, float]]) -> dict:
    return {
        "origin": _waypoint(points[0]),
        "destination": _waypoint(points[-1]),
        "intermediates": [_waypoint(point) for point in points[1:-1]],
        "travelMode": "DRIVE",
        "polylineQuality": "OVERVIEW",
    }


def _waypoint(point: tuple[float, float]) -> dict:
    return {"location": {"latLng": {"latitude": point[0], "longitude": point[1]}}}


def _seconds(duration) -> int:
    """Google sends a duration as a string of seconds with an `s` on it."""
    if not isinstance(duration, str):
        return 0

    try:
        return int(float(duration.rstrip("s")))
    except ValueError:
        return 0


def _joined(polylines: list[str]) -> str:
    """Several encoded polylines as one.

    Decoded and re-encoded rather than concatenated: an encoded polyline is
    a chain of *differences* from the point before, so the first point of
    the second piece would be read as an offset from the last point of the
    first and the line would fly off the map. The pieces overlap by a
    point, which is dropped where they join.
    """
    if len(polylines) == 1:
        return polylines[0]

    points: list[tuple[float, float]] = []

    for polyline in polylines:
        decoded = decode_polyline(polyline)

        if points and decoded and decoded[0] == points[-1]:
            decoded = decoded[1:]

        points.extend(decoded)

    return encode_polyline(points)


def decode_polyline(encoded: str) -> list[tuple[float, float]]:
    """Google's encoded polyline format, back into points."""
    points: list[tuple[float, float]] = []
    index = lat = lng = 0

    while index < len(encoded):
        for is_latitude in (True, False):
            result = shift = 0

            while index < len(encoded):
                byte = ord(encoded[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5

                if byte < 0x20:
                    break

            delta = ~(result >> 1) if result & 1 else result >> 1

            if is_latitude:
                lat += delta
            else:
                lng += delta

        points.append((lat / 1e5, lng / 1e5))

    return points


def encode_polyline(points: list[tuple[float, float]]) -> str:
    """Points back into Google's encoded polyline format."""
    out: list[str] = []
    previous_lat = previous_lng = 0

    for latitude, longitude in points:
        lat = round(latitude * 1e5)
        lng = round(longitude * 1e5)
        out.append(_chunk(lat - previous_lat))
        out.append(_chunk(lng - previous_lng))
        previous_lat, previous_lng = lat, lng

    return "".join(out)


def _chunk(value: int) -> str:
    value = ~(value << 1) if value < 0 else value << 1
    out = []

    while value >= 0x20:
        out.append(chr((0x20 | (value & 0x1F)) + 63))
        value >>= 5

    out.append(chr(value + 63))

    return "".join(out)
