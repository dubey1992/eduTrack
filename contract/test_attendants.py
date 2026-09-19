"""The Bus Attendant - served by the Python backend only (docs/maps.md).

Against Laravel these skip. Against Django they walk the whole path the two
Flutter screens depend on: an admin creates an attendant with no email and
no password, issues a setup code, the phone registers and signs in with a
passcode, the attendant sees only their route, and a revoked phone stops
working. Starting a trip needs a school day, so the sync part is skipped at
the weekend rather than failing.
"""

from __future__ import annotations

import datetime as dt
import random
import unittest
import uuid

import coverage
import shapes
from client import Client
from test_transport import TransportTest

ACCESS = {"login_mobile": "str", "has_passcode": "bool", "is_locked": "bool", "setup_code_pending": "bool", "devices": "list"}


class Attendants(TransportTest):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        probe = cls.WORLD.admin.get("/transport/my-routes")
        if probe.status == 404:
            raise unittest.SkipTest("the Bus Attendant is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    def make_attendant(self) -> tuple[dict, str]:
        mobile = f"+91 9{random.randint(100000000, 999999999)}"
        created = self.created(
            self.w.admin.post("/staff", {
                "school_id": self.w.school_id, "first_name": "Contract", "last_name": "Attendant", "mobile": mobile,
                "role": "BUS_ATTENDANT", "employee_id": f"ATT-{uuid.uuid4().hex[:8]}", "joining_date": "2026-04-01",
            }),
            "POST an attendant",
        )
        self.assertFalse(created["has_email"])

        return created, mobile

    def test_an_attendant_is_set_up_signs_in_and_reaches_only_their_route(self):
        attendant, mobile = self.make_attendant()

        route = self.make_route(f"ATT{uuid.uuid4().hex[:4]}")
        assigned = self.w.admin.patch(f"/transport/routes/{route['id']}", {"attendant_user_id": attendant["user_id"]})
        self.assertEqual(200, assigned.status, f"{assigned!r}")
        self.assertEqual(attendant["user_id"], assigned.body["attendant_user_id"])

        code = self.created(self.w.admin.post(f"/staff/{attendant['id']}/attendant/setup-code"), "POST a setup code")
        self.assertRegex(code["setup_code"], r"^\d{8}$")

        anonymous = Client()
        registered = anonymous.post("/auth/attendant/setup", {"mobile": mobile, "setup_code": code["setup_code"], "passcode": "4827"})
        self.assertEqual(201, registered.status, f"{registered!r}")
        secret = registered.body["device_secret"]

        signed_in = anonymous.post("/auth/attendant/login", {"mobile": mobile, "passcode": "4827", "device_secret": secret})
        self.assertEqual(200, signed_in.status, f"{signed_in!r}")
        phone = Client(token=signed_in.body["token"])

        mine = phone.get("/transport/my-routes")
        self.assertEqual(200, mine.status, f"{mine!r}")
        self.assertEqual([route["id"]], [row["id"] for row in mine.body["routes"]])
        self.assertEqual({"pickup", "drop"}, set(mine.body["routes"][0]["today"]))

        self.assertEqual(403, phone.get("/transport/vehicles").status)

        access = self.w.admin.get(f"/staff/{attendant['id']}/attendant")
        shapes.assert_shape(self, access.body, ACCESS, "GET /staff/{profile}/attendant")
        device_id = access.body["devices"][0]["id"]

        revoked = self.w.admin.delete(f"/staff/{attendant['id']}/attendant/devices/{device_id}")
        self.assertEqual(200, revoked.status, f"{revoked!r}")
        self.assertEqual(401, phone.get("/me").status)

        again = Client().post("/auth/attendant/login", {"mobile": mobile, "passcode": "4827", "device_secret": secret})
        self.assertEqual((401, "DEVICE_NOT_REGISTERED"), (again.status, again.body["code"]))

    def test_a_trip_is_synced_from_the_phone_and_its_position_reported(self):
        route, stop, trip = self.try_running_trip()

        now = dt.datetime.now(dt.timezone.utc).isoformat()
        synced = self.w.admin.post(f"/transport/trips/{trip['id']}/sync", {"operations": [
            {"client_id": uuid.uuid4().hex, "type": "stop_reached", "stop_id": stop["id"], "occurred_at": now},
        ]})
        self.assertEqual(200, synced.status, f"{synced!r}")
        self.assertEqual("applied", synced.body["results"][0]["status"])

        reported = self.w.admin.post(f"/transport/trips/{trip['id']}/locations", {"points": [
            {"latitude": "18.52", "longitude": "73.85", "accuracy": 10, "recorded_at": now},
        ]})
        self.assertEqual({"accepted": 1, "refused": 0}, reported.body)

        live = self.w.admin.get(f"/transport/trips/{trip['id']}/live")
        self.assertEqual(200, live.status, f"{live!r}")
        self.assertEqual("18.5200000", live.body["position"]["latitude"])

        self.w.admin.post(f"/transport/trips/{trip['id']}/cancel")

    def try_running_trip(self):
        suffix = f"SYN{uuid.uuid4().hex[:4]}"
        route = self.make_route(suffix)
        stop = self.make_stop(route["id"], f"Stop {suffix}", 1)
        self.w.admin.put(f"/students/{self.w.student_id}/transport", {"route_id": route["id"], "transport_stop_id": stop["id"]})
        started = self.w.admin.post("/transport/trips", {"route_id": route["id"], "direction": "pickup"})

        if started.status == 409:
            self.skipTest(f"no trip can start today: {started.body.get('message')}")

        trip = self.created(started, "POST a trip")

        return route, stop, trip
