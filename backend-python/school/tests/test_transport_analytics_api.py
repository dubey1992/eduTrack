"""Transport analytics, A6 (docs/analytics.md), over HTTP.

Monday 14 September 2026, a UTC school, as in the report tests. Route A has
two stops - Gate (pickup 07:30) and Market (pickup 07:45). What matters:
service is out of the school's working days, riders count boarded and
dropped as on the bus, a bus is late only **more than 10 minutes** after a
stop's scheduled time (early never is), and only the transport report's
audience may look.
"""

import datetime as dt

from rest_framework.test import APIClient

from school import factories
from school.enums import UserRole
from school.models import ModuleSetting, TransportTrip, TransportTripEvent, TransportTripRider

from .test_reports_api import NOW, ReportTestCase, client_for

URL = "/api/v1/analytics/transport"
SEPTEMBER = {"from": "2026-09-01", "to": "2026-09-14"}


class TransportTestCase(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.vehicle = factories.VehicleFactory(school=self.school, name="Bus 1")
        self.driver = factories.DriverFactory(school=self.school, name="Ramesh")
        self.route = factories.TransportRouteFactory(
            school=self.school, name="Route A", vehicle=self.vehicle, driver=self.driver, status="active"
        )
        self.gate = factories.TransportStopFactory(route=self.route, name="Gate", sequence_number=1,
                                                   pickup_time=dt.time(7, 30))
        self.market = factories.TransportStopFactory(route=self.route, name="Market", sequence_number=2,
                                                     pickup_time=dt.time(7, 45))

    def trip(self, day, status="completed", started="07:20", ended="08:10", direction="pickup"):
        on = dt.date.fromisoformat(day)
        at = lambda hhmm: dt.datetime.combine(on, dt.time.fromisoformat(hhmm), tzinfo=dt.timezone.utc)  # noqa: E731

        return TransportTrip.objects.create(
            school=self.school, route=self.route, vehicle=self.vehicle, driver=self.driver, trip_date=day,
            direction=direction, status=status, started_by=self.admin, started_at=at(started),
            ended_at=at(ended) if status == "completed" else None, created_at=NOW, updated_at=NOW,
        )

    def reached(self, trip, stop, hhmm):
        TransportTripEvent.objects.create(
            school=self.school, trip=trip, type="stop_reached", stop=stop, stop_name=stop.name,
            recorded_by=self.admin,
            recorded_at=dt.datetime.combine(
                dt.date.fromisoformat(str(trip.trip_date)), dt.time.fromisoformat(hhmm), tzinfo=dt.timezone.utc
            ),
            created_at=NOW, updated_at=NOW,
        )

    def rider(self, trip, status):
        TransportTripRider.objects.create(
            trip=trip, student=factories.StudentFactory(class_section=self.section), stop=self.gate,
            stop_name="Gate", stop_sequence_number=1, status=status, created_at=NOW, updated_at=NOW,
        )

    def look(self, user=None, **params):
        response = client_for(user or self.admin).get(URL, {**SEPTEMBER, **params})
        self.assertEqual(200, response.status_code, getattr(response, "data", response))

        return response.data

    def september(self, data=None):
        data = data or self.look()

        return data["routes"][0]["months"][0]


class Service(TransportTestCase):
    def test_days_run_against_the_school_s_working_days(self):
        self.trip("2026-09-07")
        self.trip("2026-09-07", direction="drop")
        self.trip("2026-09-08", status="cancelled")

        service = self.september()["service"]

        # 1-14 September: ten weekdays, of which a trip ran on one.
        self.assertEqual({"working_days": 10, "days_run": 1, "trips_completed": 2, "trips_cancelled": 1}, service)

    def test_an_active_route_with_no_trips_still_shows(self):
        data = self.look()

        self.assertEqual(["Route A"], [route["route"] for route in data["routes"]])
        self.assertEqual(0, self.september(data)["service"]["days_run"])


class Riders(TransportTestCase):
    def test_boarded_and_dropped_are_on_the_bus_absent_is_a_no_show(self):
        trip = self.trip("2026-09-07")
        for status in ("boarded", "dropped", "dropped", "absent"):
            self.rider(trip, status)

        self.assertEqual({"on_list": 4, "boarded": 3, "absent": 1, "boarded_rate": 75.0}, self.september()["riders"])


class OnTime(TransportTestCase):
    def test_more_than_ten_minutes_after_the_scheduled_time_is_late_and_early_never_is(self):
        trip = self.trip("2026-09-07")
        self.reached(trip, self.gate, "07:40")  # exactly 10 minutes: on time
        self.reached(trip, self.market, "08:01")  # 16 minutes: late
        other = self.trip("2026-09-08")
        self.reached(other, self.gate, "07:20")  # early: on time

        on_time = self.september()["on_time"]

        self.assertEqual({"arrivals": 3, "late": 1, "on_time_rate": 66.7, "average_minutes_late": 16.0}, on_time)

    def test_the_stops_most_often_late_worst_first(self):
        for day in ("2026-09-07", "2026-09-08"):
            trip = self.trip(day)
            self.reached(trip, self.gate, "07:35")
            self.reached(trip, self.market, "08:05")

        stops = self.look()["late_stops"]

        # Gate was never more than 10 minutes late, so it is not listed.
        self.assertEqual(
            [{"stop_id": self.market.id, "stop": "Market", "route": "Route A", "arrivals": 2, "late": 2,
              "late_rate": 100.0, "average_minutes_late": 20.0}],
            stops,
        )

    def test_a_stop_with_no_scheduled_time_says_nothing_about_lateness(self):
        self.gate.pickup_time = None
        self.gate.save()
        trip = self.trip("2026-09-07")
        self.reached(trip, self.gate, "09:00")

        self.assertEqual({"arrivals": 0, "late": 0, "on_time_rate": None, "average_minutes_late": None},
                         self.september()["on_time"])

    def test_the_time_is_the_school_s_own(self):
        # 02:10 UTC is 07:40 in Kolkata: ten minutes after 07:30, so on time.
        self.school.timezone = "Asia/Kolkata"
        self.school.save()
        trip = self.trip("2026-09-07")
        self.reached(trip, self.gate, "02:10")

        self.assertEqual(0, self.september()["on_time"]["late"])


class Length(TransportTestCase):
    def test_average_and_longest_of_the_completed_trips(self):
        self.trip("2026-09-07", started="07:20", ended="08:00")  # 40 minutes
        self.trip("2026-09-08", started="07:20", ended="08:20")  # 60 minutes
        self.trip("2026-09-09", status="cancelled")

        self.assertEqual({"trips": 2, "average_minutes": 50.0, "longest_minutes": 60.0}, self.september()["length"])


class WhoSees(TransportTestCase):
    def test_admins_and_the_transport_manager_and_nobody_else(self):
        manager = factories.UserFactory(school=self.school, role=UserRole.TRANSPORT_MANAGER)
        self.assertEqual(200, client_for(manager).get(URL, SEPTEMBER).status_code)

        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.ACCOUNTANT, UserRole.STAFF):
            with self.subTest(role=role):
                user = factories.UserFactory(school=self.school, role=role)
                self.assertEqual(403, client_for(user).get(URL, SEPTEMBER).status_code)

        self.assertEqual(401, APIClient().get(URL).status_code)

    def test_another_school_s_admin_sees_their_own_routes(self):
        other = factories.SchoolFactory(timezone="UTC")
        theirs = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)

        data = self.look(theirs, school_id=self.school.id)

        self.assertEqual([], data["routes"])

    def test_a_school_without_transport_has_none(self):
        ModuleSetting.objects.update_or_create(
            school=self.school, module="transport",
            defaults={"platform_enabled": True, "school_enabled": False, "created_at": NOW, "updated_at": NOW},
        )

        response = client_for(self.admin).get(URL, SEPTEMBER)

        self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))

    def test_more_than_two_years_is_refused(self):
        response = client_for(self.admin).get(URL, {"from": "2024-01-01", "to": "2026-09-14"})

        self.assertEqual(422, response.status_code)
        self.assertEqual({"from": ["Transport analytics covers at most 24 months. Pick a shorter range."]},
                         response.data["details"]["errors"])
