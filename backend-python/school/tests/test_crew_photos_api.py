"""Children's photos for the bus crew (docs/mobile-apps-review.md, M9, 3.3).

Decided by the owner 2026-11-24: the crew see the photos of the children on
their own routes - beside each name on the trip and the route roster - and
nobody else's. Only the photo: a crew member still cannot read the
student's record.
"""

import shutil
import tempfile

from django.test import override_settings

from school import factories, student_photos
from school.enums import UserRole
from school.models import StudentTransportAssignment

from . import test_attendants_api as attendants
from .test_profile_api import image_bytes
from .test_transport_trips_api import TRIPS


class CrewPhotoTest(attendants.AttendantTest):
    def setUp(self):
        super().setUp()
        media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media, ignore_errors=True)
        settings = override_settings(MEDIA_ROOT=media)
        settings.enable()
        self.addCleanup(settings.disable)

        self.arjun = self.f["students"][0]
        student_photos.set_photo(self.arjun, image_bytes(size=(60, 80)), "png")
        self.arjun.refresh_from_db()

        # A child on the other route of the same school, with a photo too.
        self.lake_road_child = self.other["students"][0]
        student_photos.set_photo(self.lake_road_child, image_bytes(size=(60, 80)), "png")
        self.lake_road_child.refresh_from_db()

    def photo(self, user, student):
        return self.as_user(user).get(f"/api/v1/students/{student.id}/photo")


class TheCrewSeeTheirOwnChildren(CrewPhotoTest):
    def test_the_attendant_sees_a_child_on_their_route(self):
        response = self.photo(self.attendant, self.arjun)

        self.assertEqual(200, response.status_code)
        self.assertTrue(response["Content-Type"].startswith("image/"))
        self.assertIn("private", response["Cache-Control"])

    def test_the_driver_of_the_route_sees_them_too(self):
        profile = self.make_attendant("+919845000111")
        driver = self.f["route"].driver
        driver.staff_profile = profile
        driver.save(update_fields=["staff_profile"])

        self.assertEqual(200, self.photo(profile.user, self.arjun).status_code)

    def test_the_route_roster_carries_the_photo(self):
        routes = self.as_user(self.attendant).get("/api/v1/transport/my-routes").data["routes"]
        riders = {r["student_id"]: r for r in routes[0]["roster"]["riders"]}

        self.assertEqual(student_photos.photo_url(self.arjun), riders[self.arjun.id]["photo_url"])
        self.assertIsNone(riders[self.f["students"][1].id]["photo_url"], "no photo, initials")

    def test_a_running_trip_carries_the_photo(self):
        trip_id = self.start(user=self.attendant).data["id"]
        riders = {r["student_id"]: r for r in self.as_user(self.attendant).get(f"{TRIPS}/{trip_id}").data["riders"]}

        self.assertEqual(student_photos.photo_url(self.arjun), riders[self.arjun.id]["photo_url"])


class AndNobodyElses(CrewPhotoTest):
    def test_not_a_child_on_another_route(self):
        self.assertEqual(404, self.photo(self.attendant, self.lake_road_child).status_code)

    def test_not_once_the_child_has_left_the_route(self):
        StudentTransportAssignment.objects.filter(student=self.arjun).delete()

        self.assertEqual(404, self.photo(self.attendant, self.arjun).status_code)

    def test_not_a_crew_member_of_another_school(self):
        elsewhere = self.ready_route(factories.SchoolFactory(name="Hillside School"), name="Hill Road")
        stranger = factories.UserFactory(school=elsewhere["school"], role=UserRole.BUS_ATTENDANT)
        elsewhere["route"].attendant_user = stranger
        elsewhere["route"].save()

        self.assertEqual(404, self.photo(stranger, self.arjun).status_code)

    def test_only_the_photo_not_the_record(self):
        self.assertEqual(403, self.as_user(self.attendant).get(f"/api/v1/students/{self.arjun.id}").status_code)

    def test_crew_still_cannot_change_a_photo(self):
        response = self.as_user(self.attendant).delete(f"/api/v1/students/{self.arjun.id}/photo")

        self.assertEqual(403, response.status_code)
