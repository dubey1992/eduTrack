"""Photos on a teaching report (docs/mobile-apps-review.md, M9, 6.6).

Decided by the owner 2026-11-24: up to three per report, from the Staff
app's camera, seen by staff only - the teacher, their HOD and the school's
admins. The author adds and removes them until the report is reviewed.
"""

import shutil
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings

from school import factories
from school.enums import UserRole
from school.models import AuditLog, DailyTeachingReport, TeachingReportPhoto

from .test_profile_api import image_bytes
from .test_teaching_reports_api import TeachingReportCase


class ReportPhotoTest(TeachingReportCase):
    def setUp(self):
        super().setUp()
        media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media, ignore_errors=True)
        settings = override_settings(MEDIA_ROOT=media)
        settings.enable()
        self.addCleanup(settings.disable)

        response = self.file(homework="Exercise 4.2")
        self.assertEqual(201, response.status_code, response.data)
        self.report_id = response.data["id"]

    def url(self, photo_id=None, report_id=None):
        base = f"/api/v1/teaching-reports/{report_id or self.report_id}/photos"
        return base if photo_id is None else f"{base}/{photo_id}"

    def add(self, user=None, data=None, name="board.jpg"):
        upload = SimpleUploadedFile(name, data or image_bytes(fmt="JPEG", size=(800, 600)), content_type="image/jpeg")
        return self.as_user(user or self.teacher).post(self.url(), {"photo": upload}, format="multipart")

    def added(self) -> int:
        response = self.add()
        self.assertEqual(201, response.status_code, response.data)
        return response.data["photos"][-1]["id"]

    def review(self):
        DailyTeachingReport.objects.filter(pk=self.report_id).update(reviewed_by=self.hod)


class TheTeacherAddsPhotos(ReportPhotoTest):
    def test_a_photo_is_added_and_the_report_lists_it(self):
        response = self.add()

        self.assertEqual(201, response.status_code, response.data)
        photo = response.data["photos"][0]
        self.assertEqual(f"/teaching-reports/{self.report_id}/photos/{photo['id']}", photo["url"])
        self.assertTrue(AuditLog.objects.filter(action="teaching_report.photo_added").exists())

        listed = self.as_user(self.teacher).get("/api/v1/teaching-reports", {"mine": 1}).data["data"]
        self.assertEqual([photo["id"]], [p["id"] for p in listed[0]["photos"]])

    def test_at_most_three(self):
        for _ in range(3):
            self.added()

        response = self.add()

        self.assertEqual(422, response.status_code)
        self.assertEqual(["A report can carry at most 3 photos."], self.errors(response)["photo"])

    def test_only_a_real_photo(self):
        response = self.add(data=b"not a picture", name="board.jpg")

        self.assertEqual(422, response.status_code)
        self.assertEqual(["The photo must be a JPEG or PNG image."], self.errors(response)["photo"])

    def test_the_teacher_removes_one(self):
        photo_id = self.added()

        response = self.as_user(self.teacher).delete(self.url(photo_id))

        self.assertEqual(200, response.status_code)
        self.assertEqual([], response.data["photos"])
        self.assertFalse(TeachingReportPhoto.objects.filter(pk=photo_id).exists())

    def test_a_reviewed_report_keeps_its_photos(self):
        photo_id = self.added()
        self.review()

        self.assertEqual(422, self.add().status_code)
        self.assertEqual(422, self.as_user(self.teacher).delete(self.url(photo_id)).status_code)
        self.assertTrue(TeachingReportPhoto.objects.filter(pk=photo_id).exists())


class OnlyTheAuthorChangesThem(ReportPhotoTest):
    def test_the_hod_and_the_admin_cannot_add(self):
        self.assertEqual(403, self.add(self.hod).status_code)
        self.assertEqual(403, self.add(self.admin).status_code)

    def test_the_hod_cannot_remove(self):
        photo_id = self.added()

        self.assertEqual(403, self.as_user(self.hod).delete(self.url(photo_id)).status_code)

    def test_another_teacher_cannot_even_find_the_report(self):
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(404, self.add(colleague).status_code)


class WhoSeesThem(ReportPhotoTest):
    def setUp(self):
        super().setUp()
        self.photo_id = self.added()

    def see(self, user, photo_id=None, report_id=None):
        return self.as_user(user).get(self.url(photo_id or self.photo_id, report_id))

    def test_the_author_the_hod_and_the_admin(self):
        for user in (self.teacher, self.hod, self.admin):
            response = self.see(user)
            self.assertEqual(200, response.status_code, user.role)
            self.assertEqual("image/jpeg", response["Content-Type"])
            self.assertIn("private", response["Cache-Control"])

    def test_not_another_teacher(self):
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(404, self.see(colleague).status_code)

    def test_not_another_school(self):
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(404, self.see(stranger).status_code)

    def test_a_photo_is_only_reached_through_its_own_report(self):
        entry = self.period_for(self.teacher, self.second)
        other_report = self.file(timetable_entry_id=entry.id).data["id"]

        self.assertEqual(404, self.see(self.teacher, report_id=other_report).status_code)
