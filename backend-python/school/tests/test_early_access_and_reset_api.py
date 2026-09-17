"""Early access and password resets, over HTTP - the endpoints a stranger can
reach without an account.

**Early access** is how a school with no account asks for one. It answers the
same way whether the school is new or correcting a request already open, and
it tells a stranger nothing about anyone else. The queue is the Super Admin's
alone; *converted* is set by onboarding a school, never by hand.

**A password reset link** is sent without saying whether the address has an
account, lasts an hour, works once, and signs the account out everywhere. The
token is stored only as a bcrypt hash in Laravel's own table, so a link either
backend sends is one either backend honours.
"""

import datetime as dt
import re
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, hashing, queue, tokens
from school.enums import UserRole
from school.models import EarlyAccessRequest, PasswordResetToken, PersonalAccessToken

SIGNUP = {
    "school_name": "Greenfield Academy",
    "contact_name": "Nneka Okafor",
    "contact_role": "Head",
    "email": "head@greenfield.invalid",
    "phone": "+234 8000000000",
    "city": "Lagos",
    "country": "Nigeria",
    "expected_students": 800,
}


class PublicTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


class SignupTest(PublicTestCase):
    def sign_up(self, **overrides):
        body = dict(SIGNUP)
        body.update(overrides)

        return APIClient().post("/api/v1/early-access", body, format="json")

    def test_a_school_asks_for_access_without_an_account(self):
        response = self.sign_up()

        self.assertEqual(201, response.status_code)
        self.assertEqual({"message": "Thanks - we have your details and will be in touch soon."}, response.data)
        self.assertEqual("new", EarlyAccessRequest.objects.get().status)

    def test_the_form_says_what_it_needs(self):
        response = APIClient().post("/api/v1/early-access", {}, format="json")

        self.assertEqual(["school_name", "contact_name", "email", "phone", "city", "country"], list(self.errors(response)))

    def test_a_phone_without_a_country_code_and_an_absurd_size_are_refused(self):
        response = self.sign_up(phone="9876543210", email="nope", expected_students=200001)

        self.assertEqual(
            {
                "email": ["The email field must be a valid email address."],
                "phone": ["Include the country code, like +91 9876543210."],
                "expected_students": ["That is more students than any school we know of - please get in touch directly."],
            },
            self.errors(response),
        )
        self.assertEqual(["The expected students field must be at least 1."], self.errors(self.sign_up(expected_students=0))["expected_students"])

    def test_the_size_is_optional(self):
        self.assertEqual(201, self.sign_up(expected_students=None).status_code)

    def test_asking_again_updates_the_open_request_and_keeps_its_place(self):
        self.sign_up()
        request = EarlyAccessRequest.objects.get()
        EarlyAccessRequest.objects.filter(pk=request.pk).update(status="contacted")

        self.sign_up(contact_name="Nneka O.", city="Abuja")

        request.refresh_from_db()
        self.assertEqual(1, EarlyAccessRequest.objects.count())
        self.assertEqual(("Nneka O.", "Abuja", "contacted"), (request.contact_name, request.city, request.status))

    def test_a_school_turned_down_before_can_ask_again(self):
        self.sign_up()
        EarlyAccessRequest.objects.update(status="declined")

        self.sign_up()

        self.assertEqual(["declined", "new"], list(EarlyAccessRequest.objects.order_by("id").values_list("status", flat=True)))

    def test_the_form_is_throttled_by_address(self):
        statuses = [self.sign_up(email=f"head{n}@greenfield.invalid").status_code for n in range(6)]

        self.assertEqual([201] * 5 + [429], statuses)

    def test_the_form_tells_a_stranger_nothing_about_anyone_else(self):
        self.sign_up()

        again = self.sign_up(contact_name="Somebody else")

        self.assertEqual({"message": "Thanks - we have your details and will be in touch soon."}, again.data)


class PanelTest(PublicTestCase):
    def request(self, **fields):
        values = dict(SIGNUP, status="new", created_at=dt.datetime(2026, 9, 16, 6, 50, tzinfo=dt.timezone.utc))
        values.update(fields)

        return EarlyAccessRequest.objects.create(**values)

    def test_a_super_admin_sees_the_requests_newest_first(self):
        older = self.request(school_name="Older")
        newer = self.request(school_name="Newer", email="n@x.invalid")

        rows = self.as_user(self.root).get("/api/v1/early-access").data["data"]

        self.assertEqual([newer.id, older.id], [row["id"] for row in rows])

    def test_the_list_filters_by_status_and_searches_case_insensitively(self):
        self.request(school_name="Greenfield Academy")
        self.request(school_name="Sunrise School", email="s@x.invalid", status="declined")
        client = self.as_user(self.root)

        self.assertEqual(["Sunrise School"], [r["school_name"] for r in client.get("/api/v1/early-access?status=declined").data["data"]])
        self.assertEqual(["Greenfield Academy"], [r["school_name"] for r in client.get("/api/v1/early-access?q=GREENFIELD").data["data"]])

    def test_a_request_shows_everything_and_its_times_on_the_platform_clock(self):
        request = self.request()

        data = self.as_user(self.root).get(f"/api/v1/early-access/{request.id}").data

        self.assertEqual(("Head", 800, "New", "09/16/2026 6:50 AM", None, None),
                         (data["contact_role"], data["expected_students"], data["status_label"], data["submitted_at"],
                          data["reviewed_at"], data["converted_school_name"]))

    def test_a_super_admin_moves_a_request_along_with_a_note(self):
        request = self.request()

        response = self.as_user(self.root).patch(
            f"/api/v1/early-access/{request.id}", {"status": "contacted", "notes": "Called on Tuesday"}, format="json"
        )

        self.assertEqual(("contacted", "Called on Tuesday", self.root.name), (response.data["status"], response.data["notes"], response.data["reviewed_by_name"]))
        self.assertIsNotNone(response.data["reviewed_at"])

    def test_converted_is_not_claimed_by_hand_and_a_blank_status_is_required(self):
        request = self.request()
        client = self.as_user(self.root)

        converted = client.patch(f"/api/v1/early-access/{request.id}", {"status": "converted"}, format="json")
        blank = client.patch(f"/api/v1/early-access/{request.id}", {"status": ""}, format="json")

        self.assertEqual(["A request becomes Converted by onboarding the school, not by saying so."], self.errors(converted)["status"])
        self.assertEqual(["The status field is required."], self.errors(blank)["status"])

    def test_onboarding_from_a_request_marks_it_converted_and_names_the_school(self):
        request = self.request()

        created = self.as_user(self.root).post(
            "/api/v1/schools",
            {"name": "Greenfield Academy", "email": "office@greenfield.invalid", "phone": "+234 8000000001",
             "address": "1 Road", "city": "Lagos", "state": "Lagos", "postal_code": "100001", "country": "Nigeria", "currency_code": "NGN",
             "timezone": "Africa/Lagos", "early_access_request_id": request.id},
            format="json",
        )
        data = self.as_user(self.root).get(f"/api/v1/early-access/{request.id}").data

        self.assertEqual(201, created.status_code, created.data)
        self.assertEqual(("converted", "Greenfield Academy"), (data["status"], data["converted_school_name"]))

    def test_nobody_but_a_super_admin_reads_the_panel(self):
        request = self.request()
        school = factories.SchoolFactory()

        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN):
            client = self.as_user(factories.UserFactory(school=school, role=role))
            self.assertEqual(403, client.get("/api/v1/early-access").status_code, role)
            self.assertEqual(403, client.get(f"/api/v1/early-access/{request.id}").status_code, role)
            self.assertEqual(403, client.patch(f"/api/v1/early-access/{request.id}", {"status": "x"}, format="json").status_code, role)

        self.assertEqual(401, APIClient().get("/api/v1/early-access").status_code)


@override_settings(FRONTEND_URL="https://app.school365.invalid/")
class PasswordResetTest(PublicTestCase):
    def setUp(self):
        super().setUp()
        self.user = factories.UserFactory(email="priya.sharma@example.com", password=hashing.make("old-password"))

    def forgot(self, email=None):
        response = APIClient().post("/api/v1/auth/forgot-password", {"email": email or self.user.email}, format="json")
        queue.work()

        return response

    def token_from_mail(self) -> str:
        return re.search(r"token=([0-9a-f]+)&", mail.outbox[-1].body).group(1)

    def reset(self, token, password="brand-new-password", email=None):
        return APIClient().post(
            "/api/v1/auth/reset-password",
            {"email": email or self.user.email, "token": token, "password": password},
            format="json",
        )

    def test_the_answer_is_the_same_for_a_known_and_an_unknown_address(self):
        known = self.forgot()
        unknown = self.forgot("nobody@example.invalid")

        message = {"message": "If an account exists for that email, a password reset link has been sent."}
        self.assertEqual((200, message), (known.status_code, known.data))
        self.assertEqual((200, message), (unknown.status_code, unknown.data))
        self.assertEqual(1, len(mail.outbox))

    def test_the_email_is_branded_and_links_to_the_frontend(self):
        self.forgot()
        email = mail.outbox[0]
        html = email.alternatives[0][0]

        self.assertEqual(("Reset your password", ["priya.sharma@example.com"]), (email.subject, email.to))
        self.assertIn("https://app.school365.invalid/reset-password?token=", email.body)
        self.assertIn("&email=priya.sharma@example.com", email.body)
        self.assertIn("This password reset link will expire in 60 minutes.", email.body)
        for fragment in ("School365ai", "Smarter Schools. Brighter Futures.", "#2563eb", "&amp;email=priya.sharma@example.com"):
            self.assertIn(fragment, html)

    def test_only_a_hash_of_the_token_is_stored(self):
        self.forgot()
        token = self.token_from_mail()
        row = PasswordResetToken.objects.get(email=self.user.email)

        self.assertNotIn(token, row.token)
        self.assertTrue(hashing.check(token, row.token))

    def test_a_valid_token_resets_the_password_once_and_signs_out_everywhere(self):
        self.user.must_change_password = True
        self.user.save()
        tokens.issue(self.user)
        self.forgot()
        token = self.token_from_mail()

        first = self.reset(token)
        second = self.reset(token, password="another-new-one")

        self.assertEqual({"message": "Password reset successfully."}, first.data)
        self.assertEqual(422, second.status_code)
        self.user.refresh_from_db()
        self.assertTrue(hashing.check("brand-new-password", self.user.password))
        self.assertFalse(self.user.must_change_password)
        self.assertFalse(PersonalAccessToken.objects.filter(tokenable_id=self.user.id).exists())
        login = APIClient().post("/api/v1/auth/login", {"email": self.user.email, "password": "brand-new-password"}, format="json")
        self.assertEqual(200, login.status_code)

    def test_an_address_typed_with_capitals_is_the_same_account(self):
        # Addresses are stored lowercase; the forms ask in the same form.
        self.forgot("  Priya.Sharma@Example.com ")
        self.assertEqual(["priya.sharma@example.com"], mail.outbox[0].to)

        response = self.reset(self.token_from_mail(), email="PRIYA.SHARMA@EXAMPLE.COM")

        self.assertEqual(200, response.status_code, response.data)
        self.user.refresh_from_db()
        self.assertTrue(hashing.check("brand-new-password", self.user.password))

    def test_a_wrong_token_changes_nothing_and_answers_with_an_object_for_details(self):
        self.forgot()

        response = self.reset("not-a-real-token")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            {"code": "INVALID_RESET_TOKEN", "message": "This password reset link is invalid or has expired.", "details": {}},
            response.data,
        )
        self.assertIn(b'"details":{}', response.content)
        self.user.refresh_from_db()
        self.assertTrue(hashing.check("old-password", self.user.password))

    def test_an_unknown_address_gets_the_same_refusal(self):
        self.assertEqual("INVALID_RESET_TOKEN", self.reset("anything", email="nobody@example.invalid").data["code"])

    def test_a_link_expires_after_an_hour(self):
        self.forgot()
        token = self.token_from_mail()
        later = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=61)

        with mock.patch("django.utils.timezone.now", return_value=later):
            response = self.reset(token)

        self.assertEqual("INVALID_RESET_TOKEN", response.data["code"])

    def test_a_second_link_within_a_minute_is_not_sent(self):
        self.forgot()
        self.forgot()

        self.assertEqual(1, len(mail.outbox))

    def test_a_token_laravel_issued_is_honoured(self):
        # A bcrypt hash made the way Laravel makes it ($2y$), in Laravel's table.
        PasswordResetToken.objects.create(
            email=self.user.email, token=hashing.make("laravel-issued-token"), created_at=dt.datetime.now(dt.timezone.utc)
        )

        self.assertEqual(200, self.reset("laravel-issued-token").status_code)

    def test_the_forms_say_what_they_need(self):
        forgot = APIClient().post("/api/v1/auth/forgot-password", {"email": "nope"}, format="json")
        reset = APIClient().post("/api/v1/auth/reset-password", {}, format="json")
        short = self.reset("x", password="short")

        self.assertEqual(["The email field must be a valid email address."], self.errors(forgot)["email"])
        self.assertEqual(["token", "email", "password"], list(self.errors(reset)))
        self.assertEqual(["The password field must be at least 8 characters."], self.errors(short)["password"])

    def test_reset_requests_are_limited_per_account(self):
        statuses = [APIClient().post("/api/v1/auth/forgot-password", {"email": self.user.email}, format="json").status_code for _ in range(4)]

        self.assertEqual([200, 200, 200, 429], statuses)
