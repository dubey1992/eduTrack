"""A school's logo (docs/school-logo.md, decided 2026-11-17).

The School Admin uploads it (a Super Admin may, for any school); everyone at
the school reads it for the menu; nobody outside the school can tell whether
it has one. A school's profile is complete once it does, which is what the
session tells the app so it can ask the School Admin at sign-in.
"""

import io
import shutil
import tempfile

from django.core.cache import cache
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from school import factories, pdf_design, tokens
from school.enums import UserRole
from school.models import AuditLog, School


def image_bytes(fmt="PNG", size=(1200, 900)) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", size, (30, 90, 140)).save(out, format=fmt)

    return out.getvalue()


def upload(data: bytes, name="logo.png", content_type="image/png"):
    return SimpleUploadedFile(name, data, content_type=content_type)


class LogoTest(TestCase):
    def setUp(self):
        cache.clear()
        self.media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.media, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=self.media)
        media.enable()
        self.addCleanup(media.disable)

        self.school = factories.SchoolFactory(name="Riverside Public School")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)
        self.url = f"/api/v1/schools/{self.school.id}/logo"

    def client_for(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def send(self, user, data=None, **kwargs):
        return self.client_for(user).post(self.url, {"logo": upload(data or image_bytes(), **kwargs)}, format="multipart")

    def school_now(self) -> School:
        return School.objects.get(pk=self.school.pk)


class Uploading(LogoTest):
    def test_the_school_admin_uploads_it_and_the_profile_is_complete(self):
        response = self.send(self.admin)

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(response.data["profile_complete"])
        self.assertTrue(response.data["logo_url"].startswith(f"/schools/{self.school.id}/logo?v="))
        self.assertTrue(self.school_now().logo_path.startswith("school-logos/"))

    def test_it_is_re_encoded_and_scaled_to_at_most_800_pixels(self):
        self.send(self.admin, image_bytes(size=(1600, 1000)))

        with default_storage.open(self.school_now().logo_path, "rb") as handle:
            with Image.open(handle) as stored:
                self.assertEqual((800, 500), stored.size)

    def test_a_jpeg_is_kept_as_a_jpeg(self):
        self.send(self.admin, image_bytes("JPEG"), name="logo.jpg", content_type="image/jpeg")

        self.assertTrue(self.school_now().logo_path.endswith(".jpg"))

    def test_a_new_logo_replaces_the_old_file(self):
        self.send(self.admin)
        first = self.school_now().logo_path

        self.send(self.admin)

        self.assertNotEqual(first, self.school_now().logo_path)
        self.assertFalse(default_storage.exists(first))

    def test_the_upload_is_audited_without_the_image(self):
        self.send(self.admin)

        entry = AuditLog.objects.filter(action="school.logo_changed").get()
        self.assertEqual((self.school.id, self.admin.id), (entry.school_id, entry.user_id))
        self.assertEqual({"has_logo": True}, entry.new_values)

    def test_a_super_admin_uploads_for_any_school(self):
        self.assertEqual(200, self.send(self.root).status_code)

    def test_a_group_admin_uploads_for_a_branch(self):
        group = factories.SchoolFactory(name="St Mary's Group")
        School.objects.filter(pk=self.school.pk).update(parent_school=group)
        group_admin = factories.UserFactory(school=group, role=UserRole.GROUP_ADMIN)

        self.assertEqual(200, self.send(group_admin).status_code)

    def test_removing_it_makes_the_profile_incomplete_again(self):
        self.send(self.admin)
        path = self.school_now().logo_path

        response = self.client_for(self.admin).delete(self.url)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((None, False), (response.data["logo_url"], response.data["profile_complete"]))
        self.assertFalse(default_storage.exists(path))
        self.assertTrue(AuditLog.objects.filter(action="school.logo_removed").exists())


class Refusing(LogoTest):
    def test_a_teacher_may_not_change_it(self):
        response = self.send(self.teacher)

        self.assertEqual(403, response.status_code)
        self.assertIsNone(self.school_now().logo_path)

    def test_an_accountant_may_not_remove_it(self):
        self.send(self.admin)

        self.assertEqual(403, self.client_for(self.accountant).delete(self.url).status_code)
        self.assertIsNotNone(self.school_now().logo_path)

    def test_another_schools_admin_gets_a_404_not_a_403(self):
        self.assertEqual(404, self.send(self.stranger).status_code)
        self.assertEqual(404, self.client_for(self.stranger).delete(self.url).status_code)
        self.assertIsNone(self.school_now().logo_path)

    def test_signed_out_is_refused(self):
        self.assertEqual(401, APIClient().post(self.url, {"logo": upload(image_bytes())}).status_code)

    def test_no_file_says_choose_one(self):
        response = self.client_for(self.admin).post(self.url, {}, format="multipart")

        self.assertEqual(422, response.status_code)
        self.assertIn("Choose a logo", response.data["details"]["errors"]["logo"][0])

    def test_a_file_that_is_not_an_image_is_refused_whatever_its_name(self):
        response = self.send(self.admin, b"%PDF-1.4 not an image", name="logo.png")

        self.assertEqual(422, response.status_code)
        self.assertEqual(["The logo must be a JPEG or PNG image."], response.data["details"]["errors"]["logo"])

    def test_a_gif_is_refused(self):
        response = self.send(self.admin, image_bytes("GIF"), name="logo.gif", content_type="image/gif")

        self.assertEqual(422, response.status_code)

    def test_a_file_over_2_mb_is_refused(self):
        response = self.send(self.admin, b"\x89PNG" + b"0" * (2 * 1024 * 1024 + 1))

        self.assertEqual(["The logo must be 2 MB or smaller."], response.data["details"]["errors"]["logo"])

    def test_an_unknown_school_is_a_404(self):
        response = self.client_for(self.root).get("/api/v1/schools/999999/logo")

        self.assertEqual(404, response.status_code)


class Reading(LogoTest):
    def setUp(self):
        super().setUp()
        self.send(self.admin)

    def test_a_teacher_at_the_school_reads_it(self):
        response = self.client_for(self.teacher).get(self.url)

        self.assertEqual(200, response.status_code)
        self.assertEqual("image/png", response["Content-Type"])
        self.assertIn("private", response["Cache-Control"])

    def test_someone_at_another_school_gets_a_404(self):
        self.assertEqual(404, self.client_for(self.stranger).get(self.url).status_code)

    def test_a_school_with_no_logo_is_a_404(self):
        self.client_for(self.admin).delete(self.url)

        self.assertEqual(404, self.client_for(self.teacher).get(self.url).status_code)


class TheSession(LogoTest):
    def me(self, user) -> dict:
        response = self.client_for(user).get("/api/v1/me")
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def test_without_a_logo_the_profile_is_incomplete_for_everyone_at_the_school(self):
        for user in (self.admin, self.teacher):
            body = self.me(user)
            self.assertEqual((None, False), (body["school_logo_url"], body["school_profile_complete"]))

    def test_with_a_logo_the_session_carries_where_to_fetch_it(self):
        self.send(self.admin)

        body = self.me(self.teacher)

        self.assertTrue(body["school_profile_complete"])
        self.assertTrue(body["school_logo_url"].startswith(f"/schools/{self.school.id}/logo?v="))

    def test_a_super_admin_has_no_school_profile_to_complete(self):
        body = self.me(self.root)

        self.assertEqual((None, True), (body["school_logo_url"], body["school_profile_complete"]))

    def test_the_school_record_says_so_too(self):
        response = self.client_for(self.root).get(f"/api/v1/schools/{self.school.id}")

        self.assertFalse(response.data["profile_complete"])
        self.assertIsNone(response.data["logo_image_url"])


class ThePdfs(LogoTest):
    def test_the_band_inlines_the_uploaded_logo(self):
        self.send(self.admin)

        band = pdf_design.school_band(self.school_now(), "Fee receipt")

        self.assertIn('src="data:image/png;base64,', band)

    def test_with_no_logo_the_band_has_none(self):
        self.assertNotIn("<img", pdf_design.school_band(self.school_now(), "Fee receipt"))
