"""Messaging channels and SMTP settings - served by the Python backend only
(docs/communication.md).

Against Laravel these skip. Against Django they check the shapes the Flutter
Alert Settings, Send Message and Email Settings screens read, that a secret
saved through the API never comes back through it, and that one school's
admin cannot message another school's student.
"""

from __future__ import annotations

import unittest

import coverage
import shapes
import world

SETTINGS_EXTRAS = {
    "whatsapp_enabled": "bool",
    "whatsapp_provider": "str",
    "whatsapp_provider_label": "str",
    "email_enabled": "bool",
    "email_delivers": "bool",
    "credential_fields": "dict",
    "credentials": "dict",
}

NOTICE_RESULT = {"recipients": "int", "by_channel": "dict", "channels": "list", "audience_label": "str", "queued": "bool"}

MAIL_SETTINGS = {
    "is_saved": "bool",
    "is_active": "bool",
    "host": "str",
    "port": "int",
    "encryption": "str",
    "password_set": "bool",
    "from_address": "str",
    "from_name": "str",
    "source": "str",
}


class Messaging(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/communication/notices/preview", kind="message", audience_type="staff", channels="in_app")
        if probe.status == 404:
            raise unittest.SkipTest("messaging channels are served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert Messaging.WORLD is not None
        return Messaging.WORLD

    def test_the_settings_carry_the_channels_and_never_a_secret(self):
        saved = self.w.admin.put(
            "/communication/settings",
            {
                "sms_enabled": True, "attendance_alerts": "absent", "transport_alerts_enabled": True,
                "leave_alerts_enabled": True, "provider": "log", "whatsapp_enabled": False,
                "whatsapp_provider": "log", "email_enabled": False,
                "credentials": {"twilio": {"account_sid": "ACcontract0001", "auth_token": "contract-secret-token"}},
            },
        )
        self.assertEqual(200, saved.status, f"{saved!r}")
        shapes.assert_shape(self, saved.body, SETTINGS_EXTRAS, "PUT /communication/settings")
        self.assertNotIn("contract-secret-token", repr(saved.body))
        self.assertTrue(saved.body["credentials"]["twilio"]["auth_token"]["set"])

        # Cleared again, so the world is left as it was found.
        cleared = self.w.admin.put(
            "/communication/settings",
            {
                "sms_enabled": True, "attendance_alerts": "absent", "transport_alerts_enabled": True,
                "leave_alerts_enabled": True, "provider": "log",
                "credentials": {"twilio": {"account_sid": "", "auth_token": ""}},
            },
        )
        self.assertFalse(cleared.body["credentials"]["twilio"]["auth_token"]["set"])

    def test_a_whatsapp_template_is_mapped_and_cleared(self):
        mapped = self.w.admin.put(
            "/communication/templates/attendance.absent/whatsapp",
            {"template_name": "contract_absent", "language": "en", "parameters": ["student_name", "date"]},
        )
        self.assertEqual(200, mapped.status, f"{mapped!r}")
        self.assertEqual("contract_absent", mapped.body["whatsapp"]["template_name"])

        cleared = self.w.admin.delete("/communication/templates/attendance.absent/whatsapp")
        self.assertEqual(200, cleared.status, f"{cleared!r}")
        self.assertIsNone(cleared.body["whatsapp"])

    def test_a_notice_is_previewed_then_sent_to_one_person(self):
        preview = self.w.admin.get(
            "/communication/notices/preview", kind="message", audience_type="staff", channels="in_app",
        )
        self.assertEqual(200, preview.status, f"{preview!r}")
        shapes.assert_shape(self, preview.body, NOTICE_RESULT, "GET /communication/notices/preview")

        sent = self.w.admin.post(
            "/communication/notices",
            {
                "kind": "message", "audience_type": "staff_member", "audience_id": self.w.staff_user_id,
                "channels": ["in_app"], "subject": "Contract check", "body": "A message from the contract suite.",
            },
        )
        self.assertEqual(201, sent.status, f"{sent!r}")
        shapes.assert_shape(self, sent.body, NOTICE_RESULT, "POST /communication/notices")
        self.assertEqual(1, len(sent.body["messages"]))
        shapes.assert_shape(self, sent.body["messages"][0], shapes.MESSAGE, "a notice's message")

        # Another school's admin cannot message this school's people.
        refused = self.w.other_admin.post(
            "/communication/notices",
            {
                "kind": "message", "audience_type": "staff_member", "audience_id": self.w.staff_user_id,
                "channels": ["in_app"], "subject": "x", "body": "Should not be allowed.",
            },
        )
        self.assertEqual(422, refused.status, f"{refused!r}")

    def test_a_test_message_through_the_demo_gateway_is_accepted(self):
        sent = self.w.admin.post("/communication/settings/test", {"channel": "sms", "to": "+91 9000000000"})
        self.assertEqual(200, sent.status, f"{sent!r}")

    def test_the_mail_settings_are_super_admin_only_and_hide_the_password(self):
        self.assertEqual(403, self.w.admin.get("/settings/mail").status)

        read = self.w.super_admin.get("/settings/mail")
        self.assertEqual(200, read.status, f"{read!r}")
        shapes.assert_shape(self, read.body, MAIL_SETTINGS, "GET /settings/mail")
        self.assertNotIn("password", read.body)

        # Saving and testing change the platform's real settings, so the
        # contract only checks that the shapes are validated, not that a
        # server is reachable.
        refused = self.w.super_admin.put("/settings/mail", {"host": "", "port": 0, "encryption": "x"})
        self.assertEqual(422, refused.status, f"{refused!r}")

        untested = self.w.super_admin.post("/settings/mail/test", {"to": "not-an-address"})
        self.assertEqual(422, untested.status, f"{untested!r}")
