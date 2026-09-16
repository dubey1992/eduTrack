"""Transport: the biggest single block in the API, and the only live one.

Twenty-six endpoints across vehicles, drivers, routes, stops, student
assignments and trips. Everything else in this product records something that
already happened; a trip is happening while somebody is looking at it, which
makes it the part where a rewrite's mistakes are least recoverable - a child
marked boarded who is not on the bus is not a data quality problem.

So the trip tests follow a whole journey rather than poking at endpoints:
start, reach a stop, board a rider, end. The state machine is the contract, not
just the shapes.
"""

from __future__ import annotations

import unittest

import shapes
import world


class TransportTest(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        if TransportTest.WORLD is None:
            TransportTest.WORLD = world.shared()

    @property
    def w(self) -> world.World:
        assert TransportTest.WORLD is not None
        return TransportTest.WORLD

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}: expected HTTP 201\n{response!r}")
        return response.body

    def make_vehicle(self, suffix: str) -> dict:
        return self.created(
            self.w.admin.post(
                "/transport/vehicles",
                {
                    "school_id": self.w.school_id,
                    "name": f"Bus {suffix}",
                    "registration_number": f"KA-01-{suffix}",
                    "capacity": 40,
                },
            ),
            "POST a vehicle",
        )

    def make_driver(self, suffix: str) -> dict:
        return self.created(
            self.w.admin.post(
                "/transport/drivers",
                {
                    "school_id": self.w.school_id,
                    "name": f"Driver {suffix}",
                    # Digits only: the suffix is a label like "R1", and a
                    # letter in a phone number is a 422 rather than a driver.
                    "mobile": "+91 90000" + str(abs(hash(suffix)) % 100000).zfill(5),
                    "licence_number": f"LIC-{suffix}",
                    "licence_expiry": "2030-01-01",
                },
            ),
            "POST a driver",
        )

    def make_route(self, suffix: str) -> dict:
        vehicle = self.make_vehicle(suffix)
        driver = self.make_driver(suffix)

        return self.created(
            self.w.admin.post(
                "/transport/routes",
                {
                    "school_id": self.w.school_id,
                    "name": f"Route {suffix}",
                    "vehicle_id": vehicle["id"],
                    "driver_id": driver["id"],
                },
            ),
            "POST a route",
        )

    def make_stop(self, route_id: int, name: str, sequence: int) -> dict:
        return self.created(
            self.w.admin.post(
                f"/transport/routes/{route_id}/stops",
                {"name": name, "sequence_number": sequence, "pickup_time": "07:30", "drop_time": "15:30"},
            ),
            "POST a stop",
        )


class Vehicles(TransportTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/transport/vehicles")

        shapes.assert_paginated(self, response, "GET /transport/vehicles")
        for vehicle in response.data:
            shapes.assert_shape(self, vehicle, shapes.VEHICLE, "a vehicle in the list")

    def test_a_vehicle_can_be_created_read_changed_and_deleted(self):
        created = self.make_vehicle("V1")
        shapes.assert_shape(self, created, shapes.VEHICLE, "POST a vehicle")

        read = self.w.admin.get(f"/transport/vehicles/{created['id']}")
        self.assertEqual(200, read.status, f"GET a vehicle\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.VEHICLE, "GET a vehicle")

        changed = self.w.admin.patch(f"/transport/vehicles/{created['id']}", {"capacity": 45})
        self.assertEqual(200, changed.status, f"PATCH a vehicle\n{changed!r}")
        self.assertEqual(45, changed.body["capacity"])

        self.assertIn(self.w.admin.delete(f"/transport/vehicles/{created['id']}").status, (200, 204))

    def test_another_school_cannot_read_this_vehicles(self):
        created = self.make_vehicle("V2")

        response = self.w.other_admin.get(f"/transport/vehicles/{created['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Drivers(TransportTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/transport/drivers")

        shapes.assert_paginated(self, response, "GET /transport/drivers")
        for driver in response.data:
            shapes.assert_shape(self, driver, shapes.DRIVER, "a driver in the list")

    def test_a_driver_can_be_created_read_changed_and_deleted(self):
        created = self.make_driver("D1")
        shapes.assert_shape(self, created, shapes.DRIVER, "POST a driver")

        read = self.w.admin.get(f"/transport/drivers/{created['id']}")
        self.assertEqual(200, read.status, f"GET a driver\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.DRIVER, "GET a driver")

        changed = self.w.admin.patch(f"/transport/drivers/{created['id']}", {"name": "Renamed Driver"})
        self.assertEqual(200, changed.status, f"PATCH a driver\n{changed!r}")

        self.assertIn(self.w.admin.delete(f"/transport/drivers/{created['id']}").status, (200, 204))

    def test_another_school_cannot_read_this_drivers(self):
        created = self.make_driver("D2")

        response = self.w.other_admin.get(f"/transport/drivers/{created['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Routes(TransportTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/transport/routes")

        shapes.assert_paginated(self, response, "GET /transport/routes")
        for route in response.data:
            shapes.assert_shape(self, route, shapes.ROUTE, "a route in the list")

    def test_a_route_carries_its_vehicle_driver_and_stops(self):
        # The client draws a route as one card: bus, driver, stops, counts. A
        # route that answers with only its own columns renders as an empty row.
        route = self.make_route("R1")
        self.make_stop(route["id"], "Green Park", 1)
        self.make_stop(route["id"], "Central Square", 2)

        read = self.w.admin.get(f"/transport/routes/{route['id']}")
        self.assertEqual(200, read.status, f"GET a route\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.ROUTE_DETAIL, "GET a route")

        self.assertIsNotNone(read.body["vehicle_id"], "the route was given a vehicle")
        self.assertIsNotNone(read.body["driver_id"], "the route was given a driver")
        self.assertEqual(2, read.body["stops_count"], "both stops are counted")

        for stop in read.body["stops"]:
            shapes.assert_shape(self, stop, shapes.STOP, "a stop on a route")

    def test_a_stop_can_be_changed_and_removed(self):
        route = self.make_route("R2")
        stop = self.make_stop(route["id"], "Temporary Stop", 1)
        shapes.assert_shape(self, stop, shapes.STOP, "POST a stop")

        changed = self.w.admin.patch(f"/transport/stops/{stop['id']}", {"pickup_time": "07:45"})
        self.assertEqual(200, changed.status, f"PATCH a stop\n{changed!r}")

        self.assertIn(self.w.admin.delete(f"/transport/stops/{stop['id']}").status, (200, 204))

    def test_a_route_can_be_changed_and_deleted(self):
        route = self.make_route("R3")

        changed = self.w.admin.patch(f"/transport/routes/{route['id']}", {"name": "Renamed Route"})
        self.assertEqual(200, changed.status, f"PATCH a route\n{changed!r}")

        self.assertIn(self.w.admin.delete(f"/transport/routes/{route['id']}").status, (200, 204))

    def test_another_school_cannot_read_this_routes(self):
        route = self.make_route("R4")

        response = self.w.other_admin.get(f"/transport/routes/{route['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class StudentAssignment(TransportTest):
    def test_a_student_is_assigned_to_a_stop_and_appears_on_the_route(self):
        route = self.make_route("A1")
        stop = self.make_stop(route["id"], "Oak Avenue", 1)

        assigned = self.w.admin.put(
            f"/students/{self.w.student_id}/transport",
            {"route_id": route["id"], "transport_stop_id": stop["id"]},
        )
        self.assertEqual(200, assigned.status, f"PUT student transport\n{assigned!r}")

        riders = self.w.admin.get(f"/transport/routes/{route['id']}/students")
        self.assertEqual(200, riders.status, f"GET route students\n{riders!r}")

        listed = [r for r in riders.data if r["student_id"] == self.w.student_id]
        self.assertEqual(1, len(listed), "the assigned student should be on the route")
        shapes.assert_shape(self, listed[0], shapes.ROUTE_STUDENT, "a student on a route")
        self.assertEqual(stop["id"], listed[0]["stop_id"], "and at the stop they were given")

    def test_an_assignment_can_be_taken_away(self):
        route = self.make_route("A2")
        stop = self.make_stop(route["id"], "Elm Street", 1)

        self.assertEqual(
            200,
            self.w.admin.put(
                f"/students/{self.w.student_id}/transport",
                {"route_id": route["id"], "transport_stop_id": stop["id"]},
            ).status,
        )

        removed = self.w.admin.delete(f"/students/{self.w.student_id}/transport")
        self.assertIn(removed.status, (200, 204), f"DELETE student transport\n{removed!r}")

        riders = self.w.admin.get(f"/transport/routes/{route['id']}/students")
        self.assertEqual([], [r for r in riders.data if r["student_id"] == self.w.student_id])


class Trips(TransportTest):
    """A whole journey, because the state machine is the contract."""

    def running_trip(self, suffix: str) -> tuple[dict, dict, dict]:
        """A started trip with one stop and one rider on it."""
        route = self.make_route(suffix)
        stop = self.make_stop(route["id"], f"Stop {suffix}", 1)

        self.assertEqual(
            200,
            self.w.admin.put(
                f"/students/{self.w.student_id}/transport",
                {"route_id": route["id"], "transport_stop_id": stop["id"]},
            ).status,
            "the rider has to be on the route before a trip can carry them",
        )

        trip = self.created(
            self.w.admin.post("/transport/trips", {"route_id": route["id"], "direction": "pickup"}),
            "POST a trip",
        )

        return route, stop, trip

    def test_the_trip_list_is_shaped(self):
        response = self.w.admin.get("/transport/trips")

        self.assertEqual(200, response.status, f"GET /transport/trips\n{response!r}")
        for trip in response.data:
            shapes.assert_shape(self, trip, shapes.TRIP, "a trip in the list")

    def test_a_trip_carries_its_riders_stops_and_counts(self):
        _, _, trip = self.running_trip("T1")

        read = self.w.admin.get(f"/transport/trips/{trip['id']}")
        self.assertEqual(200, read.status, f"GET a trip\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.TRIP_DETAIL, "GET a trip")

        self.assertGreaterEqual(len(read.body["riders"]), 1, "the assigned student should be aboard the manifest")
        for rider in read.body["riders"]:
            shapes.assert_shape(self, rider, shapes.TRIP_RIDER, "a rider on a trip")

        self.assertEqual("pending", read.body["riders"][0]["status"], "nobody has boarded yet")

    def test_a_stop_is_reached_and_a_rider_boards(self):
        _, stop, trip = self.running_trip("T2")

        reached = self.w.admin.post(f"/transport/trips/{trip['id']}/stops/{stop['id']}/reached")
        self.assertEqual(200, reached.status, f"POST stop reached\n{reached!r}")

        boarded = self.w.admin.patch(
            f"/transport/trips/{trip['id']}/riders/{self.w.student_id}",
            {"status": "boarded"},
        )
        self.assertEqual(200, boarded.status, f"PATCH a rider\n{boarded!r}")

        read = self.w.admin.get(f"/transport/trips/{trip['id']}")
        rider = [r for r in read.body["riders"] if r["student_id"] == self.w.student_id][0]
        self.assertEqual("boarded", rider["status"])
        self.assertIsNotNone(rider["boarded_at"], "boarding records when, not just that")

    def test_a_trip_cannot_end_with_somebody_still_aboard(self):
        # The rule the whole module exists for. Ending a trip with a child
        # recorded as on the bus means nobody knows where they got off, so the
        # API refuses rather than closing the record quietly.
        _, stop, trip = self.running_trip("T3")

        self.assertEqual(200, self.w.admin.post(f"/transport/trips/{trip['id']}/stops/{stop['id']}/reached").status)
        self.assertEqual(
            200,
            self.w.admin.patch(
                f"/transport/trips/{trip['id']}/riders/{self.w.student_id}", {"status": "boarded"}
            ).status,
        )

        refused = self.w.admin.post(f"/transport/trips/{trip['id']}/end")
        self.assertIn(
            refused.status,
            (409, 422),
            f"ending a trip with a rider aboard must be refused\n{refused!r}",
        )

    def test_a_trip_ends_once_everybody_is_off(self):
        _, stop, trip = self.running_trip("T4")

        self.assertEqual(200, self.w.admin.post(f"/transport/trips/{trip['id']}/stops/{stop['id']}/reached").status)
        self.assertEqual(
            200,
            self.w.admin.patch(
                f"/transport/trips/{trip['id']}/riders/{self.w.student_id}", {"status": "absent"}
            ).status,
            "a rider who never boarded is marked absent, not left pending",
        )

        ended = self.w.admin.post(f"/transport/trips/{trip['id']}/end")
        self.assertEqual(200, ended.status, f"POST end\n{ended!r}")
        self.assertEqual("completed", ended.body["status"])
        self.assertIsNotNone(ended.body["ended_at"], "an ended trip records when")

    def test_a_trip_can_be_cancelled(self):
        _, _, trip = self.running_trip("T5")

        cancelled = self.w.admin.post(f"/transport/trips/{trip['id']}/cancel")
        self.assertEqual(200, cancelled.status, f"POST cancel\n{cancelled!r}")
        self.assertEqual("cancelled", cancelled.body["status"])

    def test_another_school_cannot_see_this_trip(self):
        _, _, trip = self.running_trip("T6")

        response = self.w.other_admin.get(f"/transport/trips/{trip['id']}")
        self.assertEqual(403, response.status, f"cross-school trip\n{response!r}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
