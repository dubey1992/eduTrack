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

BATCH = {
    "id": "int",
    "school_id": "int",
    "from_academic_year_id": "int",
    "from_academic_year_name": "str",
    "to_academic_year_id": "int",
    "to_academic_year_name": "str",
    "from_class_section_id": "int",
    "from_class_section_name": "str",
    "to_class_section_id": "int?",
    "to_class_section_name": "str?",
    "promoted_count": "int",
    "retained_count": "int",
    "graduated_count": "int",
    "left_count": "int",
    "student_count": "int",
    "run_by_name": "str",
    "run_at": "str",
}

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


class RunningOne(unittest.TestCase):
    """The run writes, so it is given a class of its own.

    Promoting the world's own section would move the students every other
    file in this suite is working with, which is exactly the kind of
    surprise a contract suite must not spring on itself.
    """

    WORLD: world.World | None = None
    SOURCE: dict | None = None
    TARGET_YEAR: dict | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/promotions")
        if probe.status == 404:
            raise unittest.SkipTest("class promotion is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

        tag = uuid.uuid4().hex[:6]
        cls.TARGET_YEAR = cls.year(f"Run {tag}", "2031-04-01", "2032-03-31")

        # This year's class to promote out of, and next year's to land in.
        cls.SOURCE = cls.section(cls.WORLD.academic_year_id, f"Promo {tag}", 8)
        cls.section(cls.TARGET_YEAR["id"], f"Promo up {tag}", 9)

    @classmethod
    def year(cls, name: str, start: str, end: str) -> dict:
        created = cls.WORLD.admin.post(
            "/academic-years",
            {"school_id": cls.WORLD.school_id, "name": name, "start_date": start, "end_date": end},
        )
        assert created.status == 201, f"POST a year for the promotion: {created!r}"

        return created.body

    @classmethod
    def section(cls, year_id: int, name: str, level: int) -> dict:
        school_class = cls.WORLD.admin.post(
            "/classes",
            {"school_id": cls.WORLD.school_id, "academic_year_id": year_id, "name": name, "level": level},
        )
        assert school_class.status == 201, f"POST a class: {school_class!r}"

        created = cls.WORLD.admin.post(f"/classes/{school_class.body['id']}/sections", {"name": "A"})
        assert created.status == 201, f"POST a section: {created!r}"

        return created.body

    @property
    def w(self) -> world.World:
        assert RunningOne.WORLD is not None
        return RunningOne.WORLD

    def admit(self) -> dict:
        response = self.w.admin.post(
            "/students",
            {
                "school_id": self.w.school_id,
                "class_section_id": RunningOne.SOURCE["id"],
                "admission_number": f"PRM-{uuid.uuid4().hex[:8]}",
                "first_name": "Promotion",
                "last_name": "Candidate",
                "guardian_name": "Contract Guardian",
            },
        )
        self.assertEqual(201, response.status, f"POST /students: {response!r}")

        return response.body

    def promote(self, student, outcome: str = "promote", client=None, **overrides):
        body = {
            "class_section_id": RunningOne.SOURCE["id"],
            "to_academic_year_id": RunningOne.TARGET_YEAR["id"],
            "outcomes": [{"student_id": student["id"], "outcome": outcome}],
        }
        body.update(overrides)

        return (client or self.w.admin).post("/promotions", body)

    def test_a_class_moves_up_and_the_batch_reads_back(self):
        student = self.admit()

        response = self.promote(student)

        self.assertEqual(201, response.status, f"POST /promotions: {response!r}")
        shapes.assert_shape(self, response.body, BATCH, "POST /promotions")
        self.assertEqual(1, response.body["promoted_count"])
        self.assertEqual(1, response.body["student_count"])

        # The student's own history now covers both years.
        history = self.w.admin.get(f"/students/{student['id']}/enrollments").body
        self.assertEqual(2, len(history), f"{history!r}")
        self.assertEqual({"promoted", "studying"}, {row["status"] for row in history})

        # And the batch reads back student by student.
        one = self.w.admin.get(f"/promotions/{response.body['id']}")
        self.assertEqual(200, one.status, f"{one!r}")
        self.assertEqual(1, len(one.body["students"]))
        self.assertEqual("promoted", one.body["students"][0]["outcome"])

        listed = self.w.admin.get("/promotions")
        shapes.assert_paginated(self, listed, "GET /promotions")
        self.assertIn(response.body["id"], [row["id"] for row in listed.data])

    def test_a_graduated_student_keeps_the_record_and_loses_the_class(self):
        student = self.admit()

        response = self.promote(student, outcome="graduate")

        self.assertEqual(201, response.status, f"{response!r}")
        self.assertEqual(1, response.body["graduated_count"])

        after = self.w.admin.get(f"/students/{student['id']}").body
        self.assertEqual("graduated", after["status"])
        self.assertIsNone(after["class_section_id"])

    def test_a_student_who_is_not_in_the_class_refuses_the_whole_batch(self):
        student = self.admit()

        response = self.promote(student, outcomes=[{"student_id": 99999999, "outcome": "promote"}])

        shapes.assert_error(self, response, 409, "POST a batch naming somebody else's student")
        self.assertEqual("ROSTER_CHANGED", response.body["code"])

    def test_the_same_batch_twice_is_refused(self):
        student = self.admit()
        self.assertEqual(201, self.promote(student).status)

        again = self.promote(student)

        shapes.assert_error(self, again, 409, "POST the same batch twice")
        self.assertEqual("ALREADY_ENROLLED", again.body["code"])

    def test_a_batch_that_names_nobody_is_refused_by_field(self):
        response = self.w.admin.post(
            "/promotions",
            {
                "class_section_id": RunningOne.SOURCE["id"],
                "to_academic_year_id": RunningOne.TARGET_YEAR["id"],
                "outcomes": [],
            },
        )

        shapes.assert_validation_error(self, response, "outcomes", "POST a promotion of nobody")

    def test_another_school_may_not_run_one(self):
        student = self.admit()

        response = self.promote(student, client=self.w.other_admin)

        self.assertEqual(403, response.status, f"{response!r}")

    def test_a_teacher_may_not_run_one(self):
        staff_client = self.w.staff_client

        if staff_client is None:
            self.skipTest("the world has no teacher client")

        student = self.admit()

        self.assertEqual(403, self.promote(student, client=staff_client).status)
