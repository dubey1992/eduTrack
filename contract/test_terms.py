"""Academic terms - served by the Python backend only (docs/assessments.md).

Against Laravel these skip. Against Django they walk the path the Terms dialog
depends on: a term is created inside its year, a second one may touch it but
not overlap it, the year it belongs to is fixed, and a year with terms under
it cannot be deleted.
"""

from __future__ import annotations

import unittest
import uuid

import coverage
import shapes
import world

TERM = {
    "id": "int",
    "school_id": "int",
    "academic_year_id": "int",
    "academic_year_name": "str?",
    "name": "str",
    "sequence_number": "int",
    "start_date": "str",
    "end_date": "str",
}


class Terms(unittest.TestCase):
    WORLD: world.World | None = None
    YEAR: dict | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/academic-terms")
        if probe.status == 404:
            raise unittest.SkipTest("academic terms are served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

    @property
    def w(self) -> world.World:
        assert Terms.WORLD is not None
        return Terms.WORLD

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}\n{response!r}")
        return response.body

    def make_year(self, start: str, end: str) -> dict:
        """A year of its own per test, so one test's terms are never in
        another's way."""
        return self.created(
            self.w.admin.post(
                "/academic-years",
                {
                    "school_id": self.w.school_id,
                    "name": f"Y{uuid.uuid4().hex[:6]}",
                    "start_date": start,
                    "end_date": end,
                },
            ),
            "POST /academic-years",
        )

    def test_a_term_is_created_read_changed_and_removed(self):
        year = self.make_year("2030-04-01", "2031-03-31")

        term = self.created(
            self.w.admin.post(
                "/academic-terms",
                {
                    "academic_year_id": year["id"],
                    "name": "Term 1",
                    "sequence_number": 1,
                    "start_date": "2030-04-01",
                    "end_date": "2030-08-31",
                },
            ),
            "POST /academic-terms",
        )
        shapes.assert_shape(self, term, TERM, "POST /academic-terms")
        self.assertEqual(self.w.school_id, term["school_id"])

        listed = self.w.admin.get("/academic-terms", academic_year_id=year["id"])
        shapes.assert_paginated(self, listed, "GET /academic-terms")
        self.assertEqual([term["id"]], [row["id"] for row in listed.data])

        one = self.w.admin.get(f"/academic-terms/{term['id']}")
        self.assertEqual(200, one.status, f"{one!r}")
        shapes.assert_shape(self, one.body, TERM, "GET /academic-terms/{term}")

        renamed = self.w.admin.patch(f"/academic-terms/{term['id']}", {"name": "First Term"})
        self.assertEqual(200, renamed.status, f"{renamed!r}")
        self.assertEqual("First Term", renamed.body["name"])

        removed = self.w.admin.delete(f"/academic-terms/{term['id']}")
        self.assertEqual(204, removed.status, f"{removed!r}")
        self.assertEqual(404, self.w.admin.get(f"/academic-terms/{term['id']}").status)

    def test_terms_may_touch_but_not_overlap(self):
        year = self.make_year("2031-04-01", "2032-03-31")
        first = {
            "academic_year_id": year["id"],
            "name": "Term 1",
            "sequence_number": 1,
            "start_date": "2031-04-01",
            "end_date": "2031-08-31",
        }
        self.created(self.w.admin.post("/academic-terms", first), "POST the first term")

        overlapping = self.w.admin.post(
            "/academic-terms",
            {**first, "name": "Term 2", "sequence_number": 2, "start_date": "2031-08-31", "end_date": "2031-12-31"},
        )
        shapes.assert_validation_error(self, overlapping, "start_date", "POST an overlapping term")

        touching = self.w.admin.post(
            "/academic-terms",
            {**first, "name": "Term 2", "sequence_number": 2, "start_date": "2031-09-01", "end_date": "2031-12-31"},
        )
        self.assertEqual(201, touching.status, f"{touching!r}")

    def test_a_term_must_sit_inside_its_year(self):
        year = self.make_year("2032-04-01", "2033-03-31")

        response = self.w.admin.post(
            "/academic-terms",
            {
                "academic_year_id": year["id"],
                "name": "Term 1",
                "sequence_number": 1,
                "start_date": "2032-03-01",
                "end_date": "2032-08-31",
            },
        )

        shapes.assert_validation_error(self, response, "start_date", "POST a term before its year")

    def test_a_year_with_terms_cannot_be_deleted(self):
        year = self.make_year("2033-04-01", "2034-03-31")
        self.created(
            self.w.admin.post(
                "/academic-terms",
                {
                    "academic_year_id": year["id"],
                    "name": "Term 1",
                    "sequence_number": 1,
                    "start_date": "2033-04-01",
                    "end_date": "2033-08-31",
                },
            ),
            "POST a term",
        )

        refused = self.w.admin.delete(f"/academic-years/{year['id']}")

        shapes.assert_error(self, refused, 409, "DELETE a year that still has terms")

    def test_another_school_reaches_none_of_it(self):
        year = self.make_year("2034-04-01", "2035-03-31")
        term = self.created(
            self.w.admin.post(
                "/academic-terms",
                {
                    "academic_year_id": year["id"],
                    "name": "Term 1",
                    "sequence_number": 1,
                    "start_date": "2034-04-01",
                    "end_date": "2034-08-31",
                },
            ),
            "POST a term",
        )

        stranger = self.w.other_admin

        self.assertEqual(403, stranger.get(f"/academic-terms/{term['id']}").status)
        self.assertEqual(403, stranger.patch(f"/academic-terms/{term['id']}", {"name": "Mine"}).status)
        self.assertEqual(403, stranger.delete(f"/academic-terms/{term['id']}").status)
        self.assertNotIn(term["id"], [row["id"] for row in stranger.get("/academic-terms").data])

        # The year itself is not nameable from outside either, so a term
        # cannot be created into somebody else's year.
        refused = stranger.post(
            "/academic-terms",
            {
                "academic_year_id": year["id"],
                "name": "Term 9",
                "sequence_number": 9,
                "start_date": "2034-04-01",
                "end_date": "2034-08-31",
            },
        )
        shapes.assert_validation_error(self, refused, "academic_year_id", "POST into another school's year")

    def test_a_missing_field_is_named(self):
        year = self.make_year("2035-04-01", "2036-03-31")

        response = self.w.admin.post("/academic-terms", {"academic_year_id": year["id"]})

        shapes.assert_validation_error(self, response, "name", "POST a term with nothing in it")
