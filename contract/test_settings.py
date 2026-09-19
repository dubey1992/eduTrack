"""Module settings and the permissions matrix - served by the Python backend
only (docs/settings.md).

Against Laravel these skip. Against Django they check the shapes the Module
Settings and Permissions screens read, that /me carries what the app gates
on, and that a School Admin cannot edit the platform's matrix or another
school's modules.
"""

from __future__ import annotations

import unittest

import coverage
import shapes
import world

MODULE = {
    "module": "str",
    "label": "str",
    "switchable": "bool",
    "platform_enabled": "bool",
    "school_enabled": "bool",
    "enabled": "bool",
    "can_change_platform": "bool",
    "settings": "dict",
    "settings_schema": "list",
}

MATRIX = {"roles": "list", "modules": "list", "levels": "list", "matrix": "dict", "defaults": "dict", "can_edit": "bool"}


class Settings(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/settings/modules")
        if probe.status == 404:
            raise unittest.SkipTest("module settings are served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert Settings.WORLD is not None
        return Settings.WORLD

    def test_me_carries_permissions_and_modules(self):
        me = self.w.admin.get("/me")
        self.assertEqual(200, me.status, f"{me!r}")
        self.assertIn("permissions", me.body)
        self.assertIn("modules", me.body)
        self.assertEqual("manage", me.body["permissions"]["students"])
        self.assertTrue(me.body["modules"]["attendance"])

    def test_a_school_admin_reads_and_switches_their_own_modules_only(self):
        listed = self.w.admin.get("/settings/modules")
        self.assertEqual(200, listed.status, f"{listed!r}")
        for row in listed.body:
            shapes.assert_shape(self, row, MODULE, "a module setting")

        # Off, then on again - and the API refuses the module in between.
        off = self.w.admin.put("/settings/modules/syllabus", {"school_enabled": False})
        self.assertEqual(200, off.status, f"{off!r}")
        self.assertFalse(off.body["enabled"])
        self.assertEqual(403, self.w.admin.get("/syllabus-topics", subject_id=1).status)

        on = self.w.admin.put("/settings/modules/syllabus", {"school_enabled": True})
        self.assertTrue(on.body["enabled"])

        # The platform switch is not theirs, and neither is another school.
        self.assertEqual(422, self.w.admin.put("/settings/modules/syllabus", {"platform_enabled": False}).status)
        self.assertEqual(403, self.w.other_admin.get("/settings/modules", school_id=self.w.school_id).status)

    def test_the_matrix_is_readable_by_admins_and_edited_by_the_super_admin(self):
        read = self.w.admin.get("/settings/permissions")
        self.assertEqual(200, read.status, f"{read!r}")
        shapes.assert_shape(self, read.body, MATRIX, "GET /settings/permissions")
        self.assertFalse(read.body["can_edit"])

        self.assertEqual(403, self.w.admin.put("/settings/permissions", {"matrix": {"TEACHER": {"students": "manage"}}}).status)

        saved = self.w.super_admin.put("/settings/permissions", {"matrix": {"STAFF": {"timetable": "none"}}})
        self.assertEqual(200, saved.status, f"{saved!r}")
        self.assertEqual("none", saved.body["matrix"]["STAFF"]["timetable"])

        # Put back, so the world is left as it was found.
        restored = self.w.super_admin.post("/settings/permissions/reset")
        self.assertEqual(200, restored.status, f"{restored!r}")
        self.assertEqual(restored.body["defaults"]["STAFF"]["timetable"], restored.body["matrix"]["STAFF"]["timetable"])
