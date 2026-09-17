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
from school.enums import UserRole
from school.models import (
    Holiday,
    Message,
    StudentTransportAssignment,
    TransportRoute,
    TransportStop,
    TransportTrip,
    TransportTripRider,
)

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

    def ready_route(self, school=None):
        school = school or factories.SchoolFactory()
        vehicle = factories.VehicleFactory(school=school, name="Bus 04", capacity=30)
        driver = factories.DriverFactory(school=school, name="Sanjay Patel")
        route = factories.TransportRouteFactory(school=school, name="Green Park", vehicle=vehicle, driver=driver)
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


class WeekendTest(TripTestCase):
    def setUp(self):
        cache.clear()
        self.freeze(dt.datetime(2026, 9, 12, 7, 30, tzinfo=dt.timezone.utc))
        self.f = self.ready_route()

    def test_trips_do_not_run_at_the_weekend(self):
        response = self.start()

        self.assertEqual(("TRIP_ON_NON_WORKING_DAY", "Trips do not run on weekends or holidays."),
                         (response.data["code"], response.data["message"]))


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
