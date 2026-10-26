"""Push notifications (docs/teacher-app.md, T6), over HTTP and through the
sender with Firebase replaced by a fake.

**The phones a person is signed in on are theirs alone.** Registering acts on
the caller; forgetting removes only the caller's own; a shared phone moves to
whoever signed in on it last.

**A push is a second delivery of an in-app message.** Whatever reaches a
member of staff's inbox buzzes their phones, so an alert the school switched
off - never recorded - is never pushed either.
"""

import base64
import datetime as dt
import json
import tempfile
from pathlib import Path
from unittest import mock

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, jobs, notifications, push, tokens
from school.enums import MessageChannel, MessageEvent, MessageStatus, UserRole
from school.models import CommunicationSetting, DeviceToken, Message, QueuedJob

KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ACCOUNT = {
    "project_id": "school365ai-test",
    "client_email": "push@school365ai-test.iam.gserviceaccount.com",
    "private_key": KEY.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode(),
}


def account_file() -> str:
    folder = Path(tempfile.mkdtemp())
    path = folder / "firebase.json"
    path.write_text(json.dumps(ACCOUNT), encoding="utf-8")
    return str(path)


class FakeFirebase:
    """Stands in for http.post: the token endpoint, then one answer per push."""

    def __init__(self, answers=None):
        self.answers = list(answers or [])
        self.token_calls = 0
        self.pushes = []

    def __call__(self, url, *, form=None, body=None, basic=None, bearer=None, headers=None):
        if url == push.TOKEN_URL:
            self.token_calls += 1
            return {"_status": 200, "access_token": "ya29.fake", "expires_in": 3600}

        self.pushes.append({"url": url, "body": body, "bearer": bearer})
        return self.answers.pop(0) if self.answers else {"_status": 200, "name": "projects/x/messages/1"}


class PushTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(name="Greenfield School")
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
        return client

    def phone(self, user, token="tok-1"):
        return DeviceToken.objects.create(
            user_id=user.id, token=token, platform="android", app="staff",
            created_at="2026-10-26T00:00:00Z", updated_at="2026-10-26T00:00:00Z",
        )

    def inbox_message(self, user=None, **overrides):
        fields = {
            "school": self.school,
            "event": MessageEvent.LEAVE_APPROVED,
            "category": "leave",
            "channel": MessageChannel.IN_APP,
            "recipient_name": user.name if user else "",
            "user": user,
            "subject": None,
            "body": "Your Casual leave from 10/28/2026 to 10/28/2026 has been approved.",
            "status": MessageStatus.SENT,
        }
        fields.update(overrides)
        return factories.MessageFactory(**fields)


class RegisteringAPhone(PushTestCase):
    url = "/api/v1/devices"

    def register(self, user, **body):
        return self.as_user(user).post(
            self.url, {"token": "tok-1", "platform": "android", "app": "staff", **body}, format="json"
        )

    def test_a_signed_in_person_registers_their_phone(self):
        response = self.register(self.teacher)

        self.assertEqual(200, response.status_code)
        device = DeviceToken.objects.get(token="tok-1")
        self.assertEqual((self.teacher.id, "android", "staff"), (device.user_id, device.platform, device.app))
        self.assertIsNotNone(device.last_seen_at)

    def test_registering_again_keeps_one_row(self):
        self.register(self.teacher)
        self.register(self.teacher)

        self.assertEqual(1, DeviceToken.objects.count())

    def test_a_shared_phone_moves_to_whoever_signed_in_last(self):
        self.register(self.teacher)
        self.register(self.colleague)

        self.assertEqual(self.colleague.id, DeviceToken.objects.get(token="tok-1").user_id)

    def test_two_phones_are_two_rows(self):
        self.register(self.teacher)
        self.register(self.teacher, token="tok-2")

        self.assertEqual(2, DeviceToken.objects.filter(user_id=self.teacher.id).count())

    def test_an_unknown_platform_or_app_is_refused(self):
        self.assertEqual(422, self.register(self.teacher, platform="symbian").status_code)
        self.assertEqual(422, self.register(self.teacher, app="parent").status_code)
        self.assertFalse(DeviceToken.objects.exists())

    def test_a_missing_or_overlong_token_is_refused(self):
        self.assertEqual(422, self.register(self.teacher, token="").status_code)
        self.assertEqual(422, self.register(self.teacher, token="x" * 256).status_code)

    def test_signed_out_is_refused(self):
        response = APIClient().post(self.url, {"token": "t", "platform": "android", "app": "staff"}, format="json")

        self.assertEqual(401, response.status_code)


class ForgettingAPhone(PushTestCase):
    url = "/api/v1/devices"

    def forget(self, user, token="tok-1"):
        return self.as_user(user).delete(self.url, {"token": token}, format="json")

    def test_signing_out_forgets_the_phone(self):
        self.phone(self.teacher)

        self.assertEqual(204, self.forget(self.teacher).status_code)
        self.assertFalse(DeviceToken.objects.exists())

    def test_somebody_elses_phone_is_left_alone_and_nothing_says_it_exists(self):
        self.phone(self.teacher)

        self.assertEqual(204, self.forget(self.colleague).status_code)
        self.assertTrue(DeviceToken.objects.filter(user_id=self.teacher.id).exists())

    def test_forgetting_a_phone_that_is_not_there_is_fine(self):
        self.assertEqual(204, self.forget(self.teacher, token="never-seen").status_code)


@override_settings(FIREBASE_CREDENTIALS_FILE="")
class WithoutFirebase(PushTestCase):
    def test_nothing_is_sent_and_nothing_fails(self):
        self.phone(self.teacher)

        with mock.patch("school.push.http.post") as post:
            self.assertEqual(0, push.deliver(self.inbox_message(self.teacher)))

        post.assert_not_called()

    def test_an_inbox_message_queues_no_push(self):
        message = self.inbox_message(self.teacher, status=MessageStatus.QUEUED)
        self.phone(self.teacher)

        jobs.send_message(message.id)

        self.assertFalse(QueuedJob.objects.filter(name=jobs.SEND_PUSH).exists())


class TheSender(PushTestCase):
    def setUp(self):
        super().setUp()
        self.settings_override = override_settings(FIREBASE_CREDENTIALS_FILE=account_file())
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)

    def test_pushes_to_every_phone_of_the_person_and_only_theirs(self):
        self.phone(self.teacher, "tok-1")
        self.phone(self.teacher, "tok-2")
        self.phone(self.colleague, "tok-3")
        firebase = FakeFirebase()

        with mock.patch("school.push.http.post", firebase):
            sent = push.deliver(self.inbox_message(self.teacher))

        self.assertEqual(2, sent)
        self.assertEqual({"tok-1", "tok-2"}, {p["body"]["message"]["token"] for p in firebase.pushes})
        self.assertEqual(
            "https://fcm.googleapis.com/v1/projects/school365ai-test/messages:send", firebase.pushes[0]["url"]
        )
        self.assertEqual("ya29.fake", firebase.pushes[0]["bearer"])

    def test_says_what_it_is_and_where_a_tap_goes(self):
        self.phone(self.teacher)
        firebase = FakeFirebase()
        message = self.inbox_message(self.teacher)

        with mock.patch("school.push.http.post", firebase):
            push.deliver(message)

        body = firebase.pushes[0]["body"]["message"]
        self.assertEqual("Leave approved", body["notification"]["title"])
        self.assertEqual(message.body, body["notification"]["body"])
        self.assertEqual({"route": "/leave", "message_id": str(message.id), "event": "leave.approved"}, body["data"])

    def test_an_announcement_keeps_its_own_title_and_opens_the_inbox(self):
        self.phone(self.teacher)
        firebase = FakeFirebase()
        message = self.inbox_message(
            self.teacher, event=MessageEvent.ANNOUNCEMENT_PUBLISHED, category="announcement", subject="Sports day"
        )

        with mock.patch("school.push.http.post", firebase):
            push.deliver(message)

        body = firebase.pushes[0]["body"]["message"]
        self.assertEqual("Sports day", body["notification"]["title"])
        self.assertEqual("/inbox", body["data"]["route"])

    def test_a_long_message_is_cut_for_the_notification_shade(self):
        self.phone(self.teacher)
        firebase = FakeFirebase()

        with mock.patch("school.push.http.post", firebase):
            push.deliver(self.inbox_message(self.teacher, body="x" * 600))

        self.assertEqual(push.BODY_LIMIT, len(firebase.pushes[0]["body"]["message"]["notification"]["body"]))

    def test_a_phone_firebase_no_longer_knows_is_forgotten(self):
        self.phone(self.teacher, "dead")
        self.phone(self.teacher, "alive")
        unregistered = {
            "_status": 404,
            "error": {"details": [{"errorCode": "UNREGISTERED"}]},
        }
        firebase = FakeFirebase([unregistered, {"_status": 200}])

        with mock.patch("school.push.http.post", firebase):
            sent = push.deliver(self.inbox_message(self.teacher))

        self.assertEqual(1, sent)
        self.assertEqual(["alive"], list(DeviceToken.objects.values_list("token", flat=True)))

    def test_a_firebase_outage_keeps_the_phones(self):
        self.phone(self.teacher)
        firebase = FakeFirebase([{"_status": 503}])

        with mock.patch("school.push.http.post", firebase):
            self.assertEqual(0, push.deliver(self.inbox_message(self.teacher)))

        self.assertTrue(DeviceToken.objects.exists())

    def test_the_access_token_is_reused_between_messages(self):
        self.phone(self.teacher)
        firebase = FakeFirebase()

        with mock.patch("school.push.http.post", firebase):
            push.deliver(self.inbox_message(self.teacher))
            push.deliver(self.inbox_message(self.teacher))

        self.assertEqual(1, firebase.token_calls)
        self.assertEqual(2, len(firebase.pushes))

    def test_nobody_signed_in_anywhere_means_no_call_at_all(self):
        firebase = FakeFirebase()

        with mock.patch("school.push.http.post", firebase):
            self.assertEqual(0, push.deliver(self.inbox_message(self.teacher)))

        self.assertEqual(0, firebase.token_calls)

    def test_the_assertion_is_signed_with_the_service_accounts_key(self):
        assertion = push.signed_assertion(ACCOUNT, 1_800_000_000)
        header, claims, signature = assertion.split(".")

        def decode(part):
            return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))

        KEY.public_key().verify(decode(signature), f"{header}.{claims}".encode(), padding.PKCS1v15(), hashes.SHA256())
        payload = json.loads(decode(claims))
        self.assertEqual(ACCOUNT["client_email"], payload["iss"])
        self.assertEqual(push.SCOPE, payload["scope"])
        self.assertEqual(1_800_000_000 + 3600, payload["exp"])

    def test_an_inbox_message_queues_its_push(self):
        message = self.inbox_message(self.teacher, status=MessageStatus.QUEUED)

        jobs.send_message(message.id)

        job = QueuedJob.objects.get(name=jobs.SEND_PUSH)
        self.assertIn(str(message.id), json.dumps(job.payload))
        self.assertEqual(MessageStatus.SENT, Message.objects.get(pk=message.id).status)

    def test_a_message_for_a_guardian_has_nobody_to_push_to(self):
        message = self.inbox_message(user=None, status=MessageStatus.QUEUED, recipient_name="A guardian")

        jobs.send_message(message.id)

        self.assertFalse(QueuedJob.objects.filter(name=jobs.SEND_PUSH).exists())


class SwitchedOffIsNeverPushed(PushTestCase):
    """The muted rule: a leave decision the school does not announce is never
    recorded, so there is no inbox row and no push."""

    def test_a_muted_leave_alert_records_nothing_to_push(self):
        CommunicationSetting.objects.create(
            school_id=self.school.id,
            **{**notifications.DEFAULTS, "leave_alerts_enabled": False},
            created_at="2026-10-26T00:00:00Z",
            updated_at="2026-10-26T00:00:00Z",
        )

        recorded = notifications.notify_staff(
            MessageEvent.LEAVE_APPROVED, self.teacher,
            {"leave_type": "Casual", "start_date": "10/28/2026", "end_date": "10/28/2026", "days": "1", "remarks": ""},
        )

        self.assertFalse(recorded)
        self.assertFalse(Message.objects.exists())


class TheReviewTellsTheTeacher(PushTestCase):
    """An HOD reviewing a report tells the teacher who wrote it - in the
    inbox only, never by SMS (docs/teacher-app.md, T6)."""

    def setUp(self):
        super().setUp()
        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        department = factories.DepartmentFactory(school=self.school, hod_user=self.hod)
        factories.StaffProfileFactory(school=self.school, user=self.teacher, department=department)
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                school=self.school, academic_year=factories.AcademicYearFactory(school=self.school), name="Grade 3"
            ),
            name="A",
        )
        entry = factories.TimetableEntryFactory(
            school=self.school, class_section=section,
            period=factories.PeriodFactory(school=self.school, period_number=1),
            subject=factories.SubjectFactory(school=self.school, department=department, name="Mathematics"),
            teacher=self.teacher,
        )
        self.report = factories.DailyTeachingReportFactory(
            school=self.school, timetable_entry=entry, teacher=self.teacher, report_date=dt.date(2026, 10, 26)
        )

    def test_the_teacher_gets_an_inbox_message_and_nothing_else(self):
        response = self.as_user(self.hod).patch(f"/api/v1/teaching-reports/{self.report.id}/review")

        self.assertEqual(200, response.status_code)
        [message] = Message.objects.filter(user_id=self.teacher.id)
        self.assertEqual(MessageEvent.REPORT_REVIEWED, message.event)
        self.assertEqual("teaching", message.category)
        self.assertEqual(MessageChannel.IN_APP, message.channel)
        self.assertEqual(
            f"{self.hod.name} reviewed your report for Mathematics, Grade 3 A, period 1 on 10/26/2026.", message.body
        )
        self.assertFalse(Message.objects.exclude(channel=MessageChannel.IN_APP).exists())

    def test_its_push_opens_the_teaching_tab(self):
        self.as_user(self.hod).patch(f"/api/v1/teaching-reports/{self.report.id}/review")

        self.assertEqual("/teaching", push.route_for(Message.objects.get(user_id=self.teacher.id)))

