"""My Profile - served by the Python backend only (docs/profile.md).

Against Laravel these skip. Against Django they check the shape the Flutter
profile screen reads, that a person changes only themselves, that a photo
goes in and comes back as an image, and that another school's admin cannot
see it.
"""

from __future__ import annotations

import base64
import unittest

import coverage
import shapes
import world

PROFILE = {
    "id": "int",
    "first_name": "str",
    "last_name": "str",
    "name": "str",
    "email": "str",
    "mobile": "str?",
    "role": "str",
    "role_label": "str",
    "photo_url": "str?",
    "has_staff_record": "bool",
    "address": "str?",
}

# A 1x1 PNG, so the suite needs no image library.
TINY_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
)


class Profile(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.staff_client.get("/profile")
        if probe.status == 404:
            raise unittest.SkipTest("my profile is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert Profile.WORLD is not None
        return Profile.WORLD

    def test_a_member_of_staff_reads_and_changes_their_own_details(self):
        read = self.w.staff_client.get("/profile")
        self.assertEqual(200, read.status, f"{read!r}")
        shapes.assert_shape(self, read.body, PROFILE, "GET /profile")
        self.assertTrue(read.body["has_staff_record"])

        changed = self.w.staff_client.patch("/profile", {"mobile": "+91 9123456789", "address": "Contract Lane 1"})
        self.assertEqual(200, changed.status, f"{changed!r}")
        self.assertEqual(("+91 9123456789", "Contract Lane 1"), (changed.body["mobile"], changed.body["address"]))

        # Admin-only fields are not reachable, however the body is edited.
        self.w.staff_client.patch("/profile", {"role": "SCHOOL_ADMIN", "first_name": read.body["first_name"]})
        self.assertEqual(read.body["role"], self.w.staff_client.get("/profile").body["role"])

        refused = self.w.staff_client.patch("/profile", {"mobile": "12"})
        shapes.assert_validation_error(self, refused, "mobile", "PATCH /profile with a bad mobile")

    def test_changing_email_needs_the_current_password(self):
        refused = self.w.staff_client.post("/profile/email", {"email": "someone.else@example.invalid", "current_password": "wrong"})
        shapes.assert_validation_error(self, refused, "current_password", "POST /profile/email, wrong password")

    def test_a_photo_goes_in_comes_back_and_stays_private(self):
        uploaded = self.w.staff_client.upload("/profile/photo", "photo", "me.png", TINY_PNG, "image/png")
        self.assertEqual(200, uploaded.status, f"{uploaded!r}")
        self.assertIsNotNone(uploaded.body["photo_url"])

        path = uploaded.body["photo_url"]
        status, body, content_type = self.w.staff_client.get_bytes(path)
        self.assertEqual((200, "image/png"), (status, content_type.split(";")[0]))
        self.assertTrue(body.startswith(b"\x89PNG"))

        self.assertEqual(200, self.w.admin.get_bytes(path)[0], "their school's admin")
        self.assertEqual(404, self.w.other_admin.get_bytes(path)[0], "another school's admin")

        not_an_image = self.w.staff_client.upload("/profile/photo", "photo", "me.png", b"not an image", "image/png")
        shapes.assert_validation_error(self, not_an_image, "photo", "POST /profile/photo with text")

        removed = self.w.staff_client.delete("/profile/photo")
        self.assertEqual(200, removed.status, f"{removed!r}")
        self.assertIsNone(removed.body["photo_url"])
