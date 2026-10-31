"""The welcome a new school gets (docs/onboarding.md, slice O3).

A School Admin is always welcomed - their school, the address they sign in
with, the way in, and the first steps - and the school's own address hears
it is set up when it is not the admin's. A password is never in an email.
"""

import re

from django.conf import settings
from django.core import mail
from django.core.cache import cache
from django.test import SimpleTestCase, TestCase
from rest_framework.test import APIClient

from school import factories, queue, tokens, welcome_emails
from school.enums import UserRole


class Wording(SimpleTestCase):
    def build(self, **overrides):
        args = {
            "first_name": "Ada",
            "email": "ada@greenfield.invalid",
            "school_name": "Greenfield Academy",
            "sub_admin": False,
            "set_password_link": "https://example.invalid/app/#/reset-password?token=abc&email=x",
            "year": 2026,
        }
        args.update(overrides)

        return welcome_emails.school_admin(**args)

    def test_it_names_the_school_the_address_and_the_steps_in_order(self):
        subject, text, body = self.build()

        self.assertEqual(f"Welcome to {settings.APP_NAME} - Greenfield Academy is ready", subject)
        self.assertIn("as the School Admin of Greenfield Academy", text)
        self.assertIn("Sign-in email: ada@greenfield.invalid", text)
        steps = [title for title, _ in welcome_emails.FIRST_STEPS]
        positions = [text.index(f"{n}. {title}") for n, title in enumerate(steps, start=1)]
        self.assertEqual(sorted(positions), positions)
        self.assertIn("Quick setup adds Nursery to Class 10", body)

    def test_with_a_link_it_offers_to_set_a_password(self):
        _, text, body = self.build()

        self.assertIn("Set your password: https://example.invalid/app/#/reset-password", text)
        self.assertIn("Forgot password", text)
        self.assertIn("&amp;email=x", body)

    def test_without_a_link_it_offers_to_sign_in(self):
        _, text, _ = self.build(set_password_link=None)

        self.assertNotIn("reset-password", text)
        self.assertIn(f"Sign in: {settings.FRONTEND_URL.rstrip('/')}/#/login", text)

    def test_a_sub_admin_is_told_so(self):
        _, text, _ = self.build(sub_admin=True)

        self.assertIn("as a Sub Admin of Greenfield Academy", text)

    def test_names_are_escaped_in_the_html(self):
        _, _, body = self.build(first_name="<b>Ada</b>", school_name="A & B School")

        self.assertIn("&lt;b&gt;Ada&lt;/b&gt;", body)
        self.assertIn("A &amp; B School", body)
        self.assertNotIn("<b>Ada</b>", body)

    def test_the_school_note_names_the_admin(self):
        subject, text, _ = welcome_emails.school_note(
            school_name="Greenfield Academy", admin_name="Ada Obi", admin_email="ada@x.invalid", year=2026
        )

        self.assertEqual(f"Greenfield Academy is set up on {settings.APP_NAME}", subject)
        self.assertIn("Your School Admin is Ada Obi (ada@x.invalid)", text)


class WelcomeTest(TestCase):
    def setUp(self):
        cache.clear()
        self.root = APIClient()
        self.root.credentials(
            HTTP_AUTHORIZATION="Bearer " + tokens.issue(factories.UserFactory(role=UserRole.SUPER_ADMIN, school=None))
        )

    def add_school(self, **overrides):
        body = {
            "name": "Greenfield Academy",
            "email": "office@greenfield.invalid",
            "phone": "+234 8000000000",
            "address": "1 Test Road",
            "city": "Lagos",
            "state": "Lagos",
            "country": "Nigeria",
            "postal_code": "100001",
            "currency_code": "NGN",
            "timezone": "Africa/Lagos",
            "admin_first_name": "Ada",
            "admin_last_name": "Obi",
            "admin_email": "ada@greenfield.invalid",
        }
        body.update(overrides)
        response = self.root.post("/api/v1/schools", {k: v for k, v in body.items() if v is not None}, format="json")
        queue.work()

        return response

    def to(self, address):
        return [message for message in mail.outbox if message.to == [address]]


class AddingASchool(WelcomeTest):
    def test_the_admin_and_the_school_each_get_their_own_email(self):
        response = self.add_school()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(2, len(mail.outbox))
        (welcome,) = self.to("ada@greenfield.invalid")
        (note,) = self.to("office@greenfield.invalid")
        self.assertIn("Greenfield Academy is ready", welcome.subject)
        self.assertIn("/#/reset-password?token=", welcome.body)
        self.assertIn("Your School Admin is Ada Obi (ada@greenfield.invalid)", note.body)
        self.assertNotIn("reset-password", note.body, "the school's inbox never gets the admin's link")

    def test_the_link_in_the_welcome_sets_a_password_that_signs_in(self):
        self.add_school()
        (welcome,) = self.to("ada@greenfield.invalid")
        token = re.search(r"token=([0-9a-f]+)&", welcome.body).group(1)

        reset = APIClient().post(
            "/api/v1/auth/reset-password",
            {"email": "ada@greenfield.invalid", "token": token, "password": "ChosenByAda2026"},
            format="json",
        )
        self.assertEqual(200, reset.status_code, reset.data)

        login = APIClient().post(
            "/api/v1/auth/login", {"email": "ada@greenfield.invalid", "password": "ChosenByAda2026"}, format="json"
        )
        self.assertEqual(200, login.status_code, login.data)

    def test_one_address_for_both_gets_one_email(self):
        self.add_school(admin_email="office@greenfield.invalid")

        self.assertEqual(1, len(mail.outbox))
        self.assertIn("is ready", mail.outbox[0].subject)

    def test_a_password_typed_for_the_admin_is_never_emailed(self):
        self.add_school(admin_password="TypedByOffice2026")

        for message in mail.outbox:
            self.assertNotIn("TypedByOffice2026", message.body)
            self.assertNotIn("TypedByOffice2026", message.alternatives[0][0])
        (welcome,) = self.to("ada@greenfield.invalid")
        self.assertNotIn("reset-password", welcome.body)

    def test_a_school_without_an_admin_still_hears_it_is_set_up(self):
        self.add_school(admin_first_name=None, admin_last_name=None, admin_email=None)

        (note,) = self.to("office@greenfield.invalid")
        self.assertIn("A School Admin will be added for you", note.body)
        self.assertEqual(1, len(mail.outbox))

    def test_a_refused_school_sends_nothing(self):
        response = self.add_school(currency_code="XXXX")

        self.assertEqual(422, response.status_code)
        self.assertEqual([], mail.outbox)

