"""The school bus in the Family app (docs/parent-student-app.md, F4).

What this file guards that a quick read would not:

- **The live bus only during the child's own trip** (decision D9): a trip
  not running, a trip the child is not on, and a trip they have already
  got off are all BUS_NOT_LIVE - so a parent cannot follow the bus, and the
  crew, all day.
- **The crew's personal number only when the school allows it**; the office
  number always.
- **"The bus is near your stop" once per trip, in the app only**, only for a
  child still waiting at a stop the bus has not passed, and only within the
  school's distance (0 turns it off).
- **Only their own child**, and the Transport module must be on.
"""

import datetime as dt
from decimal import Decimal

from django.utils import timezone

from school import factories, family_bus
from school.enums import MessageChannel, MessageEvent
from school.models import (
    Message,
    ModuleSetting,
    StudentTransportAssignment,
    TransportTrip,
    TransportTripEvent,
    TransportTripLocation,
    TransportTripRider,
)
from school.tests.test_family_f1_api import FAMILY, FamilyAppTest

# Two stops 1.1 km apart on one road; the bus position sits 300 m short of the second.
STOP_1 = (Decimal("18.5590000"), Decimal("73.7860000"))
STOP_2 = (Decimal("18.5690000"), Decimal("73.7860000"))
NEAR_STOP_2 = (Decimal("18.5663000"), Decimal("73.7860000"))
FAR_AWAY = (Decimal("18.6200000"), Decimal("73.7860000"))


class BusTest(FamilyAppTest):
    def setUp(self):
        super().setUp()
        now = timezone.now()
        self.attendant = factories.UserFactory(school=self.school, role="BUS_ATTENDANT", first_name="Ravi",
                                               last_name="Kumar", mobile="+91 90000 55555")
        self.vehicle = factories.VehicleFactory(school=self.school, name="Bus 3", registration_number="MH-12-AB-1234")
        self.driver = factories.DriverFactory(school=self.school)
        self.route = factories.TransportRouteFactory(school=self.school, name="Baner Road", vehicle=self.vehicle,
                                                     driver=self.driver, attendant_user=self.attendant)
        self.stop_1 = factories.TransportStopFactory(route=self.route, name="Baner Gaon", sequence_number=1,
                                                     latitude=STOP_1[0], longitude=STOP_1[1],
                                                     pickup_time=dt.time(7, 20))
        self.stop_2 = factories.TransportStopFactory(route=self.route, name="Sakal Nagar", sequence_number=2,
                                                     latitude=STOP_2[0], longitude=STOP_2[1],
                                                     pickup_time=dt.time(7, 35), drop_time=dt.time(14, 10))
        StudentTransportAssignment.objects.create(school=self.school, student=self.child, route=self.route,
                                                  transport_stop=self.stop_2, created_at=now, updated_at=now)
        self.school.phone = "+91 20 4000 1234"
        self.school.save(update_fields=["phone"])

    def trip(self, direction="pickup", status="in_progress", rider_status="pending", child=None):
        now = timezone.now()
        trip = TransportTrip.objects.create(
            school=self.school, route=self.route, vehicle=self.vehicle, driver=self.driver, started_by=self.attendant,
            trip_date=self.today(), direction=direction, status=status, started_at=now - dt.timedelta(minutes=10),
            created_at=now, updated_at=now,
        )
        if rider_status is not None:
            TransportTripRider.objects.create(
                trip=trip, student=child or self.child, stop=self.stop_2, stop_name=self.stop_2.name,
                stop_sequence_number=2, status=rider_status,
                boarded_at=now if rider_status in ("boarded", "dropped") else None,
                dropped_at=now if rider_status == "dropped" else None, created_at=now, updated_at=now,
            )
        return trip

    def position(self, trip, where, minutes_ago=0):
        now = timezone.now()
        TransportTripLocation.objects.create(
            school=self.school, trip=trip, latitude=where[0], longitude=where[1], accuracy_m=10,
            recorded_at=now - dt.timedelta(minutes=minutes_ago), recorded_by=self.attendant, created_at=now,
            updated_at=now,
        )

    def reached(self, trip, stop):
        now = timezone.now()
        TransportTripEvent.objects.create(school=self.school, trip=trip, type="stop_reached", stop=stop,
                                          stop_name=stop.name, recorded_by=self.attendant, recorded_at=now,
                                          created_at=now, updated_at=now)

    def bus(self):
        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/bus")
        self.assertEqual(200, response.status_code, getattr(response, "data", None))
        return response.data

    def live(self):
        return self.parent.get(f"{FAMILY}/children/{self.child.id}/bus/live")

    def near_stop_alerts(self):
        return Message.objects.filter(event=MessageEvent.TRANSPORT_NEAR_STOP, student_id=self.child.id)


class TheBusTab(BusTest):
    def test_route_stop_vehicle_and_the_offices_number(self):
        data = self.bus()

        self.assertEqual("Baner Road", data["route"]["name"])
        self.assertEqual({"name": "Bus 3", "registration_number": "MH-12-AB-1234"}, data["vehicle"])
        self.assertEqual(("Sakal Nagar", "07:35", "14:10"),
                         (data["stop"]["name"], data["stop"]["pickup_time"], data["stop"]["drop_time"]))
        self.assertEqual("+91 20 4000 1234", data["contacts"]["office_phone"])

    def test_the_attendants_number_only_when_the_school_allows_it(self):
        self.assertIsNone(self.bus()["contacts"]["attendant"])

        ModuleSetting.objects.update_or_create(
            school=self.school, module="transport",
            defaults={"platform_enabled": True, "school_enabled": True,
                      "settings": {"show_crew_phone_to_parents": True},
                      "created_at": timezone.now(), "updated_at": timezone.now()},
        )

        self.assertEqual({"name": "Ravi Kumar", "mobile": "+91 90000 55555"}, self.bus()["contacts"]["attendant"])

    def test_todays_trip_tells_the_childs_own_part(self):
        trip = self.trip(rider_status="boarded")
        self.reached(trip, self.stop_2)

        [today] = self.bus()["trips"]

        self.assertEqual(("pickup", "boarded", True), (today["direction"], today["rider_status"], today["is_live"]))
        self.assertIsNotNone(today["reached_stop_at"])
        self.assertIsNotNone(today["boarded_at"])

    def test_a_child_without_transport_is_not_found(self):
        StudentTransportAssignment.objects.filter(student=self.child).delete()

        self.assertEqual(404, self.parent.get(f"{FAMILY}/children/{self.child.id}/bus").status_code)


class TheLiveBus(BusTest):
    def test_while_the_childs_trip_runs_the_bus_their_stop_and_how_far(self):
        trip = self.trip()
        self.position(trip, NEAR_STOP_2)

        response = self.live()

        self.assertEqual(200, response.status_code, response.data)
        data = response.data
        self.assertEqual(("pickup", False), (data["direction"], data["position"]["is_stale"]))
        stop = data["your_stop"]
        self.assertEqual(("Sakal Nagar", False, 1), (stop["name"], stop["reached"], stop["stops_before"]))
        self.assertTrue(250 <= stop["distance_m"] <= 350, stop["distance_m"])

    def test_no_trip_running_is_not_live(self):
        self.trip(status="completed")

        response = self.live()

        self.assertEqual(404, response.status_code)
        self.assertEqual("BUS_NOT_LIVE", response.data["code"])

    def test_a_trip_the_child_is_not_on_is_not_live(self):
        self.trip(rider_status=None)

        self.assertEqual("BUS_NOT_LIVE", self.live().data["code"])

    def test_once_dropped_the_bus_is_no_longer_theirs_to_follow(self):
        self.trip(direction="drop", rider_status="dropped")

        self.assertEqual("BUS_NOT_LIVE", self.live().data["code"])

    def test_marked_absent_the_bus_is_not_theirs_either(self):
        self.trip(rider_status="absent")

        self.assertEqual("BUS_NOT_LIVE", self.live().data["code"])


class NearYourStop(BusTest):
    def setUp(self):
        super().setUp()
        ModuleSetting.objects.update_or_create(
            school=self.school, module="communication",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {},
                      "created_at": timezone.now(), "updated_at": timezone.now()},
        )

    def test_the_parent_is_told_once_in_the_app_when_the_bus_is_close(self):
        trip = self.trip()
        self.position(trip, NEAR_STOP_2)

        self.assertEqual(1, family_bus.alert_near_stops(trip))
        self.assertEqual(0, family_bus.alert_near_stops(trip), "only once per trip")

        [alert] = self.near_stop_alerts()
        self.assertEqual(MessageChannel.IN_APP, alert.channel)
        self.assertEqual(self.parent_user.id, alert.user_id)
        self.assertIn("Sakal Nagar", alert.body)
        self.assertIn("300 m", alert.body)

    def test_never_by_sms(self):
        self.assertEqual([MessageChannel.IN_APP], MessageEvent.channels(MessageEvent.TRANSPORT_NEAR_STOP))

    def test_a_bus_still_far_away_says_nothing(self):
        trip = self.trip()
        self.position(trip, FAR_AWAY)

        self.assertEqual(0, family_bus.alert_near_stops(trip))

    def test_a_stop_already_reached_says_nothing(self):
        trip = self.trip()
        self.reached(trip, self.stop_2)
        self.position(trip, NEAR_STOP_2)

        self.assertEqual(0, family_bus.alert_near_stops(trip))

    def test_a_child_already_on_board_for_the_pickup_says_nothing(self):
        trip = self.trip(rider_status="boarded")
        self.position(trip, NEAR_STOP_2)

        self.assertEqual(0, family_bus.alert_near_stops(trip))

    def test_on_the_drop_it_is_the_children_on_board_who_are_coming_home(self):
        trip = self.trip(direction="drop", rider_status="boarded")
        self.position(trip, NEAR_STOP_2)

        self.assertEqual(1, family_bus.alert_near_stops(trip))

    def test_a_position_minutes_old_says_nothing(self):
        trip = self.trip()
        self.position(trip, NEAR_STOP_2, minutes_ago=10)

        self.assertEqual(0, family_bus.alert_near_stops(trip))

    def test_the_school_can_switch_it_off(self):
        ModuleSetting.objects.update_or_create(
            school=self.school, module="transport",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {"near_stop_alert_m": 0},
                      "created_at": timezone.now(), "updated_at": timezone.now()},
        )
        trip = self.trip()
        self.position(trip, NEAR_STOP_2)

        self.assertEqual(0, family_bus.alert_near_stops(trip))

    def test_the_parents_bus_switch_stops_it(self):
        self.parent.patch(f"{FAMILY}/notification-settings", {"transport": False}, format="json")
        trip = self.trip()
        self.position(trip, NEAR_STOP_2)

        family_bus.alert_near_stops(trip)

        self.assertFalse(self.near_stop_alerts().exists())

    def test_the_crews_upload_raises_it(self):
        trip = self.trip()

        response = self.as_user(self.attendant).post(
            f"/api/v1/transport/trips/{trip.id}/locations",
            {"points": [{"latitude": str(NEAR_STOP_2[0]), "longitude": str(NEAR_STOP_2[1]), "accuracy_m": 8,
                         "recorded_at": timezone.now().isoformat()}]},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(self.near_stop_alerts().exists())


class OnlyTheirOwnChildsBus(BusTest):
    def test_another_familys_child_is_not_found(self):
        other = self.other_family_child()

        for path in (f"children/{other.id}/bus", f"children/{other.id}/bus/live"):
            with self.subTest(path=path):
                self.assertEqual(404, self.parent.get(f"{FAMILY}/{path}").status_code)

    def test_a_staff_session_is_refused(self):
        response = self.as_user(self.admin).get(f"{FAMILY}/children/{self.child.id}/bus")

        self.assertEqual("NOT_A_FAMILY_ACCOUNT", response.data["code"])

    def test_transport_switched_off_shows_nothing(self):
        ModuleSetting.objects.update_or_create(
            school=self.school, module="transport",
            defaults={"platform_enabled": True, "school_enabled": False, "settings": {},
                      "created_at": timezone.now(), "updated_at": timezone.now()},
        )

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/bus")

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])


class TheMapKey(BusTest):
    def test_a_family_account_gets_the_map_key(self):
        with self.settings(GOOGLE_MAPS_BROWSER_KEY="browser-key"):
            response = self.parent.get(f"{FAMILY}/maps-config")

        self.assertEqual({"available": True, "browser_key": "browser-key"}, response.data)

    def test_without_a_key_the_app_is_told_so(self):
        with self.settings(GOOGLE_MAPS_BROWSER_KEY=""):
            response = self.parent.get(f"{FAMILY}/maps-config")

        self.assertEqual({"available": False, "browser_key": ""}, response.data)
