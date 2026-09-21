"""Grade scales - served by the Python backend only (docs/assessments.md).

Against Laravel these skip. Against Django they walk the path the Grade
Scales screen depends on: a scale is created with its bands, the bands come
back highest first, a set with a hole in it is refused by field, and the
school's default cannot be deleted out from under it.
"""

from __future__ import annotations

import unittest
import uuid

import coverage
import shapes
import world

SCALE = {
    "id": "int",
    "school_id": "int",
    "school_name": "str?",
    "name": "str",
    "is_default": "bool",
    "bands": "list",
}

BAND = {
    "id": "int",
    "label": "str",
    "min_percentage": "str",
    "max_percentage": "str",
    "is_failing": "bool",
}


def band(label: str, low, high, failing: bool = False) -> dict:
    return {"label": label, "min_percentage": low, "max_percentage": high, "is_failing": failing}


PASS_FAIL = [band("Pass", 33, 100), band("Fail", 0, 32, failing=True)]


class GradeScales(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/grade-scales")
        if probe.status == 404:
            raise unittest.SkipTest("grade scales are served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert GradeScales.WORLD is not None
        return GradeScales.WORLD

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}\n{response!r}")
        return response.body

    def make_scale(self, bands=None, **overrides) -> dict:
        body = {"school_id": self.w.school_id, "name": f"Scale {uuid.uuid4().hex[:6]}", "bands": bands or PASS_FAIL}
        body.update(overrides)

        return self.created(self.w.admin.post("/grade-scales", body), "POST /grade-scales")

    def test_a_scale_is_created_read_changed_and_removed(self):
        scale = self.make_scale()
        shapes.assert_shape(self, scale, SCALE, "POST /grade-scales")
        for row in scale["bands"]:
            shapes.assert_shape(self, row, BAND, "a band of a scale")

        # Highest band first, so a screen can print them as a school reads them.
        self.assertEqual(["Pass", "Fail"], [row["label"] for row in scale["bands"]])
        self.assertEqual("33.00", scale["bands"][0]["min_percentage"])

        listed = self.w.admin.get("/grade-scales")
        shapes.assert_paginated(self, listed, "GET /grade-scales")
        self.assertIn(scale["id"], [row["id"] for row in listed.data])

        one = self.w.admin.get(f"/grade-scales/{scale['id']}")
        self.assertEqual(200, one.status, f"{one!r}")

        # A PUT replaces the bands as a set: three go in, three come back.
        replaced = self.w.admin.put(
            f"/grade-scales/{scale['id']}",
            {
                "name": scale["name"],
                "bands": [band("A", 61, 100), band("B", 33, 60), band("C", 0, 32, failing=True)],
            },
        )
        self.assertEqual(200, replaced.status, f"{replaced!r}")
        self.assertEqual(["A", "B", "C"], [row["label"] for row in replaced.body["bands"]])

        # Not the default, so it may go. (The first scale this school ever
        # made is the default, and this is not it.)
        removed = self.w.admin.delete(f"/grade-scales/{scale['id']}")
        self.assertEqual(204, removed.status, f"{removed!r}")
        self.assertEqual(404, self.w.admin.get(f"/grade-scales/{scale['id']}").status)

    def test_a_set_of_bands_with_a_hole_in_it_is_refused_by_field(self):
        response = self.w.admin.post(
            "/grade-scales",
            {"school_id": self.w.school_id, "name": f"Holey {uuid.uuid4().hex[:4]}", "bands": [band("Pass", 33, 100)]},
        )

        shapes.assert_validation_error(self, response, "bands.0.min_percentage", "POST bands starting above zero")

    def test_overlapping_bands_are_refused(self):
        response = self.w.admin.post(
            "/grade-scales",
            {
                "school_id": self.w.school_id,
                "name": f"Overlap {uuid.uuid4().hex[:4]}",
                "bands": [band("Pass", 32, 100), band("Fail", 0, 32)],
            },
        )

        shapes.assert_validation_error(self, response, "bands.0.min_percentage", "POST overlapping bands")

    def test_a_scale_needs_at_least_one_band(self):
        response = self.w.admin.post(
            "/grade-scales", {"school_id": self.w.school_id, "name": f"Empty {uuid.uuid4().hex[:4]}", "bands": []}
        )

        shapes.assert_validation_error(self, response, "bands", "POST a scale with no bands")

    def test_the_default_cannot_be_deleted_while_another_remains(self):
        default = self.w.admin.get("/grade-scales").data[0]
        self.assertTrue(default["is_default"], "the default sorts first")
        self.make_scale()

        refused = self.w.admin.delete(f"/grade-scales/{default['id']}")

        shapes.assert_error(self, refused, 409, "DELETE the school's default scale")

    def test_another_school_reaches_none_of_it(self):
        scale = self.make_scale()
        stranger = self.w.other_admin

        self.assertEqual(403, stranger.get(f"/grade-scales/{scale['id']}").status)
        self.assertEqual(
            403, stranger.put(f"/grade-scales/{scale['id']}", {"name": "Mine", "bands": PASS_FAIL}).status
        )
        self.assertEqual(403, stranger.delete(f"/grade-scales/{scale['id']}").status)
        self.assertNotIn(scale["id"], [row["id"] for row in stranger.get("/grade-scales").data])
