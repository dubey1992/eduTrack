"""The smart bus (docs/mobile-apps-review.md, M7): a stop the Driver app
marked Reached by itself, "The bus has reached your stop" (off until the
school turns it on), and the crew's one-tap "Running late".

Decided by the owner 2026-11-24: the at-stop alert goes out whether Reached
was tapped or detected, once per stop per trip; the delay offers 10, 15 and
30 minutes and nothing else.
"""

import datetime as dt

from school.models import (
    CommunicationSetting,
    Message,
    ModuleSetting,
    TransportTrip,
    TransportTripEvent,
    TransportTripRider,
)

from . import test_attendants_api as attendants
from .test_transport_trips_api import TRIPS, WEDNESDAY


class SmartBusTest(attendants.AttendantTest):
    """The attendant's running trip, as test_attendants_api.Syncing sets it
    up - copied rather than inherited, so its tests do not run again here."""

    def setUp(self):
        super().setUp()
        self.trip_id = self.start(user=self.attendant).data["id"]
        TransportTrip.objects.filter(pk=self.trip_id).update(started_at=WEDNESDAY - dt.timedelta(hours=1))
        self.lake_view, self.central_park = self.f["stops"]

    def sync(self, operations, user=None):
        return self.as_user(user or self.attendant).post(
            f"{TRIPS}/{self.trip_id}/sync", {"operations": operations}, format="json"
        )

    def op(self, client_id, kind, minutes, stop=None, student=None):
        return {"client_id": client_id, "type": kind, "occurred_at": attendants.at(minutes),
                "stop_id": stop.id if stop else None, "student_id": student.id if student else None}

    def turn_on_at_stop_alert(self, **more):
        ModuleSetting.objects.update_or_create(
            school_id=self.f["school"].id, module="transport",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {"at_stop_alert": True, **more}},
        )

    def riders_at(self, stop):
        return list(TransportTripRider.objects.filter(trip_id=self.trip_id, stop_id=stop.id).select_related("student"))

    def told(self, event):
        """The students whose guardians got [event], once each."""
        return set(Message.objects.filter(event=event).values_list("student_id", flat=True))

    def reach(self, client_id, stop, minutes=-20, auto=False):
        return self.sync([{**self.op(client_id, "stop_reached", minutes, stop=stop), "auto": auto}])

    def delay(self, client_id, late, minutes=-10):
        return self.sync([{**self.op(client_id, "delay", minutes), "minutes": late}])


class ReachedByItself(SmartBusTest):
    def test_an_automatic_reached_is_recorded_and_says_so(self):
        response = self.reach("auto-0001", self.lake_view, auto=True)

        self.assertEqual("applied", response.data["results"][0]["status"], response.data)
        event = TransportTripEvent.objects.get(client_id="auto-0001")
        self.assertEqual(("stop_reached", "Reached automatically"), (event.type, event.note))

    def test_a_tapped_reached_carries_no_such_note(self):
        self.reach("tap-00001", self.lake_view)

        self.assertIsNone(TransportTripEvent.objects.get(client_id="tap-00001").note)

    def test_the_trip_tells_the_phone_how_close_to_mark_it(self):
        trip = self.as_user(self.attendant).get(f"{TRIPS}/{self.trip_id}").json()
        self.assertEqual(50, trip["auto_reach_m"])

        ModuleSetting.objects.update_or_create(
            school_id=self.f["school"].id, module="transport",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {"auto_reach_m": 0}},
        )
        self.assertEqual(0, self.as_user(self.attendant).get(f"{TRIPS}/{self.trip_id}").json()["auto_reach_m"])


class AtTheStop(SmartBusTest):
    def test_off_until_the_school_turns_it_on(self):
        self.reach("tap-00001", self.lake_view)

        self.assertEqual(set(), self.told("transport.at_stop"))

    def test_once_on_the_parents_waiting_at_that_stop_are_told(self):
        self.turn_on_at_stop_alert()
        waiting = {rider.student_id for rider in self.riders_at(self.lake_view)}
        self.assertTrue(waiting, "the fixture has children at Lake View")

        self.reach("tap-00001", self.lake_view)

        self.assertEqual(waiting, self.told("transport.at_stop"))
        body = Message.objects.filter(event="transport.at_stop").first().body
        self.assertIn(self.lake_view.name, body)

    def test_it_goes_out_whether_reached_was_tapped_or_detected(self):
        self.turn_on_at_stop_alert()

        self.reach("auto-0001", self.lake_view, auto=True)

        self.assertEqual({r.student_id for r in self.riders_at(self.lake_view)}, self.told("transport.at_stop"))

    def test_a_stop_is_announced_once_even_if_marked_twice(self):
        self.turn_on_at_stop_alert()
        self.reach("auto-0001", self.lake_view, auto=True)
        first = Message.objects.filter(event="transport.at_stop").count()

        self.reach("tap-00001", self.lake_view, minutes=-19)

        self.assertEqual(first, Message.objects.filter(event="transport.at_stop").count())

    def test_a_child_already_aboard_or_absent_is_not_waiting(self):
        self.turn_on_at_stop_alert()
        at_stop = self.riders_at(self.lake_view)
        self.sync([self.op("mark-0001", "absent", -25, student=at_stop[0].student)])

        self.reach("tap-00001", self.lake_view)

        self.assertNotIn(at_stop[0].student_id, self.told("transport.at_stop"))

    def test_the_schools_transport_switch_still_rules(self):
        self.turn_on_at_stop_alert()
        CommunicationSetting.objects.update_or_create(
            school_id=self.f["school"].id,
            defaults={"sms_enabled": True, "attendance_alerts": "absent_only", "transport_alerts_enabled": False,
                      "leave_alerts_enabled": True, "provider": "log"},
        )

        self.reach("tap-00001", self.lake_view)

        self.assertFalse(Message.objects.filter(event="transport.at_stop").exists())


class RunningLate(SmartBusTest):
    def test_the_parents_still_waiting_on_the_route_are_told_by_how_much(self):
        boarded = self.f["students"][0]
        self.sync([self.op("mark-0001", "boarded", -15, student=boarded)])
        waiting = set(
            TransportTripRider.objects.filter(trip_id=self.trip_id, status="pending").values_list("student_id", flat=True)
        )

        response = self.delay("late-0001", 15)

        self.assertEqual("applied", response.data["results"][0]["status"], response.data)
        self.assertEqual(waiting, self.told("transport.delay"))
        self.assertNotIn(boarded.id, self.told("transport.delay"))
        self.assertIn("about 15 minutes late", Message.objects.filter(event="transport.delay").first().body)

    def test_the_office_sees_it_on_the_trip(self):
        self.delay("late-0001", 30)

        trip = self.as_user(self.f["manager"]).get(f"{TRIPS}/{self.trip_id}").json()
        event = next(e for e in trip["events"] if e["type"] == "delay_reported")
        self.assertEqual("Running about 30 minutes late", event["note"])

    def test_only_ten_fifteen_or_thirty_minutes(self):
        for late in (20, 0, "15", None):
            response = self.delay(f"late-{late}-01", late)
            self.assertEqual(422, response.status_code, late)

        self.assertFalse(TransportTripEvent.objects.filter(type="delay_reported").exists())

    def test_sent_twice_it_is_recorded_once(self):
        self.delay("late-0001", 10)
        messages = Message.objects.filter(event="transport.delay").count()

        again = self.delay("late-0001", 10)

        self.assertEqual("duplicate", again.data["results"][0]["status"])
        self.assertEqual(messages, Message.objects.filter(event="transport.delay").count())

    def test_not_after_the_trip_has_ended(self):
        for rider in TransportTripRider.objects.filter(trip_id=self.trip_id):
            self.sync([self.op(f"absent-{rider.student_id:04d}", "absent", -30, student=rider.student)])
        self.sync([self.op("end-00001", "end", -5)])

        response = self.delay("late-0001", 10, minutes=-4)

        self.assertEqual("rejected", response.data["results"][0]["status"])


class TheSettings(SmartBusTest):
    def test_both_are_offered_to_the_school_with_their_defaults(self):
        response = self.as_user(self.f["admin"]).get("/api/v1/settings/modules")

        transport = next(row for row in response.data if row["module"] == "transport")
        schema = {row["key"]: row for row in transport["settings_schema"]}
        self.assertEqual(("int", 50, 0, 200), (schema["auto_reach_m"]["type"], schema["auto_reach_m"]["default"],
                                               schema["auto_reach_m"]["min"], schema["auto_reach_m"]["max"]))
        self.assertEqual(("bool", False), (schema["at_stop_alert"]["type"], schema["at_stop_alert"]["default"]))

    def test_a_distance_out_of_range_is_refused(self):
        response = self.as_user(self.f["admin"]).put(
            "/api/v1/settings/modules/transport", {"settings": {"auto_reach_m": 500}}, format="json"
        )

        self.assertEqual(422, response.status_code)
