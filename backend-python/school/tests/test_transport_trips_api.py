"""Bus trips, over HTTP - Laravel's fixture and cases, ported.

A ready route (Bus 04 driven by Sanjay Patel, stops Lake View and Central
Park) with three active riders - two at Lake View, one at Central Park - and an
inactive student who must be left off the trip. The clock is frozen on a plain
Wednesday, so "today" is a working day unless a test says otherwise.

**A trip runs once per route, direction and day**, one at a time, on a working
day, with an active vehicle and driver. **A rider boards, then drops; or is
absent - never back again.** **A trip does not end with anybody still aboard**,
and ending it marks everybody who never boarded absent. **A finished trip is
finished.** And **guardians are told**, on the school's clock.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.clock import SchoolClock
from school.enums import UserRole
from school.fields import as_utc
from school.models import (
    AuditLog,
    CommunicationSetting,
    Holiday,
    Message,
    StudentTransportAssignment,
    TransportRoute,
    TransportStop,
    TransportTrip,
    TransportTripEvent,
    TransportTripRider,
    User,
)
from school.services import TransportTripService

TRIPS = "/api/v1/transport/trips"
WEDNESDAY = dt.datetime(2026, 9, 9, 7, 30, tzinfo=dt.timezone.utc)


class TripTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.freeze(WEDNESDAY)
        self.f = self.ready_route()

    def freeze(self, instant):
        patcher = mock.patch("django.utils.timezone.now", return_value=instant)
        patcher.start()
        self.addCleanup(patcher.stop)

    def ready_route(self, school=None, name="Green Park", vehicle_name="Bus 04"):
        school = school or factories.SchoolFactory()
        vehicle = factories.VehicleFactory(school=school, name=vehicle_name, capacity=30)
        driver = factories.DriverFactory(school=school, name="Sanjay Patel")
        route = factories.TransportRouteFactory(school=school, name=name, vehicle=vehicle, driver=driver)
        lake_view = factories.TransportStopFactory(route=route, sequence_number=1, name="Lake View")
        central_park = factories.TransportStopFactory(route=route, sequence_number=2, name="Central Park")

        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=school, academic_year=factories.AcademicYearFactory(school=school))
        )
        arjun = factories.StudentFactory(school=school, class_section=section, first_name="Arjun", last_name="Kumar", guardian_mobile="+91 9800000001")
        aarav = factories.StudentFactory(school=school, class_section=section, first_name="Aarav", last_name="Mehta", guardian_mobile="+91 9800000002")
        meera = factories.StudentFactory(school=school, class_section=section, first_name="Meera", last_name="Singh", guardian_mobile="+91 9800000003")
        inactive = factories.StudentFactory(school=school, class_section=section, status="inactive")

        for student, stop in ((arjun, lake_view), (aarav, lake_view), (meera, central_park), (inactive, lake_view)):
            StudentTransportAssignment.objects.create(school=school, student=student, route=route, transport_stop=stop)

        return {
            "school": school, "route": route, "stops": [lake_view, central_park], "students": [arjun, aarav, meera],
            "section": section,
            "manager": factories.UserFactory(school=school, role=UserRole.TRANSPORT_MANAGER),
            "admin": factories.UserFactory(school=school, role=UserRole.SCHOOL_ADMIN),
            "teacher": factories.UserFactory(school=school, role=UserRole.TEACHER),
        }

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def start(self, user=None, route=None, direction="pickup"):
        return self.as_user(user or self.f["manager"]).post(
            TRIPS, {"route_id": (route or self.f["route"]).id, "direction": direction}, format="json"
        )

    def act(self, trip_id, path, user=None, body=None, method="post"):
        client = self.as_user(user or self.f["manager"])

        return getattr(client, method)(f"{TRIPS}/{trip_id}{path}", body or {}, format="json")

    def rider(self, trip_id, student, status, user=None):
        return self.act(trip_id, f"/riders/{student.id}", user, {"status": status}, method="patch")


class StartTest(TripTestCase):
    def test_a_transport_manager_starts_a_pickup_with_the_routes_active_riders(self):
        response = self.start()

        self.assertEqual(201, response.status_code)
        data = response.data
        self.assertEqual(
            ("Bus 04 - Green Park", "Bus 04", "Sanjay Patel", "2026-09-09", "pickup", "in_progress", None,
             self.f["manager"].name, 3, 3, 0, 2, "Lake View", False, "started", "Trip started with 3 students expected"),
            (data["route_label"], data["vehicle_name"], data["driver_name"], data["trip_date"], data["direction"],
             data["status"], data["current_stop_id"], data["started_by_name"], data["riders_count"], data["pending_count"],
             data["boarded_count"], data["stops_left"], data["stops"][0]["name"], data["stops"][0]["reached"],
             data["events"][0]["type"], data["events"][0]["note"]),
        )
        self.assertEqual(["Aarav Mehta", "Arjun Kumar", "Meera Singh"], sorted(r["name"] for r in data["riders"]))
        self.assertEqual("Central Park", next(r for r in data["riders"] if r["name"] == "Meera Singh")["stop_name"])
        self.assertEqual(3, TransportTripRider.objects.count())

    def test_riders_at_one_stop_keep_the_order_they_were_assigned_in(self):
        names = [r["name"] for r in self.start().data["riders"]]

        self.assertEqual(["Arjun Kumar", "Aarav Mehta", "Meera Singh"], names)

    def test_admins_and_super_admins_start_trips_and_viewers_do_not(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        first = self.start(self.f["admin"])
        self.assertEqual(201, first.status_code)
        self.assertEqual(200, self.act(first.data["id"], "/cancel", self.f["admin"]).status_code)
        self.assertEqual(201, self.start(root).status_code)

        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF):
            self.assertEqual(403, self.start(factories.UserFactory(school=self.f["school"], role=role)).status_code)

    def test_another_schools_route_is_invalid(self):
        foreign = self.ready_route()

        response = self.start(route=foreign["route"])

        self.assertEqual(["The selected route does not belong to this school."], response.data["details"]["errors"]["route_id"])

    def test_the_direction_is_checked(self):
        self.assertIn("direction", self.start(direction="evening").data["details"]["errors"])

    def test_a_route_needs_an_active_vehicle_and_driver(self):
        route = self.f["route"]

        TransportRoute.objects.filter(pk=route.pk).update(driver=None)
        self.assertEqual("ROUTE_NOT_READY", self.start().data["code"])

        TransportRoute.objects.filter(pk=route.pk).update(driver=factories.DriverFactory(school=self.f["school"], status="inactive"))
        self.assertEqual("ROUTE_NOT_READY", self.start().data["code"])

        TransportRoute.objects.filter(pk=route.pk).update(driver=factories.DriverFactory(school=self.f["school"]), status="inactive")
        response = self.start()
        self.assertEqual((409, "ROUTE_NOT_READY", "Green Park needs an active vehicle and driver before a trip can start."),
                         (response.status_code, response.data["code"], response.data["message"]))

    def test_trips_do_not_run_on_holidays(self):
        Holiday.objects.create(school_id=self.f["school"].id, name="Founders Day", type="school_event",
                               start_date=dt.date(2026, 9, 9), end_date=dt.date(2026, 9, 9))

        self.assertEqual("TRIP_ON_NON_WORKING_DAY", self.start().data["code"])


class DayOffTest(TripTestCase):
    """A Saturday, for a school keeping the Monday-to-Friday week."""

    def setUp(self):
        cache.clear()
        self.freeze(dt.datetime(2026, 9, 12, 7, 30, tzinfo=dt.timezone.utc))
        self.f = self.ready_route()

    def test_trips_do_not_run_on_a_day_the_school_is_closed(self):
        response = self.start()

        self.assertEqual(("TRIP_ON_NON_WORKING_DAY", "Trips do not run on a day the school is closed."),
                         (response.data["code"], response.data["message"]))

    def test_a_school_that_runs_saturdays_runs_its_buses(self):
        """The same date, the same route, a different week."""
        school = self.f["school"]
        school.working_days = "1111110"
        school.save()

        self.assertEqual(201, self.start().status_code)


class OncePerDayTest(TripTestCase):
    def test_one_trip_in_progress_and_each_direction_once_a_day(self):
        trip = self.start().data["id"]

        busy = self.start(direction="drop")
        self.assertEqual(("TRIP_ALREADY_IN_PROGRESS", "Green Park already has a trip in progress. End or cancel it first."),
                         (busy.data["code"], busy.data["message"]))

        self.assertEqual(200, self.act(trip, "/end").status_code)

        again = self.start()
        self.assertEqual(("TRIP_ALREADY_EXISTS", "Today's pickup trip for Green Park has already been run."),
                         (again.data["code"], again.data["message"]))
        self.assertEqual("drop", self.start(direction="drop").data["direction"])

    def test_a_cancelled_trip_can_run_again_the_same_day(self):
        trip = self.start().data["id"]

        cancelled = self.act(trip, "/cancel")

        self.assertEqual(("cancelled", "cancelled"), (cancelled.data["status"], cancelled.data["events"][1]["type"]))
        self.assertEqual(201, self.start().status_code)

    def test_a_route_with_no_riders_still_starts(self):
        StudentTransportAssignment.objects.all().delete()

        response = self.start()

        self.assertEqual((0, 2), (response.data["riders_count"], response.data["stops_left"]))


class StopsAndRidersTest(TripTestCase):
    def setUp(self):
        super().setUp()
        self.trip = self.start().data["id"]

    def test_reaching_stops_moves_the_trip_along(self):
        lake_view, central_park = self.f["stops"]

        response = self.act(self.trip, f"/stops/{lake_view.id}/reached")

        self.assertEqual(
            (lake_view.id, "Lake View", True, False, 1, "stop_reached", "Lake View"),
            (response.data["current_stop_id"], response.data["current_stop_name"], response.data["stops"][0]["reached"],
             response.data["stops"][1]["reached"], response.data["stops_left"], response.data["events"][1]["type"],
             response.data["events"][1]["stop_name"]),
        )
        self.assertEqual(0, self.act(self.trip, f"/stops/{central_park.id}/reached").data["stops_left"])

    def test_a_stop_on_another_route_is_refused_and_a_teacher_reaches_nothing(self):
        other = factories.TransportStopFactory(route=factories.TransportRouteFactory(school=self.f["school"]))

        wrong = self.act(self.trip, f"/stops/{other.id}/reached")
        teacher = self.act(self.trip, f"/stops/{self.f['stops'][0].id}/reached", self.f["teacher"])

        self.assertEqual(["The selected stop is not on this trip's route."], wrong.data["details"]["errors"]["stop"])
        self.assertEqual(403, teacher.status_code)

    def test_a_rider_boards_at_the_current_stop_then_drops(self):
        arjun = self.f["students"][0]
        self.act(self.trip, f"/stops/{self.f['stops'][0].id}/reached")

        boarded = self.rider(self.trip, arjun, "boarded")
        mine = next(r for r in boarded.data["riders"] if r["student_id"] == arjun.id)
        last = boarded.data["events"][-1]

        self.assertEqual((1, 2), (boarded.data["boarded_count"], boarded.data["pending_count"]))
        self.assertEqual(("boarded", "2026-09-09T07:30:00.000000Z", None), (mine["status"], mine["boarded_at"], mine["dropped_at"]))
        self.assertEqual(["boarded", "Lake View", "Arjun Kumar"], [last["type"], last["stop_name"], last["student_name"]])

        dropped = self.rider(self.trip, arjun, "dropped")
        self.assertEqual((1, 0), (dropped.data["dropped_count"], dropped.data["boarded_count"]))

    def test_boarding_tells_the_guardian_on_the_schools_clock(self):
        school = self.f["school"]
        school.timezone = "Asia/Kolkata"
        school.save()
        self.act(self.trip, f"/stops/{self.f['stops'][0].id}/reached")

        self.rider(self.trip, self.f["students"][0], "boarded")

        message = Message.objects.get(event="transport.boarded")
        # 07:30 UTC is 1:00 PM in Kolkata.
        self.assertIn("boarded Bus 04 at Lake View at 1:00 PM", message.body)

    def test_a_pending_rider_can_be_absent(self):
        response = self.rider(self.trip, self.f["students"][2], "absent")

        self.assertEqual((1, 2), (response.data["absent_count"], response.data["pending_count"]))
        self.assertIn("did not board Bus 04 for the pickup trip", Message.objects.get(event="transport.absent").body)

    def test_a_rider_moves_one_way_only(self):
        arjun, aarav = self.f["students"][:2]

        def code(student, status):
            response = self.rider(self.trip, student, status)
            return response.status_code, response.data.get("code")

        self.assertEqual((409, "INVALID_RIDER_STATUS_CHANGE"), code(arjun, "dropped"))
        self.assertEqual(200, code(arjun, "boarded")[0])
        self.assertEqual(409, code(arjun, "boarded")[0])
        self.assertEqual(409, code(arjun, "absent")[0])
        self.assertEqual(200, code(arjun, "dropped")[0])
        self.assertEqual(409, code(arjun, "boarded")[0])
        self.assertEqual(200, code(aarav, "absent")[0])
        self.assertEqual("A absent student cannot be marked boarded.", self.rider(self.trip, aarav, "boarded").data["message"])
        self.assertEqual(422, code(aarav, "pending")[0])

    def test_a_student_not_on_the_trip_is_refused(self):
        walker = factories.StudentFactory(school=self.f["school"], class_section=self.f["section"])

        response = self.rider(self.trip, walker, "boarded")

        self.assertEqual(["This student is not on this trip."], response.data["details"]["errors"]["student"])

    def test_a_teacher_changes_no_rider(self):
        self.assertEqual(403, self.rider(self.trip, self.f["students"][0], "boarded", self.f["teacher"]).status_code)


class EndTest(TripTestCase):
    def setUp(self):
        super().setUp()
        self.trip = self.start().data["id"]

    def test_a_trip_does_not_end_with_anybody_aboard_and_ending_marks_the_rest_absent(self):
        arjun, aarav = self.f["students"][:2]
        self.rider(self.trip, arjun, "boarded")
        self.rider(self.trip, aarav, "boarded")
        self.rider(self.trip, aarav, "dropped")

        refused = self.act(self.trip, "/end")
        self.assertEqual(("TRIP_RIDERS_ON_BOARD", "1 student is still on board. Drop them off before ending the trip."),
                         (refused.data["code"], refused.data["message"]))

        self.rider(self.trip, arjun, "dropped")
        ended = self.act(self.trip, "/end")

        self.assertEqual(("completed", 2, 1, 0), (ended.data["status"], ended.data["dropped_count"], ended.data["absent_count"], ended.data["pending_count"]))
        self.assertIsNotNone(ended.data["ended_at"])
        self.assertEqual("Trip completed; 1 marked absent", ended.data["events"][-1]["note"])

    def test_a_finished_trip_is_finished(self):
        self.act(self.trip, "/cancel")

        for response in (
            self.act(self.trip, f"/stops/{self.f['stops'][0].id}/reached"),
            self.rider(self.trip, self.f["students"][0], "boarded"),
            self.act(self.trip, "/end"),
            self.act(self.trip, "/cancel"),
        ):
            self.assertEqual(("TRIP_NOT_IN_PROGRESS", "This trip is no longer in progress."), (response.data["code"], response.data["message"]))

    def test_only_managing_roles_of_the_school_end_or_cancel(self):
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(403, self.act(self.trip, "/end", self.f["teacher"]).status_code)
        self.assertEqual(403, self.act(self.trip, "/cancel", self.f["teacher"]).status_code)
        self.assertEqual(403, self.act(self.trip, "/end", stranger).status_code)


class ListTest(TripTestCase):
    def test_trips_are_listed_newest_first_with_counts_scoped_and_filterable(self):
        foreign = self.ready_route()
        self.start(foreign["manager"], foreign["route"])
        first = self.start().data["id"]
        self.act(first, "/end")

        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 9, 15, 0, tzinfo=dt.timezone.utc)):
            second = self.start(direction="drop").data["id"]

        hod = factories.UserFactory(school=self.f["school"], role=UserRole.HOD)
        for viewer in (self.f["admin"], self.f["manager"], self.f["teacher"], hod):
            rows = self.as_user(viewer).get(TRIPS).data["data"]
            self.assertEqual((2, second, "drop", 3, "completed"),
                             (len(rows), rows[0]["id"], rows[0]["direction"], rows[0]["riders_count"], rows[1]["status"]))
            self.assertNotIn("riders", rows[0])

        manager = self.as_user(self.f["manager"])
        self.assertEqual(1, len(manager.get(f"{TRIPS}?status=in_progress").data["data"]))
        self.assertEqual(0, len(manager.get(f"{TRIPS}?route_id={self.f['route'].id}&date=2026-09-08").data["data"]))
        self.assertEqual(403, self.as_user(factories.UserFactory(school=self.f["school"], role=UserRole.STAFF)).get(TRIPS).status_code)

        foreign_trip = TransportTrip.objects.get(school_id=foreign["school"].id)
        self.assertEqual(403, manager.get(f"{TRIPS}/{foreign_trip.id}").status_code)

    def test_a_super_admin_sees_every_school_and_can_narrow_it(self):
        foreign = self.ready_route()
        self.start()
        self.start(foreign["manager"], foreign["route"])
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(2, len(root.get(TRIPS).data["data"]))
        self.assertEqual(1, len(root.get(f"{TRIPS}?school_id={self.f['school'].id}").data["data"]))


class HistoryTest(TripTestCase):
    def test_fleet_with_trip_history_is_kept_but_a_used_stop_can_go(self):
        trip = self.start().data["id"]
        self.act(trip, f"/stops/{self.f['stops'][1].id}/reached")
        self.act(trip, "/cancel")
        admin = self.as_user(self.f["admin"])
        route = self.f["route"]

        # Riders and events keep the stop's name when the stop itself goes.
        StudentTransportAssignment.objects.filter(transport_stop=self.f["stops"][1]).delete()
        removed = admin.delete(f"/api/v1/transport/stops/{self.f['stops'][1].id}")

        self.assertEqual(204, removed.status_code)
        self.assertFalse(TransportStop.objects.filter(pk=self.f["stops"][1].id).exists())
        self.assertEqual("Central Park", TransportTripRider.objects.get(student=self.f["students"][2]).stop_name)

        StudentTransportAssignment.objects.all().delete()
        self.assertEqual(409, admin.delete(f"/api/v1/transport/routes/{route.id}").status_code)


class TripMapTest(TripTestCase):
    """What the trip detail carries for the map (docs/maps.md, M3).

    The same road and the same school the route detail draws, so a trip and
    its route can never show two different roads. The list carries none of
    it: a polyline per row would be the largest thing in the answer.
    """

    def setUp(self):
        super().setUp()
        route = self.f["route"]
        route.path_status = "ok"
        route.path_polyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        route.path_distance_m = 13116
        route.path_duration_s = 2313
        route.save()

        school = self.f["school"]
        school.latitude = "18.5255022"
        school.longitude = "73.8416335"
        school.save()

        self.trip_id = self.start().json()["id"]

    def detail(self):
        return self.as_user(self.f["manager"]).get(f"{TRIPS}/{self.trip_id}").json()

    def test_the_detail_carries_the_road(self):
        path = self.detail()["path"]

        self.assertEqual(path["status"], "ok")
        self.assertEqual(path["polyline"], "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        self.assertEqual(path["distance_m"], 13116)
        self.assertEqual(path["duration_s"], 2313)

    def test_the_detail_carries_the_school(self):
        body = self.detail()

        self.assertEqual(body["school_latitude"], "18.5255022")
        self.assertEqual(body["school_longitude"], "73.8416335")

    def test_a_school_nobody_has_placed_is_null_rather_than_absent(self):
        school = self.f["school"]
        school.latitude = None
        school.longitude = None
        school.save()

        body = self.detail()

        self.assertIn("school_latitude", body)
        self.assertIsNone(body["school_latitude"])
        self.assertIsNone(body["school_longitude"])

    def test_a_road_nobody_has_worked_out_says_so_rather_than_lying(self):
        route = self.f["route"]
        route.path_status = "failed"
        route.path_polyline = None
        route.path_failure_reason = "Google could not be reached."
        route.save()

        path = self.detail()["path"]

        self.assertEqual(path["status"], "failed")
        self.assertIsNone(path["polyline"])
        self.assertEqual(path["failure_reason"], "Google could not be reached.")

    def test_the_list_carries_no_road_and_no_school_position(self):
        rows = self.as_user(self.f["manager"]).get(TRIPS).json()["data"]

        self.assertTrue(rows)
        for row in rows:
            self.assertNotIn("path", row)
            self.assertNotIn("school_latitude", row)

    def test_the_road_the_trip_draws_is_the_road_the_route_draws(self):
        trip = self.detail()["path"]
        route = self.as_user(self.f["manager"]).get(
            f"/api/v1/transport/routes/{self.f['route'].id}"
        ).json()["path"]

        self.assertEqual(trip, route)


class ADropBeforeThePickup(TripTestCase):
    """A drop takes home the children a pickup brought in, so the day's
    pickup has to have happened first (docs/driver-app.md).

    Without this, starting a drop on a morning nobody drove would end with
    every child marked absent and their guardians told so.
    """

    def start(self, direction):
        return self.as_user(self.f["admin"]).post(TRIPS, {
            "route_id": self.f["route"].id, "direction": direction,
        }, format="json")

    def test_a_drop_with_no_pickup_today_is_refused_by_name(self):
        response = self.start("drop")

        self.assertEqual(409, response.status_code)
        self.assertEqual("PICKUP_NOT_STARTED", response.data["code"])
        self.assertIn(self.f["route"].name, response.data["message"])

    def test_once_the_pickup_has_started_the_drop_is_allowed(self):
        """Started, not finished: a bus still out on its pickup may be made
        ready for the drop."""
        pickup = self.start("pickup")
        self.as_user(self.f["admin"]).post(f"{TRIPS}/{pickup.data['id']}/cancel")

        response = self.start("drop")

        self.assertEqual(201, response.status_code, response.data)

    def test_a_cancelled_pickup_still_counts(self):
        """The morning happened. Children who reached school another way
        still have to get home, and refusing the drop would strand them."""
        pickup = self.start("pickup")
        self.as_user(self.f["admin"]).post(f"{TRIPS}/{pickup.data['id']}/cancel")

        self.assertEqual(201, self.start("drop").status_code)

    def test_yesterdays_pickup_does_not_unlock_todays_drop(self):
        TransportTrip.objects.create(
            school_id=self.f["school"].id, route_id=self.f["route"].id,
            vehicle_id=self.f["route"].vehicle_id, driver_id=self.f["route"].driver_id,
            trip_date=WEDNESDAY.date() - dt.timedelta(days=1), direction="pickup",
            status="completed", started_by_id=self.f["admin"].id, started_at=WEDNESDAY - dt.timedelta(days=1),
        )

        self.assertEqual(409, self.start("drop").status_code)

    def test_a_pickup_is_never_held_up_by_this(self):
        self.assertEqual(201, self.start("pickup").status_code)


class ATripNobodyEnded(TripTestCase):
    """A crew member forgets to end a trip and the next morning's run is
    blocked: the route already has one in progress, and only the office can
    clear it. The driver finds out in a yard at six (docs/driver-app.md).
    """

    def setUp(self):
        super().setUp()
        self.manager = self.f["manager"]
        self.trip = self.start_trip()

    def start_trip(self, direction="pickup"):
        response = self.as_user(self.f["admin"]).post(TRIPS, {
            "route_id": self.f["route"].id, "direction": direction,
        }, format="json")
        self.assertEqual(201, response.status_code, response.data)

        return TransportTrip.objects.get(pk=response.data["id"])

    def run_job(self, days=1):
        """The job, as cron runs it, some time after the trip's own day."""
        later = as_utc(self.trip.started_at) + dt.timedelta(days=days)

        return TransportTripService.close_left_open(now=later)

    def test_a_trip_still_running_the_next_day_is_closed(self):
        outcome = self.run_job()

        self.trip.refresh_from_db()
        self.assertEqual(1, outcome["closed"])
        self.assertEqual("cancelled", self.trip.status)

    def test_it_is_cancelled_rather_than_ended(self):
        """Ending marks everyone who never boarded as absent and texts their
        guardians. At two in the morning, about a trip nobody watched, that
        would be inventing a fact and sending it to parents."""
        before = Message.objects.filter(event="transport.absent").count()

        self.run_job()

        riders = TransportTripRider.objects.filter(trip_id=self.trip.pk)
        self.assertEqual({"pending"}, {rider.status for rider in riders})
        self.assertEqual(before, Message.objects.filter(event="transport.absent").count())

    def test_the_record_says_the_day_it_ended_not_the_night_the_job_ran(self):
        self.run_job(days=3)

        self.trip.refresh_from_db()
        clock = SchoolClock.for_school(self.f["school"])
        self.assertEqual(clock.end_of_day_utc(self.trip.trip_date), as_utc(self.trip.ended_at))

    def test_a_trip_still_inside_its_own_day_is_left_alone(self):
        """Buses run late. A trip at 11pm is not a trip nobody ended."""
        outcome = TransportTripService.close_left_open(
            now=as_utc(self.trip.started_at) + dt.timedelta(hours=6)
        )

        self.trip.refresh_from_db()
        self.assertEqual(0, outcome["closed"])
        self.assertEqual("in_progress", self.trip.status)

    def test_the_transport_manager_is_told(self):
        outcome = self.run_job()

        # One alert, several channels: the inbox and whatever the school has on.
        message = Message.objects.filter(
            event="transport.trip_left_open", user_id=self.manager.id
        ).first()
        self.assertEqual(1, outcome["alerts"])
        self.assertIsNotNone(message)
        self.assertIn(self.f["route"].name, message.body)
        self.assertIn("has been closed", message.body)

    def test_the_alert_reaches_an_inbox(self):
        """Every other transport alert goes to a guardian, who has no login.
        This one is for the school's own staff."""
        self.run_job()

        self.assertTrue(
            Message.objects.filter(
                event="transport.trip_left_open", user_id=self.manager.id, channel="in_app"
            ).exists()
        )

    def test_a_school_with_no_transport_manager_tells_its_admins(self):
        """An alert nobody receives is not an alert."""
        User.objects.filter(pk=self.manager.id).delete()

        outcome = self.run_job()

        self.assertEqual(1, outcome["alerts"])
        self.assertTrue(
            Message.objects.filter(event="transport.trip_left_open", user_id=self.f["admin"].id).exists()
        )

    def test_switching_off_guardian_transport_alerts_does_not_silence_it(self):
        """The switch is about what parents are told. A manager still needs
        to hear that a bus was left running overnight."""
        CommunicationSetting.objects.create(
            school_id=self.f["school"].id,
            sms_enabled=True,
            transport_alerts_enabled=False,
            leave_alerts_enabled=True,
            result_alerts_enabled=True,
            provider="log",
        )

        self.run_job()

        self.assertTrue(Message.objects.filter(event="transport.trip_left_open").exists())

    def test_the_closing_is_audited_as_the_system_doing_it(self):
        self.run_job()

        entry = AuditLog.objects.get(action="transport_trip.closed_automatically")
        self.assertEqual(self.trip.pk, entry.entity_id)

    def test_and_the_trail_says_nobody_ended_it(self):
        self.run_job()

        event = TransportTripEvent.objects.filter(trip_id=self.trip.pk, type="cancelled").latest("id")
        self.assertIn("Closed automatically", event.note)

    def test_a_trip_from_months_ago_is_closed_but_nobody_is_told(self):
        """The first run after this ships finds every trip anybody ever
        left open. Telling a manager about a bus from March is not an alert,
        it is a flood that teaches people to ignore the ones that matter."""
        outcome = self.run_job(days=90)

        self.trip.refresh_from_db()
        self.assertEqual("cancelled", self.trip.status)
        self.assertEqual(0, outcome["alerts"])
        self.assertFalse(Message.objects.filter(event="transport.trip_left_open").exists())

    def test_but_it_is_still_audited(self):
        self.run_job(days=90)

        self.assertTrue(AuditLog.objects.filter(action="transport_trip.closed_automatically").exists())

    def test_another_schools_running_trip_is_untouched(self):
        elsewhere = self.ready_route(factories.SchoolFactory(), name="Far Road", vehicle_name="Bus 21")
        theirs = self.as_user(elsewhere["admin"]).post(TRIPS, {
            "route_id": elsewhere["route"].id, "direction": "pickup",
        }, format="json")
        self.assertEqual(201, theirs.status_code, theirs.data)

        TransportTripService.close_left_open(now=as_utc(self.trip.started_at) + dt.timedelta(hours=6))

        self.assertEqual("in_progress", TransportTrip.objects.get(pk=theirs.data["id"]).status)

    def test_the_morning_after_a_close_a_new_trip_starts(self):
        """The whole point: the next day's run is not blocked."""
        self.run_job()

        with mock.patch("django.utils.timezone.now", return_value=WEDNESDAY + dt.timedelta(days=1)):
            response = self.as_user(self.f["admin"]).post(TRIPS, {
                "route_id": self.f["route"].id, "direction": "pickup",
            }, format="json")

        self.assertEqual(201, response.status_code, response.data)
