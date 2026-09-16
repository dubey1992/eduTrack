"""Signing in, over HTTP.

These go through the URL map and the real authentication class, so they assert
the thing the Flutter app actually meets: a status code, an envelope, and a
token that works on the next request.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, hashing, tokens
from school.enums import UserRole, UserStatus
from school.models import PersonalAccessToken, User


class AuthTest(TestCase):
    def setUp(self):
        # The login limiter counts in the cache, which outlives a single test
        # inside one run. Without this the sixth test to post a login starts
        # failing with a 429 that looks like a broken password.
        cache.clear()
        self.client = APIClient()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")

    def sign_in(self, email, password=factories.TEST_PASSWORD):
        return self.client.post(
            "/api/v1/auth/login", {"email": email, "password": password}, format="json"
        )

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client


class SigningIn(AuthTest):
    def test_a_good_password_returns_a_token_and_the_session_user(self):
        user = factories.UserFactory(school=self.school, email="head@example.invalid")

        response = self.sign_in("head@example.invalid")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIn("token", response.data)
        self.assertEqual(user.id, response.data["user"]["id"])
        self.assertEqual("Asia/Kolkata", response.data["user"]["timezone"])

    def test_the_token_works_on_the_next_request(self):
        factories.UserFactory(school=self.school, email="head@example.invalid")

        token = self.sign_in("head@example.invalid").data["token"]

        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + token)
        response = self.client.get("/api/v1/me")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("head@example.invalid", response.data["email"])

    def test_the_session_user_never_carries_the_password(self):
        # Not "the field is empty" - the key must not be there at all, so it
        # cannot come back by somebody adding a field later (CLAUDE.md
        # rule 11).
        factories.UserFactory(school=self.school, email="head@example.invalid")

        body = self.sign_in("head@example.invalid").data["user"]

        self.assertNotIn("password", body)
        self.assertNotIn("remember_token", body)

    def test_a_wrong_password_is_401_in_the_standard_envelope(self):
        factories.UserFactory(school=self.school, email="head@example.invalid")

        response = self.sign_in("head@example.invalid", "definitely-not-the-password")

        # 401, not 422. Wrong credentials are not a malformed request - the
        # form was fine, the answer was no - and the client shows `message`
        # rather than marking up a field.
        self.assertEqual(401, response.status_code, response.data)
        self.assertEqual("UNAUTHENTICATED", response.data["code"])
        self.assertEqual("These credentials do not match our records.", response.data["message"])
        self.assertEqual({}, response.data["details"])

    def test_an_address_nobody_has_answers_exactly_the_same(self):
        # Byte for byte, so the login form cannot be used to find out which
        # addresses have accounts.
        factories.UserFactory(school=self.school, email="head@example.invalid")

        real = self.sign_in("head@example.invalid", "wrong-password")
        imaginary = self.sign_in("nobody@example.invalid", "wrong-password")

        self.assertEqual(real.status_code, imaginary.status_code)
        self.assertEqual(real.data, imaginary.data)

    def test_the_address_is_matched_regardless_of_case(self):
        # The column is stored lowercase, so a lookup that asked in the user's
        # own capitalisation would report a perfectly good password as wrong.
        factories.UserFactory(school=self.school, email="head@example.invalid")

        response = self.sign_in("  Head@Example.Invalid  ")

        self.assertEqual(200, response.status_code, response.data)

    def test_a_deactivated_account_is_told_why(self):
        # Different from a wrong password on purpose: these credentials were
        # right, and the person needs to know that retyping will not help.
        factories.UserFactory(
            school=self.school, email="gone@example.invalid", status=UserStatus.INACTIVE
        )

        response = self.sign_in("gone@example.invalid")

        self.assertEqual(403, response.status_code, response.data)
        self.assertEqual("ACCOUNT_INACTIVE", response.data["code"])

    def test_a_missing_field_is_422_naming_it(self):
        response = self.client.post("/api/v1/auth/login", {"email": ""}, format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("VALIDATION_ERROR", response.data["code"])
        self.assertIn("email", response.data["details"]["errors"])
        self.assertIn("password", response.data["details"]["errors"])

    def test_laravel_wording_survives_the_port(self):
        # The sentence a person reads when they leave a field blank is part of
        # what this migration must not change.
        response = self.client.post("/api/v1/auth/login", {"email": "not-an-address"}, format="json")

        self.assertEqual(
            "The email field must be a valid email address.",
            response.data["details"]["errors"]["email"][0],
        )
        self.assertEqual(
            "The password field is required.",
            response.data["details"]["errors"]["password"][0],
        )

    def test_guessing_is_rate_limited(self):
        factories.UserFactory(school=self.school, email="head@example.invalid")

        for _ in range(5):
            self.sign_in("head@example.invalid", "wrong")

        response = self.sign_in("head@example.invalid", "wrong")

        self.assertEqual(429, response.status_code, response.data)
        self.assertEqual("TOO_MANY_REQUESTS", response.data["code"])


class TheSessionEndpoint(AuthTest):
    def test_me_describes_the_holder_of_the_token(self):
        user = factories.UserFactory(school=self.school, email="head@example.invalid")

        response = self.as_user(user).get("/api/v1/me")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(user.id, response.data["id"])
        self.assertEqual(self.school.name, response.data["school_name"])

    def test_no_token_is_401_not_a_redirect(self):
        # A redirect to a login page is a web convention the client cannot
        # read, and DRF answers 403 here unless the authentication class
        # offers a WWW-Authenticate header.
        response = self.client.get("/api/v1/me")

        self.assertEqual(401, response.status_code, response.data)
        self.assertEqual("UNAUTHENTICATED", response.data["code"])

    def test_a_rubbish_token_is_401(self):
        self.client.credentials(HTTP_AUTHORIZATION="Bearer not-a-real-token")

        self.assertEqual(401, self.client.get("/api/v1/me").status_code)

    def test_an_account_deactivated_after_signing_in_stops_working(self):
        # Deactivating does not revoke tokens, so the check has to run on
        # every request. Otherwise an account switched off this morning stays
        # signed in until its holder happens to sign out.
        user = factories.UserFactory(school=self.school)
        client = self.as_user(user)

        self.assertEqual(200, client.get("/api/v1/me").status_code)

        User.objects.filter(pk=user.pk).update(status=UserStatus.INACTIVE)

        self.assertEqual(401, client.get("/api/v1/me").status_code)

    def test_manages_branches_is_true_only_inside_a_group(self):
        group = factories.SchoolFactory()
        branch = factories.SchoolFactory(parent_school=group)

        standalone_admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        branch_admin = factories.UserFactory(school=branch, role=UserRole.SCHOOL_ADMIN)

        self.assertFalse(self.as_user(standalone_admin).get("/api/v1/me").data["manages_branches"])
        self.assertTrue(self.as_user(branch_admin).get("/api/v1/me").data["manages_branches"])


class SigningOut(AuthTest):
    def test_logging_out_revokes_the_token_used(self):
        user = factories.UserFactory(school=self.school)
        client = self.as_user(user)

        response = client.post("/api/v1/auth/logout")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(401, client.get("/api/v1/me").status_code)

    def test_logging_out_leaves_other_sessions_alone(self):
        # Signing out of the office desktop must not sign you out of the phone.
        user = factories.UserFactory(school=self.school)
        desktop = self.as_user(user)
        phone = self.as_user(user)

        desktop.post("/api/v1/auth/logout")

        self.assertEqual(200, phone.get("/api/v1/me").status_code)


class ChangingAPassword(AuthTest):
    def setUp(self):
        super().setUp()
        self.user = factories.UserFactory(school=self.school, must_change_password=True)
        self.client = self.as_user(self.user)

    def change(self, **payload):
        return self.client.post("/api/v1/auth/change-password", payload, format="json")

    def test_a_new_password_replaces_the_old_one(self):
        response = self.change(
            current_password=factories.TEST_PASSWORD,
            password="A Whole New Password 2026",
            password_confirmation="A Whole New Password 2026",
        )

        self.assertEqual(200, response.status_code, response.data)

        self.user.refresh_from_db()
        self.assertTrue(hashing.check("A Whole New Password 2026", self.user.password))
        self.assertFalse(hashing.check(factories.TEST_PASSWORD, self.user.password))

    def test_changing_it_clears_the_must_change_flag(self):
        self.change(
            current_password=factories.TEST_PASSWORD,
            password="A Whole New Password 2026",
            password_confirmation="A Whole New Password 2026",
        )

        self.user.refresh_from_db()
        self.assertFalse(self.user.must_change_password)

    def test_every_other_session_is_signed_out_but_this_one_is_not(self):
        # If an imported account's temporary password reached the wrong
        # person, this is the moment that stops mattering - without signing
        # the user out of the browser they are changing it from.
        elsewhere = self.as_user(self.user)

        self.change(
            current_password=factories.TEST_PASSWORD,
            password="A Whole New Password 2026",
            password_confirmation="A Whole New Password 2026",
        )

        self.assertEqual(401, elsewhere.get("/api/v1/me").status_code)
        self.assertEqual(200, self.client.get("/api/v1/me").status_code)
        self.assertEqual(
            1, PersonalAccessToken.objects.filter(tokenable_id=self.user.id).count()
        )

    def test_the_wrong_current_password_is_refused_by_name(self):
        response = self.change(
            current_password="not-my-password",
            password="A Whole New Password 2026",
            password_confirmation="A Whole New Password 2026",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "That is not your current password.",
            response.data["details"]["errors"]["current_password"][0],
        )

    def test_a_mismatched_confirmation_is_refused(self):
        response = self.change(
            current_password=factories.TEST_PASSWORD,
            password="A Whole New Password 2026",
            password_confirmation="Something Else Entirely",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("password", response.data["details"]["errors"])

    def test_a_short_password_is_refused(self):
        response = self.change(
            current_password=factories.TEST_PASSWORD,
            password="short",
            password_confirmation="short",
        )

        self.assertEqual(
            "The password field must be at least 8 characters.",
            response.data["details"]["errors"]["password"][0],
        )

    def test_reusing_the_current_password_is_refused(self):
        response = self.change(
            current_password=factories.TEST_PASSWORD,
            password=factories.TEST_PASSWORD,
            password_confirmation=factories.TEST_PASSWORD,
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn(
            "Choose a password you have not just been using.",
            response.data["details"]["errors"]["password"],
        )

    def test_a_signed_out_caller_cannot_change_anybodys_password(self):
        self.assertEqual(
            401,
            APIClient().post(
                "/api/v1/auth/change-password",
                {"current_password": "x", "password": "yyyyyyyy"},
                format="json",
            ).status_code,
        )
