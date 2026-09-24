"""Enrollment history - served by the Python backend only (docs/promotion.md).

Against Laravel these skip. Against Django they check the one thing the
history has to get right without being asked: the row follows the student.
Admitting a student writes the year, moving them between sections moves the
row rather than adding a second one, and another school reaches none of it.
"""

from __future__ import annotations

import unittest
import uuid

import coverage
import shapes
import world

ENROLLMENT = {
    "id": "int",
    "academic_year_id": "int",
    "academic_year_name": "str",
    "school_class_id": "int",
    "class_name": "str",
    "class_section_id": "int?",
    "section_name": "str?",
    "roll_number": "str?",
    "status": "str",
}


class Enrollments(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get(f"/students/{cls.WORLD.student_id}/enrollments")
        if probe.status == 404:
            raise unittest.SkipTest("enrollment history is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

        # Another file in this suite may have made a different year current
        # by the time this one runs, and a section belonging to a year that
        # is not current is not where a student is *now*. Pin the world's own
        # year back, so what is being tested is the history rather than the
        # order the files happened to run in.
        cls.WORLD.admin.patch(f"/academic-years/{cls.WORLD.academic_year_id}/set-current", {})

    @property
    def w(self) -> world.World:
        assert Enrollments.WORLD is not None
        return Enrollments.WORLD

    def admit(self, **overrides) -> dict:
        body = {
            "school_id": self.w.school_id,
            "class_section_id": self.w.class_section_id,
            "admission_number": f"ENR-{uuid.uuid4().hex[:8]}",
            "first_name": "Contract",
            "last_name": "Student",
            "guardian_name": "Contract Guardian",
            "roll_number": "7",
        }
        body.update(overrides)

        response = self.w.admin.post("/students", body)
        self.assertEqual(201, response.status, f"POST /students\n{response!r}")

        return response.body

    def history(self, student_id: int, client=None):
        response = (client or self.w.admin).get(f"/students/{student_id}/enrollments")
        self.assertEqual(200, response.status, f"GET /students/{{student}}/enrollments\n{response!r}")

        return response.body

    def test_admitting_a_student_records_the_year_and_the_shape_is_right(self):
        student = self.admit()

        rows = self.history(student["id"])

        self.assertEqual(1, len(rows), f"one row for the year they arrived in: {rows!r}")
        shapes.assert_shape(self, rows[0], ENROLLMENT, "GET /students/{student}/enrollments")
        self.assertEqual("studying", rows[0]["status"])
        self.assertEqual("7", rows[0]["roll_number"])
        self.assertEqual(self.w.class_section_id, rows[0]["class_section_id"])

    def test_moving_a_student_moves_the_row_rather_than_adding_one(self):
        student = self.admit()

        renumbered = self.w.admin.patch(f"/students/{student['id']}", {"roll_number": "21"})
        self.assertEqual(200, renumbered.status, f"{renumbered!r}")

        rows = self.history(student["id"])
        self.assertEqual(1, len(rows))
        self.assertEqual("21", rows[0]["roll_number"])

    def test_another_school_reaches_none_of_it(self):
        student = self.admit()

        refused = self.w.other_admin.get(f"/students/{student['id']}/enrollments")

        self.assertEqual(403, refused.status, f"{refused!r}")

    def test_a_student_that_does_not_exist_is_a_404(self):
        self.assertEqual(404, self.w.admin.get("/students/99999999/enrollments").status)
