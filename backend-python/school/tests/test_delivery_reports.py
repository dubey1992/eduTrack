"""Delivery reports (docs/dashboard.md, D2): Twilio's status callback, its
signature, what a report may change, and where the result is shown."""

import datetime as dt
from unittest import mock
from urllib.parse import urlencode

from django.test import override_settings
from rest_framework.test import APIClient

from school import factories, notifications, queue
from school.enums import MessageStatus
from school.gateways import twilio
from school.models import Message

from .test_messaging_api import TWILIO, MessagingTest

CALLBACK = "https://api.school365ai.com/api/v1/webhooks/twilio/status"
HOOK = "/api/v1/webhooks/twilio/status"


@override_settings(PUBLIC_API_URL="https://api.school365ai.com/api/v1")
class DeliveryTest(MessagingTest):
    def setUp(self):
        super().setUp()
        self.platform()

    def sent(self, sid="SM100", channel="sms", **overrides) -> Message:
        values = dict(
            school=self.school, event="attendance.absent", category="attendance", channel=channel,
            recipient_name="Meera Sharma", recipient_mobile="+91 9000000000", status=MessageStatus.SENT,
            provider="twilio", provider_message_id=sid,
        )
        values.update(overrides)

        return factories.MessageFactory(**values)

    def report(self, token=TWILIO["auth_token"], signed_url=CALLBACK, signature=None, **params):
        params = {"MessageSid": "SM100", "AccountSid": TWILIO["account_sid"], **params}
        header = signature if signature is not None else twilio.signature(signed_url, params, token)

        # As Twilio sends it: a form, not JSON.
        return APIClient().post(
            HOOK, urlencode(params), content_type="application/x-www-form-urlencoded", HTTP_X_TWILIO_SIGNATURE=header
        )


class Sending(DeliveryTest):
    def test_every_twilio_message_asks_for_its_delivery_report(self):
        message = factories.MessageFactory(
            school=self.school, event="attendance.absent", category="attendance", channel="sms",
            recipient_name="Meera", recipient_mobile="+91 9000000000", status="queued", provider="twilio",
        )
        queue.push(notifications.SEND_MESSAGE, {"message_id": message.id})

        with mock.patch("school.gateways.twilio.post", return_value={"_status": 201, "sid": "SM9"}) as post:
            queue.work()

        self.assertEqual(CALLBACK, post.call_args.kwargs["form"]["StatusCallback"])

    @override_settings(PUBLIC_API_URL="http://localhost:8000/api/v1")
    def test_not_from_an_address_twilio_cannot_reach(self):
        self.assertIsNone(twilio.status_callback_url())


class TheCallback(DeliveryTest):
    def test_delivered_is_recorded_with_the_time(self):
        message = self.sent()

        response = self.report(MessageStatus="delivered")

        self.assertEqual(204, response.status_code)
        message.refresh_from_db()
        self.assertEqual("delivered", message.delivery_status)
        self.assertIsNotNone(message.delivered_at)
        # What School365ai did with it does not change.
        self.assertEqual(MessageStatus.SENT, message.status)

    def test_whatsapp_read_beats_delivered_and_is_never_taken_back(self):
        message = self.sent(channel="whatsapp")

        self.report(MessageStatus="delivered")
        self.report(MessageStatus="read")
        # Reports can arrive out of order.
        self.report(MessageStatus="delivered")
        self.report(MessageStatus="undelivered", ErrorCode="30003")

        message.refresh_from_db()
        self.assertEqual(("read", None), (message.delivery_status, message.delivery_error))

    def test_undelivered_and_failed_keep_twilios_reason(self):
        for status in ("undelivered", "failed"):
            with self.subTest(status=status):
                message = self.sent(sid=f"SM-{status}")

                self.report(MessageSid=f"SM-{status}", MessageStatus=status, ErrorCode="30006")

                message.refresh_from_db()
                self.assertEqual(("undelivered", "Twilio error 30006"), (message.delivery_status, message.delivery_error))

    def test_statuses_that_say_nothing_about_the_phone_change_nothing(self):
        message = self.sent()

        for status in ("queued", "accepted", "sending", "sent"):
            self.assertEqual(204, self.report(MessageStatus=status).status_code)

        message.refresh_from_db()
        self.assertIsNone(message.delivery_status)

    def test_an_unknown_message_is_answered_the_same_and_changes_nothing(self):
        self.sent()

        response = self.report(MessageSid="SM-not-ours", MessageStatus="delivered")

        self.assertEqual(204, response.status_code)
        self.assertFalse(Message.objects.filter(delivery_status__isnull=False).exists())

    def test_an_email_or_inbox_message_with_the_same_id_is_never_touched(self):
        message = self.sent(channel="email", recipient_email="meera@example.com", provider="smtp")

        self.report(MessageStatus="delivered")

        message.refresh_from_db()
        self.assertIsNone(message.delivery_status)


class TheSignature(DeliveryTest):
    def test_a_forged_or_missing_signature_is_refused_and_changes_nothing(self):
        message = self.sent()

        for response in (
            self.report(token="not-the-token", MessageStatus="delivered"),
            self.report(signature="", MessageStatus="delivered"),
            self.report(signature="bm90IGEgc2lnbmF0dXJl", MessageStatus="delivered"),
            # Signed for another address than the one Twilio was told to call.
            self.report(signed_url="https://evil.example/hook", MessageStatus="delivered"),
        ):
            self.assertEqual((403, "INVALID_SIGNATURE"), (response.status_code, response.data["code"]))

        message.refresh_from_db()
        self.assertIsNone(message.delivery_status)

    def test_a_platform_with_no_twilio_account_accepts_no_reports(self):
        from school.models import PlatformMessaging

        PlatformMessaging.objects.all().delete()
        self.platform(provider="log")
        self.sent()

        self.assertEqual(403, self.report(token="", signature="anything", MessageStatus="delivered").status_code)

    def test_the_signature_is_twilios_published_example(self):
        # Twilio's documented example: this URL, these parameters and the
        # token 12345 sign to this value.
        params = {
            "CallSid": "CA1234567890ABCDE", "Caller": "+12349013030", "Digits": "1234",
            "From": "+12349013030", "To": "+18005551212",
        }

        self.assertEqual(
            "0/KCTR6DLpKmkAf8muzZqo1nDgQ=",
            twilio.signature("https://mycompany.com/myapp.php?foo=1&bar=2", params, "12345"),
        )


class WhereItShows(DeliveryTest):
    def test_the_message_log_says_what_became_of_each_message(self):
        self.sent()
        self.report(MessageStatus="delivered")

        row = self.as_user(self.admin).get("/api/v1/communication/messages").data["data"][0]

        self.assertEqual(("delivered", "Delivered", None), (row["delivery_status"], row["delivery_status_label"],
                                                            row["delivery_error"]))
        self.assertIsNotNone(row["delivered_at"])

    def test_the_dashboard_counts_delivered_and_not_delivered_among_the_sent(self):
        factories.ModuleSettingFactory(school=self.school, module="communication")
        july = dt.datetime.now(dt.UTC)
        for sid, status in (("S1", "delivered"), ("S2", "read"), ("S3", "undelivered"), ("S4", None)):
            message = self.sent(sid=sid, channel="whatsapp" if status == "read" else "sms")
            Message.objects.filter(pk=message.pk).update(delivery_status=status, created_at=july)

        panel = self.as_user(self.admin).get("/api/v1/dashboard").data["messages_this_month"]

        self.assertEqual((4, 2, 1), (panel["total"]["sent"], panel["total"]["delivered"], panel["total"]["undelivered"]))
        self.assertEqual([("sms", 1, 1), ("whatsapp", 1, 0)],
                         [(line["channel"], line["delivered"], line["undelivered"]) for line in panel["channels"]])
        self.assertTrue(panel["delivery_reported"])
