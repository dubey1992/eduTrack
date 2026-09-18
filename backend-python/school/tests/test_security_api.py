"""Phase 21's sign-in security, over HTTP (docs/security.md).

Lockout after ten wrong passwords, the password rules, sessions that end,
signing other devices out, and sessions ended when an administrator changes
what an account is. Decided with the user on 2026-09-18.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import csv_export, factories, hashing, tokens
from school.enums import UserRole
from school.models import AuditLog, PasswordResetToken, PersonalAccessToken

GOOD = factories.TEST_PASSWORD
CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0 Safari/537.36"
ANDROID_APP = "Dart/3.9 (dart:io) Android"


class SecurityTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="UTC")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER, email="tara@example.invalid")

    def sign_in(self, email="tara@example.invalid", password=GOOD, agent=None):
        # The per-minute throttle is its own tested rule (test_auth_api); here
        # it would only get in the way of counting to ten.
        cache.clear()
        extra = {"HTTP_USER_AGENT": agent} if agent else {}
        return APIClient().post("/api/v1/auth/login", {"email": email, "password": password}, format="json", **extra)

    def client_with(self, token: str) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + token)
        return client

    def as_user(self, user) -> APIClient:
        return self.client_with(tokens.issue(user))


class Lockout(SecurityTest):
    def test_ten_wrong_passwords_lock_the_account_even_against_the_right_one(self):
        for attempt in range(9):
            self.assertEqual(401, self.sign_in(password="Wrong-guess-1").status_code, attempt)

        self.assertEqual(401, self.sign_in(password="Wrong-guess-1").status_code)
        locked = self.sign_in()

        self.assertEqual(423, locked.status_code)
        self.assertEqual("ACCOUNT_LOCKED", locked.data["code"])
        self.assertIn("15 minutes", locked.data["message"])

    def test_the_lock_runs_out_after_fifteen_minutes(self):
        for _ in range(10):
            self.sign_in(password="Wrong-guess-1")

        later = timezone.now() + dt.timedelta(minutes=15, seconds=1)
        with mock.patch("django.utils.timezone.now", return_value=later):
            response = self.sign_in()

        self.assertEqual(200, response.status_code)
        self.teacher.refresh_from_db()
        self.assertEqual((0, None), (self.teacher.failed_login_attempts, self.teacher.locked_until))

    def test_a_good_sign_in_starts_the_count_again(self):
        for _ in range(9):
            self.sign_in(password="Wrong-guess-1")
        self.assertEqual(200, self.sign_in().status_code)

        for _ in range(9):
            self.sign_in(password="Wrong-guess-1")

        self.assertEqual(200, self.sign_in().status_code)

    def test_an_address_nobody_has_is_refused_the_same_way_and_recorded(self):
        response = self.sign_in(email="nobody@example.invalid", password="Wrong-guess-1")

        self.assertEqual(401, response.status_code)
        entry = AuditLog.objects.get(action="user.sign_in_failed")
        self.assertEqual((None, None, {"email": "nobody@example.invalid"}), (entry.user_id, entry.school_id, entry.new_values))

    def test_every_step_is_in_the_audit_log_and_no_password_is(self):
        for _ in range(10):
            self.sign_in(password="Wrong-guess-1")

        actions = list(AuditLog.objects.filter(user=self.teacher).values_list("action", flat=True).order_by("id"))

        self.assertEqual(["user.sign_in_failed"] * 10 + ["user.locked"], actions)
        self.assertNotIn("Wrong-guess-1", str(list(AuditLog.objects.values_list("new_values", flat=True))))

    def test_resetting_the_password_unlocks_the_account(self):
        for _ in range(10):
            self.sign_in(password="Wrong-guess-1")
        PasswordResetToken.objects.create(email=self.teacher.email, token=hashing.make("reset-token"),
                                          created_at=timezone.now())

        reset = APIClient().post("/api/v1/auth/reset-password", {
            "email": self.teacher.email, "token": "reset-token", "password": "Brand-new-2026",
            "password_confirmation": "Brand-new-2026",
        }, format="json")

        self.assertEqual(200, reset.status_code, reset.data)
        self.assertEqual(200, self.sign_in(password="Brand-new-2026").status_code)

    def test_an_administrator_may_unlock_their_own_staff(self):
        for _ in range(10):
            self.sign_in(password="Wrong-guess-1")

        shown = self.as_user(self.admin).get(f"/api/v1/users/{self.teacher.id}").data
        response = self.as_user(self.admin).post(f"/api/v1/users/{self.teacher.id}/unlock")

        self.assertIsNotNone(shown["locked_until"])
        self.assertEqual(200, response.status_code)
        self.assertIsNone(response.data["locked_until"])
        self.assertEqual(200, self.sign_in().status_code)
        self.assertTrue(AuditLog.objects.filter(action="user.unlocked", entity_id=self.teacher.id,
                                                user=self.admin).exists())

    def test_nobody_else_may_unlock(self):
        elsewhere = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.as_user(colleague).post(f"/api/v1/users/{self.teacher.id}/unlock").status_code)
        self.assertEqual(403, self.as_user(elsewhere).post(f"/api/v1/users/{self.teacher.id}/unlock").status_code)
        # Nor themselves: the lock is exactly for when somebody else is them.
        self.assertEqual(403, self.as_user(self.teacher).post(f"/api/v1/users/{self.teacher.id}/unlock").status_code)


class PasswordRules(SecurityTest):
    def change(self, new):
        return self.as_user(self.teacher).post("/api/v1/auth/change-password", {
            "current_password": GOOD, "password": new, "password_confirmation": new,
        }, format="json")

    def test_a_new_password_needs_a_letter_and_a_number(self):
        for weak in ("abcdefghij", "1234567890"):
            response = self.change(weak)
            self.assertEqual(422, response.status_code, weak)
            self.assertIn("The password must contain at least one letter and one number.",
                          response.data["details"]["errors"]["password"])

    def test_a_common_password_is_refused(self):
        response = self.change("Password1")

        self.assertEqual(422, response.status_code)
        self.assertIn("This password is too common. Choose one that is harder to guess.",
                      response.data["details"]["errors"]["password"])

    def test_a_good_one_is_accepted(self):
        self.assertEqual(200, self.change("Blue-kettle-42").status_code)

    def test_every_form_that_sets_a_password_applies_the_rules(self):
        admin = self.as_user(self.admin)
        new_admin = admin.post("/api/v1/users", {
            "first_name": "Sam", "last_name": "Sub", "email": "sam@example.invalid", "password": "password",
            "role": UserRole.SCHOOL_ADMIN,
        }, format="json")
        edit = admin.patch(f"/api/v1/users/{self.teacher.id}", {"password": "onlyletters"}, format="json")

        self.assertEqual(422, new_admin.status_code)
        self.assertIn("password", new_admin.data["details"]["errors"])
        self.assertEqual(422, edit.status_code)

    def test_an_existing_password_still_signs_in_whatever_it_is(self):
        self.teacher.password = hashing.make("password")
        self.teacher.save()

        self.assertEqual(200, self.sign_in(password="password").status_code)


class Sessions(SecurityTest):
    def test_each_sign_in_is_a_session_named_for_its_device(self):
        windows = self.sign_in(agent=CHROME_WINDOWS).data["token"]
        self.sign_in(agent=ANDROID_APP)

        sessions = self.client_with(windows).get("/api/v1/auth/sessions").data["data"]

        self.assertEqual({"Chrome on Windows", "the app on Android"}, {row["device"] for row in sessions})
        self.assertEqual([True], [row["current"] for row in sessions if row["device"] == "Chrome on Windows"])

    def test_a_device_can_be_signed_out_from_another(self):
        windows = self.sign_in(agent=CHROME_WINDOWS).data["token"]
        phone = self.sign_in(agent=ANDROID_APP).data["token"]
        phone_id = int(phone.split("|")[0])

        response = self.client_with(windows).delete(f"/api/v1/auth/sessions/{phone_id}")

        self.assertEqual(200, response.status_code)
        self.assertEqual(401, self.client_with(phone).get("/api/v1/me").status_code)
        self.assertEqual(200, self.client_with(windows).get("/api/v1/me").status_code)

    def test_nobody_can_end_someone_elses_session(self):
        theirs = int(tokens.issue(self.admin).split("|")[0])

        response = self.as_user(self.teacher).delete(f"/api/v1/auth/sessions/{theirs}")

        self.assertEqual(404, response.status_code)
        self.assertTrue(PersonalAccessToken.objects.filter(pk=theirs).exists())

    def test_signing_out_every_other_device_keeps_this_one(self):
        here = self.sign_in(agent=CHROME_WINDOWS).data["token"]
        others = [self.sign_in(agent=ANDROID_APP).data["token"] for _ in range(2)]

        response = self.client_with(here).post("/api/v1/auth/sessions/others")

        self.assertEqual((200, 2), (response.status_code, response.data["ended"]))
        self.assertEqual(200, self.client_with(here).get("/api/v1/me").status_code)
        for token in others:
            self.assertEqual(401, self.client_with(token).get("/api/v1/me").status_code)

    def test_a_session_unused_for_seven_days_has_ended_and_is_removed(self):
        token = self.sign_in().data["token"]
        row_id = int(token.split("|")[0])
        PersonalAccessToken.objects.filter(pk=row_id).update(last_used_at=timezone.now() - dt.timedelta(days=7, minutes=1))

        self.assertEqual(401, self.client_with(token).get("/api/v1/me").status_code)
        self.assertFalse(PersonalAccessToken.objects.filter(pk=row_id).exists())

    def test_a_session_used_every_day_still_ends_after_thirty(self):
        token = self.sign_in().data["token"]
        row_id = int(token.split("|")[0])
        PersonalAccessToken.objects.filter(pk=row_id).update(
            created_at=timezone.now() - dt.timedelta(days=30, minutes=1),
            last_used_at=timezone.now() - dt.timedelta(hours=1),
            expires_at=None,
        )

        self.assertEqual(401, self.client_with(token).get("/api/v1/me").status_code)

    def test_a_laravel_token_with_no_expiry_lives_by_the_same_rules(self):
        token = tokens.issue(self.teacher)
        PersonalAccessToken.objects.filter(pk=int(token.split("|")[0])).update(
            expires_at=None, created_at=timezone.now() - dt.timedelta(days=6), last_used_at=None,
        )

        self.assertEqual(200, self.client_with(token).get("/api/v1/me").status_code)

    def test_changing_the_password_ends_the_other_sessions(self):
        here = self.sign_in().data["token"]
        other = self.sign_in().data["token"]

        self.client_with(here).post("/api/v1/auth/change-password", {
            "current_password": GOOD, "password": "Blue-kettle-42", "password_confirmation": "Blue-kettle-42",
        }, format="json")

        self.assertEqual((200, 401), (self.client_with(here).get("/api/v1/me").status_code,
                                      self.client_with(other).get("/api/v1/me").status_code))


class AdministratorChanges(SecurityTest):
    def test_a_new_password_or_role_signs_the_account_out_everywhere(self):
        for change in ({"password": "Blue-kettle-42"}, {"role": UserRole.HOD}):
            token = tokens.issue(self.teacher)

            response = self.as_user(self.admin).patch(f"/api/v1/users/{self.teacher.id}", change, format="json")

            self.assertEqual(200, response.status_code, response.data)
            self.assertEqual(401, self.client_with(token).get("/api/v1/me").status_code, change)

    def test_a_new_name_does_not(self):
        token = tokens.issue(self.teacher)

        self.as_user(self.admin).patch(f"/api/v1/users/{self.teacher.id}", {"first_name": "Tara"}, format="json")

        self.assertEqual(200, self.client_with(token).get("/api/v1/me").status_code)

    def test_a_role_change_is_recorded_with_before_and_after(self):
        self.as_user(self.admin).patch(f"/api/v1/users/{self.teacher.id}", {"role": UserRole.HOD}, format="json")

        entry = AuditLog.objects.get(action="user.role_changed")
        self.assertEqual(({"role": UserRole.TEACHER}, {"role": UserRole.HOD}), (entry.old_values, entry.new_values))
        self.assertEqual((self.admin.id, self.school.id), (entry.user_id, entry.school_id))


class Hardening(SecurityTest):
    def test_every_answer_carries_the_security_headers(self):
        response = self.as_user(self.admin).get("/api/v1/me")

        self.assertEqual("DENY", response["X-Frame-Options"])
        self.assertEqual("nosniff", response["X-Content-Type-Options"])
        self.assertEqual("no-referrer", response["Referrer-Policy"])
        self.assertIn("default-src 'none'", response["Content-Security-Policy"])

    def test_the_sign_in_throttle_is_not_fooled_by_a_forwarded_address(self):
        cache.clear()
        statuses = [
            APIClient().post("/api/v1/auth/login", {"email": self.teacher.email, "password": "Wrong-guess-1"},
                             format="json", HTTP_X_FORWARDED_FOR=f"10.0.0.{n}").status_code
            for n in range(6)
        ]

        # Six "different" addresses, one real one: the sixth is still refused.
        self.assertEqual(429, statuses[-1])

    def test_an_exported_cell_that_would_run_as_a_formula_stays_text(self):
        self.assertEqual("'=HYPERLINK(\"http://x\")", csv_export.cell('=HYPERLINK("http://x")'))
        self.assertEqual("'@SUM(A1)", csv_export.cell("@SUM(A1)"))
        self.assertEqual("'+cmd", csv_export.cell("+cmd"))
        # A phone number, a negative figure and the dash for "nothing" are not formulas.
        for plain in ("+91 98765 43210", "-12.5", "-"):
            self.assertEqual(plain, csv_export.cell(plain))
