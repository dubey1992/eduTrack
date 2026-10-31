"""Asking Google a question (docs/maps.md, M1).

Google is replaced at the HTTP boundary, as Twilio and Meta are: no test
reaches the network, and every answer here is one Google really sends.

Two things most of this is about. **The server key never leaves the server** -
it is what an administrator's search is spent through, and lifting it out of
a built app would let somebody else spend it. And **every call costs money**,
so the same question asked twice is asked of Google once.
"""

from __future__ import annotations

from unittest import mock

from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.gateways import google_maps

CONFIG = "/api/v1/maps/config"
AUTOCOMPLETE = "/api/v1/maps/places/autocomplete"
PLACE = "/api/v1/maps/places/{}"
REVERSE = "/api/v1/maps/geocode/reverse"

SERVER_KEY = "server-key-for-tests"
BROWSER_KEY = "browser-key-for-tests"

SUGGESTIONS = {
    "_status": 200,
    "suggestions": [
        {
            "placePrediction": {
                "placeId": "ChIJ_station",
                "structuredFormat": {
                    "mainText": {"text": "Station Road"},
                    "secondaryText": {"text": "Pune, Maharashtra, India"},
                },
            }
        }
    ],
}

PLACE_DETAILS = {
    "_status": 200,
    "id": "ChIJ_station",
    "displayName": {"text": "Station Road"},
    "formattedAddress": "Station Rd, Pune, Maharashtra 411001, India",
    "location": {"latitude": 18.5289, "longitude": 73.8744},
}

GEOCODED = {
    "_status": 200,
    "status": "OK",
    "results": [{"formatted_address": "Station Rd, Pune, Maharashtra 411001, India"}],
}


def signed_in_as(role, **extra) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=role, **extra)))

    return client


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY, GOOGLE_MAPS_BROWSER_KEY=BROWSER_KEY)
class WhatTheAppIsToldAboutDrawingMaps(TestCase):
    def setUp(self):
        cache.clear()

    def test_a_signed_in_user_is_given_the_browser_key(self):
        """It is published inside the app the moment a map draws, so there
        is nothing to keep from somebody already signed in to that app."""
        body = signed_in_as(UserRole.TEACHER).get(CONFIG).data

        self.assertTrue(body["available"])
        self.assertEqual(BROWSER_KEY, body["browser_key"])

    def test_a_visitor_who_is_not_signed_in_is_told_nothing(self):
        self.assertEqual(401, APIClient().get(CONFIG).status_code)

    @override_settings(GOOGLE_MAPS_BROWSER_KEY="")
    def test_no_key_is_an_answer_rather_than_an_error(self):
        """Every map falls back to the list screen beside it, and this is
        how the app knows to."""
        response = signed_in_as(UserRole.TEACHER).get(CONFIG)

        self.assertEqual(200, response.status_code)
        self.assertFalse(response.data["available"])

    def test_the_server_key_is_never_handed_out(self):
        body = signed_in_as(UserRole.SUPER_ADMIN).get(CONFIG).data

        self.assertNotIn(SERVER_KEY, str(body))


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
class SearchingForAnAddress(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SCHOOL_ADMIN)

    def search(self, query="Station Road", **extra):
        return self.client.get(AUTOCOMPLETE, {"q": query, **extra})

    def test_it_returns_what_somebody_typing_might_mean(self):
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS):
            body = self.search().data

        self.assertEqual(
            [{"place_id": "ChIJ_station", "label": "Station Road", "detail": "Pune, Maharashtra, India"}],
            body["suggestions"],
        )

    def test_two_characters_are_not_worth_asking_about(self):
        """It costs the same as a real question and tells nobody anything."""
        with mock.patch.object(google_maps, "post") as asked:
            self.assertEqual([], self.search("St").data["suggestions"])

        asked.assert_not_called()

    def test_the_same_question_is_asked_of_google_once(self):
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS) as asked:
            self.search()
            self.search()

        self.assertEqual(1, asked.call_count)

    def test_a_different_question_is_a_different_answer(self):
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS) as asked:
            self.search("Station Road")
            self.search("Market Road")

        self.assertEqual(2, asked.call_count)

    def test_the_search_is_biased_towards_the_school(self):
        """"Station Road" means a different road in every city."""
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS) as asked:
            self.search(near_lat="18.52", near_lng="73.85")

        body = asked.call_args.kwargs["body"]
        self.assertAlmostEqual(18.52, body["locationBias"]["circle"]["center"]["latitude"])

    def test_a_search_near_one_place_is_not_the_cached_answer_for_another(self):
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS) as asked:
            self.search(near_lat="18.52", near_lng="73.85")
            self.search(near_lat="28.61", near_lng="77.20")

        self.assertEqual(2, asked.call_count)

    def test_the_key_goes_in_the_header_and_never_in_the_answer(self):
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS) as asked:
            body = self.search().data

        self.assertEqual(SERVER_KEY, asked.call_args.kwargs["headers"]["X-Goog-Api-Key"])
        self.assertNotIn(SERVER_KEY, str(body))

    def test_a_shape_google_has_never_sent_is_skipped_rather_than_crashing(self):
        answer = {"_status": 200, "suggestions": [{"queryPrediction": {"text": "nonsense"}}, "nonsense"]}

        with mock.patch.object(google_maps, "post", return_value=answer):
            self.assertEqual([], self.search().data["suggestions"])


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
class LookingUpThePlaceTheyPicked(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SCHOOL_ADMIN)

    def test_it_says_where_the_place_is(self):
        with mock.patch.object(google_maps, "get", return_value=PLACE_DETAILS):
            body = self.client.get(PLACE.format("ChIJ_station")).data

        self.assertAlmostEqual(18.5289, body["latitude"])
        self.assertAlmostEqual(73.8744, body["longitude"])
        self.assertEqual("Station Road", body["label"])

    def test_it_asks_for_only_the_fields_the_picker_draws(self):
        """Every field named is a field Google charges for."""
        with mock.patch.object(google_maps, "get", return_value=PLACE_DETAILS) as asked:
            self.client.get(PLACE.format("ChIJ_station"))

        self.assertEqual(google_maps.PLACE_FIELDS, asked.call_args.kwargs["headers"]["X-Goog-FieldMask"])

    def test_the_same_place_is_asked_about_once(self):
        with mock.patch.object(google_maps, "get", return_value=PLACE_DETAILS) as asked:
            self.client.get(PLACE.format("ChIJ_station"))
            self.client.get(PLACE.format("ChIJ_station"))

        self.assertEqual(1, asked.call_count)

    def test_a_place_with_no_location_is_refused_rather_than_guessed_at(self):
        answer = {"_status": 200, "id": "ChIJ_station", "displayName": {"text": "Station Road"}}

        with mock.patch.object(google_maps, "get", return_value=answer):
            self.assertEqual(503, self.client.get(PLACE.format("ChIJ_station")).status_code)

    def test_a_place_nobody_recognises_is_passed_on_as_googles_own_words(self):
        refused = {"_status": 404, "error": {"message": "Requested entity was not found."}}

        with mock.patch.object(google_maps, "get", return_value=refused):
            response = self.client.get(PLACE.format("ChIJ_nothing"))

        self.assertEqual(503, response.status_code)
        self.assertIn("not found", response.data["message"])


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
class NamingAPointOnTheMap(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SCHOOL_ADMIN)

    def at(self, lat="18.5289", lng="73.8744"):
        return self.client.get(REVERSE, {"lat": lat, "lng": lng})

    def test_it_names_the_point(self):
        with mock.patch.object(google_maps, "get", return_value=GEOCODED):
            self.assertIn("Station Rd", self.at().data["address"])

    def test_the_sea_has_no_address_and_that_is_not_a_failure(self):
        """The picker is happy to let somebody name the pin themselves."""
        empty = {"_status": 200, "status": "ZERO_RESULTS", "results": []}

        with mock.patch.object(google_maps, "get", return_value=empty):
            response = self.at()

        self.assertEqual(200, response.status_code)
        self.assertEqual("", response.data["address"])

    def test_a_pin_dragged_a_metre_is_the_same_place(self):
        """Without rounding the cache key, dragging a pin is a call a pixel."""
        with mock.patch.object(google_maps, "get", return_value=GEOCODED) as asked:
            self.at("18.52890", "73.87440")
            self.at("18.528901", "73.874402")

        self.assertEqual(1, asked.call_count)

    def test_a_pin_dragged_a_street_is_a_different_place(self):
        with mock.patch.object(google_maps, "get", return_value=GEOCODED) as asked:
            self.at("18.5289", "73.8744")
            self.at("18.5312", "73.8801")

        self.assertEqual(2, asked.call_count)

    def test_a_coordinate_that_is_not_a_number_is_refused(self):
        self.assertEqual(422, self.at("north", "73.8744").status_code)

    def test_a_coordinate_off_the_earth_is_refused(self):
        self.assertEqual(422, self.at("91", "73.8744").status_code)
        self.assertEqual(422, self.at("18.5", "181").status_code)

    def test_googles_own_refusal_is_passed_on(self):
        refused = {"_status": 200, "status": "REQUEST_DENIED", "error_message": "This API key is not authorized."}

        with mock.patch.object(google_maps, "get", return_value=refused):
            response = self.at()

        self.assertEqual(503, response.status_code)
        self.assertIn("not authorized", response.data["message"])


class WhenGoogleCannotBeAsked(TestCase):
    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SCHOOL_ADMIN)

    @override_settings(GOOGLE_MAPS_SERVER_KEY="")
    def test_no_key_is_said_plainly_rather_than_as_a_crash(self):
        """503, not 500: nothing is broken. The app falls back to letting
        somebody type the coordinates in."""
        response = self.client.get(AUTOCOMPLETE, {"q": "Station Road"})

        self.assertEqual(503, response.status_code)
        self.assertEqual("MAPS_UNAVAILABLE", response.data["code"])

    @override_settings(GOOGLE_MAPS_SERVER_KEY="")
    def test_no_key_means_google_is_not_called_at_all(self):
        with mock.patch.object(google_maps, "post") as asked:
            self.client.get(AUTOCOMPLETE, {"q": "Station Road"})

        asked.assert_not_called()

    @override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
    def test_google_being_unreachable_is_said_plainly_too(self):
        with mock.patch.object(google_maps, "post", side_effect=google_maps.ProviderError("Network is down")):
            response = self.client.get(AUTOCOMPLETE, {"q": "Station Road"})

        self.assertEqual(503, response.status_code)
        self.assertIn("Network is down", response.data["message"])

    @override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
    def test_a_failure_is_not_cached_as_if_it_were_an_answer(self):
        """Otherwise a blip during one search would blank that search for a
        day, and nobody would understand why."""
        with mock.patch.object(google_maps, "post", side_effect=google_maps.ProviderError("Network is down")):
            self.client.get(AUTOCOMPLETE, {"q": "Station Road"})

        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS) as asked:
            self.client.get(AUTOCOMPLETE, {"q": "Station Road"})

        self.assertEqual(1, asked.call_count)


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
class WhoMaySpendACallOnGoogle(TestCase):
    """The two jobs that need it are placing a school and placing a route's
    stops. Everybody else sees maps without ever asking Google anything."""

    def setUp(self):
        cache.clear()

    def search_as(self, role, query):
        with mock.patch.object(google_maps, "post", return_value=SUGGESTIONS):
            return signed_in_as(role).get(AUTOCOMPLETE, {"q": query})

    def test_the_administrators_who_place_schools_and_stops_may(self):
        for index, role in enumerate(
            (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.TRANSPORT_MANAGER)
        ):
            self.assertEqual(200, self.search_as(role, f"Road {index}").status_code, role)

    def test_nobody_else_may(self):
        for index, role in enumerate((UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.ACCOUNTANT)):
            self.assertEqual(403, self.search_as(role, f"Lane {index}").status_code, role)

    def test_a_teacher_may_not_look_up_a_place_or_name_a_point_either(self):
        client = signed_in_as(UserRole.TEACHER)

        self.assertEqual(403, client.get(PLACE.format("ChIJ_station")).status_code)
        self.assertEqual(403, client.get(REVERSE, {"lat": "18.5", "lng": "73.8"}).status_code)

    def test_a_visitor_who_is_not_signed_in_may_not(self):
        client = APIClient()

        self.assertEqual(401, client.get(AUTOCOMPLETE, {"q": "Station Road"}).status_code)
        self.assertEqual(401, client.get(PLACE.format("ChIJ_station")).status_code)
        self.assertEqual(401, client.get(REVERSE, {"lat": "18.5", "lng": "73.8"}).status_code)


POSTAL = "/api/v1/maps/geocode/postal"

# What Geocoding sends for an Indian PIN code: a postal_code result whose
# parts name the city, the state and the country, and the post offices the
# code serves.
PIN_CODE = {
    "_status": 200,
    "status": "OK",
    "results": [
        {
            "types": ["postal_code"],
            "formatted_address": "Pune, Maharashtra 411001, India",
            "postcode_localities": ["Pune Cantonment", "Pune Station"],
            "geometry": {"location": {"lat": 18.5236, "lng": 73.8740}},
            "address_components": [
                {"long_name": "411001", "short_name": "411001", "types": ["postal_code"]},
                {"long_name": "Pune", "short_name": "Pune", "types": ["locality", "political"]},
                {"long_name": "Pune", "short_name": "Pune", "types": ["administrative_area_level_3", "political"]},
                {"long_name": "Maharashtra", "short_name": "MH", "types": ["administrative_area_level_1", "political"]},
                {"long_name": "India", "short_name": "IN", "types": ["country", "political"]},
            ],
        }
    ],
}

# A UK postcode names its town as a postal_town, not a locality.
UK_POSTCODE = {
    "_status": 200,
    "status": "OK",
    "results": [
        {
            "types": ["postal_code"],
            "formatted_address": "London SW1A 1AA, UK",
            "geometry": {"location": {"lat": 51.501, "lng": -0.1416}},
            "address_components": [
                {"long_name": "SW1A 1AA", "short_name": "SW1A 1AA", "types": ["postal_code"]},
                {"long_name": "London", "short_name": "London", "types": ["postal_town"]},
                {"long_name": "England", "short_name": "England", "types": ["administrative_area_level_1", "political"]},
                {"long_name": "United Kingdom", "short_name": "GB", "types": ["country", "political"]},
            ],
        }
    ],
}


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY, GOOGLE_MAPS_BROWSER_KEY=BROWSER_KEY, GOOGLE_MAPS_REGION="IN")
class LookingUpAPostalCode(TestCase):
    """Typing a postal code fills in the rest of a school's address."""

    def setUp(self):
        cache.clear()
        self.client = signed_in_as(UserRole.SUPER_ADMIN)

    def look_up(self, code="411001", **extra):
        return self.client.get(POSTAL, {"postal_code": code, **extra})

    def test_it_names_the_city_state_and_country_and_says_where_it_is(self):
        with mock.patch.object(google_maps, "get", return_value=PIN_CODE):
            response = self.look_up()

        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {
                "found": True,
                "postal_code": "411001",
                "city": "Pune",
                "state": "Maharashtra",
                "country": "India",
                "country_code": "IN",
                "latitude": 18.5236,
                "longitude": 73.874,
                "address": "Pune, Maharashtra 411001, India",
                "localities": ["Pune Cantonment", "Pune Station"],
            },
            response.data,
        )

    def test_it_asks_only_about_postal_codes_in_the_country_given(self):
        with mock.patch.object(google_maps, "get", return_value=PIN_CODE) as asked:
            self.look_up(country="India")

        params = asked.call_args.kwargs["params"]
        self.assertEqual("postal_code:411001|country:India", params["components"])
        self.assertNotIn("region", params)

    def test_with_no_country_it_prefers_the_platforms_region(self):
        with mock.patch.object(google_maps, "get", return_value=PIN_CODE) as asked:
            self.look_up()

        self.assertEqual(("postal_code:411001", "in"), (asked.call_args.kwargs["params"]["components"],
                                                         asked.call_args.kwargs["params"]["region"]))

    def test_a_postal_town_is_a_city_too(self):
        with mock.patch.object(google_maps, "get", return_value=UK_POSTCODE):
            data = self.look_up("sw1a  1aa", country="United Kingdom").data

        self.assertEqual(("SW1A 1AA", "London", "England", "GB"),
                         (data["postal_code"], data["city"], data["state"], data["country_code"]))

    def test_a_code_google_does_not_know_is_an_answer_not_an_error(self):
        with mock.patch.object(google_maps, "get", return_value={"_status": 200, "status": "ZERO_RESULTS", "results": []}):
            response = self.look_up("999999")

        self.assertEqual((200, {"found": False}), (response.status_code, response.data))

    def test_a_street_that_happens_to_match_is_not_a_postal_code(self):
        street = {"_status": 200, "status": "OK", "results": [{**PIN_CODE["results"][0], "types": ["route"]}]}

        with mock.patch.object(google_maps, "get", return_value=street):
            self.assertEqual({"found": False}, self.look_up().data)

    def test_the_same_code_is_asked_of_google_once(self):
        with mock.patch.object(google_maps, "get", return_value=PIN_CODE) as asked:
            self.look_up("411001", country="India")
            self.look_up(" 411001 ", country="india")

        self.assertEqual(1, asked.call_count)

    def test_the_key_is_never_in_the_answer(self):
        with mock.patch.object(google_maps, "get", return_value=PIN_CODE):
            response = self.look_up()

        self.assertNotIn(SERVER_KEY, response.content.decode())

    def test_what_is_not_a_postal_code_is_refused_before_google_is_asked(self):
        for code in ("", "1", "41100<script>", "12345678901", "-12345"):
            with self.subTest(code=code), mock.patch.object(google_maps, "get") as asked:
                response = self.look_up(code)
                self.assertEqual(422, response.status_code)
                asked.assert_not_called()

    def test_no_key_or_a_google_refusal_is_a_503_the_form_can_shrug_off(self):
        with override_settings(GOOGLE_MAPS_SERVER_KEY=""):
            self.assertEqual(503, self.look_up().status_code)

        refused = {"_status": 200, "status": "REQUEST_DENIED", "error_message": "The provided API key is invalid."}
        with mock.patch.object(google_maps, "get", return_value=refused):
            self.assertEqual(503, self.look_up("411002").status_code)

    def test_only_those_who_place_schools_or_stops_may_ask(self):
        for role in (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role), mock.patch.object(google_maps, "get", return_value=PIN_CODE):
                cache.clear()
                self.assertEqual(200, signed_in_as(role).get(POSTAL, {"postal_code": "411001"}).status_code)

        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                self.assertEqual(403, signed_in_as(role).get(POSTAL, {"postal_code": "411001"}).status_code)

        self.assertEqual(401, APIClient().get(POSTAL, {"postal_code": "411001"}).status_code)
