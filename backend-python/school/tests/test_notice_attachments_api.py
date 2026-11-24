"""Files a notice carries (docs/mobile-apps-review.md, M9, 8.3).

Decided by the owner 2026-11-24: at most three per notice, PDF, JPEG or
PNG, 5 MB each.

What this file guards that a quick read would not:

- **A file is checked by its bytes**, never its name: a "PDF" that is not
  one, or a script named .png, is refused; an image is re-encoded.
- **Before publishing a file is the uploader's alone**, and only their own
  waiting files can be named by a publish - never someone else's, another
  school's, or one already sent.
- **Files are seen in the app**, so an SMS-only notice carries none.
- **Readers are the notice's publishers and its in-app recipients** - a
  staff inbox (or, once it ships, a parent's Family app). Everyone else
  gets one 404.
"""

import datetime as dt
import shutil
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone

from school import factories
from school.enums import UserRole
from school.models import AnnouncementAttachment, AuditLog

from . import test_announcements_api as announcements
from .test_profile_api import image_bytes

FILES = "/api/v1/announcement-attachments"
PDF_BYTES = b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"


class MediaRoot:
    def use_temporary_media(self):
        media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media, ignore_errors=True)
        settings = override_settings(MEDIA_ROOT=media)
        settings.enable()
        self.addCleanup(settings.disable)

    def add_file(self, client, name="circular.pdf", data=PDF_BYTES, content_type="application/pdf", **fields):
        return client.post(FILES, {"file": SimpleUploadedFile(name, data, content_type=content_type), **fields},
                           format="multipart")


class AttachmentTest(MediaRoot, announcements.AnnouncementTestCase):
    def setUp(self):
        super().setUp()
        self.use_temporary_media()
        self.admin = self.as_user(self.f["admin"])

    def uploaded(self, **kwargs) -> int:
        response = self.add_file(self.admin, **kwargs)
        self.assertEqual(201, response.status_code, response.data)

        return response.data["id"]

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


class AddingAFile(AttachmentTest):
    def test_a_pdf_is_kept_as_it_is(self):
        response = self.add_file(self.admin)

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("circular.pdf", "application/pdf", len(PDF_BYTES)),
                         (response.data["name"], response.data["content_type"], response.data["size_bytes"]))
        self.assertEqual(f"/announcement-attachments/{response.data['id']}", response.data["url"])

    def test_an_image_is_re_encoded(self):
        response = self.add_file(self.admin, name="poster.png", data=image_bytes(size=(300, 200)),
                                 content_type="image/png")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("poster.png", "image/png"), (response.data["name"], response.data["content_type"]))

    def test_the_name_says_what_the_file_really_is(self):
        response = self.add_file(self.admin, name="../../holiday.exe", data=image_bytes(fmt="JPEG"),
                                 content_type="application/octet-stream")

        self.assertEqual("holiday.jpg", response.data["name"])

    def test_a_file_that_is_not_a_pdf_or_an_image_is_refused(self):
        response = self.add_file(self.admin, name="fees.pdf", data=b"<script>alert(1)</script>")

        self.assertEqual(422, response.status_code)
        self.assertEqual(["Attach a PDF, JPEG or PNG file."], self.errors(response)["file"])

    def test_more_than_5_mb_is_refused(self):
        response = self.add_file(self.admin, data=PDF_BYTES + b"0" * (5 * 1024 * 1024))

        self.assertEqual(["Each file must be 5 MB or smaller."], self.errors(response)["file"])

    def test_no_file_is_refused(self):
        response = self.admin.post(FILES, {}, format="multipart")

        self.assertEqual(["Choose a file to attach."], self.errors(response)["file"])

    def test_someone_with_many_schools_names_the_school(self):
        root = self.as_user(self.f["root"])

        missing = self.add_file(root)
        named = self.add_file(root, school_id=self.f["school"].id)

        self.assertEqual(["The school id field is required."], self.errors(missing)["school_id"])
        self.assertEqual(201, named.status_code, named.data)

    def test_only_someone_who_may_announce(self):
        self.assertEqual(403, self.add_file(self.as_user(self.f["teacher"])).status_code)

    def test_a_day_old_upload_never_published_is_cleared(self):
        old = self.uploaded()
        AnnouncementAttachment.objects.filter(pk=old).update(created_at=timezone.now() - dt.timedelta(days=2))

        self.uploaded()

        self.assertFalse(AnnouncementAttachment.objects.filter(pk=old).exists())

    def test_a_waiting_file_can_be_taken_back(self):
        attachment_id = self.uploaded()

        self.assertEqual(204, self.admin.delete(f"{FILES}/{attachment_id}").status_code)
        self.assertFalse(AnnouncementAttachment.objects.filter(pk=attachment_id).exists())

    def test_a_waiting_file_is_the_uploaders_alone(self):
        attachment_id = self.uploaded()
        other_admin = factories.UserFactory(school=self.f["school"], role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(404, self.as_user(other_admin).get(f"{FILES}/{attachment_id}").status_code)
        self.assertEqual(404, self.as_user(other_admin).delete(f"{FILES}/{attachment_id}").status_code)


class PublishingWithFiles(AttachmentTest):
    def test_the_notice_carries_its_files_in_order(self):
        first, second = self.uploaded(name="b.pdf"), self.uploaded(name="a.pdf")

        response = self.publish(self.f["admin"], attachment_ids=[first, second])

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(["b.pdf", "a.pdf"], [f["name"] for f in response.data["attachments"]])
        listed = self.admin.get(announcements.URL).data["data"][0]
        self.assertEqual(["b.pdf", "a.pdf"], [f["name"] for f in listed["attachments"]])
        self.assertTrue(AuditLog.objects.filter(action="announcement.attachments_added").exists())

    def test_a_notice_without_files_has_none(self):
        self.assertEqual([], self.publish(self.f["admin"]).data["attachments"])

    def test_at_most_three(self):
        ids = [self.uploaded() for _ in range(4)]

        response = self.publish(self.f["admin"], attachment_ids=ids)

        self.assertEqual(["A notice can carry at most 3 files."], self.errors(response)["attachment_ids"])

    def test_sms_only_to_staff_cannot_carry_files(self):
        response = self.publish(self.f["admin"], audience_type="teachers", channels="sms",
                                attachment_ids=[self.uploaded()])

        self.assertEqual(["Files are seen in the app. Send the notice in-app to attach them."],
                         self.errors(response)["attachment_ids"])

    def test_someone_elses_upload_cannot_be_named(self):
        other_admin = factories.UserFactory(school=self.f["school"], role=UserRole.SCHOOL_ADMIN)
        theirs = self.add_file(self.as_user(other_admin)).data["id"]

        response = self.publish(self.f["admin"], attachment_ids=[theirs])

        self.assertEqual(422, response.status_code)
        self.assertIsNone(AnnouncementAttachment.objects.get(pk=theirs).announcement_id)

    def test_a_file_already_sent_cannot_be_sent_again(self):
        attachment_id = self.uploaded()
        self.publish(self.f["admin"], attachment_ids=[attachment_id])

        response = self.publish(self.f["admin"], attachment_ids=[attachment_id])

        self.assertEqual(422, response.status_code)

    def test_a_notice_to_parents_by_sms_carries_them_to_the_family_app(self):
        # The Family app's copy of a parents' notice comes with its SMS.
        response = self.publish(self.f["admin"], audience_type="parents", channels="sms",
                                attachment_ids=[self.uploaded()])

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(1, len(response.data["attachments"]))

    def test_a_sent_file_cannot_be_taken_back(self):
        attachment_id = self.uploaded()
        self.publish(self.f["admin"], attachment_ids=[attachment_id])

        self.assertEqual(403, self.admin.delete(f"{FILES}/{attachment_id}").status_code)


class ReadingAFile(AttachmentTest):
    def setUp(self):
        super().setUp()
        self.attachment_id = self.uploaded()
        # To the Mathematics department: its teacher gets it in the app, the
        # Science clerk does not.
        self.publish(self.f["admin"], audience_type="department", audience_id=self.f["maths"].id,
                     channels="in_app", attachment_ids=[self.attachment_id])

    def read(self, user):
        return self.as_user(user).get(f"{FILES}/{self.attachment_id}")

    def test_a_recipient_reads_it_from_their_inbox(self):
        inbox = self.as_user(self.f["teacher"]).get("/api/v1/inbox").json()["data"]
        self.assertEqual(["circular.pdf"], [f["name"] for f in inbox[0]["attachments"]])

        response = self.read(self.f["teacher"])

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertEqual(PDF_BYTES, response.content)
        self.assertEqual("nosniff", response["X-Content-Type-Options"])
        self.assertIn("private", response["Cache-Control"])

    def test_marking_it_read_keeps_its_files(self):
        inbox = self.as_user(self.f["teacher"]).get("/api/v1/inbox").json()["data"]

        response = self.as_user(self.f["teacher"]).post(f"/api/v1/inbox/{inbox[0]['id']}/read")

        self.assertEqual(["circular.pdf"], [f["name"] for f in response.data["attachments"]])

    def test_the_publishers_read_it(self):
        self.assertEqual(200, self.read(self.f["admin"]).status_code)
        self.assertEqual(200, self.read(self.f["maths_hod"]).status_code, "their department's notice")

    def test_staff_it_did_not_reach_do_not(self):
        self.assertEqual(404, self.read(self.f["staff"]).status_code)

    def test_another_school_does_not(self):
        elsewhere = self.make_school()

        self.assertEqual(404, self.read(elsewhere["admin"]).status_code)

    def test_nobody_once_the_notice_is_deleted(self):
        announcement_id = AnnouncementAttachment.objects.get(pk=self.attachment_id).announcement_id
        self.admin.delete(f"{announcements.URL}/{announcement_id}")

        self.assertEqual(404, self.read(self.f["teacher"]).status_code)
