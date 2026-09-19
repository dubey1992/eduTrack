"""Announcements, over HTTP.

Laravel's own fixture, ported: one school with three students (one guardian
without a number, one inactive student with one), an admin, a teacher, a
maths HOD and a clerk with no mobile, and two departments. Every count Laravel
asserts is asserted here.

**The reach count is who can actually be reached**; a guardian with no number
still gets a *skipped* row when the notice fans out, so an admin can see who
was missed. **An audience nobody can reach is refused**, not recorded as sent.
**A head of department announces to their own department and nothing else.**
And **the preview never names another school's class or department** - the
leak fixed on both backends with this slice.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, queue, tokens
from school.enums import UserRole
from school.models import Announcement, CommunicationSetting, Message

URL = "/api/v1/announcements"


class AnnouncementTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.f = self.make_school()

    def make_school(self):
        school = factories.SchoolFactory(name="Sunrise Public School")
        year = factories.AcademicYearFactory(school=school)
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=school, academic_year=year, name="Grade 8"), name="A"
        )
        other_section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=school, academic_year=year, name="Grade 9"), name="B"
        )

        factories.StudentFactory(
            school=school, class_section=section, first_name="Arjun", last_name="Kumar",
            guardian_name="Raj Kumar", guardian_mobile="+91 9876543210",
        )
        factories.StudentFactory(
            school=school, class_section=other_section, guardian_name="Rohit Singh", guardian_mobile="+91 9876500000"
        )
        factories.StudentFactory(school=school, class_section=section, guardian_name="Anita Rao", guardian_mobile=None)
        factories.StudentFactory(school=school, class_section=section, status="inactive", guardian_mobile="+91 9000000000")

        # A number of their own, as Laravel's user factory always gives one.
        admin = factories.UserFactory(school=school, role=UserRole.SCHOOL_ADMIN, mobile="+91 9800000000")
        teacher = factories.UserFactory(school=school, role=UserRole.TEACHER, mobile="+91 9811111111")
        maths_hod = factories.UserFactory(school=school, role=UserRole.HOD, mobile="+91 9822222222")
        staff = factories.UserFactory(school=school, role=UserRole.STAFF, mobile=None)

        maths = factories.DepartmentFactory(school=school, name="Mathematics", hod_user=maths_hod)
        science = factories.DepartmentFactory(school=school, name="Science")
        for user, department in ((maths_hod, maths), (teacher, maths), (staff, science)):
            factories.StaffProfileFactory(school=school, user=user, department=department)

        return {
            "school": school, "section": section, "admin": admin, "teacher": teacher,
            "maths_hod": maths_hod, "staff": staff, "maths": maths, "science": science,
            "root": factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN),
        }

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def publish(self, user, **overrides):
        body = {
            "title": "Parent meeting",
            "body": "Parent meeting scheduled Friday at 3 PM.",
            "audience_type": "all_school",
            "channels": "sms_in_app",
        }
        body.update(overrides)
        response = self.as_user(user).post(URL, body, format="json")

        # The fan-out is a job; run what it queued, as the cron worker would.
        queue.work()

        return response

    def announcement(self, **fields):
        school = fields.pop("school", self.f["school"])
        values = dict(
            school=school, title="Notice", body="Something happening.", audience_type="all_school",
            audience_id=None, audience_label="All School", channels="in_app",
            published_at=dt.datetime(2026, 9, 1, 4, 0, tzinfo=dt.timezone.utc),
            recipients_count=1, sms_count=0, in_app_count=1,
        )
        values.update(fields)

        return Announcement.objects.create(**values)

    def for_department(self, department, **fields):
        return self.announcement(
            audience_type="department", audience_id=department.id, audience_label=department.name, **fields
        )

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


class PublishingTest(AnnouncementTestCase):
    def test_a_whole_school_notice_fans_out_to_guardians_and_staff(self):
        response = self.publish(self.f["admin"])

        self.assertEqual(201, response.status_code)
        self.assertEqual(
            ("Parent meeting", "all_school", "All School", "SMS + In-app", self.f["admin"].name, 6),
            (response.data["title"], response.data["audience_type"], response.data["audience_label"],
             response.data["channels_label"], response.data["published_by_name"], response.data["recipients_count"]),
        )

        # Guardians get SMS only; staff get both. The guardian and the clerk
        # with no number are skipped rather than dropped.
        self.assertEqual(4, Message.objects.filter(channel="in_app").count())
        self.assertEqual(7, Message.objects.filter(channel="sms").count())
        self.assertEqual(2, Message.objects.filter(status="skipped").count())

        guardian_copy = Message.objects.get(recipient_name="Raj Kumar")
        self.assertEqual(("announcement", "Parent meeting"), (guardian_copy.category, guardian_copy.subject))
        self.assertIn("Sunrise Public School: Parent meeting - Parent meeting scheduled Friday at 3 PM.", guardian_copy.body)
        self.assertNotIn("{", guardian_copy.body)
        self.assertIsNotNone(guardian_copy.announcement_id)

    def test_sms_only_skips_the_in_app_copies(self):
        response = self.publish(self.f["admin"], channels="sms")

        self.assertEqual((0, 6), (response.data["in_app_count"], response.data["sms_count"]))
        self.assertEqual(0, Message.objects.filter(channel="in_app").count())
        self.assertEqual(7, Message.objects.filter(channel="sms").count())

    def test_in_app_only_reaches_staff_and_never_texts_a_guardian(self):
        response = self.publish(self.f["admin"], channels="in_app")

        self.assertEqual((4, 0), (response.data["recipients_count"], response.data["sms_count"]))
        self.assertEqual(4, Message.objects.count())

    def test_an_in_app_notice_to_parents_is_refused_rather_than_sent_to_nobody(self):
        response = self.publish(self.f["admin"], audience_type="parents", channels="in_app")

        self.assertEqual(422, response.status_code)
        self.assertEqual("UNREACHABLE_AUDIENCE", response.data["code"])
        self.assertEqual(
            "Guardians have no app login, so this audience can only be reached by SMS, WhatsApp or email.",
            response.data["message"],
        )
        self.assertFalse(Announcement.objects.exists())

    def test_the_parents_audience_reaches_only_guardians(self):
        response = self.publish(self.f["admin"], audience_type="parents")

        self.assertEqual(2, response.data["recipients_count"])
        self.assertEqual(
            ["Anita Rao", "Raj Kumar", "Rohit Singh"],
            list(Message.objects.order_by("recipient_name").values_list("recipient_name", flat=True)),
        )
        skipped = Message.objects.get(status="skipped")
        self.assertEqual(("Anita Rao", "No mobile number on record."), (skipped.recipient_name, skipped.failure_reason))

    def test_the_teachers_audience_reaches_teachers_and_heads_only(self):
        response = self.publish(self.f["admin"], audience_type="teachers")

        self.assertEqual(2, response.data["recipients_count"])
        self.assertEqual(
            {self.f["teacher"].id, self.f["maths_hod"].id},
            set(Message.objects.filter(channel="in_app").values_list("user_id", flat=True)),
        )

    def test_a_class_audience_reaches_only_that_sections_guardians(self):
        response = self.publish(self.f["admin"], audience_type="class_section", audience_id=self.f["section"].id)

        self.assertEqual(("Grade 8 A", 1), (response.data["audience_label"], response.data["recipients_count"]))
        self.assertEqual("Anita Rao", Message.objects.get(status="skipped").recipient_name)
        self.assertEqual("Raj Kumar", Message.objects.exclude(status="skipped").get().recipient_name)

    def test_a_department_audience_reaches_that_departments_staff(self):
        response = self.publish(self.f["admin"], audience_type="department", audience_id=self.f["maths"].id)

        self.assertEqual(("Mathematics", 2), (response.data["audience_label"], response.data["recipients_count"]))

    def test_inactive_people_are_left_out(self):
        self.f["teacher"].status = "inactive"
        self.f["teacher"].save()

        self.assertEqual(1, self.publish(self.f["admin"], audience_type="teachers").data["recipients_count"])

    def test_a_school_with_sms_switched_off_still_delivers_in_app(self):
        CommunicationSetting.objects.create(
            school=self.f["school"], sms_enabled=False, attendance_alerts="absent",
            transport_alerts_enabled=True, leave_alerts_enabled=True, provider="log",
        )

        self.publish(self.f["admin"])

        self.assertEqual((4, 0), (Message.objects.count(), Message.objects.filter(channel="sms").count()))

    def test_a_notice_deleted_before_the_worker_ran_is_not_sent(self):
        self.as_user(self.f["admin"]).post(
            URL,
            {"title": "Parent meeting", "body": "Parent meeting scheduled Friday.", "audience_type": "teachers", "channels": "in_app"},
            format="json",
        )
        Announcement.objects.update(deleted_at=dt.datetime(2026, 9, 1, tzinfo=dt.timezone.utc))

        queue.work()

        self.assertFalse(Message.objects.exists())


class ValidationTest(AnnouncementTestCase):
    def test_an_empty_form_names_the_four_required_fields(self):
        response = self.as_user(self.f["admin"]).post(URL, {}, format="json")

        self.assertEqual(
            {
                "title": ["The title field is required."],
                "body": ["The body field is required."],
                "audience_type": ["The audience type field is required."],
                "channels": ["The channels field is required."],
            },
            self.errors(response),
        )

    def test_every_bad_field_is_named_at_once(self):
        response = self.publish(
            self.f["admin"], title="Hi", body="short", audience_type="aliens", channels="pigeon", expires_at="2020-01-01"
        )

        self.assertEqual(
            {
                "title": ["The title field must be at least 3 characters."],
                "body": ["The body field must be at least 10 characters."],
                "audience_type": ["The selected audience type is invalid."],
                "channels": ["The selected channels is invalid."],
                "expires_at": ["An expiry date cannot be in the past."],
            },
            self.errors(response),
        )

    def test_a_class_or_department_audience_names_its_target(self):
        response = self.publish(self.f["admin"], audience_type="class_section")

        self.assertEqual(["Pick the class or department this announcement is for."], self.errors(response)["audience_id"])

    def test_a_target_from_another_school_is_refused(self):
        other = self.make_school()

        department = self.publish(self.f["admin"], audience_type="department", audience_id=other["maths"].id)
        section = self.publish(self.f["admin"], audience_type="class_section", audience_id=other["section"].id)

        self.assertEqual(["That class or department does not belong to this school."], self.errors(department)["audience_id"])
        self.assertEqual(422, section.status_code)

    def test_a_target_that_is_not_a_number_is_only_that(self):
        response = self.publish(self.f["admin"], audience_type="department", audience_id="abc", channels="in_app")

        self.assertEqual(["The audience id field must be an integer."], self.errors(response)["audience_id"])

    def test_an_unreadable_expiry_is_told_both_problems(self):
        response = self.publish(self.f["admin"], expires_at="soon")

        self.assertEqual(
            ["The expires at field must be a valid date.", "An expiry date cannot be in the past."],
            self.errors(response)["expires_at"],
        )


class AuthorizationTest(AnnouncementTestCase):
    def test_teachers_and_staff_neither_publish_nor_see_the_list(self):
        for role in ("teacher", "staff"):
            self.assertEqual(403, self.publish(self.f[role]).status_code)
            self.assertEqual(403, self.as_user(self.f[role]).get(URL).status_code)

    def test_a_head_of_department_announces_only_to_their_own_department(self):
        hod = self.f["maths_hod"]

        self.assertEqual(201, self.publish(hod, audience_type="department", audience_id=self.f["maths"].id).status_code)
        self.assertEqual(403, self.publish(hod, audience_type="department", audience_id=self.f["science"].id).status_code)
        self.assertEqual(403, self.publish(hod).status_code)
        self.assertEqual(403, self.publish(hod, audience_type="parents").status_code)

    def test_a_head_of_department_reads_only_their_departments_notices(self):
        self.announcement(title="Staff briefing")
        mine = self.for_department(self.f["maths"], title="Maths meeting")
        theirs = self.for_department(self.f["science"], title="Science meeting")
        client = self.as_user(self.f["maths_hod"])

        self.assertEqual(200, client.get(f"{URL}/{mine.id}").status_code)
        self.assertEqual(403, client.get(f"{URL}/{theirs.id}").status_code)
        self.assertEqual(["Maths meeting"], [row["title"] for row in client.get(URL).data["data"]])

    def test_an_admin_cannot_touch_another_schools_announcement(self):
        theirs = self.announcement(school=self.make_school()["school"])
        client = self.as_user(self.f["admin"])

        self.assertEqual(403, client.get(f"{URL}/{theirs.id}").status_code)
        self.assertEqual(403, client.delete(f"{URL}/{theirs.id}").status_code)

    def test_the_list_is_scoped_and_a_super_admin_can_narrow_it(self):
        other = self.make_school()
        self.announcement()
        self.announcement(school=other["school"])

        self.assertEqual(1, len(self.as_user(self.f["admin"]).get(URL).data["data"]))
        self.assertEqual(2, len(self.as_user(self.f["root"]).get(URL).data["data"]))
        self.assertEqual(1, len(self.as_user(self.f["root"]).get(f"{URL}?school_id={other['school'].id}").data["data"]))

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get(URL).status_code)
        self.assertEqual(401, APIClient().post(URL, {}, format="json").status_code)


class ListPreviewAndDeleteTest(AnnouncementTestCase):
    def test_the_list_filters_by_audience_search_and_active_only(self):
        self.announcement(title="Sports day")
        self.for_department(self.f["maths"], title="Syllabus review")
        self.announcement(title="Old notice", expires_at=dt.date(2020, 1, 1))
        client = self.as_user(self.f["admin"])

        self.assertEqual(1, len(client.get(f"{URL}?audience_type=department").data["data"]))
        self.assertEqual(1, len(client.get(f"{URL}?q=sPoRtS").data["data"]))
        self.assertEqual(2, len(client.get(f"{URL}?active_only=1").data["data"]))
        self.assertEqual(2, len(client.get(f"{URL}?active_only=yes").data["data"]))
        self.assertEqual(3, len(client.get(f"{URL}?active_only=0").data["data"]))
        self.assertEqual(3, len(client.get(URL).data["data"]))

    def test_a_row_carries_labels_on_the_schools_clock(self):
        self.f["school"].timezone = "Asia/Kolkata"
        self.f["school"].save()
        self.announcement(expires_at=dt.date(2020, 1, 1), published_by=self.f["admin"])

        row = self.as_user(self.f["admin"]).get(URL).data["data"][0]

        # 04:00 UTC is 9:30 AM in Kolkata.
        self.assertEqual(
            ("Sunrise Public School", "In-app Only", True, self.f["admin"].name, "2026-09-01T04:00:00.000000Z", "09/01/2026 9:30 AM"),
            (row["school_name"], row["channels_label"], row["has_expired"], row["published_by_name"],
             row["published_at"], row["published_at_label"]),
        )

    def test_the_preview_counts_an_audience_before_anything_is_sent(self):
        client = self.as_user(self.f["admin"])

        section = client.get(f"{URL}/preview?audience_type=class_section&channels=sms_in_app&audience_id={self.f['section'].id}")
        everyone = client.get(f"{URL}/preview?audience_type=all_school&channels=in_app")

        self.assertEqual(
            {"recipients": 1, "sms": 1, "in_app": 0, "whatsapp": 0, "email": 0, "audience_label": "Grade 8 A"},
            section.data,
        )
        self.assertEqual(
            {"recipients": 4, "sms": 0, "in_app": 4, "whatsapp": 0, "email": 0, "audience_label": "All School"},
            everyone.data,
        )
        self.assertFalse(Announcement.objects.exists())

    def test_the_preview_never_names_another_schools_class_or_department(self):
        # DENY. Laravel used to answer with the other school's names.
        theirs = self.make_school()
        ours = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        client = self.as_user(ours)

        section = client.get(f"{URL}/preview?audience_type=class_section&channels=sms_in_app&audience_id={theirs['section'].id}")
        department = client.get(f"{URL}/preview?audience_type=department&channels=in_app&audience_id={theirs['maths'].id}")

        self.assertEqual(("Class", 0), (section.data["audience_label"], section.data["recipients"]))
        self.assertEqual("Department", department.data["audience_label"])

    def test_the_preview_takes_any_mix_of_channels(self):
        response = self.as_user(self.f["admin"]).get(f"{URL}/preview?audience_type=all_school&channels=sms,in_app,email")

        self.assertEqual(200, response.status_code, response.data)
        # Two guardians have a number for the SMS copy and four staff have an
        # inbox; nobody has a guardian email, and every staff member has one.
        self.assertEqual((6, 4), (response.data["recipients"], response.data["email"]))

    def test_a_bad_audience_or_channel_is_a_bare_422(self):
        response = self.as_user(self.f["admin"]).get(f"{URL}/preview?audience_type=x&channels=sms")
        self.assertEqual(422, response.status_code)

        response = self.as_user(self.f["admin"]).get(f"{URL}/preview?audience_type=all_school&channels=sms,fax")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            {"code": "HTTP_ERROR", "message": "An error occurred while processing the request.", "details": {}},
            response.data,
        )

    def test_a_head_of_department_cannot_preview_another_department(self):
        response = self.as_user(self.f["maths_hod"]).get(
            f"{URL}/preview?audience_type=department&channels=in_app&audience_id={self.f['science'].id}"
        )

        self.assertEqual(403, response.status_code)

    def test_deleting_drops_it_from_the_feed_but_keeps_the_log(self):
        self.publish(self.f["admin"])
        announcement = Announcement.objects.get()
        teacher = self.as_user(self.f["teacher"])

        self.assertEqual(1, len(teacher.get("/api/v1/inbox").data["data"]))
        self.assertEqual(204, self.as_user(self.f["admin"]).delete(f"{URL}/{announcement.id}").status_code)

        self.assertIsNotNone(Announcement.objects.get().deleted_at)
        self.assertEqual(11, Message.objects.count())
        self.assertEqual(0, len(teacher.get("/api/v1/inbox").data["data"]))
        self.assertEqual(404, self.as_user(self.f["admin"]).get(f"{URL}/{announcement.id}").status_code)

    def test_an_expired_announcement_leaves_the_feed_on_its_own(self):
        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 17, 6, 0, tzinfo=dt.timezone.utc)):
            self.publish(self.f["admin"], expires_at="2026-09-17")
            teacher = self.as_user(self.f["teacher"])
            self.assertEqual(1, len(teacher.get("/api/v1/inbox").data["data"]))

        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 18, 9, 0, tzinfo=dt.timezone.utc)):
            self.assertEqual(0, len(teacher.get("/api/v1/inbox").data["data"]))
            self.assertEqual({"unread": 0}, teacher.get("/api/v1/inbox/unread-count").data)

    def test_the_in_app_copy_carries_the_title_as_its_subject(self):
        self.publish(self.f["admin"], title="Sports day moved")

        row = self.as_user(self.f["teacher"]).get("/api/v1/inbox").data["data"][0]

        self.assertEqual(("Sports day moved", "announcement"), (row["subject"], row["category"]))

    def test_announcements_show_in_the_communication_log(self):
        self.publish(self.f["admin"], audience_type="parents")

        rows = self.as_user(self.f["admin"]).get("/api/v1/communication/messages?category=announcement").data["data"]

        self.assertEqual((3, "Announcement"), (len(rows), rows[0]["event_label"]))
