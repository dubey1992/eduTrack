"""Events and photos (docs/mobile-apps-review.md, M12, 8.6).

What this file guards:

- **Who posts where.** An admin posts to the whole school or any class; a
  class teacher only to their own class; another teacher, another school's
  admin and a parent not at all.
- **Who sees what.** A parent sees the school's events and their children's
  classes', once an event has a photo - never another class's, never
  another school's. A photo is served only through a signed-in endpoint.
- **What is kept.** Each photo is re-encoded to at most 1600 px with a
  400 px copy; at most 20 per event; deleting an event deletes its files.
"""

import datetime as dt
import io
import shutil
import tempfile

from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from PIL import Image
from rest_framework.test import APIClient

from school import factories, gallery
from school.models import AuditLog, GalleryEvent, GalleryPhoto

from . import test_family_f1_api as f1
from .test_profile_api import image_bytes

FAMILY = f1.FAMILY
API = "/api/v1"


class GalleryTest(f1.FamilyAppTest):
    def setUp(self):
        super().setUp()
        media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media, ignore_errors=True)
        settings = override_settings(MEDIA_ROOT=media)
        settings.enable()
        self.addCleanup(settings.disable)

        self.teacher = factories.UserFactory(school=self.school, role="TEACHER")
        self.other_teacher = factories.UserFactory(school=self.school, role="TEACHER")
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Class 6",
                                                    level=6)
        self.section = factories.ClassSectionFactory(school_class=school_class, name="A", class_teacher=self.teacher)
        self.other_section = factories.ClassSectionFactory(school_class=school_class, name="B",
                                                           class_teacher=self.other_teacher)
        self.child.class_section = self.section
        self.child.save(update_fields=["class_section"])

    def post(self, user=None, **body):
        payload = {"title": "Annual Day", "event_date": self.today().isoformat(), **body}
        return self.as_user(user or self.admin).post(f"{API}/gallery-events", payload, format="json")

    def event(self, user=None, **body) -> int:
        response = self.post(user, **body)
        self.assertEqual(201, response.status_code, response.data)
        return response.data["id"]

    def add(self, event_id, user=None, size=(3000, 2000)):
        upload = SimpleUploadedFile("stage.jpg", image_bytes(fmt="JPEG", size=size), content_type="image/jpeg")
        return self.as_user(user or self.admin).post(
            f"{API}/gallery-events/{event_id}/photos", {"photo": upload}, format="multipart"
        )

    def gallery(self):
        response = self.parent.get(f"{FAMILY}/gallery")
        self.assertEqual(200, response.status_code, response.data)
        return response.data["data"]


class WhoPosts(GalleryTest):
    def test_an_admin_posts_to_the_whole_school(self):
        response = self.post(description="Our 25th year.")

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(response.data["class_section"])
        self.assertTrue(response.data["can_change"])
        self.assertTrue(AuditLog.objects.filter(action="gallery.event_posted").exists())

    def test_a_class_teacher_posts_to_their_own_class(self):
        response = self.post(self.teacher, class_section_id=self.section.id)

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Class 6 A", response.data["class_section"]["name"])

    def test_a_teacher_cannot_post_school_wide_or_to_another_class(self):
        self.assertEqual(422, self.post(self.teacher).status_code)
        self.assertEqual(422, self.post(self.teacher, class_section_id=self.other_section.id).status_code)

    def test_another_schools_class_is_refused(self):
        elsewhere = factories.ClassSectionFactory()

        self.assertEqual(422, self.post(class_section_id=elsewhere.id).status_code)

    def test_a_blank_title_and_a_date_years_away_are_refused(self):
        self.assertEqual(422, self.post(title=" ").status_code)
        self.assertEqual(422, self.post(event_date=(self.today() + dt.timedelta(days=400)).isoformat()).status_code)
        self.assertEqual(422, self.post(description="x" * (gallery.DESCRIPTION_MAX + 1)).status_code)

    def test_another_teacher_cannot_change_or_add_to_it(self):
        event_id = self.event(self.teacher, class_section_id=self.section.id)

        self.assertEqual(404, self.as_user(self.other_teacher).delete(f"{API}/gallery-events/{event_id}").status_code)
        self.assertEqual(404, self.add(event_id, user=self.other_teacher).status_code)

    def test_a_teacher_cannot_change_a_school_wide_event_they_did_not_post(self):
        event_id = self.event()

        self.assertEqual(403, self.as_user(self.teacher).delete(f"{API}/gallery-events/{event_id}").status_code)
        self.assertEqual(403, self.add(event_id, user=self.teacher).status_code)

    def test_another_schools_admin_cannot_see_it(self):
        event_id = self.event()
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role="SCHOOL_ADMIN")

        self.assertEqual([], self.as_user(stranger).get(f"{API}/gallery-events").data["data"])
        self.assertEqual(404, self.as_user(stranger).get(f"{API}/gallery-events/{event_id}").status_code)

    def test_a_parent_cannot_reach_the_staff_side(self):
        self.assertIn(self.parent.get(f"{API}/gallery-events").status_code, (401, 403))


class ThePhotos(GalleryTest):
    def test_a_photo_is_shrunk_and_given_a_small_copy(self):
        event_id = self.event()

        response = self.add(event_id)

        self.assertEqual(201, response.status_code, response.data)
        photo = GalleryPhoto.objects.get()
        with default_storage.open(photo.file_path, "rb") as f:
            self.assertEqual(gallery.MAX_SIDE, max(Image.open(io.BytesIO(f.read())).size))
        with default_storage.open(photo.thumb_path, "rb") as f:
            self.assertEqual(gallery.THUMB_SIDE, max(Image.open(io.BytesIO(f.read())).size))
        self.assertEqual(1, response.data["photo_count"])

    def test_not_a_picture_is_refused(self):
        event_id = self.event()
        upload = SimpleUploadedFile("notes.jpg", b"not an image", content_type="image/jpeg")

        response = self.as_user(self.admin).post(f"{API}/gallery-events/{event_id}/photos", {"photo": upload},
                                                 format="multipart")

        self.assertEqual(422, response.status_code)

    def test_at_most_twenty(self):
        event_id = self.event()
        event = GalleryEvent.objects.get(pk=event_id)
        for _ in range(gallery.MAX_PHOTOS):
            GalleryPhoto.objects.create(school=self.school, gallery_event=event, file_path="x", thumb_path="x")

        self.assertEqual(422, self.add(event_id).status_code)

    def test_staff_read_the_picture_and_its_small_copy(self):
        event_id = self.event()
        photo = self.add(event_id).data["photos"][0]

        full = self.as_user(self.teacher).get(f"{API}{photo['url']}")
        thumb = self.as_user(self.teacher).get(f"{API}{photo['thumb_url']}")

        self.assertEqual(200, full.status_code)
        self.assertEqual("image/jpeg", full["Content-Type"])
        self.assertLess(len(thumb.content), len(full.content))

    def test_deleting_the_event_deletes_the_files(self):
        event_id = self.event()
        self.add(event_id)
        photo = GalleryPhoto.objects.get()

        response = self.as_user(self.admin).delete(f"{API}/gallery-events/{event_id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(GalleryPhoto.objects.exists())
        self.assertFalse(default_storage.exists(photo.file_path))
        self.assertFalse(default_storage.exists(photo.thumb_path))

    def test_an_admin_removes_a_teachers_photo(self):
        event_id = self.event(self.teacher, class_section_id=self.section.id)
        photo_id = self.add(event_id, user=self.teacher).data["photos"][0]["id"]

        self.assertEqual(204, self.as_user(self.admin).delete(f"{API}/gallery-photos/{photo_id}").status_code)
        self.assertTrue(AuditLog.objects.filter(action="gallery.photo_removed").exists())


class WhatParentsSee(GalleryTest):
    def test_the_school_and_the_childs_class_but_not_another_class(self):
        school_wide = self.event(title="Annual Day")
        ours = self.event(self.teacher, title="Class picnic", class_section_id=self.section.id)
        theirs = self.event(self.other_teacher, title="Their picnic", class_section_id=self.other_section.id)
        for event_id, user in ((school_wide, self.admin), (ours, self.teacher), (theirs, self.other_teacher)):
            self.add(event_id, user=user)

        titles = [row["title"] for row in self.gallery()]

        self.assertEqual({"Annual Day", "Class picnic"}, set(titles))

    def test_an_event_with_no_photo_is_not_shown(self):
        self.event()

        self.assertEqual([], self.gallery())

    def test_a_parent_reads_a_photo_they_see_but_not_another(self):
        ours = self.event()
        theirs = self.event(self.other_teacher, class_section_id=self.other_section.id)
        mine = self.add(ours).data["photos"][0]
        other = self.add(theirs, user=self.other_teacher).data["photos"][0]

        [row] = self.gallery()
        self.assertEqual(f"/family/gallery-photos/{mine['id']}", row["photos"][0]["url"])
        self.assertEqual(200, self.parent.get(f"{FAMILY}/gallery-photos/{mine['id']}?size=thumb").status_code)
        self.assertEqual(404, self.parent.get(f"{FAMILY}/gallery-photos/{other['id']}").status_code)
        self.assertNotIn("posted_by", row)

    def test_another_schools_events_are_not_shown(self):
        elsewhere = factories.SchoolFactory()
        admin = factories.UserFactory(school=elsewhere, role="SCHOOL_ADMIN")
        response = self.as_user(admin).post(f"{API}/gallery-events", {
            "title": "Not ours", "event_date": self.today().isoformat()}, format="json")
        self.add(response.data["id"], user=admin)

        self.assertEqual([], self.gallery())

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get(f"{FAMILY}/gallery").status_code)
