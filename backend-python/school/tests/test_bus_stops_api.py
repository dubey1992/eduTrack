"""The school's list of bus stops (docs/maps.md).

The places, not the calls. A row in `transport_stops` is a route stopping
somewhere fourth at 07:15; a row here is the corner by the post office,
which several routes may call at and which somebody fixes the position of
once. Before this list existed, two routes passing the same corner were two
unrelated rows that happened to share coordinates.

Three rules carry the weight:

- **A position is required.** These are picked on a map, so a stop nobody
  can point to is not a stop. A route's stop keeps its nullable pair, for
  rows that were made before any of this.
- **The name is unique per school.** It is how people refer to a stop, and
  it is also what keeps routes honest - `transport_stops` is unique on
  (route, name), so two library stops can never collide on one route.
- **A stop a route calls at is not deleted.** Deactivate it instead; the
  refusal names the routes, because "cannot delete" without saying why is
  the thing that makes somebody go looking through every route.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
import decimal

from school.models import AuditLog, BusStop, TransportRoute, TransportStop

URL = "/api/v1/transport/bus-stops"


def dec(value: str) -> decimal.Decimal:
    return decimal.Decimal(value)


class BusStopTest(TestCase):
    def setUp(self):
        cache.clear()
        # Placed, because every stop is measured against where the school is.
        self.school = factories.SchoolFactory(latitude="28.6139", longitude="77.2090")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.manager = factories.UserFactory(school=self.school, role=UserRole.TRANSPORT_MANAGER)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.attendant = factories.UserFactory(school=self.school, role=UserRole.BUS_ATTENDANT)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.elsewhere = factories.SchoolFactory(latitude="19.0760", longitude="72.8777")
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def add(self, user=None, **overrides):
        body = {"name": "Market Square", "latitude": "28.6200", "longitude": "77.2100"}
        body.update(overrides)

        return self.as_user(user or self.admin).post(URL, body, format="json")

    def a_stop(self, school=None, **fields):
        values = {
            "school": school or self.school,
            "name": "Market Square",
            "latitude": "28.6200",
            "longitude": "77.2100",
            "status": "active",
        }
        values.update(fields)

        return factories.BusStopFactory(**values)


class Adding(BusStopTest):
    def test_a_stop_is_recorded_against_the_school(self):
        response = self.add()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            ("Market Square", self.school.id, "active", 0),
            (
                response.data["name"],
                response.data["school_id"],
                response.data["status"],
                response.data["routes_count"],
            ),
        )

    def test_a_landmark_is_optional_and_kept(self):
        self.assertIsNone(self.add().data["landmark"])
        self.assertEqual(
            "Opposite the post office",
            self.add(name="Post Office", landmark="Opposite the post office").data["landmark"],
        )

    def test_a_stop_without_a_position_is_refused(self):
        """Unlike a route's stop, which may have none: these are picked on
        a map, so there is always one."""
        response = self.as_user(self.admin).post(URL, {"name": "Nowhere"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("latitude", self.errors(response))

    def test_half_a_position_is_refused(self):
        response = self.as_user(self.admin).post(
            URL, {"name": "Nowhere", "latitude": "28.62"}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("longitude", self.errors(response))

    def test_a_position_the_wrong_way_round_is_refused(self):
        """The mistake people make when they type coordinates instead of
        tapping: the stop lands hundreds of kilometres away."""
        response = self.add(latitude="77.2100", longitude="28.6200")

        self.assertEqual(422, response.status_code)
        self.assertIn("the wrong way round", self.errors(response)["latitude"][0])

    def test_two_stops_at_one_school_cannot_share_a_name(self):
        self.add()

        response = self.add()

        self.assertEqual(422, response.status_code)
        self.assertIn("name", self.errors(response))

    def test_two_schools_may_both_have_a_market_square(self):
        """Every town has one."""
        self.add()

        response = self.add(user=self.stranger, latitude="19.0800", longitude="72.8800")

        self.assertEqual(201, response.status_code, response.data)

    def test_nobody_adds_a_stop_to_another_school(self):
        """The client's school_id is never trusted (CLAUDE.md 10)."""
        response = self.add(user=self.stranger, school_id=self.school.id, latitude="19.08", longitude="72.88")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.elsewhere.id, response.data["school_id"])


class WhoMayKeepTheList(BusStopTest):
    def test_the_transport_manager_keeps_it(self):
        """A stop is what a route is built from, so the people who define a
        route define the places it calls at."""
        self.assertEqual(201, self.add(self.manager).status_code)

    def test_a_teacher_may_look_but_not_touch(self):
        self.a_stop()

        self.assertEqual(200, self.as_user(self.teacher).get(URL).status_code)
        self.assertEqual(403, self.add(self.teacher).status_code)

    def test_a_bus_attendant_gets_none_of_it(self):
        """Their "manage transport" is for running the trip they are on."""
        self.a_stop()

        self.assertEqual(403, self.as_user(self.attendant).get(URL).status_code)
        self.assertEqual(403, self.add(self.attendant).status_code)

    def test_another_schools_list_is_not_visible(self):
        self.a_stop()
        self.a_stop(school=self.elsewhere, name="Their Stop")

        names = [row["name"] for row in self.as_user(self.admin).get(URL).data["data"]]

        self.assertEqual(["Market Square"], names)

    def test_a_super_admin_sees_a_schools_list_when_they_ask_for_it(self):
        self.a_stop()
        self.a_stop(school=self.elsewhere, name="Their Stop")

        listed = self.as_user(self.root).get(f"{URL}?school_id={self.elsewhere.id}").data["data"]

        self.assertEqual(["Their Stop"], [row["name"] for row in listed])


class FindingOne(BusStopTest):
    def test_the_list_is_in_name_order(self):
        self.a_stop(name="Temple Road")
        self.a_stop(name="Market Square")

        names = [row["name"] for row in self.as_user(self.admin).get(URL).data["data"]]

        self.assertEqual(["Market Square", "Temple Road"], names)

    def test_search_looks_at_the_name_and_the_landmark(self):
        self.a_stop(name="Temple Road")
        self.a_stop(name="Market Square", landmark="Opposite the post office")

        by_name = self.as_user(self.admin).get(f"{URL}?q=temple").data["data"]
        by_landmark = self.as_user(self.admin).get(f"{URL}?q=post office").data["data"]

        self.assertEqual(["Temple Road"], [row["name"] for row in by_name])
        self.assertEqual(["Market Square"], [row["name"] for row in by_landmark])

    def test_retired_stops_can_be_filtered_out(self):
        self.a_stop(name="Old Depot", status="inactive")
        self.a_stop(name="Market Square")

        active = self.as_user(self.admin).get(f"{URL}?status=active").data["data"]

        self.assertEqual(["Market Square"], [row["name"] for row in active])


class ChangingOne(BusStopTest):
    def test_it_can_be_renamed_and_moved(self):
        stop = self.a_stop()

        response = self.as_user(self.admin).patch(
            f"{URL}/{stop.id}", {"name": "Market Corner", "latitude": "28.6250"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("Market Corner", "28.6250000"), (response.data["name"], response.data["latitude"]))

    def test_keeping_its_own_name_is_not_a_clash_with_itself(self):
        stop = self.a_stop()

        response = self.as_user(self.admin).patch(
            f"{URL}/{stop.id}", {"name": "Market Square", "landmark": "By the clock"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_taking_another_stops_name_is_refused(self):
        self.a_stop(name="Temple Road")
        stop = self.a_stop()

        response = self.as_user(self.admin).patch(f"{URL}/{stop.id}", {"name": "Temple Road"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("name", self.errors(response))

    def test_it_can_be_retired_without_being_deleted(self):
        stop = self.a_stop()

        response = self.as_user(self.admin).patch(f"{URL}/{stop.id}", {"status": "inactive"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("inactive", BusStop.objects.get(pk=stop.id).status)

    def test_moving_it_the_wrong_way_round_is_refused(self):
        stop = self.a_stop()

        response = self.as_user(self.admin).patch(
            f"{URL}/{stop.id}", {"latitude": "77.2100", "longitude": "28.6200"}, format="json"
        )

        self.assertEqual(422, response.status_code)

    def test_another_schools_stop_cannot_be_touched(self):
        theirs = self.a_stop(school=self.elsewhere, name="Their Stop")

        response = self.as_user(self.admin).patch(f"{URL}/{theirs.id}", {"name": "Mine now"}, format="json")

        self.assertEqual(403, response.status_code)


class RemovingOne(BusStopTest):
    def test_one_nothing_uses_goes(self):
        stop = self.a_stop()

        response = self.as_user(self.admin).delete(f"{URL}/{stop.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(BusStop.objects.filter(pk=stop.id).exists())

    def test_one_a_route_calls_at_stays(self):
        stop = self.a_stop()
        route = factories.TransportRouteFactory(school=self.school, name="North Loop")
        factories.TransportStopFactory(route=route, school=self.school, bus_stop=stop)

        response = self.as_user(self.admin).delete(f"{URL}/{stop.id}")

        self.assertEqual(409, response.status_code)
        self.assertTrue(BusStop.objects.filter(pk=stop.id).exists())

    def test_and_the_refusal_names_the_routes(self):
        """"Cannot delete" without saying why is what sends somebody
        looking through every route one at a time."""
        stop = self.a_stop()
        for name in ("North Loop", "Lake Road"):
            route = factories.TransportRouteFactory(school=self.school, name=name)
            factories.TransportStopFactory(route=route, school=self.school, bus_stop=stop)

        response = self.as_user(self.admin).delete(f"{URL}/{stop.id}")

        self.assertIn("Lake Road and North Loop", response.data["message"])

    def test_the_count_of_routes_is_on_the_row(self):
        """So the screen can warn before anybody presses delete."""
        stop = self.a_stop()
        route = factories.TransportRouteFactory(school=self.school, name="North Loop")
        factories.TransportStopFactory(route=route, school=self.school, bus_stop=stop)

        listed = self.as_user(self.admin).get(URL).data["data"][0]

        self.assertEqual(1, listed["routes_count"])


class WhereTheSchoolIs(BusStopTest):
    """The page carries it, because the screen draws a map and has to
    centre it before there is a single stop to frame - and the people who
    keep this list cannot read /schools at all."""

    def test_the_page_says_where_the_school_is(self):
        listed = self.as_user(self.admin).get(URL).data

        self.assertEqual(("28.6139000", "77.2090000"), (listed["school_latitude"], listed["school_longitude"]))

    def test_the_name_comes_with_it(self):
        """The stop form says what a distance is measured from, and cannot
        read /schools to look the name up."""
        self.assertEqual(self.school.name, self.as_user(self.manager).get(URL).data["school_name"])

    def test_a_transport_manager_gets_it_too(self):
        """They answer for their own school without being able to list
        schools, so this is the only way they learn where it is."""
        listed = self.as_user(self.manager).get(URL).data

        self.assertEqual("28.6139000", listed["school_latitude"])

    def test_a_super_admin_who_has_not_picked_a_school_gets_nothing(self):
        """Honestly "no single school" rather than a guess at the first."""
        listed = self.as_user(self.root).get(URL).data

        self.assertIsNone(listed["school_latitude"])

    def test_and_the_school_they_asked_for_once_they_pick(self):
        listed = self.as_user(self.root).get(f"{URL}?school_id={self.elsewhere.id}").data

        self.assertEqual("19.0760000", listed["school_latitude"])


class WhenAPlaceChanges(BusStopTest):
    """The point of keeping a list (docs/maps.md, S3).

    Fix a wrong pin once and every route using it is right; rename a stop
    once and every route says the new name. Before the list, the same
    corner on three routes was three rows to fix one at a time.

    Safe because a trip keeps its own record of where the bus went -
    `transport_trip_events.stop_name` and the riders' are snapshots - so
    none of this can rewrite what a trip recorded.
    """

    def setUp(self):
        super().setUp()
        self.place = self.a_stop()
        self.north = factories.TransportRouteFactory(school=self.school, name="North Loop")
        self.lake = factories.TransportRouteFactory(school=self.school, name="Lake Road")
        self.calls = [
            factories.TransportStopFactory(
                route=route, school=self.school, bus_stop=self.place, name=self.place.name,
                latitude=self.place.latitude, longitude=self.place.longitude, sequence_number=1,
            )
            for route in (self.north, self.lake)
        ]

    def change(self, **body):
        return self.as_user(self.admin).patch(f"{URL}/{self.place.id}", body, format="json")

    def calls_now(self):
        return list(
            TransportStop.objects.filter(bus_stop_id=self.place.id)
            .order_by("route__name")
            .values_list("name", "latitude", "longitude")
        )

    def test_a_rename_reaches_every_route(self):
        self.change(name="Market Corner")

        self.assertEqual(["Market Corner", "Market Corner"], [name for name, _, _ in self.calls_now()])

    def test_a_move_reaches_every_route(self):
        self.change(latitude="28.6300000", longitude="77.2200000")

        self.assertEqual(
            [(dec("28.6300000"), dec("77.2200000"))] * 2,
            [(latitude, longitude) for _, latitude, longitude in self.calls_now()],
        )

    def test_a_landmark_is_the_lists_own_and_reaches_nothing(self):
        """A route's stop has no landmark; changing one should not touch a
        single route row."""
        before = self.calls_now()

        self.change(landmark="By the clock tower")

        self.assertEqual(before, self.calls_now())

    def test_a_move_queues_each_route_for_a_new_road(self):
        """The road between the stops changed, so the drawn path is stale."""
        self.change(latitude="28.6300000", longitude="77.2200000")

        self.assertEqual(
            {self.north.id, self.lake.id},
            set(TransportRoute.objects.filter(path_status="stale").values_list("id", flat=True)),
        )

    def test_a_rename_queues_nothing(self):
        """A rename moves no bus. Recomputing a path for it would spend a
        key quota on nothing."""
        TransportRoute.objects.update(path_status="ready")

        self.change(name="Market Corner")

        self.assertEqual(0, TransportRoute.objects.filter(path_status="stale").count())

    def test_a_one_off_on_the_same_route_is_untouched(self):
        """It owns its own name: it came from before the list existed."""
        one_off = factories.TransportStopFactory(
            route=self.north, school=self.school, name="Old Corner", sequence_number=2
        )

        self.change(name="Market Corner")

        self.assertEqual("Old Corner", TransportStop.objects.get(pk=one_off.pk).name)

    def test_another_schools_stop_of_the_same_name_is_untouched(self):
        theirs = self.a_stop(school=self.elsewhere, name="Market Square")
        route = factories.TransportRouteFactory(school=self.elsewhere, name="Theirs")
        call = factories.TransportStopFactory(
            route=route, school=self.elsewhere, bus_stop=theirs, name="Market Square", sequence_number=1
        )

        self.change(name="Market Corner")

        self.assertEqual("Market Square", TransportStop.objects.get(pk=call.pk).name)

    def test_it_is_audited_once_for_the_change(self):
        """One act by one person, not a row per route."""
        self.change(name="Market Corner")

        entry = AuditLog.objects.get(action="transport.stops_followed_the_list")
        self.assertEqual(["name"], entry.new_values["changed"])
        self.assertEqual(sorted([self.north.id, self.lake.id]), entry.new_values["route_ids"])


class ARenameThatWouldCollide(BusStopTest):
    """Two library stops cannot share a name - that is unique per school -
    so the only thing in the way is a one-off made before the list."""

    def setUp(self):
        super().setUp()
        self.place = self.a_stop()
        self.route = factories.TransportRouteFactory(school=self.school, name="North Loop")
        factories.TransportStopFactory(
            route=self.route, school=self.school, bus_stop=self.place, name=self.place.name, sequence_number=1
        )
        self.one_off = factories.TransportStopFactory(
            route=self.route, school=self.school, name="Old Corner", sequence_number=2
        )

    def test_it_is_refused_rather_than_failing_at_the_database(self):
        response = self.as_user(self.admin).patch(
            f"{URL}/{self.place.id}", {"name": "Old Corner"}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("name", self.errors(response))

    def test_and_the_message_names_the_route_in_the_way(self):
        response = self.as_user(self.admin).patch(
            f"{URL}/{self.place.id}", {"name": "Old Corner"}, format="json"
        )

        self.assertIn("North Loop already has a stop called Old Corner", self.errors(response)["name"][0])

    def test_nothing_is_changed_when_it_is_refused(self):
        self.as_user(self.admin).patch(f"{URL}/{self.place.id}", {"name": "Old Corner"}, format="json")

        self.assertEqual("Market Square", BusStop.objects.get(pk=self.place.id).name)
        self.assertEqual(
            "Market Square",
            TransportStop.objects.get(bus_stop_id=self.place.id).name,
        )
