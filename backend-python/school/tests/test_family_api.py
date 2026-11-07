"""Guardians and the Family app's sign-in (docs/parent-student-app.md, F0).

What this file guards that a quick read would not:

- **A parent is one person across their children.** The same mobile number in
  a school is the same guardian, so a sibling's guardian is linked rather than
  copied, and the student's own guardian columns follow the primary link.
- **A family account reaches the Family app and nothing else.** Its session
  is refused by every staff endpoint, and a staff session is refused by the
  Family app's.
- **The passcode is useless without the phone**, a lock lifts by itself after
  15 minutes, and an unknown number and an unregistered phone get one answer.
- **A parent sees their own children, at their own school, and no one else's.**
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, family, family_letter, notices, pdf_design, tokens
from school.enums import NoticeAudience, UserRole, UserStatus
from school.family_accounts import FamilyAuthService, GuardianService
from school.models import (
    FamilyCredential,
    FamilyDevice,
    Guardian,
    GuardianStudent,
    ModuleSetting,
    PersonalAccessToken,
    Student,
    User,
)

SETUP = "/api/v1/family/auth/setup"
LOGIN = "/api/v1/family/auth/login"
ME = "/api/v1/family/me"
MOBILE = "+91 98765 43210"
PASSCODE = "482915"


class FamilyTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=self.school, module="family_app")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.section = factories.ClassSectionFactory(school_class__school=self.school)
        self.child = self.student("Aarav", MOBILE)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
        return client

    def as_token(self, token) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + token)
        return client

    def student(self, first_name, mobile, section=None, guardian_name="Meera Sharma", status="active"):
        """A student with their guardian linked, the way the student form makes one."""
        student = factories.StudentFactory(class_section=section or self.section, first_name=first_name,
                                           guardian_name=guardian_name, guardian_mobile=mobile, status=status)
        GuardianService.follow_student(student)
        return student

    def link_of(self, student) -> GuardianStudent:
        return GuardianStudent.objects.select_related("guardian").get(student=student, is_primary=True)

    def guardians_url(self, student, link=None, tail=""):
        url = f"/api/v1/students/{student.id}/guardians"
        return url + (f"/{link.id}" if link else "") + tail

    def code_for(self, student=None, consent=True):
        student = student or self.child
        response = self.as_user(self.admin).post(
            self.guardians_url(student, self.link_of(student), "/family-access/setup-code"), {"consent": consent},
            format="json",
        )
        self.assertEqual(201, response.status_code, response.data)
        return response.data["data"]["setup_code"]

    def register(self, mobile=MOBILE, passcode=PASSCODE, student=None):
        """Registers a phone the way the Family app does; returns (token, device secret)."""
        code = self.code_for(student)
        response = APIClient().post(SETUP, {"mobile": mobile, "setup_code": code, "passcode": passcode},
                                    format="json")
        self.assertEqual(201, response.status_code, response.data)
        return response.data["token"], response.data["device_secret"]


class TheOfficeLinksGuardians(FamilyTestCase):
    def test_a_student_has_their_guardian_from_the_form(self):
        response = self.as_user(self.admin).get(self.guardians_url(self.child))

        self.assertEqual(200, response.status_code)
        [guardian] = response.data["data"]
        self.assertEqual(("Meera Sharma", "+919876543210", True), (guardian["name"], guardian["mobile"],
                                                                   guardian["is_primary"]))

    def test_a_sibling_with_the_same_number_shares_the_guardian(self):
        sister = self.student("Meera", "+91-98765-43210")

        self.assertEqual(self.link_of(self.child).guardian_id, self.link_of(sister).guardian_id)
        self.assertEqual(1, Guardian.objects.filter(school=self.school).count())

    def test_adding_a_second_guardian_who_becomes_primary_updates_the_student(self):
        response = self.as_user(self.admin).post(self.guardians_url(self.child), {
            "name": "Rohit Sharma", "mobile": "+91 91234 56789", "relationship": "father", "is_primary": True,
        }, format="json")

        self.assertEqual(201, response.status_code, response.data)
        student = Student.objects.get(pk=self.child.id)
        self.assertEqual(("Rohit Sharma", "+919123456789"), (student.guardian_name, student.guardian_mobile))
        self.assertEqual(1, GuardianStudent.objects.filter(student=self.child, is_primary=True).count())

    def test_the_relationship_must_be_one_the_office_offers(self):
        response = self.as_user(self.admin).post(self.guardians_url(self.child), {
            "name": "Uncle", "relationship": "neighbour",
        }, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("relationship", response.data["details"]["errors"])

    def test_the_only_guardian_cannot_be_unlinked(self):
        response = self.as_user(self.admin).delete(self.guardians_url(self.child, self.link_of(self.child)))

        self.assertEqual(422, response.status_code)
        self.assertEqual("GUARDIAN_PROBLEM", response.data["code"])

    def test_unlinking_one_of_two_keeps_a_primary(self):
        self.as_user(self.admin).post(self.guardians_url(self.child), {"name": "Rohit Sharma",
                                                                       "mobile": "+91 91234 56789"}, format="json")
        primary = self.link_of(self.child)

        response = self.as_user(self.admin).delete(self.guardians_url(self.child, primary))

        self.assertEqual(204, response.status_code)
        self.assertEqual("Rohit Sharma", self.link_of(self.child).guardian.name)

    def test_a_number_another_guardian_has_is_refused(self):
        self.student("Kabir", "+91 90000 11111", guardian_name="Anita Verma")

        response = self.as_user(self.admin).patch(self.guardians_url(self.child, self.link_of(self.child)),
                                                  {"mobile": "+91 90000 11111"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual("GUARDIAN_PROBLEM", response.data["code"])

    def test_changing_the_number_on_the_student_form_makes_a_new_primary_and_keeps_the_old(self):
        response = self.as_user(self.admin).patch(f"/api/v1/students/{self.child.id}",
                                                  {"guardian_mobile": "+91 99999 00000"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("+919999900000", self.link_of(self.child).guardian.login_mobile)
        self.assertEqual(2, GuardianStudent.objects.filter(student=self.child).count())

    def test_another_schools_admin_is_refused(self):
        other_admin = factories.UserFactory(role=UserRole.SCHOOL_ADMIN)

        response = self.as_user(other_admin).get(self.guardians_url(self.child))

        self.assertIn(response.status_code, (403, 404))

    def test_a_member_of_staff_who_cannot_edit_students_is_refused(self):
        staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        response = self.as_user(staff).get(self.guardians_url(self.child))

        self.assertEqual(403, response.status_code)


class TheOfficeIssuesSetupCodes(FamilyTestCase):
    def url(self):
        return self.guardians_url(self.child, self.link_of(self.child), "/family-access/setup-code")

    def test_a_code_makes_the_family_account_and_records_consent(self):
        response = self.as_user(self.admin).post(self.url(), {"consent": True}, format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertRegex(response.data["data"]["setup_code"], r"^\d{8}$")
        guardian = self.link_of(self.child).guardian
        self.assertIsNotNone(guardian.consent_at)
        self.assertEqual(UserRole.PARENT, guardian.user.role)
        self.assertTrue(guardian.user.email.endswith("@no-email.invalid"))

    def test_no_code_without_consent(self):
        response = self.as_user(self.admin).post(self.url(), {}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual("GUARDIAN_PROBLEM", response.data["code"])

    def test_no_code_without_a_mobile_number(self):
        child = self.student("Ira", None, guardian_name="Sunita Rao")

        response = self.as_user(self.admin).post(
            self.guardians_url(child, self.link_of(child), "/family-access/setup-code"), {"consent": True},
            format="json",
        )

        self.assertEqual(422, response.status_code)

    def test_no_code_while_the_family_app_is_off(self):
        school = factories.SchoolFactory()
        admin = factories.UserFactory(school=school, role=UserRole.SCHOOL_ADMIN)
        child = self.student("Dev", "+91 90000 22222", section=factories.ClassSectionFactory(school_class__school=school))

        response = self.as_user(admin).post(
            self.guardians_url(child, self.link_of(child), "/family-access/setup-code"), {"consent": True},
            format="json",
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_the_letter_issues_a_fresh_code_and_prints_it(self):
        response = self.as_user(self.admin).post(
            self.guardians_url(self.child, self.link_of(self.child), "/family-access/letter"), {"consent": True},
            format="json",
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertTrue(response.content.startswith(b"%PDF"))
        self.assertTrue(FamilyCredential.objects.get().setup_code)

    def test_the_letter_lays_out_cleanly_with_every_detail(self):
        guardian = self.link_of(self.child).guardian
        html = family_letter.document(guardian, [self.child], "12345678", timezone.now() + dt.timedelta(days=7))

        self.assertEqual(0, pdf_design.style_errors(html))
        for detail in ("Meera Sharma", "Aarav", "+919876543210", "1234 5678", self.school.name):
            self.assertIn(detail, html)

    def test_the_access_screen_never_shows_the_code(self):
        self.code_for()

        response = self.as_user(self.admin).get(self.guardians_url(self.child, self.link_of(self.child),
                                                                   "/family-access"))

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.data["data"]["setup_code_pending"])
        self.assertNotIn("setup_code", response.data["data"])


class AParentRegistersAPhone(FamilyTestCase):
    def test_the_code_and_a_new_passcode_register_the_phone(self):
        code = self.code_for()

        response = APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": PASSCODE},
                                    format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(response.data["device_secret"])
        self.assertEqual(["Aarav"], [child["first_name"] for child in response.data["me"]["children"]])
        self.assertEqual(1, FamilyDevice.objects.count())

    def test_a_used_code_cannot_be_used_again(self):
        code = self.code_for()
        APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": PASSCODE}, format="json")

        response = APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": PASSCODE},
                                    format="json")

        self.assertEqual(401, response.status_code)
        self.assertEqual("SETUP_CODE_REJECTED", response.data["code"])

    def test_an_expired_code_is_refused(self):
        code = self.code_for()
        FamilyCredential.objects.update(setup_code_expires_at=timezone.now() - dt.timedelta(minutes=1))

        response = APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": PASSCODE},
                                    format="json")

        self.assertEqual(401, response.status_code)

    def test_five_wrong_codes_cancel_it(self):
        code = self.code_for()
        for _ in range(family.MAX_ATTEMPTS):
            cache.clear()
            APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": "00000000", "passcode": PASSCODE},
                             format="json")

        cache.clear()
        response = APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": PASSCODE},
                                    format="json")

        self.assertEqual(401, response.status_code)

    def test_an_obvious_passcode_is_refused(self):
        code = self.code_for()

        for passcode, reason in (("123456", "straight run"), ("777777", "repeated"), ("12345", "6 digits")):
            with self.subTest(passcode=passcode):
                response = APIClient().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": passcode},
                                            format="json")
                self.assertEqual(422, response.status_code)
                self.assertIn(reason, str(response.data["details"]["errors"]["passcode"]))


class AParentSignsIn(FamilyTestCase):
    def test_mobile_and_passcode_on_the_registered_phone(self):
        _, secret = self.register()

        response = APIClient().post(LOGIN, {"mobile": MOBILE, "passcode": PASSCODE, "device_secret": secret},
                                    format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(response.data["token"])

    def test_another_phone_gets_the_same_answer_as_an_unknown_number(self):
        self.register()

        for mobile in (MOBILE, "+91 90000 99999"):
            with self.subTest(mobile=mobile):
                cache.clear()
                response = APIClient().post(LOGIN, {"mobile": mobile, "passcode": PASSCODE,
                                                    "device_secret": "not-this-phone"}, format="json")
                self.assertEqual(401, response.status_code)
                self.assertEqual("DEVICE_NOT_REGISTERED", response.data["code"])

    def test_five_wrong_passcodes_lock_for_15_minutes_then_it_opens(self):
        _, secret = self.register()

        for attempt in range(1, family.MAX_ATTEMPTS + 1):
            cache.clear()
            response = APIClient().post(LOGIN, {"mobile": MOBILE, "passcode": "905172", "device_secret": secret},
                                        format="json")
        self.assertEqual(423, response.status_code)
        self.assertEqual(15, response.data["details"]["retry_after_minutes"])

        cache.clear()
        right = {"mobile": MOBILE, "passcode": PASSCODE, "device_secret": secret}
        self.assertEqual(423, APIClient().post(LOGIN, right, format="json").status_code)

        FamilyCredential.objects.update(locked_at=timezone.now() - dt.timedelta(minutes=family.LOCK_MINUTES + 1))
        cache.clear()
        self.assertEqual(200, APIClient().post(LOGIN, right, format="json").status_code)

    def test_a_wrong_passcode_says_how_many_tries_are_left(self):
        _, secret = self.register()

        response = APIClient().post(LOGIN, {"mobile": MOBILE, "passcode": "905172", "device_secret": secret},
                                    format="json")

        self.assertEqual(401, response.status_code)
        self.assertIn("4 tries left", response.data["message"])

    def test_a_removed_phone_cannot_sign_in_and_its_sessions_end(self):
        token, secret = self.register()
        guardian = self.link_of(self.child).guardian
        device = FamilyDevice.objects.get(user=guardian.user)

        response = self.as_user(self.admin).delete(
            self.guardians_url(self.child, self.link_of(self.child), f"/family-access/devices/{device.id}")
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(401, self.as_token(token).get(ME).status_code)
        cache.clear()
        response = APIClient().post(LOGIN, {"mobile": MOBILE, "passcode": PASSCODE, "device_secret": secret},
                                    format="json")
        self.assertEqual(401, response.status_code)

    def test_the_family_app_switched_off_stops_sign_in(self):
        _, secret = self.register()
        ModuleSetting.objects.filter(school=self.school, module="family_app").update(school_enabled=False)

        response = APIClient().post(LOGIN, {"mobile": MOBILE, "passcode": PASSCODE, "device_secret": secret},
                                    format="json")

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_a_session_ends_after_30_days_unused(self):
        token, _ = self.register()
        PersonalAccessToken.objects.update(last_used_at=timezone.now() - dt.timedelta(days=family.IDLE_DAYS + 1))

        self.assertEqual(401, self.as_token(token).get(ME).status_code)

    def test_a_session_used_this_month_carries_on(self):
        token, _ = self.register()
        PersonalAccessToken.objects.update(last_used_at=timezone.now() - dt.timedelta(days=family.IDLE_DAYS - 1),
                                           created_at=timezone.now() - dt.timedelta(days=200))

        self.assertEqual(200, self.as_token(token).get(ME).status_code)


class AParentSeesTheirOwnChildren(FamilyTestCase):
    def test_every_child_linked_to_them_and_nobody_else(self):
        self.student("Meera", MOBILE)
        self.student("Kabir", "+91 90000 11111", guardian_name="Anita Verma")
        self.student("Left", MOBILE, status="inactive")
        token, _ = self.register()

        response = self.as_token(token).get(ME)

        self.assertEqual(200, response.status_code)
        self.assertEqual(["Aarav", "Meera"], [child["first_name"] for child in response.data["children"]])
        self.assertEqual(self.school.name, response.data["school"]["name"])

    def test_unlinked_from_their_last_child_the_account_stops(self):
        token, _ = self.register()
        self.as_user(self.admin).post(self.guardians_url(self.child), {"name": "Rohit Sharma",
                                                                       "mobile": "+91 91234 56789"}, format="json")

        self.as_user(self.admin).delete(self.guardians_url(
            self.child, GuardianStudent.objects.get(student=self.child, guardian__login_mobile="+919876543210")
        ))

        guardian = Guardian.objects.get(login_mobile="+919876543210")
        self.assertEqual(UserStatus.INACTIVE, User.objects.get(pk=guardian.user_id).status)
        self.assertEqual(401, self.as_token(token).get(ME).status_code)


class AFamilySessionStaysInTheFamilyApp(FamilyTestCase):
    def test_every_staff_endpoint_refuses_a_family_session(self):
        token, _ = self.register()

        for url in ("/api/v1/students", "/api/v1/dashboard", "/api/v1/users", f"/api/v1/students/{self.child.id}",
                    "/api/v1/auth/sessions", "/api/v1/inbox"):
            with self.subTest(url=url):
                response = self.as_token(token).get(url)
                self.assertEqual(403, response.status_code, url)
                self.assertEqual("FAMILY_APP_ONLY", response.data["code"])

    def test_a_staff_session_is_refused_by_the_family_app(self):
        response = self.as_user(self.admin).get(ME)

        self.assertEqual(403, response.status_code)
        self.assertEqual("NOT_A_FAMILY_ACCOUNT", response.data["code"])

    def test_signing_out_ends_the_session(self):
        token, _ = self.register()

        self.assertEqual(204, self.as_token(token).post("/api/v1/family/auth/logout").status_code)
        self.assertEqual(401, self.as_token(token).get(ME).status_code)


class FamilyAccountsAreNotStaff(FamilyTestCase):
    def setUp(self):
        super().setUp()
        self.register()
        self.parent = Guardian.objects.get(login_mobile="+919876543210").user

    def test_the_users_screen_does_not_list_or_open_them(self):
        listed = self.as_user(self.admin).get("/api/v1/users")
        opened = self.as_user(self.admin).get(f"/api/v1/users/{self.parent.id}")

        self.assertNotIn(self.parent.id, [user["id"] for user in listed.data["data"]])
        self.assertEqual(404, opened.status_code)

    def test_a_notice_to_all_staff_does_not_reach_them(self):
        reached = notices.users_for(self.school.id, NoticeAudience.STAFF, None)

        self.assertNotIn(self.parent.id, list(reached.values_list("id", flat=True)))
        self.assertIn(self.admin.id, list(reached.values_list("id", flat=True)))
