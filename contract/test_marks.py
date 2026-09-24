"""The marks sheet - served by the Python backend only (docs/assessments.md).

Against Laravel these skip. Against Django they check the three facts the
marks screen is built on: the whole class comes back whether or not anybody
has been marked, the whole sheet saves in one write, and a mark the test
cannot hold is refused by the row it came from.
"""

from __future__ import annotations

import unittest
import uuid

import coverage
import shapes
import world

HEADINGS = "admission_number,student_name,marks,absent,remarks"


def file_of(*rows: str) -> bytes:
    """A marks file: the headings, then the rows."""
    return ("\n".join([HEADINGS, *rows]) + "\n").encode("utf-8")

ENTRY = {
    "student_id": "int",
    "student_name": "str",
    "admission_number": "str",
    "roll_number": "str?",
    "marks_obtained": "str?",
    "is_absent": "bool",
    "grade": "str?",
    "remarks": "str?",
}


class Marks(unittest.TestCase):
    WORLD: world.World | None = None
    TERM: dict | None = None

    @classmethod
    def setUpClass(cls):
        cls.WORLD = world.shared()

        probe = cls.WORLD.admin.get("/assessments")
        if probe.status == 404:
            raise unittest.SkipTest("the marks sheet is served by the Python backend only")

        coverage.PYTHON_ONLY_SERVED = True

        # A term of the world's year, reusing whichever one is already there:
        # terms may not overlap, and another file in this suite makes one that
        # covers the whole year.
        existing = cls.WORLD.admin.get("/academic-terms", academic_year_id=cls.WORLD.academic_year_id)

        if existing.data:
            cls.TERM = existing.data[0]
        else:
            created = cls.WORLD.admin.post(
                "/academic-terms",
                {
                    "academic_year_id": cls.WORLD.academic_year_id,
                    "name": f"Marks {uuid.uuid4().hex[:4]}",
                    "sequence_number": 8,
                    "start_date": "2026-04-01",
                    "end_date": "2027-03-31",
                },
            )
            assert created.status == 201, f"POST a term for the marks sheet: {created!r}"
            cls.TERM = created.body

    @property
    def w(self) -> world.World:
        assert Marks.WORLD is not None
        return Marks.WORLD

    def make_assessment(self, **overrides) -> dict:
        body = {
            "class_section_id": self.w.class_section_id,
            "subject_id": self.w.subject_id,
            "academic_term_id": Marks.TERM["id"],
            "type": "class_test",
            "title": f"Marks {uuid.uuid4().hex[:6]}",
            "max_marks": "20",
            "assessment_date": "2026-07-15",
        }
        body.update(overrides)

        response = self.w.admin.post("/assessments", body)
        self.assertEqual(201, response.status, f"POST /assessments\n{response!r}")

        return response.body

    def test_the_sheet_reads_the_whole_class_and_saves_in_one_write(self):
        assessment = self.make_assessment()
        url = f"/assessments/{assessment['id']}/marks"

        sheet = self.w.admin.get(url)
        self.assertEqual(200, sheet.status, f"{sheet!r}")
        self.assertTrue(sheet.body["entries"], "the class reads back before anybody is marked")

        for row in sheet.body["entries"]:
            shapes.assert_shape(self, row, ENTRY, "a row of the marks sheet")
            self.assertIsNone(row["marks_obtained"])

        first = sheet.body["entries"][0]["student_id"]
        saved = self.w.admin.put(url, {"marks": [{"student_id": first, "marks_obtained": "17.5"}]})

        self.assertEqual(200, saved.status, f"{saved!r}")
        marked = next(row for row in saved.body["entries"] if row["student_id"] == first)
        self.assertEqual("17.50", marked["marks_obtained"])
        self.assertIs(False, marked["is_absent"])

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_absent_is_not_zero(self):
        assessment = self.make_assessment()
        url = f"/assessments/{assessment['id']}/marks"
        student = self.w.admin.get(url).body["entries"][0]["student_id"]

        saved = self.w.admin.put(url, {"marks": [{"student_id": student, "is_absent": True}]})

        row = next(entry for entry in saved.body["entries"] if entry["student_id"] == student)
        self.assertIs(True, row["is_absent"])
        self.assertIsNone(row["marks_obtained"])

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_a_mark_the_test_cannot_hold_is_refused_by_row(self):
        assessment = self.make_assessment()
        url = f"/assessments/{assessment['id']}/marks"
        student = self.w.admin.get(url).body["entries"][0]["student_id"]

        response = self.w.admin.put(url, {"marks": [{"student_id": student, "marks_obtained": "99"}]})

        shapes.assert_validation_error(self, response, "marks.0.marks_obtained", "PUT a mark above the maximum")

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_the_maximum_is_locked_once_anybody_is_marked(self):
        assessment = self.make_assessment()
        url = f"/assessments/{assessment['id']}/marks"
        student = self.w.admin.get(url).body["entries"][0]["student_id"]
        self.w.admin.put(url, {"marks": [{"student_id": student, "marks_obtained": "10"}]})

        refused = self.w.admin.patch(f"/assessments/{assessment['id']}", {"max_marks": "50"})

        shapes.assert_error(self, refused, 422, "PATCH the total after marking")
        self.assertEqual("MAX_MARKS_LOCKED", refused.body["code"])

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_the_roster_downloads_and_a_filled_in_file_comes_back(self):
        assessment = self.make_assessment()
        base = f"/assessments/{assessment['id']}/marks"

        status, raw, _ = self.w.admin.get_bytes(f"{base}/template")
        self.assertEqual(200, status)
        text = raw.decode("utf-8-sig")
        self.assertIn("admission_number,student_name,marks,absent,remarks", text)

        # The roster comes filled in, so a file can be built from the template
        # itself rather than typed from scratch.
        rows = [line for line in text.splitlines()[1:] if line.strip()]
        self.assertTrue(rows, "the class is on the template")

        admission_number = rows[0].split(",")[0]
        filled = file_of(f"{admission_number},Student,15,,")

        uploaded = self.w.admin.upload(f"{base}/import", "file", "marks.csv", filled, "text/csv")

        self.assertEqual(200, uploaded.status, f"{uploaded!r}")
        marked = next(row for row in uploaded.body["entries"] if row["admission_number"] == admission_number)
        self.assertEqual("15.00", marked["marks_obtained"])

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_a_file_the_test_cannot_hold_is_refused_row_by_row(self):
        assessment = self.make_assessment()
        base = f"/assessments/{assessment['id']}/marks"
        admission_number = self.w.admin.get(base).body["entries"][0]["admission_number"]
        filled = file_of(f"{admission_number},Student,99,,")

        refused = self.w.admin.upload(f"{base}/import", "file", "marks.csv", filled, "text/csv")

        shapes.assert_error(self, refused, 422, "POST a file with a mark above the maximum")
        self.assertEqual("BULK_IMPORT_FAILED", refused.body["code"])
        self.assertEqual(2, refused.body["details"]["rows"][0]["row"], "the heading is row 1")

        self.w.admin.delete(f"/assessments/{assessment['id']}")

    def test_another_school_reaches_neither_the_sheet_nor_the_saving(self):
        assessment = self.make_assessment()
        url = f"/assessments/{assessment['id']}/marks"
        stranger = self.w.other_admin

        self.assertEqual(403, stranger.get(url).status)
        self.assertEqual(403, stranger.put(url, {"marks": []}).status)

        self.w.admin.delete(f"/assessments/{assessment['id']}")
