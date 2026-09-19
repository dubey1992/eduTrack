"""Transport master data, over HTTP: vehicles, drivers, routes, stops and which
student rides which route.

**Read by everybody in transport at the school, changed only by its admins.**
A staff clerk reads none of it; a teacher reads it and changes nothing; the
transport manager sees who rides a route but does not edit the routes.

**Nothing in use is deleted.** A vehicle or driver on a route, a route with
riders or trip history, a stop with riders - each is refused with a sentence
naming what is in the way.

**A route's vehicle and driver are this school's, active, and not already on
another route** - except that a route keeps what it already has even after
that vehicle or driver is deactivated.

**A vehicle's seats are a hard limit** on how many students a route takes, but
moving a student already on the route between its own stops always works.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Driver, StudentTransportAssignment, TransportRoute, TransportStop, TransportTrip, Vehicle


class TransportTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = self.user(UserRole.SCHOOL_ADMIN)
        self.teacher = self.user(UserRole.TEACHER)
        self.clerk = self.user(UserRole.STAFF)
        self.manager = self.user(UserRole.TRANSPORT_MANAGER)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def user(self, role, school=None):
        return factories.UserFactory(school=school or self.school, role=role)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def student(self, school=None, **fields):
        school = school or self.school
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=school, academic_year=factories.AcademicYearFactory(school=school))
        )

        return factories.StudentFactory(school=school, class_section=section, **fields)

    def ride(self, student, route, stop):
        return StudentTransportAssignment.objects.create(
            school_id=student.school_id, student=student, route=route, transport_stop=stop
        )

    def trip(self, route):
        return TransportTrip.objects.create(
            school_id=route.school_id, route=route, vehicle_id=route.vehicle_id, driver_id=route.driver_id,
            direction="pickup", trip_date=dt.date(2026, 9, 14), status="completed",
            started_by_id=self.admin.id, started_at=dt.datetime(2026, 9, 14, 2, tzinfo=dt.timezone.utc),
        )


class VehicleTest(TransportTestCase):
    URL = "/api/v1/transport/vehicles"

    def add(self, user, **overrides):
        body = {"name": "Bus 3", "registration_number": "KA-01-AB-1234", "capacity": 40}
        body.update(overrides)

        return self.as_user(user).post(self.URL, body, format="json")

    def test_a_school_admin_adds_a_vehicle_to_their_own_school(self):
        response = self.add(self.admin, school_id=self.elsewhere.id)

        self.assertEqual(201, response.status_code)
        self.assertEqual(
            (self.school.id, "active", None, None),
            (response.data["school_id"], response.data["status"], response.data["route_id"], response.data["route_name"]),
        )

    def test_a_super_admin_names_the_school(self):
        self.assertIn("school_id", self.errors(self.add(self.root)))
        self.assertEqual(self.elsewhere.id, self.add(self.root, school_id=self.elsewhere.id).data["school_id"])

    def test_only_admins_add_vehicles(self):
        for user in (self.teacher, self.clerk, self.manager):
            self.assertEqual(403, self.add(user, name="").status_code)

    def test_the_fields_and_capacity_bounds(self):
        empty = self.as_user(self.admin).post(self.URL, {}, format="json")
        bad = self.add(self.admin, name="x" * 51, registration_number="y" * 31, capacity=0)
        many = self.add(self.admin, capacity=201)
        words = self.add(self.admin, capacity="many")

        self.assertEqual(["name", "registration_number", "capacity"], list(self.errors(empty)))
        self.assertEqual(["The capacity field must be at least 1."], self.errors(bad)["capacity"])
        self.assertEqual(["The capacity field must not be greater than 200."], self.errors(many)["capacity"])
        self.assertEqual(["The capacity field must be an integer."], self.errors(words)["capacity"])

    def test_a_registration_number_is_unique_within_a_school_only(self):
        factories.VehicleFactory(school=self.school, registration_number="KA-01-AB-1234")
        factories.VehicleFactory(school=self.elsewhere, registration_number="KA-09-ZZ-0001")

        self.assertEqual(["The registration number has already been taken."], self.errors(self.add(self.admin))["registration_number"])
        self.assertEqual(201, self.add(self.admin, registration_number="KA-09-ZZ-0001").status_code)

    def test_viewing_roles_see_their_school_and_a_clerk_sees_nothing(self):
        factories.VehicleFactory(school=self.school)
        factories.VehicleFactory(school=self.elsewhere)

        for user in (self.admin, self.teacher, self.manager):
            self.assertEqual(1, len(self.as_user(user).get(self.URL).data["data"]))

        self.assertEqual(403, self.as_user(self.clerk).get(self.URL).status_code)
        self.assertEqual(2, len(self.as_user(self.root).get(self.URL).data["data"]))

    def test_a_super_admin_filters_by_school_and_status(self):
        factories.VehicleFactory(school=self.school, status="inactive")
        factories.VehicleFactory(school=self.school)
        factories.VehicleFactory(school=self.elsewhere)

        response = self.as_user(self.root).get(f"{self.URL}?school_id={self.school.id}&status=inactive")

        self.assertEqual(1, len(response.data["data"]))

    def test_the_list_says_which_route_a_vehicle_serves(self):
        vehicle = factories.VehicleFactory(school=self.school)
        route = factories.TransportRouteFactory(school=self.school, vehicle=vehicle, name="Route A")

        row = self.as_user(self.admin).get(self.URL).data["data"][0]

        self.assertEqual((route.id, "Route A"), (row["route_id"], row["route_name"]))

    def test_another_schools_vehicle_is_not_viewed_changed_or_deleted(self):
        vehicle = factories.VehicleFactory(school=self.elsewhere)
        client = self.as_user(self.admin)

        self.assertEqual(403, client.get(f"{self.URL}/{vehicle.id}").status_code)
        self.assertEqual(403, client.patch(f"{self.URL}/{vehicle.id}", {"name": "Mine"}, format="json").status_code)
        self.assertEqual(403, client.delete(f"{self.URL}/{vehicle.id}").status_code)

    def test_a_school_admin_updates_and_deactivates(self):
        vehicle = factories.VehicleFactory(school=self.school)

        response = self.as_user(self.admin).patch(
            f"{self.URL}/{vehicle.id}", {"name": "Bus 9", "status": "inactive"}, format="json"
        )

        self.assertEqual(("Bus 9", "inactive"), (response.data["name"], response.data["status"]))

    def test_a_blank_field_on_update_is_required_and_a_bad_status_is_named(self):
        vehicle = factories.VehicleFactory(school=self.school)

        response = self.as_user(self.admin).patch(f"{self.URL}/{vehicle.id}", {"name": "", "status": "broken"}, format="json")

        self.assertEqual(
            {"name": ["The name field is required."], "status": ["The selected status is invalid."]},
            self.errors(response),
        )

    def test_a_teacher_neither_updates_nor_deletes(self):
        vehicle = factories.VehicleFactory(school=self.school)
        client = self.as_user(self.teacher)

        self.assertEqual(403, client.patch(f"{self.URL}/{vehicle.id}", {"name": ""}, format="json").status_code)
        self.assertEqual(403, client.delete(f"{self.URL}/{vehicle.id}").status_code)

    def test_a_vehicle_on_a_route_or_with_trips_is_not_deleted(self):
        serving = factories.VehicleFactory(school=self.school)
        factories.TransportRouteFactory(school=self.school, vehicle=serving)
        retired = factories.VehicleFactory(school=self.school)
        old_route = factories.TransportRouteFactory(school=self.school, vehicle=retired, driver=factories.DriverFactory(school=self.school))
        self.trip(old_route)
        TransportRoute.objects.filter(pk=old_route.pk).update(vehicle=None)
        client = self.as_user(self.admin)

        on_route = client.delete(f"{self.URL}/{serving.id}")
        with_trips = client.delete(f"{self.URL}/{retired.id}")

        self.assertEqual(("HAS_DEPENDENT_RECORDS", "This vehicle is still serving a route. Remove it from the route first."),
                         (on_route.data["code"], on_route.data["message"]))
        self.assertEqual("This vehicle has trip history and cannot be deleted. Deactivate it instead.", with_trips.data["message"])

    def test_an_unused_vehicle_is_deleted(self):
        vehicle = factories.VehicleFactory(school=self.school)

        self.assertEqual(204, self.as_user(self.admin).delete(f"{self.URL}/{vehicle.id}").status_code)
        self.assertFalse(Vehicle.objects.exists())


class DriverTest(TransportTestCase):
    URL = "/api/v1/transport/drivers"

    def add(self, user, **overrides):
        body = {"name": "Ramesh", "licence_number": "DL-0420110012345"}
        body.update(overrides)

        return self.as_user(user).post(self.URL, body, format="json")

    def test_a_school_admin_adds_a_driver(self):
        response = self.add(self.admin, mobile="+91 98765 43210", licence_expiry="2030-01-31")

        self.assertEqual(201, response.status_code)
        self.assertEqual(("+91 98765 43210", "2030-01-31"), (response.data["mobile"], response.data["licence_expiry"]))

    def test_mobile_and_expiry_are_optional_but_checked_when_given(self):
        self.assertEqual(201, self.add(self.admin, mobile="", licence_expiry=None).status_code)

        response = self.add(self.admin, licence_number="DL-2", mobile="9876543210", licence_expiry="never")

        self.assertEqual(
            {"mobile": ["The mobile field format is invalid."], "licence_expiry": ["The licence expiry field must be a valid date."]},
            self.errors(response),
        )

    def test_a_licence_number_is_unique_within_a_school_only(self):
        factories.DriverFactory(school=self.school, licence_number="DL-1")
        factories.DriverFactory(school=self.elsewhere, licence_number="DL-2")

        self.assertEqual(["The licence number has already been taken."], self.errors(self.add(self.admin, licence_number="DL-1"))["licence_number"])
        self.assertEqual(201, self.add(self.admin, licence_number="DL-2").status_code)

    def test_non_admins_do_not_change_drivers(self):
        driver = factories.DriverFactory(school=self.school)

        for user in (self.teacher, self.manager):
            client = self.as_user(user)
            self.assertEqual(403, self.add(user).status_code)
            self.assertEqual(403, client.patch(f"{self.URL}/{driver.id}", {}, format="json").status_code)
            self.assertEqual(403, client.delete(f"{self.URL}/{driver.id}").status_code)

    def test_a_clerk_sees_no_drivers_and_a_stranger_none_of_ours(self):
        driver = factories.DriverFactory(school=self.school)

        self.assertEqual(403, self.as_user(self.clerk).get(self.URL).status_code)
        self.assertEqual(403, self.as_user(self.stranger).get(f"{self.URL}/{driver.id}").status_code)
        self.assertEqual([], self.as_user(self.stranger).get(self.URL).data["data"])

    def test_an_update_can_clear_the_mobile_and_leaves_what_it_did_not_send(self):
        driver = factories.DriverFactory(school=self.school, mobile="+91 9876543210", licence_number="DL-7")

        response = self.as_user(self.admin).patch(f"{self.URL}/{driver.id}", {"mobile": None, "status": "inactive"}, format="json")

        self.assertEqual((None, "DL-7", "inactive"), (response.data["mobile"], response.data["licence_number"], response.data["status"]))

    def test_a_driver_on_a_route_is_not_deleted_but_an_unused_one_is(self):
        busy = factories.DriverFactory(school=self.school)
        factories.TransportRouteFactory(school=self.school, driver=busy)
        idle = factories.DriverFactory(school=self.school)
        client = self.as_user(self.admin)

        self.assertEqual("This driver is still assigned to a route. Remove them from the route first.",
                         client.delete(f"{self.URL}/{busy.id}").data["message"])
        self.assertEqual(204, client.delete(f"{self.URL}/{idle.id}").status_code)
        self.assertEqual([busy.id], list(Driver.objects.values_list("id", flat=True)))


class RouteTest(TransportTestCase):
    URL = "/api/v1/transport/routes"

    def create(self, user, **overrides):
        body = {"name": "Route A"}
        body.update(overrides)

        return self.as_user(user).post(self.URL, body, format="json")

    def test_a_school_admin_creates_a_route_with_a_vehicle_and_driver(self):
        vehicle = factories.VehicleFactory(school=self.school, name="Bus 3", capacity=32)
        driver = factories.DriverFactory(school=self.school, name="Ramesh", mobile="+91 9000000001")

        response = self.create(self.admin, vehicle_id=vehicle.id, driver_id=driver.id)

        self.assertEqual(201, response.status_code)
        self.assertEqual(
            ("Bus 3 - Route A", 32, "Ramesh", "+91 9000000001", 0, 0, []),
            (response.data["label"], response.data["capacity"], response.data["driver_name"],
             response.data["driver_mobile"], response.data["stops_count"], response.data["students_count"], response.data["stops"]),
        )

    def test_a_route_without_a_vehicle_is_labelled_by_its_name(self):
        self.assertEqual("Route A", self.create(self.admin).data["label"])

    def test_a_route_name_is_unique_within_a_school_only(self):
        factories.TransportRouteFactory(school=self.school, name="Route A")
        factories.TransportRouteFactory(school=self.elsewhere, name="Route B")

        self.assertEqual(["The name has already been taken."], self.errors(self.create(self.admin))["name"])
        self.assertEqual(201, self.create(self.admin, name="Route B").status_code)

    def test_a_foreign_or_inactive_vehicle_or_driver_is_refused(self):
        foreign = factories.VehicleFactory(school=self.elsewhere)
        inactive = factories.DriverFactory(school=self.school, status="inactive")

        response = self.create(self.admin, vehicle_id=foreign.id, driver_id=inactive.id)

        self.assertEqual(
            {
                "vehicle_id": ["The selected vehicle is not an active vehicle of this school."],
                "driver_id": ["The selected driver is not an active driver of this school."],
            },
            self.errors(response),
        )

    def test_a_vehicle_or_driver_already_on_a_route_is_refused(self):
        vehicle = factories.VehicleFactory(school=self.school)
        driver = factories.DriverFactory(school=self.school)
        factories.TransportRouteFactory(school=self.school, vehicle=vehicle, driver=driver)

        response = self.create(self.admin, vehicle_id=vehicle.id, driver_id=driver.id)

        self.assertEqual(
            {
                "vehicle_id": ["That vehicle is already serving another route."],
                "driver_id": ["That driver is already assigned to another route."],
            },
            self.errors(response),
        )

    def test_a_junk_driver_id_is_only_that(self):
        self.assertEqual(["The driver id field must be an integer."], self.errors(self.create(self.admin, driver_id="abc"))["driver_id"])

    def test_non_admins_do_not_create_routes(self):
        for user in (self.teacher, self.manager, self.clerk):
            self.assertEqual(403, self.create(user).status_code)

    def test_a_route_keeps_its_own_deactivated_vehicle_and_can_swap_it(self):
        own = factories.VehicleFactory(school=self.school, status="inactive")
        route = factories.TransportRouteFactory(school=self.school, vehicle=own)
        spare = factories.VehicleFactory(school=self.school, name="Bus 9")
        client = self.as_user(self.admin)

        kept = client.patch(f"{self.URL}/{route.id}", {"vehicle_id": own.id}, format="json")
        swapped = client.patch(f"{self.URL}/{route.id}", {"vehicle_id": spare.id}, format="json")

        self.assertEqual(200, kept.status_code)
        self.assertEqual(("Bus 9", spare.id), (swapped.data["vehicle_name"], swapped.data["vehicle_id"]))

    def test_a_route_drops_its_vehicle_and_driver(self):
        route = factories.TransportRouteFactory(
            school=self.school, vehicle=factories.VehicleFactory(school=self.school), driver=factories.DriverFactory(school=self.school)
        )

        response = self.as_user(self.admin).patch(f"{self.URL}/{route.id}", {"vehicle_id": None, "driver_id": None}, format="json")

        self.assertEqual((None, None, route.name), (response.data["vehicle_id"], response.data["driver_id"], response.data["label"]))

    def test_another_schools_route_is_not_touched(self):
        route = factories.TransportRouteFactory(school=self.elsewhere)
        client = self.as_user(self.admin)

        for response in (
            client.get(f"{self.URL}/{route.id}"),
            client.patch(f"{self.URL}/{route.id}", {"name": "Ours"}, format="json"),
            client.delete(f"{self.URL}/{route.id}"),
            client.post(f"{self.URL}/{route.id}/stops", {"name": "Gate", "sequence_number": 1}, format="json"),
            client.get(f"{self.URL}/{route.id}/students"),
        ):
            self.assertEqual(403, response.status_code)

    def test_a_route_with_riders_or_trips_stays_and_an_empty_one_goes_with_its_stops(self):
        busy = factories.TransportRouteFactory(school=self.school)
        stop = factories.TransportStopFactory(route=busy)
        self.ride(self.student(), busy, stop)
        driven = factories.TransportRouteFactory(
            school=self.school, vehicle=factories.VehicleFactory(school=self.school), driver=factories.DriverFactory(school=self.school)
        )
        self.trip(driven)
        empty = factories.TransportRouteFactory(school=self.school)
        factories.TransportStopFactory(route=empty)
        client = self.as_user(self.admin)

        self.assertEqual("Students are still assigned to this route. Move them to another route first.",
                         client.delete(f"{self.URL}/{busy.id}").data["message"])
        self.assertEqual("This route has trip history and cannot be deleted. Deactivate it instead.",
                         client.delete(f"{self.URL}/{driven.id}").data["message"])
        self.assertEqual(204, client.delete(f"{self.URL}/{empty.id}").status_code)
        self.assertFalse(TransportStop.objects.filter(route_id=empty.id).exists())

    def test_the_list_carries_counts_without_stops_and_is_school_scoped(self):
        route = factories.TransportRouteFactory(school=self.school)
        for number in (1, 2):
            stop = factories.TransportStopFactory(route=route, sequence_number=number)
        self.ride(self.student(), route, stop)
        factories.TransportRouteFactory(school=self.elsewhere)

        rows = self.as_user(self.teacher).get(self.URL).data["data"]

        self.assertEqual(1, len(rows))
        self.assertEqual((2, 1), (rows[0]["stops_count"], rows[0]["students_count"]))
        self.assertNotIn("stops", rows[0])

    def test_one_route_shows_its_stops_in_order_with_rider_counts(self):
        route = factories.TransportRouteFactory(school=self.school)
        later = factories.TransportStopFactory(route=route, sequence_number=2, name="Market", pickup_time=dt.time(7, 45))
        first = factories.TransportStopFactory(route=route, sequence_number=1, name="Gate")
        self.ride(self.student(), route, later)

        stops = self.as_user(self.admin).get(f"{self.URL}/{route.id}").data["stops"]

        self.assertEqual(
            [
                {"id": first.id, "route_id": route.id, "name": "Gate", "sequence_number": 1, "pickup_time": None, "drop_time": None, "latitude": None, "longitude": None, "students_count": 0},
                {"id": later.id, "route_id": route.id, "name": "Market", "sequence_number": 2, "pickup_time": "07:45", "drop_time": None, "latitude": None, "longitude": None, "students_count": 1},
            ],
            stops,
        )


class StopTest(TransportTestCase):
    def setUp(self):
        super().setUp()
        self.route = factories.TransportRouteFactory(school=self.school, name="Route A")

    def add(self, user, route=None, **overrides):
        body = {"name": "Gate", "sequence_number": 1, "pickup_time": "07:30", "drop_time": "15:10"}
        body.update(overrides)

        return self.as_user(user).post(f"/api/v1/transport/routes/{(route or self.route).id}/stops", body, format="json")

    def test_a_school_admin_adds_changes_and_removes_a_stop(self):
        added = self.add(self.admin)
        stop_id = added.data["id"]
        client = self.as_user(self.admin)

        changed = client.patch(f"/api/v1/transport/stops/{stop_id}", {"name": "Main gate", "pickup_time": None}, format="json")
        removed = client.delete(f"/api/v1/transport/stops/{stop_id}")

        self.assertEqual((201, "07:30", "15:10", 0), (added.status_code, added.data["pickup_time"], added.data["drop_time"], added.data["students_count"]))
        self.assertEqual(("Main gate", None, "15:10"), (changed.data["name"], changed.data["pickup_time"], changed.data["drop_time"]))
        self.assertEqual(204, removed.status_code)

    def test_names_and_numbers_are_unique_within_a_route_only(self):
        self.add(self.admin)
        other = factories.TransportRouteFactory(school=self.school)

        clash = self.add(self.admin)

        self.assertEqual({"name", "sequence_number"}, set(self.errors(clash)))
        self.assertEqual(201, self.add(self.admin, route=other).status_code)

    def test_times_are_hh_mm_and_the_sequence_starts_at_one(self):
        response = self.add(self.admin, pickup_time="7:30", drop_time="24:00", sequence_number=0)

        self.assertEqual(
            {
                "sequence_number": ["The sequence number field must be at least 1."],
                "pickup_time": ["The pickup time field must match the format H:i."],
                "drop_time": ["The drop time field must match the format H:i."],
            },
            self.errors(response),
        )

    def test_a_stop_with_riders_is_not_removed(self):
        stop = factories.TransportStopFactory(route=self.route)
        self.ride(self.student(), self.route, stop)

        response = self.as_user(self.admin).delete(f"/api/v1/transport/stops/{stop.id}")

        self.assertEqual("Students are still assigned to this stop. Move them to another stop first.", response.data["message"])

    def test_the_transport_manager_does_not_manage_stops(self):
        stop = factories.TransportStopFactory(route=self.route)
        client = self.as_user(self.manager)

        self.assertEqual(403, self.add(self.manager, name="").status_code)
        self.assertEqual(403, client.patch(f"/api/v1/transport/stops/{stop.id}", {}, format="json").status_code)
        self.assertEqual(403, client.delete(f"/api/v1/transport/stops/{stop.id}").status_code)

    def test_admins_and_the_manager_see_riders_in_stop_order_and_a_teacher_does_not(self):
        second = factories.TransportStopFactory(route=self.route, sequence_number=2, name="Market")
        first = factories.TransportStopFactory(route=self.route, sequence_number=1, name="Gate")
        zara = self.student(first_name="Zara")
        anil = self.student(first_name="Anil")
        self.ride(zara, self.route, first)
        self.ride(anil, self.route, second)
        url = f"/api/v1/transport/routes/{self.route.id}/students"

        rows = self.as_user(self.manager).get(url).data["data"]

        self.assertEqual([(zara.id, "Gate", 1), (anil.id, "Market", 2)],
                         [(r["student_id"], r["stop_name"], r["stop_sequence_number"]) for r in rows])
        self.assertEqual(200, self.as_user(self.admin).get(url).status_code)
        self.assertEqual(403, self.as_user(self.teacher).get(url).status_code)


class AssignmentTest(TransportTestCase):
    def setUp(self):
        super().setUp()
        self.vehicle = factories.VehicleFactory(school=self.school, name="Bus 3", capacity=2)
        self.route = factories.TransportRouteFactory(school=self.school, name="Route A", vehicle=self.vehicle)
        self.gate = factories.TransportStopFactory(route=self.route, sequence_number=1, name="Gate")
        self.market = factories.TransportStopFactory(route=self.route, sequence_number=2, name="Market")
        self.child = self.student()

    def assign(self, user, student=None, **overrides):
        body = {"route_id": self.route.id, "transport_stop_id": self.gate.id}
        body.update(overrides)

        return self.as_user(user).put(f"/api/v1/students/{(student or self.child).id}/transport", body, format="json")

    def test_a_school_admin_assigns_a_student(self):
        response = self.assign(self.admin)

        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {"route_id": self.route.id, "route_name": "Route A", "route_label": "Bus 3 - Route A",
             "vehicle_name": "Bus 3", "stop_id": self.gate.id, "stop_name": "Gate"},
            response.data["transport"],
        )

    def test_the_student_list_and_detail_carry_the_assignment_or_null(self):
        self.assign(self.admin)
        walker = self.student()
        client = self.as_user(self.admin)

        rows = {row["id"]: row["transport"] for row in client.get("/api/v1/students").data["data"]}

        self.assertEqual("Gate", rows[self.child.id]["stop_name"])
        self.assertIsNone(rows[walker.id])
        self.assertIsNone(client.get(f"/api/v1/students/{walker.id}").data["transport"])

    def test_reassigning_replaces_and_unassigning_removes(self):
        self.assign(self.admin)
        moved = self.assign(self.admin, transport_stop_id=self.market.id)
        removed = self.as_user(self.admin).delete(f"/api/v1/students/{self.child.id}/transport")

        self.assertEqual("Market", moved.data["transport"]["stop_name"])
        self.assertIsNone(removed.data["transport"])
        self.assertFalse(StudentTransportAssignment.objects.exists())

    def test_the_stop_must_be_on_the_route_and_the_route_this_schools(self):
        other_route = factories.TransportRouteFactory(school=self.school)
        foreign_route = factories.TransportRouteFactory(school=self.elsewhere)

        off_route = self.assign(self.admin, route_id=other_route.id)
        foreign = self.assign(self.admin, route_id=foreign_route.id)
        missing = self.as_user(self.admin).put(f"/api/v1/students/{self.child.id}/transport", {}, format="json")

        self.assertEqual(["The selected stop is not on the selected route."], self.errors(off_route)["transport_stop_id"])
        self.assertEqual(["The selected route does not belong to this school."], self.errors(foreign)["route_id"])
        self.assertEqual({"route_id", "transport_stop_id"}, set(self.errors(missing)))

    def test_a_full_route_refuses_a_new_rider_but_moves_an_existing_one(self):
        self.assign(self.admin)
        self.assign(self.admin, student=self.student())

        full = self.assign(self.admin, student=self.student())
        moved = self.assign(self.admin, transport_stop_id=self.market.id)

        self.assertEqual(409, full.status_code)
        self.assertEqual(("ROUTE_CAPACITY_FULL", "Bus 3 - Route A is full - its vehicle seats 2 students."),
                         (full.data["code"], full.data["message"]))
        self.assertEqual(200, moved.status_code)

    def test_a_route_without_a_vehicle_has_no_limit(self):
        open_route = factories.TransportRouteFactory(school=self.school)
        stop = factories.TransportStopFactory(route=open_route)

        for _ in range(4):
            self.assertEqual(200, self.assign(self.admin, student=self.student(), route_id=open_route.id, transport_stop_id=stop.id).status_code)

    def test_only_admins_assign_or_unassign(self):
        for user in (self.teacher, self.manager):
            self.assertEqual(403, self.assign(user).status_code)
            self.assertEqual(403, self.as_user(user).delete(f"/api/v1/students/{self.child.id}/transport").status_code)

    def test_another_schools_student_is_not_ours_to_assign_and_a_super_admin_assigns_anyone(self):
        theirs = self.student(school=self.elsewhere)

        self.assertEqual(403, self.assign(self.admin, student=theirs).status_code)
        self.assertEqual(200, self.assign(self.root).status_code)
