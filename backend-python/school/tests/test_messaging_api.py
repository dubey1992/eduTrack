"""SMS, WhatsApp and email as channels, and the settings behind them
(docs/communication.md).

Three things this file guards that a quick read of the code would not:

- **Secrets never come back.** A saved auth token is "set: true" in the API
  and ciphertext in the column, and the audit trail records neither.
- **A channel the school has not switched on is not recorded at all**, the
  same rule Phase 16 set for switched-off alerts; a switched-on channel with
  no address is "skipped", so the missing number can be noticed.
- **WhatsApp carries only mapped templates.** An event without a mapping is
  skipped with that reason, never sent as free text the provider would refuse.
- **Every school sends through School365ai's account** (decided 2026-10-29,
  docs/platform-messaging.md). The provider, its keys and the WhatsApp
  templates are the Super Admin's; a school keeps only its switches.

Providers are exercised at the HTTP boundary (`school.gateways.http.post`
is replaced), so what each adapter *sends* is asserted, not just that it
returned something.
"""

import json
from decimal import Decimal
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import crypto, factories, mailer, notifications, queue, tokens
from school.enums import MessageChannel, MessageStatus, UserRole
from school.gateways import Template
from school.gateways.http import ProviderError
from school.gateways.meta import MetaWhatsAppGateway
from school.gateways.twilio import TwilioSmsGateway, TwilioWhatsAppGateway
from school.models import (
    AuditLog,
    CommunicationSetting,
    MailSetting,
    Message,
    PlatformMessaging,
    PlatformWhatsappTemplate,
    QueuedJob,
)

SETTINGS = "/api/v1/communication/settings"
NOTICES = "/api/v1/communication/notices"
MAIL = "/api/v1/settings/mail"
PLATFORM = "/api/v1/platform/messaging"
TWILIO = {"account_sid": "AC12345678", "auth_token": "very-secret", "sms_from": "+15550001111",
          "whatsapp_from": "+15550002222"}


def section_in(school):
    year = factories.AcademicYearFactory(school=school)
    school_class = factories.SchoolClassFactory(academic_year=year, school=school, name="Grade 8")

    return factories.ClassSectionFactory(school_class=school_class, name="A")


class MessagingTest(TestCase):
    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.school = factories.SchoolFactory(name="Sunrise Public School", timezone="Asia/Kolkata")
        self.section = section_in(self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER, mobile="+91 9111111111", email="teacher@example.com"
        )
        self.student = factories.StudentFactory(
            school=self.school, class_section=self.section, first_name="Aarav", last_name="Sharma",
            guardian_name="Meera Sharma", guardian_mobile="+91 9000000000", guardian_email="meera@example.com",
            student_mobile="+91 9222222222", student_email="aarav@example.com",
        )
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def settings(self, **overrides) -> CommunicationSetting:
        values = dict(notifications.DEFAULTS)
        values.update(overrides)

        return CommunicationSetting.objects.create(school_id=self.school.id, **values)

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def platform(self, provider="twilio", **credentials) -> PlatformMessaging:
        """School365ai's account, as the Super Admin would have saved it."""
        keys = credentials if credentials else TWILIO

        return PlatformMessaging.objects.create(
            provider=provider, credentials=crypto.encrypt_json(keys) if keys and provider != "log" else None,
        )

    def whatsapp_mapping(self, event="attendance.absent", parameters="student_name,date,school_name"):
        return PlatformWhatsappTemplate.objects.create(
            event=event, template_name="attendance_absent", language="en", parameters=parameters,
        )


# -- what gets recorded, per channel ----------------------------------------


class ChannelsWhenRecording(MessagingTest):
    def alert(self):
        return notifications.notify_guardian(
            "attendance.absent", self.student, {"class_name": "Grade 8 A"}
        )

    def test_by_default_only_sms_is_recorded(self):
        self.assertEqual([MessageChannel.SMS], [m.channel for m in self.alert()])

    def test_switching_whatsapp_and_email_on_records_a_copy_on_each(self):
        self.settings(whatsapp_enabled=True, email_enabled=True)
        self.whatsapp_mapping()

        messages = self.alert()

        self.assertEqual(
            [MessageChannel.SMS, MessageChannel.WHATSAPP, MessageChannel.EMAIL], [m.channel for m in messages]
        )
        self.assertEqual({MessageStatus.QUEUED}, {m.status for m in messages})

        email = messages[2]
        self.assertEqual(("meera@example.com", None), (email.recipient_email, email.recipient_mobile))
        self.assertEqual("smtp", email.provider)

    def test_a_whatsapp_copy_carries_the_template_filled_in_at_the_time(self):
        self.settings(whatsapp_enabled=True)
        self.platform()
        self.whatsapp_mapping()

        copy = [m for m in self.alert() if m.channel == MessageChannel.WHATSAPP][0]

        # The platform's carrier, whichever school raised it.
        self.assertEqual("twilio", copy.provider)
        self.assertEqual("attendance_absent", copy.template_parameters["template"])
        self.assertEqual("en", copy.template_parameters["language"])
        values = copy.template_parameters["values"]
        self.assertEqual(("Aarav Sharma", "Sunrise Public School"), (values[0], values[2]))
        self.assertRegex(values[1], r"^\d\d/\d\d/\d{4}$")

    def test_an_event_with_no_whatsapp_template_is_skipped_with_the_reason(self):
        self.settings(whatsapp_enabled=True)

        copy = [m for m in self.alert() if m.channel == MessageChannel.WHATSAPP][0]

        self.assertEqual(MessageStatus.SKIPPED, copy.status)
        self.assertEqual("No WhatsApp template is mapped for this message.", copy.failure_reason)
        # Compared in Python, not in SQL: `payload` is a `json` column and
        # `json` has no equality operator.
        self.assertNotIn({"message_id": copy.id}, [job.payload for job in QueuedJob.objects.all()])

    def test_a_guardian_with_no_email_is_skipped_on_the_email_channel_only(self):
        self.settings(email_enabled=True)
        self.student.guardian_email = None
        self.student.save()

        by_channel = {m.channel: m for m in self.alert()}

        self.assertEqual(MessageStatus.QUEUED, by_channel[MessageChannel.SMS].status)
        self.assertEqual(MessageStatus.SKIPPED, by_channel[MessageChannel.EMAIL].status)
        self.assertEqual("No email address on record.", by_channel[MessageChannel.EMAIL].failure_reason)

    def test_a_student_can_be_told_directly_on_their_own_contacts(self):
        self.settings(email_enabled=True)

        messages = notifications.notify_student("general.message", self.student, {"subject": "Hi", "body": "Hello"})

        self.assertEqual(
            {("sms", "+91 9222222222", None), ("email", None, "aarav@example.com")},
            {(m.channel, m.recipient_mobile, m.recipient_email) for m in messages},
        )
        self.assertEqual({"Aarav Sharma"}, {m.recipient_name for m in messages})
        self.assertFalse(any(m.channel == MessageChannel.IN_APP for m in messages), "a student has no login")

    def test_staff_get_the_inbox_and_every_channel_that_is_on(self):
        self.settings(whatsapp_enabled=True, email_enabled=True)
        self.whatsapp_mapping("leave.approved", "staff_name,leave_type")

        messages = notifications.notify_staff("leave.approved", self.teacher, {"leave_type": "Casual"})

        self.assertEqual(
            [MessageChannel.IN_APP, MessageChannel.SMS, MessageChannel.WHATSAPP, MessageChannel.EMAIL],
            [m.channel for m in messages],
        )
        self.assertEqual(["Rahul", "Casual"][1], messages[2].template_parameters["values"][1])


# -- the worker: each channel to its carrier ---------------------------------


class Delivering(MessagingTest):
    def queued(self, channel: str, **overrides) -> Message:
        values = dict(
            school=self.school, event="attendance.absent", category="attendance", channel=channel,
            recipient_name="Meera Sharma", recipient_mobile="+91 9000000000", status="queued",
            provider="log", sent_at=None,
        )
        values.update(overrides)
        message = factories.MessageFactory(**values)
        queue.push(notifications.SEND_MESSAGE, {"message_id": message.id})

        return message

    def test_an_email_copy_goes_out_through_the_mailer_with_the_event_as_its_subject(self):
        message = self.queued("email", recipient_mobile=None, recipient_email="meera@example.com", provider="smtp")

        queue.work()

        message.refresh_from_db()
        self.assertEqual(MessageStatus.SENT, message.status)
        self.assertEqual(1, len(mail.outbox))
        self.assertEqual(("Marked absent - Sunrise Public School", ["meera@example.com"]), (mail.outbox[0].subject, mail.outbox[0].to))
        self.assertIn(message.body, mail.outbox[0].body)

    def test_a_notice_email_uses_the_subject_it_was_written_with(self):
        self.queued("email", event="general.message", category="general", recipient_mobile=None,
                    recipient_email="meera@example.com", provider="smtp", subject="PTA meeting")

        queue.work()

        self.assertEqual("PTA meeting", mail.outbox[0].subject)

    def test_a_mail_server_refusal_is_a_failed_row_with_the_reason_not_a_dead_worker(self):
        message = self.queued("email", recipient_mobile=None, recipient_email="meera@example.com", provider="smtp")

        with mock.patch("school.mailer.message", side_effect=OSError("Connection refused")):
            result = queue.work()

        self.assertEqual({"done": 1, "failed": 0}, result)
        message.refresh_from_db()
        self.assertEqual((MessageStatus.FAILED, "Connection refused"), (message.status, message.failure_reason))

    def test_a_whatsapp_copy_is_sent_as_its_template_through_the_platform_account(self):
        self.platform()
        message = self.queued(
            "whatsapp", provider="twilio",
            template_parameters={"template": "HX123", "language": "en", "values": ["Aarav", "09/19/2026"]},
        )

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM7"}) as post:
            queue.work()

        message.refresh_from_db()
        self.assertEqual((MessageStatus.SENT, "SM7"), (message.status, message.provider_message_id))
        form = post.call_args.kwargs["form"]
        self.assertEqual(("whatsapp:+919000000000", "whatsapp:+15550002222", "HX123"),
                         (form["To"], form["From"], form["ContentSid"]))
        self.assertEqual({"1": "Aarav", "2": "09/19/2026"}, json.loads(form["ContentVariables"]))

    def test_an_sms_goes_through_the_platform_number_and_account_for_every_school(self):
        self.platform()
        here = self.queued("sms", provider="twilio")
        there = self.queued("sms", provider="twilio", school=self.elsewhere)

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM9"}) as post:
            queue.work()

        here.refresh_from_db()
        there.refresh_from_db()
        self.assertEqual((MessageStatus.SENT, MessageStatus.SENT), (here.status, there.status))
        for call in post.call_args_list:
            self.assertEqual("https://api.twilio.com/2010-04-01/Accounts/AC12345678/Messages.json", call.args[0])
            self.assertEqual(("AC12345678", "very-secret"), call.kwargs["basic"])
            self.assertEqual("+15550001111", call.kwargs["form"]["From"])

    def test_a_school_s_old_keys_are_no_longer_used(self):
        # Saved before 2026-10-29; left in the column, never read again.
        self.settings(provider="twilio", sender_id="SUNRISE",
                      credentials=crypto.encrypt_json({"twilio": {"account_sid": "ACold", "auth_token": "old",
                                                                  "sms_from": "+1999"}}))
        self.platform()
        self.queued("sms", provider="twilio")

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM9"}) as post:
            queue.work()

        self.assertEqual(("AC12345678", "very-secret"), post.call_args.kwargs["basic"])

    def test_a_provider_refusal_is_recorded_in_its_own_words(self):
        self.platform()
        message = self.queued("sms", provider="twilio")

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 400, "message": "The 'To' number is not valid."}):
            queue.work()

        message.refresh_from_db()
        self.assertEqual((MessageStatus.FAILED, "Twilio: The 'To' number is not valid."), (message.status, message.failure_reason))

    def test_a_platform_with_no_account_on_file_gets_a_plain_reason(self):
        self.platform(provider="twilio", sms_from="")
        message = self.queued("sms", provider="twilio")

        with mock.patch("school.gateways.twilio.post") as post:
            queue.work()

        post.assert_not_called()
        message.refresh_from_db()
        self.assertEqual("No Twilio sender number or sender ID is set up.", message.failure_reason)


class TheAdapters(TestCase):
    """What each adapter sends, and how it reads what comes back."""

    def test_twilio_whatsapp_sends_a_content_template_with_numbered_variables(self):
        creds = {"account_sid": "AC1", "auth_token": "t", "whatsapp_from": "+1 555 000 2222"}

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "MM1"}) as post:
            result = TwilioWhatsAppGateway().send_template("+91 90000 00000", Template("HX123", "en", ["A", "B"]), creds)

        self.assertTrue(result.accepted)
        self.assertEqual(
            {"To": "whatsapp:+919000000000", "From": "whatsapp:+15550002222", "ContentSid": "HX123",
             "ContentVariables": json.dumps({"1": "A", "2": "B"})},
            post.call_args.kwargs["form"],
        )

    def test_a_provider_that_cannot_be_reached_is_a_failure_not_an_exception(self):
        creds = {"account_sid": "AC1", "auth_token": "t", "sms_from": "+1"}

        with mock.patch("school.gateways.twilio.post", side_effect=ProviderError("Could not reach the provider: timed out")):
            result = TwilioSmsGateway().send("+1", "hi", None, creds)

        self.assertFalse(result.accepted)
        self.assertEqual("Could not reach the provider: timed out", result.failure_reason)

    def test_meta_reads_its_error_envelope(self):
        creds = {"phone_number_id": "1", "access_token": "t"}

        with mock.patch("school.gateways.meta.post", return_value={"_status": 400, "error": {"message": "Template name does not exist"}}):
            result = MetaWhatsAppGateway().send_template("+1", Template("nope"), creds)

        self.assertEqual("Meta: Template name does not exist", result.failure_reason)

    def test_the_demo_gateways_accept_everything_and_admit_they_deliver_nothing(self):
        from school import sms, whatsapp

        self.assertFalse(whatsapp.gateway("log").delivers)
        self.assertTrue(whatsapp.gateway("log").send_template("+1", Template("x")).accepted)
        self.assertTrue(sms.gateway("twilio").delivers)
        self.assertEqual("log", whatsapp.resolve("a-provider-that-was-removed"))


# -- the settings: channels and credentials ----------------------------------


class SettingsWithChannels(MessagingTest):
    """A school's switches. Who carries the messages is not the school's to
    choose any more, so a provider or keys an older client sends are
    ignored rather than stored."""

    def body(self, **overrides) -> dict:
        data = {
            "sms_enabled": True, "attendance_alerts": "absent", "transport_alerts_enabled": True,
            "leave_alerts_enabled": True, "whatsapp_enabled": True, "email_enabled": True,
        }
        data.update(overrides)

        return data

    def test_saving_stores_the_school_s_switches(self):
        response = self.as_user(self.admin).put(SETTINGS, self.body(), format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((True, True, "absent"), (
            response.data["whatsapp_enabled"], response.data["email_enabled"], response.data["attendance_alerts"],
        ))

    def test_a_provider_or_keys_from_an_older_client_are_ignored(self):
        response = self.as_user(self.admin).put(
            SETTINGS,
            self.body(provider="twilio", sender_id="SUNRISE", whatsapp_provider="meta",
                      credentials={"twilio": {"account_sid": "ACmine", "auth_token": "mine"}}),
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        row = CommunicationSetting.objects.get()
        self.assertEqual(("log", None, None), (row.provider, row.sender_id, row.credentials))
        self.assertNotIn("credentials", response.data)

    def test_the_answer_says_how_messages_go_out_never_with_what_keys(self):
        self.platform()

        data = self.as_user(self.admin).get(SETTINGS).data

        self.assertEqual(("twilio", "Twilio", True), (data["provider"], data["provider_label"], data["provider_delivers"]))
        self.assertEqual(("twilio", True), (data["whatsapp_provider"], data["whatsapp_provider_delivers"]))
        self.assertNotIn("very-secret", json.dumps(data))
        self.assertNotIn("AC12345678", json.dumps(data))

    def test_without_a_platform_account_the_school_is_told_nothing_is_sent(self):
        data = self.as_user(self.admin).get(SETTINGS).data

        self.assertEqual(("log", False), (data["provider"], data["provider_delivers"]))

    def test_the_audit_trail_records_the_switches(self):
        self.as_user(self.admin).put(SETTINGS, self.body(), format="json")

        entry = AuditLog.objects.get(entity_type="communication_setting")
        self.assertEqual(True, entry.new_values["whatsapp_enabled"])

    def test_a_client_that_only_knows_the_sms_switches_still_saves(self):
        old = {"sms_enabled": True, "attendance_alerts": "both", "transport_alerts_enabled": True,
               "leave_alerts_enabled": True, "provider": "log"}

        response = self.as_user(self.admin).put(SETTINGS, old, format="json")

        self.assertEqual(200, response.status_code)
        self.assertEqual((False, False), (response.data["whatsapp_enabled"], response.data["email_enabled"]))

    def test_bad_switches_are_named(self):
        response = self.as_user(self.admin).put(SETTINGS, self.body(whatsapp_enabled="maybe"), format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("whatsapp_enabled", self.errors(response))

    def test_a_stranger_cannot_read_or_change_them(self):
        self.assertEqual(403, self.as_user(self.stranger).get(f"{SETTINGS}?school_id={self.school.id}").status_code)
        self.assertEqual(403, self.as_user(self.teacher).put(SETTINGS, self.body(), format="json").status_code)


class TestingAGateway(MessagingTest):
    """A school's own test: its switches, School365ai's account."""

    URL = SETTINGS + "/test"

    def test_a_test_sms_goes_through_the_platform_account_now(self):
        self.platform()

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM1"}) as post:
            response = self.as_user(self.admin).post(self.URL, {"channel": "sms", "to": "+91 9000000000"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIn("Sunrise Public School", post.call_args.kwargs["form"]["Body"])
        self.assertEqual(("AC12345678", "very-secret"), post.call_args.kwargs["basic"])
        self.assertFalse(Message.objects.exists(), "a test is not part of the school's log")

    def test_a_refused_test_says_why(self):
        self.platform(provider="twilio", sms_from="")

        response = self.as_user(self.admin).post(self.URL, {"channel": "sms", "to": "+91 9000000000"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual("GATEWAY_TEST_FAILED", response.data["code"])
        self.assertEqual("No Twilio sender number or sender ID is set up.", response.data["message"])

    def test_a_whatsapp_test_says_school365ai_has_no_template_yet(self):
        self.platform()

        response = self.as_user(self.admin).post(self.URL, {"channel": "whatsapp", "to": "+91 9000000000"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("School365ai has no template for this message", response.data["message"])

    def test_the_number_and_channel_are_checked_and_strangers_refused(self):
        response = self.as_user(self.admin).post(self.URL, {"channel": "email", "to": "12"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            {"channel": ["A test message goes by SMS or WhatsApp."], "to": ["The to field format is invalid."]},
            self.errors(response),
        )
        self.assertEqual(
            403, self.as_user(self.stranger).post(f"{self.URL}?school_id={self.school.id}", {}, format="json").status_code
        )

    def test_ten_tests_an_hour_and_no_more(self):
        # Each test goes to a typed-in number on School365ai's paid account;
        # a compromised admin login must not be a free SMS cannon.
        self.platform()
        cache.clear()

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM1"}) as post:
            answers = [
                self.as_user(self.admin).post(self.URL, {"channel": "sms", "to": "+91 9000000000"}, format="json").status_code
                for _ in range(11)
            ]

        self.assertEqual([200] * 10 + [429], answers)
        self.assertEqual(10, post.call_count, "the eleventh never reached the provider")


# -- School365ai's account (docs/platform-messaging.md, M1) -------------------


class PlatformAccount(MessagingTest):
    def save(self, user=None, **overrides):
        body = {"provider": "twilio", "credentials": dict(TWILIO)}
        body.update(overrides)

        return self.as_user(user or self.root).put(PLATFORM, body, format="json")

    def test_the_super_admin_saves_it_encrypted(self):
        response = self.save()

        self.assertEqual(200, response.status_code, response.data)
        row = PlatformMessaging.objects.get()
        self.assertTrue(row.credentials.startswith("enc:"))
        self.assertNotIn("very-secret", row.credentials)
        self.assertEqual("very-secret", crypto.decrypt_json(row.credentials)["auth_token"])

    def test_the_answer_says_what_is_set_and_never_what_it_is(self):
        data = self.save().data

        fields = {field["key"]: field for field in data["fields"]}
        self.assertEqual((True, None), (fields["auth_token"]["set"], fields["auth_token"]["hint"]))
        self.assertEqual((True, "\u20265678"), (fields["account_sid"]["set"], fields["account_sid"]["hint"]))
        self.assertEqual("twilio", data["provider"])
        self.assertNotIn("very-secret", json.dumps(data))

    def test_a_key_left_out_is_kept_and_a_blank_one_is_cleared(self):
        self.save()

        self.save(credentials={"sms_from": "+15559999999", "whatsapp_from": ""})

        stored = crypto.decrypt_json(PlatformMessaging.objects.get().credentials)
        self.assertEqual(("very-secret", "+15559999999"), (stored["auth_token"], stored["sms_from"]))
        self.assertNotIn("whatsapp_from", stored)

    def test_the_audit_trail_never_holds_the_keys(self):
        self.save()

        entry = AuditLog.objects.get(entity_type="platform_messaging")
        self.assertNotIn("credentials", entry.new_values)
        self.assertNotIn("very-secret", json.dumps(entry.new_values))

    def test_a_bad_provider_or_key_is_named(self):
        response = self.save(provider="msg91", credentials={"nope": "x", "auth_token": 5})

        self.assertEqual(422, response.status_code)
        self.assertEqual(["Choose Twilio, or the Demo Gateway that sends nothing."], self.errors(response)["provider"])
        self.assertEqual(['"nope" is not a Twilio setting.', "The auth_token must be text."],
                         self.errors(response)["credentials"])

    def test_only_the_super_admin_reads_or_changes_it(self):
        self.assertEqual(403, self.as_user(self.admin).get(PLATFORM).status_code)
        self.assertEqual(403, self.save(user=self.admin).status_code)
        self.assertEqual(401, APIClient().get(PLATFORM).status_code)
        self.assertFalse(PlatformMessaging.objects.exists())

    def test_a_test_goes_through_it_and_the_outcome_is_kept(self):
        self.save()

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM1"}):
            ok = self.as_user(self.root).post(f"{PLATFORM}/test", {"channel": "sms", "to": "+91 9000000000"},
                                              format="json")
        with mock.patch("school.gateways.twilio.post", return_value={"_status": 401, "message": "Authenticate"}):
            refused = self.as_user(self.root).post(f"{PLATFORM}/test", {"channel": "sms", "to": "+91 9000000000"},
                                                   format="json")

        self.assertEqual(200, ok.status_code, ok.data)
        self.assertEqual((422, "Twilio: Authenticate"), (refused.status_code, refused.data["message"]))
        self.assertEqual("Twilio: Authenticate", PlatformMessaging.objects.get().last_test_error)
        self.assertEqual(403, self.as_user(self.admin).post(f"{PLATFORM}/test", {"channel": "sms", "to": "+91 9000000000"},
                                                            format="json").status_code)

    def test_a_whatsapp_test_needs_the_message_event_mapped(self):
        self.save()

        response = self.as_user(self.root).post(f"{PLATFORM}/test", {"channel": "whatsapp", "to": "+91 9000000000"},
                                                format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("Map a WhatsApp template", response.data["message"])


class WhatsappTemplates(MessagingTest):
    """School365ai's approved templates, mapped once for every school."""

    def url(self, event="attendance.absent") -> str:
        return f"/api/v1/platform/whatsapp-templates/{event}"

    def test_the_super_admin_maps_an_event_for_every_school(self):
        response = self.as_user(self.root).put(
            self.url(), {"template_name": "HXabsent", "language": "en_US", "parameters": ["student_name", "date"]},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        row = next(t for t in response.data["whatsapp_templates"] if t["event"] == "attendance.absent")
        self.assertEqual({"template_name": "HXabsent", "language": "en_US", "parameters": ["student_name", "date"]},
                         {k: row["template"][k] for k in ("template_name", "language", "parameters")})

        # And each school's templates listing shows it.
        listed = self.as_user(self.admin).get("/api/v1/communication/templates").data
        self.assertEqual("HXabsent", next(r for r in listed if r["event"] == "attendance.absent")["whatsapp"]["template_name"])
        self.assertTrue(AuditLog.objects.filter(action="platform_whatsapp_template.created").exists())

    def test_a_parameter_the_event_does_not_have_is_refused_by_name(self):
        response = self.as_user(self.root).put(
            self.url(), {"template_name": "x", "parameters": ["student_name", "amount", "amount"]}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("Remove {amount}.", self.errors(response)["parameters"][0])

    def test_clearing_the_mapping_drops_the_row(self):
        self.whatsapp_mapping()

        response = self.as_user(self.root).delete(self.url())

        self.assertEqual(200, response.status_code)
        self.assertFalse(PlatformWhatsappTemplate.objects.exists())

    def test_an_unknown_event_is_a_404_and_schools_are_refused(self):
        self.assertEqual(404, self.as_user(self.root).put(self.url("bogus.event"), {}, format="json").status_code)
        self.assertEqual(403, self.as_user(self.admin).put(self.url(), {"template_name": "x"}, format="json").status_code)
        # The old per-school address is gone.
        self.assertEqual(
            404,
            self.as_user(self.admin).put("/api/v1/communication/templates/attendance.absent/whatsapp",
                                         {"template_name": "x"}, format="json").status_code,
        )


# -- notices: messages written by hand ---------------------------------------


class Notices(MessagingTest):
    def setUp(self):
        super().setUp()
        self.staff = factories.UserFactory(school=self.school, role=UserRole.STAFF, mobile=None, email="clerk@example.com")
        self.other_student = factories.StudentFactory(
            school=self.school, class_section=self.section, first_name="Sara", last_name="Ali",
            guardian_name="Imran Ali", guardian_mobile=None, guardian_email=None,
        )
        factories.StudentFactory(school=self.elsewhere, class_section=section_in(self.elsewhere), guardian_mobile="+1 5550000000")

    def notice(self, **overrides) -> dict:
        data = {
            "kind": "message", "audience_type": "student", "audience_id": self.student.id,
            "channels": ["sms"], "subject": "PTA meeting", "body": "The PTA meets on Friday at 3 PM.",
        }
        data.update(overrides)

        return data

    def test_a_message_to_one_guardian_is_recorded_now_and_queued_to_send(self):
        response = self.as_user(self.admin).post(NOTICES, self.notice(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual((1, False, "Aarav Sharma"), (
            response.data["recipients"], response.data["queued"], response.data["audience_label"],
        ))
        self.assertEqual(1, len(response.data["messages"]))

        message = Message.objects.get()
        self.assertEqual(("general.message", "general", "sms", "Meera Sharma", "PTA meeting"), (
            message.event, message.category, message.channel, message.recipient_name, message.subject,
        ))
        self.assertEqual("Sunrise Public School: PTA meeting - The PTA meets on Friday at 3 PM.", message.body)
        self.assertEqual(self.admin.id, message.created_by_id)
        self.assertTrue(QueuedJob.objects.filter(name="send_message").exists())

    def test_the_sending_is_in_the_audit_trail_with_who_it_went_to(self):
        self.as_user(self.admin).post(NOTICES, self.notice(), format="json")

        entry = AuditLog.objects.get(action="notice.sent")
        self.assertEqual((self.admin.id, self.school.id, "communication", "notice"), (
            entry.user_id, entry.school_id, entry.module, entry.entity_type,
        ))
        self.assertEqual(("student", 1, "PTA meeting"), (
            entry.new_values["audience_type"], entry.new_values["recipients_count"], entry.new_values["subject"],
        ))

    def test_a_group_is_handed_to_the_queue_and_fanned_out_by_the_worker(self):
        self.settings(email_enabled=True)

        response = self.as_user(self.admin).post(
            NOTICES, self.notice(audience_type="everyone", channels=["sms", "email", "in_app"]), format="json"
        )

        self.assertEqual(202, response.status_code, response.data)
        self.assertTrue(response.data["queued"])
        # Guardians: Meera (mobile + email), Imran (nothing) - so 1. Staff:
        # admin, teacher, clerk - 3, all with an inbox.
        self.assertEqual(4, response.data["recipients"])
        # SMS: Meera and the teacher, the only staff member with a number.
        self.assertEqual({"sms": 2, "email": 4, "in_app": 3, "whatsapp": 0}, response.data["by_channel"])
        self.assertFalse(Message.objects.exists(), "nothing recorded yet")

        queue.work()

        # Imran has no address but the school wanted to reach him: skipped.
        self.assertEqual(2, Message.objects.filter(status="skipped", recipient_name="Imran Ali").count())
        self.assertEqual(3, Message.objects.filter(channel="in_app").count())
        self.assertFalse(Message.objects.filter(school=self.elsewhere).exists())

    def test_an_emergency_reaches_everyone_and_says_so(self):
        response = self.as_user(self.admin).post(
            NOTICES, self.notice(kind="emergency", audience_type="everyone", channels=["sms", "in_app"], subject=None,
                                 body="School closes at noon today because of the storm."),
            format="json",
        )
        queue.work()

        self.assertEqual(202, response.status_code, response.data)
        copy = Message.objects.filter(recipient_name="Meera Sharma").get()
        self.assertEqual(("emergency.alert", "emergency", "Emergency alert"), (copy.event, copy.category, copy.subject))
        self.assertEqual("EMERGENCY - Sunrise Public School: School closes at noon today because of the storm.", copy.body)

    def test_a_fee_reminder_names_the_amount_in_the_schools_currency_and_the_due_date(self):
        response = self.as_user(self.admin).post(
            NOTICES, self.notice(kind="fee_reminder", subject=None, body=None, amount="4500", due_date="2026-10-15"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        message = Message.objects.get()
        self.assertEqual(("fee.reminder", "fee", "Fee reminder"), (message.event, message.category, message.subject))
        self.assertEqual(
            f"Dear Meera Sharma, a fee of {self.school.currency_code} 4,500.00 for Aarav Sharma is due on 10/15/2026. "
            "Please pay at the school office. - Sunrise Public School",
            message.body,
        )

    def test_students_can_be_the_recipients_instead_of_or_as_well_as_their_guardians(self):
        response = self.as_user(self.admin).post(
            NOTICES, self.notice(audience_type="class_section", audience_id=self.section.id, recipients="both"),
            format="json",
        )
        queue.work()

        self.assertEqual(202, response.status_code, response.data)
        self.assertEqual(
            {"Meera Sharma", "Aarav Sharma", "Imran Ali", "Sara Ali"},
            set(Message.objects.values_list("recipient_name", flat=True)),
        )

    def test_the_preview_counts_without_writing_anything(self):
        self.settings(whatsapp_enabled=True)
        self.whatsapp_mapping("general.message", "subject,body")

        response = self.as_user(self.admin).get(
            NOTICES + "/preview",
            {"kind": "message", "audience_type": "teachers", "channels": "sms,whatsapp,in_app"},
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((1, "All teachers"), (response.data["recipients"], response.data["audience_label"]))
        self.assertEqual({"sms": 1, "whatsapp": 1, "in_app": 1, "email": 0}, response.data["by_channel"])
        self.assertFalse(Message.objects.exists())
        self.assertFalse(AuditLog.objects.filter(action="notice.sent").exists())

    def test_a_channel_the_school_has_off_is_refused_by_name(self):
        response = self.as_user(self.admin).post(NOTICES, self.notice(channels=["sms", "whatsapp", "email"]), format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual(["WhatsApp and Email is switched off for this school."], self.errors(response)["channels"])

    def test_every_missing_piece_is_named_at_once(self):
        response = self.as_user(self.admin).post(
            NOTICES, {"kind": "fee_reminder", "audience_type": "class_section", "channels": ["fax"]}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            {
                "audience_id": ["Pick who this message is for."],
                "channels": ['"fax" is not a channel.'],
                "amount": ["The amount field is required."],
                "due_date": ["The due date field is required."],
            },
            self.errors(response),
        )

    def test_a_message_needs_a_subject_and_ten_characters_of_body(self):
        response = self.as_user(self.admin).post(NOTICES, self.notice(subject="", body="short"), format="json")

        self.assertEqual(
            {"body": ["The body field must be at least 10 characters."], "subject": ["The subject field is required."]},
            self.errors(response),
        )

    def test_nobody_reachable_is_refused_rather_than_sent_to_nobody(self):
        response = self.as_user(self.admin).post(
            NOTICES, self.notice(audience_type="student", audience_id=self.other_student.id), format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual("UNREACHABLE_AUDIENCE", response.data["code"])
        self.assertFalse(Message.objects.exists())

    def test_another_schools_student_is_not_this_schools_to_message(self):
        foreign = factories.StudentFactory(school=self.elsewhere, class_section=section_in(self.elsewhere))

        response = self.as_user(self.admin).post(NOTICES, self.notice(audience_id=foreign.id), format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["That person, class or department does not belong to this school."], self.errors(response)["audience_id"]
        )

    def test_the_school_comes_from_the_actor_not_the_request(self):
        response = self.as_user(self.admin).post(
            NOTICES, self.notice(school_id=self.elsewhere.id, audience_type="parents", audience_id=None), format="json"
        )
        queue.work()

        self.assertEqual(202, response.status_code, response.data)
        self.assertEqual({self.school.id}, set(Message.objects.values_list("school_id", flat=True)))

    def test_a_super_admin_names_the_school_and_teachers_may_not_send(self):
        response = self.as_user(self.root).post(
            NOTICES, self.notice(school_id=self.school.id), format="json"
        )
        self.assertEqual(201, response.status_code, response.data)

        self.assertEqual(403, self.as_user(self.teacher).post(NOTICES, self.notice(), format="json").status_code)
        self.assertEqual(403, self.as_user(self.teacher).get(NOTICES + "/preview", {"kind": "message", "audience_type": "parents", "channels": "sms"}).status_code)


# -- the platform's SMTP server ----------------------------------------------


class MailSettings(MessagingTest):
    def body(self, **overrides) -> dict:
        data = {
            "host": "smtp.example.com", "port": 587, "encryption": "tls", "username": "mailer@example.com",
            "password": "mail-secret", "from_address": "noreply@example.com", "from_name": "Sunrise",
        }
        data.update(overrides)

        return data

    def test_without_a_row_the_environment_is_shown_as_the_source(self):
        response = self.as_user(self.root).get(MAIL)

        self.assertEqual(200, response.status_code)
        self.assertEqual(("environment", False, False), (
            response.data["source"], response.data["is_saved"], response.data["password_set"],
        ))

    def test_saving_encrypts_the_password_and_never_returns_it(self):
        response = self.as_user(self.root).put(MAIL, self.body(), format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("database", True, True, "smtp.example.com"), (
            response.data["source"], response.data["is_saved"], response.data["password_set"], response.data["host"],
        ))
        self.assertNotIn("mail-secret", json.dumps(response.data))

        row = MailSetting.objects.get()
        self.assertTrue(row.password.startswith("enc:"))
        self.assertEqual("mail-secret", crypto.decrypt(row.password))
        self.assertNotIn("password", AuditLog.objects.get(action="mail_setting.created").new_values)

    def test_leaving_the_password_out_keeps_it_and_blank_clears_it(self):
        client = self.as_user(self.root)
        client.put(MAIL, self.body(), format="json")

        kept = self.body(port=465, encryption="ssl")
        del kept["password"]
        client.put(MAIL, kept, format="json")
        self.assertEqual("mail-secret", crypto.decrypt(MailSetting.objects.get().password))

        client.put(MAIL, self.body(password=""), format="json")
        self.assertIsNone(MailSetting.objects.get().password)

    def test_the_mailer_uses_the_saved_server_and_falls_back_when_it_is_off(self):
        self.as_user(self.root).put(MAIL, self.body(), format="json")

        connection = mailer.connection()
        self.assertEqual(("smtp.example.com", 587, "mailer@example.com", "mail-secret", True, False), (
            connection.host, connection.port, connection.username, connection.password, connection.use_tls, connection.use_ssl,
        ))
        self.assertEqual("Sunrise <noreply@example.com>", mailer.sender())

        self.as_user(self.root).put(MAIL, self.body(is_active=False), format="json")
        self.assertEqual("locmem", type(mailer.connection()).__module__.rsplit(".", 1)[-1])

    def test_a_test_email_goes_through_the_saved_settings_and_notes_the_outcome(self):
        self.as_user(self.root).put(MAIL, self.body(), format="json")

        with mock.patch("school.mailer.connection", return_value=mail.get_connection()):
            response = self.as_user(self.root).post(MAIL + "/test", {"to": "me@example.com"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(["me@example.com"], mail.outbox[0].to)
        self.assertIsNotNone(response.data["settings"]["last_tested_at"])
        self.assertIsNone(response.data["settings"]["last_test_error"])
        self.assertTrue(AuditLog.objects.filter(action="mail_setting.tested").exists())

    def test_a_failed_test_reports_the_servers_words_and_keeps_them_on_the_row(self):
        self.as_user(self.root).put(MAIL, self.body(), format="json")

        with mock.patch("school.mailer.connection", side_effect=OSError("[Errno 111] Connection refused")):
            response = self.as_user(self.root).post(MAIL + "/test", {"to": "me@example.com"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual("MAIL_TEST_FAILED", response.data["code"])
        self.assertIn("Connection refused", response.data["message"])
        self.assertEqual("[Errno 111] Connection refused", MailSetting.objects.get().last_test_error)

    def test_bad_settings_are_named(self):
        response = self.as_user(self.root).put(
            MAIL, self.body(port=70000, encryption="starttls", from_address="not-an-address"), format="json"
        )

        self.assertEqual(
            {
                "port": ["The port must be between 1 and 65535."],
                "encryption": ["Encryption is none, tls or ssl."],
                "from_address": ["The from address field must be a valid email address."],
            },
            self.errors(response),
        )

    def test_only_a_super_admin_reads_or_changes_them(self):
        for user in (self.admin, self.teacher):
            self.assertEqual(403, self.as_user(user).get(MAIL).status_code)
            self.assertEqual(403, self.as_user(user).put(MAIL, self.body(), format="json").status_code)
            self.assertEqual(403, self.as_user(user).post(MAIL + "/test", {"to": "x@example.com"}, format="json").status_code)


# -- students: the new contact columns ---------------------------------------


class StudentContacts(MessagingTest):
    def test_the_contact_fields_are_saved_returned_and_checked(self):
        client = self.as_user(self.admin)
        response = client.post("/api/v1/students", {
            "school_id": self.school.id, "class_section_id": self.section.id, "admission_number": "ADM-9",
            "first_name": "Zara", "last_name": "Khan", "guardian_name": "Nadia Khan",
            "guardian_email": "Nadia@Example.com", "student_mobile": "+91 9333333333", "student_email": "",
        }, format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("nadia@example.com", "+91 9333333333", None), (
            response.data["guardian_email"], response.data["student_mobile"], response.data["student_email"],
        ))

        bad = client.patch(f"/api/v1/students/{response.data['id']}", {
            "guardian_email": "nope", "student_mobile": "12", "student_email": "also nope",
        }, format="json")
        self.assertEqual(
            {
                "guardian_email": ["The guardian email field must be a valid email address."],
                "student_mobile": ["The student mobile field format is invalid."],
                "student_email": ["The student email field must be a valid email address."],
            },
            self.errors(bad),
        )


class Encryption(TestCase):
    def test_a_value_round_trips_and_is_not_readable_in_the_column(self):
        stored = crypto.encrypt("hunter2")

        self.assertTrue(stored.startswith("enc:"))
        self.assertNotIn("hunter2", stored)
        self.assertEqual("hunter2", crypto.decrypt(stored))

    def test_a_value_written_under_another_key_reads_as_not_set_up(self):
        self.assertEqual({}, crypto.decrypt_json("enc:gAAAAABnot-a-real-token"))
        with self.assertRaises(crypto.CannotDecrypt):
            crypto.decrypt("enc:gAAAAABnot-a-real-token")

    def test_plain_text_from_before_encryption_still_reads(self):
        self.assertEqual({"a": 1}, crypto.decrypt_json('{"a": 1}'))
