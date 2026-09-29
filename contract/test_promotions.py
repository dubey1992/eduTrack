"""The promotion preview - served by the Python backend only
(docs/promotion.md).

Against Laravel these skip. Against Django they check the three things the
promotion wizard is built on: the roster comes back with a default per
student and nothing is written, a pairing that makes no sense is refused by
code rather than by a generic error, and a section belonging to somebody
else is out of reach whatever ids are sent with the request.
"""

from __future__ import annotations

import unittest
import uuid

import coverage
import shapes
import world

PREVIEW_STUDENT = {
    "student_id": "int",
    "name": "str",
    "admission_number": "str",
    "roll_number": "str?",
    "status": "str",
    "default_outcome": "str",
    "is_blocked": "bool",
    "blocked_reason": "str?",
    "average_percentage": "str?",
    "suggested_outcome": "str?",
    "suggestion_reason": "str?",
}


class PromotionPreview(unittest.TestCase):
    WORLD: world.World | None = None
    NEXT_YEAR: dict | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get(
            "/promotions/preview",
            class_section_id=cls.WORLD.class_section_id,
            to_academic_year_id=cls.WORLD.academic_year_id,
        )
        if probe.status == 404 and probe.body.get("code") != "TARGET_YEAR_NOT_FOUND":
            raise unittest.SkipTest("class promotion is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

        # A year to promote into. Never made current: the world's own year is
        # the one every other file in this suite is working in.
        created = cls.WORLD.admin.post(
            "/academic-years",
            {
                "school_id": cls.WORLD.school_id,
                "name": f"Promo {uuid.uuid4().hex[:6]}",
                "start_date": "2030-04-01",
                "end_date": "2031-03-31",
            },
        )
        assert created.status == 201, f"POST a year to promote into: {created!r}"
        cls.NEXT_YEAR = created.body

    @property
    def w(self) -> world.World:
        assert PromotionPreview.WORLD is not None
        return PromotionPreview.WORLD

    @property
    def next_year(self) -> dict:
        assert PromotionPreview.NEXT_YEAR is not None
        return PromotionPreview.NEXT_YEAR

    def ask(self, client=None, **params):
        query = {
            "class_section_id": self.w.class_section_id,
            "to_academic_year_id": self.next_year["id"],
        }
        query.update(params)

        return (client or self.w.admin).get("/promotions/preview", **query)

    def test_the_roster_comes_back_with_a_default_for_every_student(self):
        response = self.ask()

        self.assertEqual(200, response.status, f"GET /promotions/preview\n{response!r}")
        self.assertEqual(self.w.class_section_id, response.body["from"]["class_section_id"])
        self.assertEqual(self.next_year["id"], response.body["to"]["academic_year_id"])
        self.assertIn("can_run", response.body)
        self.assertIn(response.body["cannot_run_reason"], (None, "NOTHING_TO_PROMOTE"))

        for row in response.body["students"]:
            shapes.assert_shape(self, row, PREVIEW_STUDENT, "a row of the promotion preview")
            self.assertIn(row["default_outcome"], ("promote", "retain", "graduate", "leave"))
            # A suggestion is only ever to hold a child back, and never the
            # default: that decision belongs to a person.
            self.assertIn(row["suggested_outcome"], (None, "retain"))

    def test_the_preview_writes_nothing(self):
        students = self.ask().body["students"]

        if not students:
            self.skipTest("the world's section is empty, so there is nothing to have written")

        student_id = students[0]["student_id"]
        before = self.w.admin.get(f"/students/{student_id}/enrollments").body

        self.ask()

        self.assertEqual(before, self.w.admin.get(f"/students/{student_id}/enrollments").body)

    def test_promoting_into_the_same_year_is_refused_by_code(self):
        response = self.ask(to_academic_year_id=self.w.academic_year_id)

        shapes.assert_error(self, response, 422, "GET a preview into the year it is already in")
        self.assertEqual("SAME_ACADEMIC_YEAR", response.body["code"])

    def test_a_year_that_is_not_this_school_s_is_not_found(self):
        response = self.ask(to_academic_year_id=99999999)

        shapes.assert_error(self, response, 404, "GET a preview into a year that does not exist")
        self.assertEqual("TARGET_YEAR_NOT_FOUND", response.body["code"])

    def test_a_target_section_outside_the_target_year_is_refused(self):
        response = self.ask(to_class_section_id=self.w.class_section_id)

        shapes.assert_error(self, response, 422, "GET a preview into a section of the wrong year")
        self.assertEqual("TARGET_SECTION_MISMATCH", response.body["code"])

    def test_a_section_that_does_not_exist_is_a_field_error(self):
        response = self.ask(class_section_id=99999999)

        shapes.assert_validation_error(self, response, "class_section_id", "GET a preview of nothing")

    def test_another_school_reaches_none_of_it(self):
        response = self.ask(client=self.w.other_admin)

        self.assertEqual(403, response.status, f"a preview of another school's class\n{response!r}")

    def test_a_teacher_may_not_preview_a_promotion(self):
        staff_client = self.w.staff_client

        if staff_client is None:
            self.skipTest("the world has no teacher client")

        response = self.ask(client=staff_client)

        self.assertEqual(403, response.status, f"a teacher previewing a promotion\n{response!r}")
