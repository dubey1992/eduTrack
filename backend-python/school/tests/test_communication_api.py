"""The Communication Center and the inbox, over HTTP.

**The log is for the admins who run a school.** It holds guardians' numbers
and what was said to them, so nobody else reads it - and nobody reads another
school's.

**The order of checks is contract.** A teacher with junk filters is a 403,
not a 422; a template event that does not exist is a 404 even to somebody who
may not configure; saving settings authorizes before it validates.

**The inbox is the reader's own in-app messages**, and nothing about another
person's is readable or markable by id.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Announcement, CommunicationSetting, Message, MessageTemplate, QueuedJob
from school.validation import LaravelBooleanField


class CommunicationTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def message(self, **overrides):
        return factories.MessageFactory(school=self.school, **overrides)

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


class LogTest(CommunicationTestCase):
    def test_an_admin_reads_their_schools_log_newest_first(self):
        older = self.message(created_at=dt.datetime(2026, 9, 1, 4, 0, tzinfo=dt.timezone.utc))
        newer = self.message(created_at=dt.datetime(2026, 9, 2, 4, 0, tzinfo=dt.timezone.utc))
        factories.MessageFactory(school=self.elsewhere)

        response = self.as_user(self.admin).get("/api/v1/communication/messages")

        self.assertEqual([newer.id, older.id], [row["id"] for row in response.data["data"]])

    def test_a_row_carries_labels_rendered_on_the_schools_clock(self):
        # 08:08 UTC is 1:38 PM in Kolkata.
        self.message(
            created_at=dt.datetime(2026, 9, 17, 8, 8, tzinfo=dt.timezone.utc),
            sent_at=None,
            status="skipped",
            channel="in_app",
            provider=None,
        )

        row = self.as_user(self.admin).get("/api/v1/communication/messages").data["data"][0]

        self.assertEqual(
            {
                "event_label": "Leave approved",
                "category_label": "Leave",
                "channel_label": "In-app",
                "status_label": "Skipped",
                "provider_label": None,
                "created_at": "2026-09-17T08:08:00.000000Z",
                "created_at_label": "1:38 PM",
                "created_on_label": "09/17/2026",
                "sent_at_label": None,
                "timezone": "Asia/Kolkata",
            },
            {key: row[key] for key in (
                "event_label", "category_label", "channel_label", "status_label", "provider_label",
                "created_at", "created_at_label", "created_on_label", "sent_at_label", "timezone",
            )},
        )

    def test_teachers_do_not_read_the_log_even_with_junk_filters(self):
        # Authorized before validated: a 403, not a 422.
        response = self.as_user(self.teacher).get("/api/v1/communication/messages?category=nonsense")

        self.assertEqual(403, response.status_code)

    def test_another_schools_admin_never_sees_this_schools_messages(self):
        self.message()

        response = self.as_user(self.stranger).get(
            f"/api/v1/communication/messages?school_id={self.school.id}"
        )

        self.assertEqual([], response.data["data"])

    def test_the_filters_narrow_the_log(self):
        wanted = self.message(category="attendance", event="attendance.absent", channel="sms", status="failed")
        self.message()

        response = self.as_user(self.admin).get(
            "/api/v1/communication/messages?category=attendance&channel=sms&status=failed"
        )

        self.assertEqual([wanted.id], [row["id"] for row in response.data["data"]])

    def test_the_search_is_case_insensitive_and_leaves_wildcards_alone(self):
        found = self.message(recipient_name="Meera SHARMA")
        self.message(recipient_name="Somebody else", body="Nothing here.")

        by_name = self.as_user(self.admin).get("/api/v1/communication/messages?q=sharma")
        # Laravel does not escape % in the term, so it matches every row.
        by_wildcard = self.as_user(self.admin).get("/api/v1/communication/messages?q=%25")

        self.assertEqual([found.id], [row["id"] for row in by_name.data["data"]])
        self.assertEqual(2, len(by_wildcard.data["data"]))

    def test_the_dates_are_days_at_the_school(self):
        # 20:00 UTC on the 16th is already the 17th in Kolkata.
        late = self.message(created_at=dt.datetime(2026, 9, 16, 20, 0, tzinfo=dt.timezone.utc))
        self.message(created_at=dt.datetime(2026, 9, 16, 10, 0, tzinfo=dt.timezone.utc))

        response = self.as_user(self.admin).get(
            "/api/v1/communication/messages?date_from=2026-09-17&date_to=2026-09-17"
        )

        self.assertEqual([late.id], [row["id"] for row in response.data["data"]])

    def test_bad_filters_are_named_one_by_one(self):
        response = self.as_user(self.admin).get(
            "/api/v1/communication/messages?category=x&channel=y&status=z&date_from=junk"
            f"&date_to=2026-01-01&q={'a' * 101}&per_page=0&school_id=999999"
        )

        self.assertEqual(
            {
                "school_id": ["The selected school id is invalid."],
                "category": ["The selected category is invalid."],
                "channel": ["The selected channel is invalid."],
                "status": ["The selected status is invalid."],
                "date_from": ["The date from field must be a valid date."],
                "q": ["The q field must not be greater than 100 characters."],
                "per_page": ["The per page field must be at least 1."],
            },
            self.errors(response),
        )

    def test_reversed_dates_are_refused(self):
        response = self.as_user(self.admin).get(
            "/api/v1/communication/messages?date_from=2026-09-10&date_to=2026-09-01"
        )

        self.assertEqual(
            ["The date to field must be a date after or equal to date from."],
            self.errors(response)["date_to"],
        )


class SummaryTest(CommunicationTestCase):
    def at(self, instant):
        return mock.patch("django.utils.timezone.now", return_value=instant)

    def test_the_tiles_count_the_schools_day(self):
        # Noon in Kolkata on the 17th. A message at 20:00 UTC on the 16th is
        # 01:30 on the 17th there - today - and one at 17:00 UTC is not.
        now = dt.datetime(2026, 9, 17, 6, 30, tzinfo=dt.timezone.utc)
        for status, channel, when in (
            ("sent", "sms", dt.datetime(2026, 9, 16, 20, 0, tzinfo=dt.timezone.utc)),
            ("sent", "in_app", now),
            ("failed", "sms", now),
            ("queued", "sms", now),
            ("skipped", "sms", now),
            ("sent", "sms", dt.datetime(2026, 9, 16, 17, 0, tzinfo=dt.timezone.utc)),
        ):
            self.message(status=status, channel=channel, created_at=when)

        with self.at(now):
            response = self.as_user(self.admin).get("/api/v1/communication/summary")

        self.assertEqual(
            {
                "sent_today": 2,
                "sms_sent_today": 1,
                "queued_today": 1,
                "failed_today": 1,
                "skipped_today": 1,
                "delivery_rate": 66.7,
                "total": 6,
                "provider_label": "Demo Gateway",
                "provider_delivers": False,
            },
            response.data,
        )

    def test_a_whole_delivery_rate_goes_out_as_an_int_and_none_attempted_is_null(self):
        now = dt.datetime(2026, 9, 17, 6, 30, tzinfo=dt.timezone.utc)
        self.message(created_at=now)

        with self.at(now):
            everything = self.as_user(self.admin).get("/api/v1/communication/summary")
            nothing = self.as_user(self.admin).get("/api/v1/communication/summary?status=queued")

        self.assertIn(b'"delivery_rate":100,', everything.content)
        self.assertIsNone(nothing.data["delivery_rate"])

    def test_teachers_do_not_see_the_tiles(self):
        self.assertEqual(403, self.as_user(self.teacher).get("/api/v1/communication/summary").status_code)


class OneMessageTest(CommunicationTestCase):
    def test_an_admin_reads_one_message_and_a_stranger_does_not(self):
        found = self.message()

        self.assertEqual(200, self.as_user(self.admin).get(f"/api/v1/communication/messages/{found.id}").status_code)
        self.assertEqual(403, self.as_user(self.stranger).get(f"/api/v1/communication/messages/{found.id}").status_code)
        self.assertEqual(404, self.as_user(self.admin).get("/api/v1/communication/messages/999999").status_code)

    def test_a_failed_message_goes_back_on_the_queue_with_its_body_intact(self):
        failed = self.message(status="failed", failure_reason="Gateway timeout", sent_at=None)

        response = self.as_user(self.admin).post(f"/api/v1/communication/messages/{failed.id}/retry")

        self.assertEqual(200, response.status_code)
        self.assertEqual(("queued", None), (response.data["status"], response.data["failure_reason"]))
        self.assertEqual(failed.body, response.data["body"])
        self.assertTrue(QueuedJob.objects.filter(name="send_message", payload={"message_id": failed.id}).exists())

    def test_anything_but_a_failed_message_is_not_retried(self):
        for status in ("sent", "queued", "skipped"):
            found = self.message(status=status)
            response = self.as_user(self.admin).post(f"/api/v1/communication/messages/{found.id}/retry")

            with self.subTest(status=status):
                self.assertEqual(409, response.status_code)
                self.assertEqual("MESSAGE_NOT_RETRYABLE", response.data["code"])

        self.assertFalse(QueuedJob.objects.exists())

    def test_another_school_cannot_retry(self):
        failed = self.message(status="failed")

        self.assertEqual(403, self.as_user(self.stranger).post(f"/api/v1/communication/messages/{failed.id}/retry").status_code)


class TemplateTest(CommunicationTestCase):
    URL = "/api/v1/communication/templates"

    def put(self, user, event="leave.approved", **body):
        return self.as_user(user).put(f"{self.URL}/{event}", body, format="json")

    def test_every_event_is_listed_with_its_default_wording(self):
        response = self.as_user(self.admin).get(self.URL)

        self.assertEqual(8, len(response.data))
        self.assertEqual(
            {
                "event": "attendance.present",
                "event_label": "Marked present",
                "category": "attendance",
                "channels": ["sms"],
                "body": "{student_name} was marked PRESENT on {date}. - {school_name}",
                "default_body": "{student_name} was marked PRESENT on {date}. - {school_name}",
                "is_custom": False,
                "tokens": ["student_name", "class_name", "date", "school_name", "guardian_name"],
                "updated_at": None,
                "updated_by_name": None,
            },
            response.data[0],
        )

    def test_an_admin_rewords_an_event_and_resets_it(self):
        reworded = self.put(self.admin, body="Dear {staff_name}, your leave is approved.")

        self.assertEqual(200, reworded.status_code)
        self.assertTrue(reworded.data["is_custom"])
        self.assertEqual(self.admin.name, reworded.data["updated_by_name"])

        reset = self.as_user(self.admin).delete(f"{self.URL}/leave.approved")

        self.assertFalse(reset.data["is_custom"])
        self.assertEqual(reset.data["default_body"], reset.data["body"])
        self.assertFalse(MessageTemplate.objects.exists())

    def test_saving_the_same_wording_again_writes_nothing(self):
        self.put(self.admin, body="Dear {staff_name}, your leave is approved.")
        before = MessageTemplate.objects.get().updated_at

        self.put(self.admin, body="Dear {staff_name}, your leave is approved.")

        self.assertEqual(before, MessageTemplate.objects.get().updated_at)

    def test_an_unknown_event_is_a_404_before_anything_else(self):
        self.assertEqual(404, self.put(self.teacher, event="nope", body="x").status_code)
        self.assertEqual(404, self.as_user(self.teacher).delete(f"{self.URL}/nope").status_code)

    def test_teachers_and_strangers_do_not_configure(self):
        self.assertEqual(403, self.put(self.teacher, body="").status_code)
        self.assertEqual(403, self.as_user(self.teacher).get(self.URL).status_code)
        self.assertEqual(403, self.as_user(self.stranger).get(f"{self.URL}?school_id={self.school.id}").status_code)
        self.assertEqual(403, self.as_user(self.admin).get(f"{self.URL}?school_id=abc").status_code)

    def test_a_short_body_with_a_foreign_placeholder_is_told_both(self):
        response = self.put(self.admin, body="Hi {foo}")

        self.assertEqual(
            [
                "The body field must be at least 10 characters.",
                "This message can only use these placeholders: {staff_name}, {leave_type}, "
                "{start_date}, {end_date}, {days}, {remarks}, {school_name}. Remove {foo}.",
            ],
            self.errors(response)["body"],
        )

    def test_each_foreign_placeholder_is_named_once(self):
        response = self.put(self.admin, body="Dear {staff_name}, {foo} and {bar} and {foo}")

        self.assertTrue(self.errors(response)["body"][0].endswith("Remove {foo}, {bar}."))

    def test_the_body_limits(self):
        self.assertEqual(
            ["The body field must not be greater than 480 characters."],
            self.errors(self.put(self.admin, body="x" * 481))["body"],
        )
        self.assertEqual(["The body field is required."], self.errors(self.put(self.admin))["body"])

    def test_a_super_admin_names_the_school(self):
        response = self.put(self.root, body="Dear {staff_name}, approved.", school_id=self.school.id)
        nameless = self.put(self.root, body="Dear {staff_name}, approved.")

        self.assertEqual(200, response.status_code)
        self.assertEqual(404, nameless.status_code)


class SettingsTest(CommunicationTestCase):
    URL = "/api/v1/communication/settings"

    def body(self, **overrides):
        data = {
            "sms_enabled": True,
            "attendance_alerts": "both",
            "transport_alerts_enabled": False,
            "leave_alerts_enabled": True,
            "provider": "log",
            "sender_id": "SUNRISE",
        }
        data.update(overrides)

        return data

    def test_a_school_that_never_saved_gets_the_defaults_without_a_row(self):
        response = self.as_user(self.admin).get(self.URL)

        self.assertEqual(
            {
                "school_id": self.school.id,
                "sms_enabled": True,
                "attendance_alerts": "absent",
                "attendance_alerts_label": "Absent only",
                "transport_alerts_enabled": True,
                "leave_alerts_enabled": True,
                "provider": "log",
                "provider_label": "Demo Gateway",
                "sender_id": None,
                "available_providers": [{"value": "log", "label": "Demo Gateway"}],
                "is_saved": False,
            },
            response.data,
        )
        self.assertFalse(CommunicationSetting.objects.exists())

    def test_a_super_admin_without_a_school_reads_school_zero(self):
        self.assertEqual(0, self.as_user(self.root).get(self.URL).data["school_id"])

    def test_saving_creates_the_row_and_answers_200(self):
        response = self.as_user(self.admin).put(self.URL, self.body(), format="json")

        self.assertEqual(200, response.status_code)
        self.assertEqual(("both", "Present + Absent", True), (
            response.data["attendance_alerts"], response.data["attendance_alerts_label"], response.data["is_saved"],
        ))

    def test_a_missing_sender_is_kept_and_a_null_one_is_cleared(self):
        self.as_user(self.admin).put(self.URL, self.body(), format="json")

        kept = self.body()
        del kept["sender_id"]
        self.as_user(self.admin).put(self.URL, kept, format="json")
        self.assertEqual("SUNRISE", CommunicationSetting.objects.get().sender_id)

        self.as_user(self.admin).put(self.URL, self.body(sender_id=None), format="json")
        self.assertIsNone(CommunicationSetting.objects.get().sender_id)

    def test_strangers_are_refused_before_their_request_is_read(self):
        response = self.as_user(self.stranger).put(f"{self.URL}?school_id={self.school.id}", {}, format="json")

        self.assertEqual(403, response.status_code)

    def test_bad_switches_are_named_with_laravels_sentences(self):
        response = self.as_user(self.admin).put(
            self.URL,
            {
                "sms_enabled": "yes",
                "attendance_alerts": "sometimes",
                "transport_alerts_enabled": 2,
                "leave_alerts_enabled": None,
                "provider": "twilio",
                "sender_id": "has space!",
            },
            format="json",
        )

        self.assertEqual(
            {
                "sms_enabled": ["The sms enabled field must be true or false."],
                "attendance_alerts": ["The selected attendance alerts is invalid."],
                "transport_alerts_enabled": ["The transport alerts enabled field must be true or false."],
                "leave_alerts_enabled": ["The leave alerts enabled field is required."],
                "provider": ["That SMS gateway is not available."],
                "sender_id": ["A sender ID can only contain letters, numbers and hyphens."],
            },
            self.errors(response),
        )


class InboxTest(CommunicationTestCase):
    def mine(self, **overrides):
        return self.message(user=self.teacher, channel="in_app", provider=None, **overrides)

    def test_the_inbox_is_my_in_app_messages_that_went_or_are_going_out(self):
        shown = [self.mine(status="sent"), self.mine(status="queued")]
        self.mine(status="failed")
        self.mine(status="skipped")
        self.message(user=self.teacher, channel="sms")
        self.message(user=self.admin, channel="in_app")

        response = self.as_user(self.teacher).get("/api/v1/inbox")

        self.assertEqual(sorted(m.id for m in shown), sorted(row["id"] for row in response.data["data"]))

    def test_an_expired_or_deleted_announcement_drops_out(self):
        def announcement(**overrides):
            fields = dict(
                school=self.school, title="Sports day", body="Friday.", audience_type="school",
                audience_label="Everyone", channels="in_app", published_at=dt.datetime(2026, 9, 1, tzinfo=dt.timezone.utc),
                recipients_count=1, sms_count=0, in_app_count=1,
            )
            fields.update(overrides)
            return Announcement.objects.create(**fields)

        live = self.mine(announcement=announcement(expires_at=dt.date(2099, 1, 1)))
        undated = self.mine(announcement=announcement())
        self.mine(announcement=announcement(expires_at=dt.date(2020, 1, 1)))
        self.mine(announcement=announcement(deleted_at=dt.datetime(2026, 9, 2, tzinfo=dt.timezone.utc)))

        response = self.as_user(self.teacher).get("/api/v1/inbox")

        self.assertEqual(sorted([live.id, undated.id]), sorted(row["id"] for row in response.data["data"]))

    def test_unread_follows_php_truthiness(self):
        self.mine(read_at=dt.datetime(2026, 9, 1, tzinfo=dt.timezone.utc))
        unread = self.mine()

        for value, expected in (("1", [unread.id]), ("false", [unread.id]), ("0", None), ("", None)):
            ids = [row["id"] for row in self.as_user(self.teacher).get(f"/api/v1/inbox?unread={value}").data["data"]]

            with self.subTest(unread=value):
                if expected is None:
                    self.assertEqual(2, len(ids))
                else:
                    self.assertEqual(expected, ids)

    def test_the_count_marking_one_and_marking_all(self):
        first = self.mine()
        self.mine()
        self.mine()
        client = self.as_user(self.teacher)

        self.assertEqual({"unread": 3}, client.get("/api/v1/inbox/unread-count").data)

        read = client.post(f"/api/v1/inbox/{first.id}/read")
        self.assertIsNotNone(read.data["read_at"])

        self.assertEqual({"marked": 2}, client.post("/api/v1/inbox/read-all").data)
        self.assertEqual({"unread": 0}, client.get("/api/v1/inbox/unread-count").data)

    def test_marking_read_twice_keeps_the_first_time(self):
        found = self.mine()
        client = self.as_user(self.teacher)

        first = client.post(f"/api/v1/inbox/{found.id}/read").data["read_at"]
        second = client.post(f"/api/v1/inbox/{found.id}/read").data["read_at"]

        self.assertEqual(first, second)

    def test_somebody_elses_message_is_not_mine_to_mark(self):
        found = self.mine()

        self.assertEqual(403, self.as_user(self.admin).post(f"/api/v1/inbox/{found.id}/read").status_code)
        self.assertEqual(404, self.as_user(self.admin).post("/api/v1/inbox/999999/read").status_code)

    def test_my_own_sms_copy_can_still_be_marked(self):
        # Ownership is the check, not whether the message is in the feed.
        own_sms = self.message(user=self.teacher, channel="sms")

        self.assertEqual(200, self.as_user(self.teacher).post(f"/api/v1/inbox/{own_sms.id}/read").status_code)

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get("/api/v1/inbox").status_code)


class BooleanFieldTest(TestCase):
    def test_only_laravels_six_values_pass(self):
        field = LaravelBooleanField("flag")

        for value, expected in ((True, True), (False, False), (1, True), (0, False), ("1", True), ("0", False)):
            self.assertIs(expected, field.to_internal_value(value), value)

        for junk in ("yes", "true", "on", "t", 2, 1.0, "", []):
            with self.subTest(value=junk), self.assertRaises(Exception):
                field.to_internal_value(junk)
