"""A student's photo (docs/student-photos.md, P1): adding, replacing and
removing it, reading it back, who may do which, and what the audit log
keeps.

The checks on the file itself - a real JPEG or PNG, re-encoded, 2 MB at
most - are the profile photo's (test_profile_api.Photo); here they are
exercised once each through the student's endpoint, plus the one thing a
student's photo adds: the 3:4 passport shape.
"""

import io
import shutil
import tempfile

from django.core.cache import cache
from django.core.files.storage import default_storage
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from school import factories, photos, tokens
from school.enums import UserRole
from school.models import AuditLog, Student

from .test_profile_api import image_bytes, upload


def photo_url(student_id: int) -> str:
    return f"/api/v1/students/{student_id}/photo"


class StudentPhotoTest(TestCase):
    def setUp(self):
        cache.clear()
        self.media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.media, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=self.media)
        media.enable()
        self.addCleanup(media.disable)

        self.school = factories.SchoolFactory(name="Sunrise Public School")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.class_teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.other_teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)

        grade = factories.SchoolClassFactory(school=self.school, name="Grade 5")
        self.section = factories.ClassSectionFactory(school_class=grade, name="A", class_teacher=self.class_teacher)
        self.other_section = factories.ClassSectionFactory(
            school_class=grade, name="B", class_teacher=self.other_teacher
        )
        self.student = factories.StudentFactory(class_section=self.section, admission_number="ADM-1")

        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

    def client_for(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def post_photo(self, user, data=None, student=None, **kwargs):
        student = student or self.student
        data = image_bytes() if data is None else data

        return self.client_for(user).post(
            photo_url(student.id), {"photo": upload(data, **kwargs)}, format="multipart"
        )

    def stored(self) -> Image.Image:
        path = Student.objects.get(pk=self.student.pk).photo_path
        with default_storage.open(path, "rb") as handle:
            return Image.open(io.BytesIO(handle.read()))


class AddingAPhoto(StudentPhotoTest):
    def test_an_admin_adds_a_photo_and_the_student_carries_its_address(self):
        response = self.post_photo(self.admin)

        self.assertEqual(200, response.status_code, response.data)
        path = Student.objects.get(pk=self.student.pk).photo_path
        self.assertTrue(path.startswith("student-photos/"))
        self.assertTrue(response.data["photo_url"].startswith(f"/students/{self.student.id}/photo?v="))

        listed = self.client_for(self.admin).get("/api/v1/students")
        row = next(row for row in listed.data["data"] if row["id"] == self.student.id)
        self.assertEqual(response.data["photo_url"], row["photo_url"])

    def test_a_student_with_no_photo_has_none(self):
        response = self.client_for(self.admin).get(f"/api/v1/students/{self.student.id}")

        self.assertIsNone(response.data["photo_url"])

    def test_a_wide_photo_is_cut_to_a_3_by_4_passport_shape(self):
        self.post_photo(self.admin, image_bytes(size=(800, 400)))

        self.assertEqual((300, 400), self.stored().size)

    def test_a_tall_photo_is_cut_too_and_a_large_one_is_scaled_to_600(self):
        self.post_photo(self.admin, image_bytes(fmt="JPEG", size=(1200, 2400)), name="a.jpg", content_type="image/jpeg")

        image = self.stored()
        self.assertEqual((450, 600), image.size)
        self.assertEqual("JPEG", image.format)

    def test_something_that_is_not_an_image_is_refused_with_a_sentence(self):
        response = self.post_photo(self.admin, b"%PDF-1.4 not a photo", name="photo.png")

        self.assertEqual(422, response.status_code)
        self.assertEqual(["The photo must be a JPEG or PNG image."], response.data["details"]["errors"]["photo"])
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)

    def test_a_photo_over_2_mb_is_refused(self):
        response = self.post_photo(self.admin, b"0" * (photos.MAX_BYTES + 1))

        self.assertEqual(422, response.status_code)
        self.assertIn("2 MB", response.data["details"]["errors"]["photo"][0])

    def test_asking_with_no_file_is_refused(self):
        response = self.client_for(self.admin).post(photo_url(self.student.id), {}, format="multipart")

        self.assertEqual(422, response.status_code)
        self.assertIn("photo", response.data["details"]["errors"])


class ReplacingAndRemoving(StudentPhotoTest):
    def test_a_new_photo_replaces_the_old_file_and_gets_a_new_address(self):
        first = self.post_photo(self.admin).data["photo_url"]
        old_path = Student.objects.get(pk=self.student.pk).photo_path

        second = self.post_photo(self.admin).data["photo_url"]

        self.assertNotEqual(first, second)
        self.assertFalse(default_storage.exists(old_path))

    def test_removing_deletes_the_file_and_clears_the_address(self):
        self.post_photo(self.admin)
        path = Student.objects.get(pk=self.student.pk).photo_path

        response = self.client_for(self.admin).delete(photo_url(self.student.id))

        self.assertEqual(200, response.status_code)
        self.assertIsNone(response.data["photo_url"])
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)
        self.assertFalse(default_storage.exists(path))

    def test_removing_when_there_is_none_is_harmless(self):
        response = self.client_for(self.admin).delete(photo_url(self.student.id))

        self.assertEqual(200, response.status_code)
        self.assertFalse(AuditLog.objects.filter(action="student.photo_removed").exists())

    def test_every_change_is_audited_without_the_image(self):
        self.post_photo(self.admin)
        self.post_photo(self.admin)
        self.client_for(self.admin).delete(photo_url(self.student.id))

        rows = list(AuditLog.objects.filter(entity_type="student", entity_id=self.student.id).order_by("id"))
        self.assertEqual(
            ["student.photo_changed", "student.photo_changed", "student.photo_removed"],
            [row.action for row in rows],
        )
        self.assertEqual({"had_photo": False}, rows[0].new_values)
        self.assertEqual({"had_photo": True}, rows[1].new_values)
        self.assertTrue(all(row.module == "students" and row.user_id == self.admin.id for row in rows))
        self.assertTrue(all(row.school_id == self.school.id for row in rows))


class WhoMaySetAPhoto(StudentPhotoTest):
    def test_the_class_teacher_of_the_section_may(self):
        self.assertEqual(200, self.post_photo(self.class_teacher).status_code)
        self.assertEqual(200, self.client_for(self.class_teacher).delete(photo_url(self.student.id)).status_code)

    def test_a_teacher_of_another_section_may_not(self):
        self.assertEqual(403, self.post_photo(self.other_teacher).status_code)
        self.assertEqual(403, self.client_for(self.other_teacher).delete(photo_url(self.student.id)).status_code)
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)

    def test_an_accountant_may_not(self):
        self.assertEqual(403, self.post_photo(self.accountant).status_code)

    def test_another_schools_admin_may_not_and_nothing_is_stored(self):
        response = self.post_photo(self.stranger)

        self.assertEqual(403, response.status_code)
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)

    def test_a_super_admin_may(self):
        self.assertEqual(200, self.post_photo(self.root).status_code)

    def test_signing_in_is_required(self):
        response = APIClient().post(photo_url(self.student.id), {"photo": upload(image_bytes())}, format="multipart")

        self.assertEqual(401, response.status_code)


class WhoMaySeeAPhoto(StudentPhotoTest):
    def setUp(self):
        super().setUp()
        self.post_photo(self.admin)

    def get(self, user):
        return self.client_for(user).get(photo_url(self.student.id))

    def test_the_admin_and_the_class_teacher_see_the_image(self):
        for user in (self.admin, self.class_teacher, self.root):
            response = self.get(user)
            self.assertEqual(200, response.status_code, user.role)
            self.assertEqual("image/png", response["Content-Type"])
            self.assertIn("private", response["Cache-Control"])
            self.assertEqual("PNG", Image.open(io.BytesIO(response.content)).format)

    def test_somebody_who_may_not_see_the_student_gets_the_same_404_as_no_photo(self):
        nobody = factories.StudentFactory(class_section=self.section)
        no_photo = self.client_for(self.admin).get(photo_url(nobody.id))

        for user in (self.other_teacher, self.stranger, self.accountant):
            response = self.get(user)
            self.assertEqual(404, response.status_code, user.role)
            self.assertEqual(no_photo.status_code, response.status_code)

    def test_a_missing_file_reads_as_no_photo(self):
        default_storage.delete(Student.objects.get(pk=self.student.pk).photo_path)

        self.assertEqual(404, self.get(self.admin).status_code)

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get(photo_url(self.student.id)).status_code)


class TheShape(TestCase):
    """The crop on its own, away from any request."""

    def test_the_largest_centred_3_by_4_part_is_kept(self):
        self.assertEqual((300, 400), photos.centre_crop(Image.new("RGB", (600, 400)), (3, 4)).size)
        self.assertEqual((300, 400), photos.centre_crop(Image.new("RGB", (300, 900)), (3, 4)).size)
        self.assertEqual((300, 400), photos.centre_crop(Image.new("RGB", (300, 400)), (3, 4)).size)

    def test_the_centre_is_what_stays(self):
        image = Image.new("RGB", (400, 200), (0, 0, 0))
        image.paste((255, 0, 0), (150, 0, 250, 200))

        cut = photos.centre_crop(image, (3, 4))

        self.assertEqual((150, 200), cut.size)
        self.assertEqual((255, 0, 0), cut.getpixel((75, 100)))
