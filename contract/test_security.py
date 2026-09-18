"""Audit and security (Phase 21) - served by the Python backend only.

Laravel was frozen before Phase 21 (docs/python-migration.md), so against it
these are skipped rather than failed. Against Django they check the shapes
the Flutter audit, devices and unlock screens read, and that one school's
admin reads none of another school's audit trail.
"""

from __future__ import annotations

import unittest

import coverage
import shapes
import world
from client import sign_in

AUDIT_ENTRY = {
    "id": "int",
    "created_at": "str",
    "created_at_label": "str",
    "school_id": "int?",
    "user_id": "int?",
    "module": "str",
    "action": "str",
    "entity_type": "str",
    "entity_id": "int?",
    "ip": "str?",
}

SESSION = {"id": "int", "device": "str", "signed_in_label": "str?", "last_used_label": "str?", "current": "bool"}


class Security(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/audit-logs")
        if probe.status == 404:
            raise unittest.SkipTest("audit and security are served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert Security.WORLD is not None
        return Security.WORLD

    def test_the_audit_log_lists_and_opens_entries_of_the_admins_own_school(self):
        listed = self.w.admin.get("/audit-logs")
        shapes.assert_paginated(self, listed, "GET /audit-logs")
        self.assertTrue(listed.data, "the world's own set-up should have left entries behind")

        for row in listed.data:
            shapes.assert_shape(self, row, AUDIT_ENTRY, "an audit entry")
            self.assertEqual(self.w.school_id, row["school_id"])

        one = self.w.admin.get(f"/audit-logs/{listed.data[0]['id']}")
        self.assertEqual(200, one.status, f"{one!r}")
        shapes.assert_shape(self, one.body, AUDIT_ENTRY, "GET /audit-logs/{entry}")

        # Another school's admin cannot open it: out of scope is not found.
        self.assertEqual(404, self.w.other_admin.get(f"/audit-logs/{listed.data[0]['id']}").status)

    def test_a_person_sees_and_ends_their_own_sessions(self):
        here = sign_in(self.w.staff_email, world.TEST_PASSWORD)
        there = sign_in(self.w.staff_email, world.TEST_PASSWORD)

        sessions = here.get("/auth/sessions")
        self.assertEqual(200, sessions.status, f"{sessions!r}")
        for row in sessions.body["data"]:
            shapes.assert_shape(self, row, SESSION, "a signed-in session")
        self.assertEqual(1, sum(row["current"] for row in sessions.body["data"]))

        theirs = [row["id"] for row in there.get("/auth/sessions").body["data"] if row["current"]][0]
        self.assertEqual(200, here.delete(f"/auth/sessions/{theirs}").status)
        self.assertEqual(401, there.get("/me").status)

        ended = here.post("/auth/sessions/others")
        self.assertEqual(200, ended.status, f"{ended!r}")
        self.assertEqual(200, here.get("/me").status)

    def test_an_admin_unlocks_an_account_of_their_own_school_only(self):
        unlocked = self.w.admin.post(f"/users/{self.w.staff_user_id}/unlock")
        self.assertEqual(200, unlocked.status, f"{unlocked!r}")
        self.assertIsNone(unlocked.body["locked_until"])

        self.assertEqual(403, self.w.other_admin.post(f"/users/{self.w.staff_user_id}/unlock").status)
