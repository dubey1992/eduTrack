"""My Profile (docs/profile.md): every role keeps their own details, email and
photo.

What this file guards:

- **Only yourself.** No profile endpoint takes an id, and nothing in the body
  reaches an admin-only field - role, school, status, employee id - however
  the request is edited.
- **Email is a security change.** It needs the current password, must be
  unique whatever its case, ends every other session and tells the old
  address.
- **A photo is decoded, never trusted.** A renamed text file, an oversized
  file, a script hidden after the image data and an EXIF location are all
  dealt with, and the photo is only readable by its owner and the admins
  whose scope covers them.
- **Every role**, including a Super Admin, who has no staff record and so no
  address.
"""

import io
import json
import shutil
import tempfile

from django.core import mail
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from school import factories, hashing, photos, queue, tokens
from school.enums import UserRole
from school.models import AuditLog, PersonalAccessToken, User

PROFILE = "/api/v1/profile"
PASSWORD = "Correct-horse-9"


def image_bytes(fmt="PNG", size=(40, 30), exif=None) -> bytes:
    out = io.BytesIO()
    image = Image.new("RGB", size, (200, 60, 60))
    kwargs = {"exif": exif} if exif is not None else {}
    image.save(out, format=fmt, **kwargs)

    return out.getvalue()


def upload(data: bytes, name="me.png", content_type="image/png"):
    return SimpleUploadedFile(name, data, content_type=content_type)


class ProfileTest(TestCase):
    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.media, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=self.media)
        media.enable()
        self.addCleanup(media.disable)

        self.school = factories.SchoolFactory(name="Sunrise Public School", timezone="Asia/Kolkata")
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.teacher = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER, first_name="Rahul", last_name="Verma",
            email="rahul@example.com", mobile="+91 9111111111", password=hashing.make(PASSWORD),
        )
        self.teacher_profile = factories.StaffProfileFactory(
            school=self.school, user=self.teacher, department=self.science, employee_id="TCH-7",
            designation="Physics teacher", address="12 Rose Lane",
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN, password=hashing.make(PASSWORD))
        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def client_for(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


# -- reading ------------------------------------------------------------------


class Reading(ProfileTest):
    def test_a_teacher_sees_their_details_and_their_employment_read_only(self):
        response = self.client_for(self.teacher).get(PROFILE)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            {"first_name": "Rahul", "last_name": "Verma", "email": "rahul@example.com", "mobile": "+91 9111111111",
             "role": "TEACHER", "role_label": "Teacher", "school_name": "Sunrise Public School",
             "has_staff_record": True, "address": "12 Rose Lane", "photo_url": None},
            {key: response.data[key] for key in ("first_name", "last_name", "email", "mobile", "role", "role_label",
                                                  "school_name", "has_staff_record", "address", "photo_url")},
        )
        self.assertEqual(
            ("TCH-7", "Science", "Physics teacher"),
            tuple(response.data["employment"][key] for key in ("employee_id", "department_name", "designation")),
        )

    def test_a_super_admin_has_a_profile_with_no_staff_record(self):
        response = self.client_for(self.root).get(PROFILE)

        self.assertEqual(200, response.status_code)
        self.assertEqual((False, None, None, None), (
            response.data["has_staff_record"], response.data["address"], response.data["employment"],
            response.data["school_name"],
        ))

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get(PROFILE).status_code)
        self.assertEqual(401, APIClient().patch(PROFILE, {"first_name": "X"}, format="json").status_code)


# -- changing details -----------------------------------------------------------------


class ChangingDetails(ProfileTest):
    def test_every_role_updates_their_own_name_and_mobile(self):
        for role in UserRole.values:
            with self.subTest(role=role):
                school = None if role == UserRole.SUPER_ADMIN else self.school
                user = factories.UserFactory(school=school, role=role)

                # A Bus Attendant's mobile is their sign-in; that has its own test.
                changes = {"first_name": "Asha", "last_name": "Rao"}
                if role != UserRole.BUS_ATTENDANT:
                    changes["mobile"] = "+91 9888888888"

                response = self.client_for(user).patch(PROFILE, changes, format="json")

                self.assertEqual(200, response.status_code, response.data)
                user.refresh_from_db()
                self.assertEqual(("Asha", "Rao"), (user.first_name, user.last_name))
                if "mobile" in changes:
                    self.assertEqual("+91 9888888888", user.mobile)

    def test_a_bus_attendant_cannot_change_the_mobile_they_sign_in_with(self):
        attendant = factories.UserFactory(school=self.school, role=UserRole.BUS_ATTENDANT, mobile="+91 9000000009")

        refused = self.client_for(attendant).patch(PROFILE, {"mobile": "+91 9888888888"}, format="json")
        self.assertEqual(422, refused.status_code)
        self.assertIn("only your school office can change it", refused.data["message"])

        same = self.client_for(attendant).patch(PROFILE, {"mobile": "+91 9000000009", "first_name": "Ravi"}, format="json")
        self.assertEqual(200, same.status_code, "sending the unchanged number with other edits is fine")

    def test_the_session_name_follows_at_once(self):
        client = self.client_for(self.teacher)
        client.patch(PROFILE, {"first_name": "Rohan"}, format="json")

        self.assertEqual("Rohan Verma", client.get("/api/v1/me").data["name"])

    def test_the_address_is_saved_on_the_staff_record(self):
        response = self.client_for(self.teacher).patch(PROFILE, {"address": "4 Lake Road, Pune"}, format="json")

        self.assertEqual("4 Lake Road, Pune", response.data["address"])
        self.teacher_profile.refresh_from_db()
        self.assertEqual("4 Lake Road, Pune", self.teacher_profile.address)

    def test_blank_mobile_and_address_mean_none_on_record(self):
        response = self.client_for(self.teacher).patch(PROFILE, {"mobile": "", "address": ""}, format="json")

        self.assertEqual((None, None), (response.data["mobile"], response.data["address"]))

    def test_an_account_with_no_staff_record_cannot_set_an_address(self):
        response = self.client_for(self.root).patch(PROFILE, {"address": "Somewhere"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual("NO_STAFF_RECORD", response.data["code"])

    def test_admin_only_fields_are_not_reachable_from_here(self):
        before = (self.teacher.role, self.teacher.school_id, self.teacher.status, self.teacher.email)

        response = self.client_for(self.teacher).patch(PROFILE, {
            "first_name": "Rahul", "role": "SCHOOL_ADMIN", "school_id": self.elsewhere.id, "status": "inactive",
            "email": "evil@example.com", "is_sub_admin": True, "employee_id": "X", "designation": "Principal",
            "password": "Something-new-1",
        }, format="json")

        self.assertEqual(200, response.status_code)
        self.teacher.refresh_from_db()
        self.teacher_profile.refresh_from_db()
        self.assertEqual(before, (self.teacher.role, self.teacher.school_id, self.teacher.status, self.teacher.email))
        self.assertEqual(("TCH-7", "Physics teacher"), (self.teacher_profile.employee_id, self.teacher_profile.designation))
        self.assertTrue(hashing.check(PASSWORD, self.teacher.password))

    def test_bad_details_are_named_one_by_one(self):
        response = self.client_for(self.teacher).patch(
            PROFILE, {"first_name": "   ", "last_name": "x" * 101, "mobile": "12", "address": "y" * 501}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            {
                "first_name": ["The first name field is required."],
                "last_name": ["The last name field must not be greater than 100 characters."],
                "mobile": ["The mobile field format is invalid."],
                "address": ["The address field must not be greater than 500 characters."],
            },
            self.errors(response),
        )

    def test_an_empty_change_is_refused(self):
        self.assertEqual(422, self.client_for(self.teacher).patch(PROFILE, {}, format="json").status_code)

    def test_a_change_is_in_the_audit_trail_and_an_unchanged_save_is_not(self):
        client = self.client_for(self.teacher)
        client.patch(PROFILE, {"mobile": "+91 9000000001", "address": "New"}, format="json")

        entries = AuditLog.objects.filter(action="profile.updated").order_by("id")
        self.assertEqual(["users", "staff"], [entry.module for entry in entries])
        self.assertEqual((self.teacher.id, "+91 9111111111", "+91 9000000001"), (
            entries[0].user_id, entries[0].old_values["mobile"], entries[0].new_values["mobile"],
        ))

        client.patch(PROFILE, {"mobile": "+91 9000000001"}, format="json")
        self.assertEqual(2, AuditLog.objects.filter(action="profile.updated").count())


# -- changing email -----------------------------------------------------------------


class ChangingEmail(ProfileTest):
    URL = PROFILE + "/email"

    def test_the_email_changes_with_the_current_password_and_is_stored_lowercase(self):
        response = self.client_for(self.teacher).post(
            self.URL, {"email": "  Rahul.Verma@Example.COM ", "current_password": PASSWORD}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("rahul.verma@example.com", response.data["email"])
        self.teacher.refresh_from_db()
        self.assertEqual("rahul.verma@example.com", self.teacher.email)

    def test_it_signs_out_every_other_device_but_not_this_one(self):
        here = self.client_for(self.teacher)
        there = self.client_for(self.teacher)

        here.post(self.URL, {"email": "new@example.com", "current_password": PASSWORD}, format="json")

        self.assertEqual(200, here.get("/api/v1/me").status_code)
        self.assertEqual(401, there.get("/api/v1/me").status_code)
        self.assertEqual(1, PersonalAccessToken.objects.filter(tokenable_id=self.teacher.id).count())

    def test_the_old_address_is_told_and_the_new_one_only_partly_named(self):
        self.client_for(self.teacher).post(self.URL, {"email": "newplace@example.com", "current_password": PASSWORD}, format="json")

        queue.work()

        self.assertEqual(1, len(mail.outbox))
        notice = mail.outbox[0]
        self.assertEqual(["rahul@example.com"], notice.to)
        self.assertIn("ne***@example.com", notice.body)
        self.assertNotIn("newplace@example.com", notice.body)

    def test_the_new_address_signs_in_and_the_old_one_does_not(self):
        self.client_for(self.teacher).post(self.URL, {"email": "new@example.com", "current_password": PASSWORD}, format="json")
        anonymous = APIClient()

        self.assertEqual(200, anonymous.post("/api/v1/auth/login", {"email": "new@example.com", "password": PASSWORD}, format="json").status_code)
        cache.clear()
        self.assertEqual(401, anonymous.post("/api/v1/auth/login", {"email": "rahul@example.com", "password": PASSWORD}, format="json").status_code)

    def test_a_wrong_password_changes_nothing(self):
        response = self.client_for(self.teacher).post(
            self.URL, {"email": "new@example.com", "current_password": "wrong"}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual(["That is not your current password."], self.errors(response)["current_password"])
        self.teacher.refresh_from_db()
        self.assertEqual("rahul@example.com", self.teacher.email)
        self.assertFalse(AuditLog.objects.filter(action="user.email_changed").exists())

    def test_an_address_somebody_else_has_is_refused_whatever_its_case(self):
        self.colleague.email = "taken@example.com"
        self.colleague.save()

        response = self.client_for(self.teacher).post(
            self.URL, {"email": "TAKEN@example.com", "current_password": PASSWORD}, format="json"
        )

        self.assertEqual(["The email has already been taken."], self.errors(response)["email"])

    def test_the_same_address_and_a_malformed_one_are_refused(self):
        client = self.client_for(self.teacher)

        same = client.post(self.URL, {"email": "RAHUL@example.com", "current_password": PASSWORD}, format="json")
        self.assertEqual(["That is already your email address."], self.errors(same)["email"])

        bad = client.post(self.URL, {"email": "not-an-address", "current_password": PASSWORD}, format="json")
        self.assertEqual(["The email field must be a valid email address."], self.errors(bad)["email"])

        missing = client.post(self.URL, {}, format="json")
        self.assertEqual({"email", "current_password"}, set(self.errors(missing)))

    def test_the_change_is_audited_without_the_password(self):
        self.client_for(self.teacher).post(self.URL, {"email": "new@example.com", "current_password": PASSWORD}, format="json")

        entry = AuditLog.objects.get(action="user.email_changed")
        self.assertEqual(("rahul@example.com", "new@example.com"), (entry.old_values["email"], entry.new_values["email"]))
        self.assertNotIn(PASSWORD, json.dumps([entry.old_values, entry.new_values]))


# -- the photo -------------------------------------------------------------------


class Photo(ProfileTest):
    URL = PROFILE + "/photo"

    def post_photo(self, user, data, **kwargs):
        return self.client_for(user).post(self.URL, {"photo": upload(data, **kwargs)}, format="multipart")

    def test_a_png_is_stored_and_served_back_to_its_owner(self):
        response = self.post_photo(self.teacher, image_bytes("PNG"))

        self.assertEqual(200, response.status_code, response.data)
        self.assertRegex(response.data["photo_url"], rf"^/users/{self.teacher.id}/photo\?v=[0-9a-f]{{12}}$")

        served = self.client_for(self.teacher).get(f"/api/v1/users/{self.teacher.id}/photo")
        self.assertEqual(200, served.status_code)
        self.assertEqual("image/png", served["Content-Type"])
        self.assertIn("private", served["Cache-Control"])
        self.assertEqual("PNG", Image.open(io.BytesIO(served.content)).format)

    def test_a_large_photo_is_scaled_down_and_a_jpeg_stays_a_jpeg(self):
        self.post_photo(self.teacher, image_bytes("JPEG", size=(2000, 1000)), name="me.jpg", content_type="image/jpeg")

        self.teacher.refresh_from_db()
        self.assertTrue(self.teacher.photo_path.endswith(".jpg"))
        data, content_type = photos.read(self.teacher.photo_path)
        self.assertEqual("image/jpeg", content_type)
        self.assertEqual((512, 256), Image.open(io.BytesIO(data)).size)

    def test_the_location_a_phone_wrote_into_the_photo_is_not_kept(self):
        exif = Image.Exif()
        exif[0x010F] = "PhoneMaker"  # Make
        exif[0x8825] = {2: (18.0, 31.0, 12.0)}  # GPSInfo: a latitude

        self.post_photo(self.teacher, image_bytes("JPEG", exif=exif.tobytes()), name="me.jpg", content_type="image/jpeg")

        self.teacher.refresh_from_db()
        stored = Image.open(io.BytesIO(photos.read(self.teacher.photo_path)[0]))
        self.assertEqual({}, dict(stored.getexif()))

    def test_something_that_is_not_an_image_is_refused_whatever_it_is_called(self):
        response = self.post_photo(self.teacher, b"<script>alert(1)</script>", name="me.png", content_type="image/png")

        self.assertEqual(422, response.status_code)
        self.assertEqual(["The photo must be a JPEG or PNG image."], self.errors(response)["photo"])
        self.teacher.refresh_from_db()
        self.assertIsNone(self.teacher.photo_path)

    def test_an_image_of_another_format_is_refused(self):
        out = io.BytesIO()
        Image.new("RGB", (10, 10)).save(out, format="GIF")

        response = self.post_photo(self.teacher, out.getvalue(), name="me.gif", content_type="image/gif")

        self.assertEqual(["The photo must be a JPEG or PNG image."], self.errors(response)["photo"])

    def test_bytes_hidden_after_the_image_are_not_kept(self):
        smuggled = image_bytes("PNG") + b"<?php system($_GET['c']); ?>"

        self.post_photo(self.teacher, smuggled)

        self.teacher.refresh_from_db()
        self.assertNotIn(b"<?php", photos.read(self.teacher.photo_path)[0])

    def test_a_photo_over_2_mb_is_refused_and_none_is_asked_for(self):
        # A real PNG header padded past the limit: the size is checked before
        # anything is decoded, so nothing that large is ever opened.
        big = image_bytes("PNG") + b"\0" * photos.MAX_BYTES

        response = self.post_photo(self.teacher, big)
        self.assertEqual(422, response.status_code, response.content[:200])
        self.assertEqual(["The photo must be 2 MB or smaller."], self.errors(response)["photo"])

        empty = self.client_for(self.teacher).post(self.URL, {}, format="multipart")
        self.assertEqual(["Choose a photo to upload."], self.errors(empty)["photo"])

    def test_a_new_photo_replaces_the_old_file_and_removing_deletes_it(self):
        self.post_photo(self.teacher, image_bytes("PNG"))
        self.teacher.refresh_from_db()
        first = self.teacher.photo_path

        self.post_photo(self.teacher, image_bytes("PNG", size=(20, 20)))
        self.teacher.refresh_from_db()
        second = self.teacher.photo_path

        self.assertNotEqual(first, second)
        self.assertIsNone(photos.read(first), "the replaced file is gone")

        response = self.client_for(self.teacher).delete(self.URL)
        self.assertIsNone(response.data["photo_url"])
        self.assertIsNone(photos.read(second))
        self.assertEqual(404, self.client_for(self.teacher).get(f"/api/v1/users/{self.teacher.id}/photo").status_code)

    def test_removing_when_there_is_none_is_harmless(self):
        self.assertEqual(200, self.client_for(self.teacher).delete(self.URL).status_code)

    def test_who_may_see_a_photo(self):
        self.post_photo(self.teacher, image_bytes("PNG"))
        url = f"/api/v1/users/{self.teacher.id}/photo"

        self.assertEqual(200, self.client_for(self.admin).get(url).status_code, "their school's admin")
        self.assertEqual(200, self.client_for(self.root).get(url).status_code, "the Super Admin")
        self.assertEqual(404, self.client_for(self.colleague).get(url).status_code, "a colleague")
        self.assertEqual(404, self.client_for(self.stranger).get(url).status_code, "another school's admin")
        self.assertEqual(401, APIClient().get(url).status_code, "nobody signed in")

    def test_a_super_admins_photo_is_not_in_a_school_admins_scope(self):
        self.post_photo(self.root, image_bytes("PNG"))
        url = f"/api/v1/users/{self.root.id}/photo"

        self.assertEqual(200, self.client_for(self.root).get(url).status_code)
        self.assertEqual(404, self.client_for(self.admin).get(url).status_code)

    def test_the_photo_shows_in_me_and_in_the_staff_list(self):
        self.post_photo(self.teacher, image_bytes("PNG"))

        me = self.client_for(self.teacher).get("/api/v1/me").data
        self.assertIsNotNone(me["photo_url"])

        staff = self.client_for(self.admin).get(f"/api/v1/staff/{self.teacher_profile.id}").data
        self.assertEqual(me["photo_url"], staff["photo_url"])

    def test_changing_and_removing_a_photo_is_audited(self):
        self.post_photo(self.teacher, image_bytes("PNG"))
        self.client_for(self.teacher).delete(self.URL)

        self.assertEqual(
            ["profile.photo_changed", "profile.photo_removed"],
            list(AuditLog.objects.filter(action__startswith="profile.photo").order_by("id").values_list("action", flat=True)),
        )


class NothingHereReachesAnotherPerson(ProfileTest):
    def test_the_profile_is_always_the_callers_whatever_the_request_says(self):
        client = self.client_for(self.teacher)

        client.patch(f"{PROFILE}?user_id={self.colleague.id}", {"first_name": "Changed", "id": self.colleague.id}, format="json")

        self.colleague.refresh_from_db()
        self.teacher.refresh_from_db()
        self.assertNotEqual("Changed", self.colleague.first_name)
        self.assertEqual("Changed", self.teacher.first_name)

    def test_a_deactivated_account_cannot_use_its_old_session(self):
        client = self.client_for(self.teacher)
        User.objects.filter(pk=self.teacher.pk).update(status="inactive")

        self.assertIn(client.patch(PROFILE, {"first_name": "X"}, format="json").status_code, (401, 403))


class BusAttendantProfile(ProfileTest):
    def setUp(self):
        super().setUp()
        from school import attendants

        self.attendant = factories.UserFactory(
            school=self.school, role=UserRole.BUS_ATTENDANT, email=attendants.placeholder_email(), mobile="+91 9000000007",
        )

    def test_the_placeholder_is_never_shown_and_the_profile_says_how_they_sign_in(self):
        response = self.client_for(self.attendant).get(PROFILE)

        self.assertEqual((None, False, "passcode"), (
            response.data["email"], response.data["has_email"], response.data["signs_in_with"],
        ))
        teacher = self.client_for(self.teacher).get(PROFILE).data
        self.assertEqual(("rahul@example.com", True, "email"), (teacher["email"], teacher["has_email"], teacher["signs_in_with"]))

    def test_they_cannot_change_an_email_they_have_no_password_for(self):
        response = self.client_for(self.attendant).post(
            PROFILE + "/email", {"email": "ravi@example.com", "current_password": "anything"}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual("Your school office keeps your email address. Ask them to change it.", response.data["message"])

