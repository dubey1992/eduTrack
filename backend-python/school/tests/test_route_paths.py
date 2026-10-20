"""The road a route follows (docs/maps.md, M2).

Google is replaced at the HTTP boundary, as it is everywhere else, so no
test reaches the network.

What most of this is about: the path is computed **once, when the stops
change**, and never per view. A map that asked for its own line would bill
a call for every administrator who opened it, and the line is the same
every time until somebody moves a stop.
"""

from __future__ import annotations

from unittest import mock

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, route_paths, tokens
from school.enums import UserRole
from school.gateways import google_maps
from school.models import QueuedJob, TransportRoute
from school.queue import HANDLERS

SERVER_KEY = "server-key-for-tests"

PUNE = ("18.5289000", "73.8744000")

# What Google answers for a two-leg route, trimmed to the fields asked for.
ROUTED = {
    "_status": 200,
    "routes": [
        {
            "polyline": {"encodedPolyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"},
            "distanceMeters": 12400,
            "duration": "1500s",
            "legs": [
                {"distanceMeters": 5200, "duration": "600s"},
                {"distanceMeters": 7200, "duration": "900s"},
            ],
        }
    ],
}


def signed_in(user) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

    return client


class RouteTest(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory(latitude=PUNE[0], longitude=PUNE[1])
        self.route = factories.TransportRouteFactory(school=self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = signed_in(self.admin)

    def stop(self, sequence: int, latitude="18.5000000", longitude="73.8000000", **extra):
        return factories.TransportStopFactory(
            route=self.route,
            school=self.school,
            sequence_number=sequence,
            latitude=latitude,
            longitude=longitude,
            **extra,
        )

    def reloaded(self) -> TransportRoute:
        return TransportRoute.objects.get(pk=self.route.pk)

    def queued(self):
        return QueuedJob.objects.filter(name=route_paths.COMPUTE_ROUTE_PATH)


class WhichPlacesTheRoadJoins(RouteTest):
    def test_the_stops_in_order_and_then_the_school(self):
        """The pickup run. The drop run is the same roads with the school at
        the other end, which is one leg's difference and not worth a second
        call for a line drawn the same way."""
        self.stop(2, "18.6000000", "73.9000000")
        self.stop(1, "18.5000000", "73.8000000")

        points = route_paths.points_for(self.reloaded())

        self.assertEqual([(18.5, 73.8), (18.6, 73.9), (18.5289, 73.8744)], points)

    def test_a_stop_with_no_coordinates_is_skipped_rather_than_refusing_everything(self):
        """A route is placed one stop at a time, and refusing to draw until
        every stop is placed would mean seeing nothing for most of the job."""
        self.stop(1)
        self.stop(2, latitude=None, longitude=None)

        self.assertEqual(2, len(route_paths.points_for(self.reloaded())))

    def test_half_a_coordinate_is_no_coordinate(self):
        self.stop(1)
        self.stop(2, longitude=None)

        self.assertEqual(2, len(route_paths.points_for(self.reloaded())))

    def test_a_school_with_no_location_is_left_out(self):
        """The road then runs stop to stop, which is still worth drawing."""
        self.school.latitude = None
        self.school.longitude = None
        self.school.save(update_fields=["latitude", "longitude"])
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        points = route_paths.points_for(self.reloaded())

        self.assertEqual([(18.5, 73.8), (18.6, 73.9)], points)

    def test_two_stops_cannot_share_a_sequence_number(self):
        """So the order is never ambiguous and the same stops always compute
        the same road. The id tiebreak in the query is insurance against a
        schema that loses this, not something reachable today."""
        from django.db import IntegrityError, transaction

        self.stop(1)

        with self.assertRaises(IntegrityError), transaction.atomic():
            self.stop(1, "18.6000000", "73.9000000")


class WhenTheRoadIsWorkedOutAgain(RouteTest):
    def test_adding_a_stop_queues_it(self):
        self.stop(1)

        self.client.post(
            f"/api/v1/transport/routes/{self.route.pk}/stops",
            {"name": "Second", "sequence_number": 2, "latitude": "18.60", "longitude": "73.90"},
            format="json",
        )

        self.assertEqual(STALE := route_paths.STALE, self.reloaded().path_status)
        self.assertEqual(1, self.queued().count())

    def test_moving_a_stop_queues_it(self):
        stop = self.stop(1)
        self.queued().delete()

        self.client.patch(
            f"/api/v1/transport/stops/{stop.pk}", {"latitude": "18.70", "longitude": "73.95"}, format="json"
        )

        self.assertEqual(route_paths.STALE, self.reloaded().path_status)
        self.assertEqual(1, self.queued().count())

    def test_reordering_queues_it(self):
        stop = self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.queued().delete()

        self.client.patch(f"/api/v1/transport/stops/{stop.pk}", {"sequence_number": 3}, format="json")

        self.assertEqual(1, self.queued().count())

    def test_removing_a_stop_queues_it(self):
        stop = self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.queued().delete()

        self.client.delete(f"/api/v1/transport/stops/{stop.pk}")

        self.assertEqual(1, self.queued().count())

    def test_renaming_a_stop_does_not(self):
        """Nothing about the road changed, and a call to Google costs money."""
        stop = self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.queued().delete()

        self.client.patch(f"/api/v1/transport/stops/{stop.pk}", {"name": "A better name"}, format="json")

        self.assertEqual(0, self.queued().count())

    def test_changing_a_pickup_time_does_not(self):
        stop = self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.queued().delete()

        self.client.patch(f"/api/v1/transport/stops/{stop.pk}", {"pickup_time": "07:45"}, format="json")

        self.assertEqual(0, self.queued().count())

    def test_saving_a_stop_unchanged_does_not(self):
        stop = self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.queued().delete()

        self.client.patch(f"/api/v1/transport/stops/{stop.pk}", {"name": stop.name}, format="json")

        self.assertEqual(0, self.queued().count())

    def test_a_route_with_nothing_to_join_asks_nothing(self):
        """One placed stop and no school location is not a road, and queuing
        would only fail."""
        self.school.latitude = None
        self.school.longitude = None
        self.school.save(update_fields=["latitude", "longitude"])

        self.stop(1)
        route_paths.mark_stale(self.route.pk)

        self.assertEqual(route_paths.NONE, self.reloaded().path_status)
        self.assertEqual(0, self.queued().count())

    def test_dragging_a_pin_does_not_wait_on_google(self):
        """The administrator gets their answer; the road is worked out
        after."""
        self.stop(1)

        with mock.patch.object(google_maps, "post") as asked:
            self.client.post(
                f"/api/v1/transport/routes/{self.route.pk}/stops",
                {"name": "Second", "sequence_number": 2, "latitude": "18.60", "longitude": "73.90"},
                format="json",
            )

        asked.assert_not_called()


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
class WorkingOutTheRoad(RouteTest):
    def run_job(self):
        HANDLERS[route_paths.COMPUTE_ROUTE_PATH](self.route.pk)

    def test_it_stores_what_google_said(self):
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED):
            self.run_job()

        route = self.reloaded()
        self.assertEqual(route_paths.OK, route.path_status)
        self.assertEqual("_p~iF~ps|U_ulLnnqC_mqNvxq`@", route.path_polyline)
        self.assertEqual(12400, route.path_distance_m)
        self.assertEqual(1500, route.path_duration_s)
        self.assertIsNotNone(route.path_computed_at)

    def test_it_keeps_each_leg_for_the_arrival_estimate(self):
        """M3 answers "how far to the next stop" from these rather than
        asking Google on every refresh."""
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED):
            self.run_job()

        self.assertEqual(
            [{"distance_m": 5200, "duration_s": 600}, {"distance_m": 7200, "duration_s": 900}],
            self.reloaded().path_legs,
        )

    def test_it_asks_google_once_however_many_stops(self):
        for index in range(1, 6):
            self.stop(index, f"18.{500 + index}000", "73.8000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED) as asked:
            self.run_job()

        self.assertEqual(1, asked.call_count)

    def test_the_stops_go_as_origin_waypoints_and_destination(self):
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED) as asked:
            self.run_job()

        body = asked.call_args.kwargs["body"]
        self.assertAlmostEqual(18.5, body["origin"]["location"]["latLng"]["latitude"])
        self.assertEqual(1, len(body["intermediates"]))
        self.assertAlmostEqual(18.5289, body["destination"]["location"]["latLng"]["latitude"])

    def test_it_reads_the_stops_as_they_are_now_not_as_they_were_queued(self):
        """Five drags queue five jobs; the first to run should compute the
        route as it finally stands."""
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.stop(3, "18.7000000", "73.9500000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED) as asked:
            self.run_job()

        self.assertEqual(2, len(asked.call_args.kwargs["body"]["intermediates"]))

    def test_a_route_google_refused_says_why_and_keeps_no_line(self):
        """A line through stops that have since moved is worse than no line,
        because it looks current."""
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED):
            self.run_job()

        refused = {"_status": 400, "error": {"message": "Waypoint is not on a road."}}

        with mock.patch.object(google_maps, "post", return_value=refused):
            self.run_job()

        route = self.reloaded()
        self.assertEqual(route_paths.FAILED, route.path_status)
        self.assertIn("not on a road", route.path_failure_reason)
        self.assertIsNone(route.path_polyline)

    def test_google_being_unreachable_is_a_failure_with_a_reason(self):
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", side_effect=google_maps.ProviderError("Network is down")):
            self.run_job()

        self.assertEqual(route_paths.FAILED, self.reloaded().path_failure_reason and route_paths.FAILED)
        self.assertIn("Network is down", self.reloaded().path_failure_reason)

    def test_an_answer_with_no_route_in_it_is_a_failure_not_a_crash(self):
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", return_value={"_status": 200, "routes": []}):
            self.run_job()

        self.assertEqual(route_paths.FAILED, self.reloaded().path_status)

    def test_a_route_deleted_before_the_job_ran_is_not_an_error(self):
        """The queue outlives the thing it was queued for."""
        route_id = self.route.pk
        self.route.delete()

        HANDLERS[route_paths.COMPUTE_ROUTE_PATH](route_id)

    def test_a_route_whose_stops_were_removed_before_the_job_ran(self):
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED):
            self.run_job()

        self.route.transportstop_set.all().delete() if hasattr(self.route, "transportstop_set") else None
        from school.models import TransportStop

        TransportStop.objects.filter(route_id=self.route.pk).delete()

        with mock.patch.object(google_maps, "post") as asked:
            self.run_job()

        asked.assert_not_called()
        route = self.reloaded()
        self.assertEqual(route_paths.NONE, route.path_status)
        self.assertIsNone(route.path_polyline)


@override_settings(GOOGLE_MAPS_SERVER_KEY=SERVER_KEY)
class ARouteWithMoreStopsThanGoogleTakes(RouteTest):
    def test_it_is_asked_for_in_pieces(self):
        for index in range(1, 30):
            self.stop(index, f"18.{500 + index}000", "73.8000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED) as asked:
            HANDLERS[route_paths.COMPUTE_ROUTE_PATH](self.route.pk)

        self.assertGreater(asked.call_count, 1)

    def test_the_pieces_overlap_so_the_line_has_no_gap(self):
        for index in range(1, 30):
            self.stop(index, f"18.{500 + index}000", "73.8000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED) as asked:
            HANDLERS[route_paths.COMPUTE_ROUTE_PATH](self.route.pk)

        first, second = asked.call_args_list[0], asked.call_args_list[1]
        self.assertEqual(
            first.kwargs["body"]["destination"]["location"], second.kwargs["body"]["origin"]["location"]
        )

    def test_the_totals_are_the_whole_route(self):
        for index in range(1, 30):
            self.stop(index, f"18.{500 + index}000", "73.8000000")

        with mock.patch.object(google_maps, "post", return_value=ROUTED) as asked:
            HANDLERS[route_paths.COMPUTE_ROUTE_PATH](self.route.pk)

        route = self.reloaded()
        self.assertEqual(12400 * asked.call_count, route.path_distance_m)
        self.assertEqual(1500 * asked.call_count, route.path_duration_s)


class TryingAgain(RouteTest):
    def test_an_administrator_may_ask_for_another_go(self):
        self.stop(1)
        self.stop(2, "18.6000000", "73.9000000")
        self.queued().delete()

        response = self.client.post(f"/api/v1/transport/routes/{self.route.pk}/path")

        self.assertEqual(200, response.status_code)
        self.assertEqual(1, self.queued().count())

    def test_nobody_who_may_not_change_the_route_may(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        response = signed_in(teacher).post(f"/api/v1/transport/routes/{self.route.pk}/path")

        self.assertEqual(403, response.status_code)

    def test_a_visitor_who_is_not_signed_in_may_not(self):
        self.assertEqual(401, APIClient().post(f"/api/v1/transport/routes/{self.route.pk}/path").status_code)

    def test_another_schools_route_is_not_reachable(self):
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)

        response = signed_in(stranger).post(f"/api/v1/transport/routes/{self.route.pk}/path")

        self.assertEqual(403, response.status_code)


class WhatTheRouteScreenIsTold(RouteTest):
    def test_the_detail_carries_the_path(self):
        self.stop(1)

        body = self.client.get(f"/api/v1/transport/routes/{self.route.pk}").data

        self.assertIn("path", body)
        self.assertIn(body["path"]["status"], (route_paths.NONE, route_paths.STALE))

    def test_the_list_does_not(self):
        """A polyline per row would be the largest thing in the answer, and
        the list draws no map."""
        self.stop(1)

        body = self.client.get("/api/v1/transport/routes").data

        self.assertNotIn("path", body["data"][0])
