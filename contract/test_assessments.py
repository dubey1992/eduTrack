"""Class tests - served by the Python backend only (docs/assessments.md).

Against Laravel these skip. Against Django they walk the path the Class Tests
screen depends on, and the two refusals that matter most: a test whose pieces
do not belong together, and a teacher reaching a class that is not theirs.
"""

from __future__ import annotations

import unittest
import uuid

import coverage
import shapes
import world

ASSESSMENT = {
    "id": "int",
    "school_id": "int",
    "academic_year_id": "int",
    "academic_term_id": "int",
    "term_name": "str",
    "class_section_id": "int",
    "class_section_name": "str",
    "subject_id": "int",
    "subject_name": "str",
    "syllabus_topic_id": "int?",
    "syllabus_topic_title": "str?",
    "grade_scale_id": "int?",
    "grade_scale_name": "str?",
    "type": "str",
    "title": "str",
    "max_marks": "str",
    "pass_marks": "str?",
    "weightage": "str?",
    "assessment_date": "str",
    "status": "str",
    "created_by_name": "str",
    "published_at": "str?",
}


class Assessments(unittest.TestCase):
    WORLD: world.World | None = None
    TERM: dict | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/assessments")
        if probe.status == 404:
            raise unittest.SkipTest("class tests are served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

        # A term of the world's own year, which every test here files under.
        created = cls.WORLD.admin.post(
            "/academic-terms",
            {
                "academic_year_id": cls.WORLD.academic_year_id,
                "name": f"Term {uuid.uuid4().hex[:4]}",
                "sequence_number": 9,
                "start_date": "2026-04-01",
                "end_date": "2027-03-31",
            },
        )
        assert created.status == 201, f"POST a term for the assessments: {created!r}"
        cls.TERM = created.body

    @property
    def w(self) -> world.World:
        assert Assessments.WORLD is not None
        return Assessments.WORLD

    @property
    def term(self) -> dict:
        assert Assessments.TERM is not None
        return Assessments.TERM

    def payload(self, **overrides) -> dict:
        body = {
            "class_section_id": self.w.class_section_id,
            "subject_id": self.w.subject_id,
            "academic_term_id": self.term["id"],
            "type": "class_test",
            "title": f"Contract test {uuid.uuid4().hex[:6]}",
            "max_marks": "20",
            "assessment_date": "2026-07-15",
        }
        body.update(overrides)

        return body

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}\n{response!r}")
        return response.body

    def test_a_test_is_created_read_changed_and_removed(self):
        assessment = self.created(self.w.admin.post("/assessments", self.payload()), "POST /assessments")
        shapes.assert_shape(self, assessment, ASSESSMENT, "POST /assessments")

        self.assertEqual("draft", assessment["status"], "everything starts as a draft")
        self.assertEqual("20.00", assessment["max_marks"])
        self.assertIsNone(assessment["published_at"])

        listed = self.w.admin.get("/assessments", class_section_id=self.w.class_section_id)
        shapes.assert_paginated(self, listed, "GET /assessments")
        self.assertIn(assessment["id"], [row["id"] for row in listed.data])

        one = self.w.admin.get(f"/assessments/{assessment['id']}")
        self.assertEqual(200, one.status, f"{one!r}")

        renamed = self.w.admin.patch(f"/assessments/{assessment['id']}", {"title": "Renamed"})
        self.assertEqual(200, renamed.status, f"{renamed!r}")
        self.assertEqual("Renamed", renamed.body["title"])

        removed = self.w.admin.delete(f"/assessments/{assessment['id']}")
        self.assertEqual(204, removed.status, f"{removed!r}")
        self.assertEqual(404, self.w.admin.get(f"/assessments/{assessment['id']}").status)

    def test_a_test_out_of_nothing_is_refused_by_field(self):
        response = self.w.admin.post("/assessments", self.payload(max_marks="0"))

        shapes.assert_validation_error(self, response, "max_marks", "POST a test out of zero")

    def test_a_date_outside_the_term_is_refused_by_field(self):
        response = self.w.admin.post("/assessments", self.payload(assessment_date="2030-01-01"))

        shapes.assert_validation_error(self, response, "assessment_date", "POST a test outside its term")

    def test_a_pass_mark_above_the_maximum_is_refused(self):
        response = self.w.admin.post("/assessments", self.payload(max_marks="20", pass_marks="30"))

        shapes.assert_validation_error(self, response, "pass_marks", "POST an unreachable pass mark")

    def test_a_teacher_may_not_set_a_test_for_a_class_they_do_not_teach(self):
        staff_client = self.w.staff_client

        if staff_client is None:
            self.skipTest("the world has no teacher client")

        response = staff_client.post("/assessments", self.payload())

        self.assertIn(response.status, (403, 422), f"a teacher outside the class must not succeed\n{response!r}")

    def test_a_result_is_published_frozen_and_taken_back(self):
        assessment = self.created(self.w.admin.post("/assessments", self.payload()), "POST /assessments")
        marks_url = f"/assessments/{assessment['id']}/marks"

        entries = self.w.admin.get(marks_url).body["entries"]
        self.w.admin.put(
            marks_url,
            {"marks": [{"student_id": row["student_id"], "marks_obtained": "18"} for row in entries]},
        )

        published = self.w.admin.post(f"/assessments/{assessment['id']}/publish")
        self.assertEqual(200, published.status, f"{published!r}")
        self.assertEqual("published", published.body["status"])
        self.assertIsNotNone(published.body["published_at"])

        # Closed: the marks may be read and not written.
        self.assertEqual(200, self.w.admin.get(marks_url).status)
        refused = self.w.admin.put(marks_url, {"marks": [{"student_id": entries[0]["student_id"], "marks_obtained": "1"}]})
        shapes.assert_error(self, refused, 409, "PUT marks on a published test")
        self.assertEqual("ASSESSMENT_PUBLISHED", refused.body["code"])

        reopened = self.w.admin.post(f"/assessments/{assessment['id']}/reopen")
        self.assertEqual(200, reopened.status, f"{reopened!r}")
        self.assertEqual("draft", reopened.body["status"])
        self.assertIsNone(reopened.body["published_at"])

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_a_class_with_anybody_unmarked_is_not_published(self):
        assessment = self.created(self.w.admin.post("/assessments", self.payload()), "POST /assessments")

        refused = self.w.admin.post(f"/assessments/{assessment['id']}/publish")

        shapes.assert_error(self, refused, 422, "POST publish with an unmarked class")
        self.assertEqual("MARKS_INCOMPLETE", refused.body["code"])

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_another_school_reaches_none_of_it(self):
        assessment = self.created(self.w.admin.post("/assessments", self.payload()), "POST /assessments")
        stranger = self.w.other_admin

        self.assertEqual(403, stranger.get(f"/assessments/{assessment['id']}").status)
        self.assertEqual(403, stranger.patch(f"/assessments/{assessment['id']}", {"title": "Mine"}).status)
        self.assertEqual(403, stranger.delete(f"/assessments/{assessment['id']}").status)
        self.assertNotIn(assessment["id"], [row["id"] for row in stranger.get("/assessments").data])

        # Nor may they name this school's section on a test of their own.
        refused = stranger.post("/assessments", self.payload())
        shapes.assert_validation_error(self, refused, "class_section_id", "POST into another school's class")

        self.w.admin.delete(f"/assessments/{assessment['id']}")
