"""Academic configuration: the things a school sets up before anybody teaches.

Years, departments, subjects, classes, sections, periods, holidays. Everything
else in the product hangs off these - a student belongs to a section, a
timetable entry to a period, an attendance record to a working day - so they are
ported first in the Python rewrite and asserted first here.

Each module gets the same five questions, because they are the ones a rewrite
gets wrong: does the list paginate, does the record come back whole, can it be
created, can it be changed, and can somebody in another school touch it.
"""

from __future__ import annotations

import unittest

import shapes
import world


class AcademicTest(unittest.TestCase):
    """One school, built once for the whole file."""

    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        if AcademicTest.WORLD is None:
            AcademicTest.WORLD = world.build()

    @property
    def w(self) -> world.World:
        assert AcademicTest.WORLD is not None
        return AcademicTest.WORLD

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}: expected HTTP 201\n{response!r}")
        return response.body


class AcademicYears(AcademicTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/academic-years")

        shapes.assert_paginated(self, response, "GET /academic-years")
        for year in response.data:
            shapes.assert_shape(self, year, shapes.ACADEMIC_YEAR, "an academic year in the list")

    def test_a_year_can_be_created_read_and_changed(self):
        created = self.created(
            self.w.admin.post(
                "/academic-years",
                {
                    "school_id": self.w.school_id,
                    "name": "2027-28",
                    "start_date": "2027-04-01",
                    "end_date": "2028-03-31",
                },
            ),
            "POST /academic-years",
        )
        shapes.assert_shape(self, created, shapes.ACADEMIC_YEAR, "POST /academic-years")

        read = self.w.admin.get(f"/academic-years/{created['id']}")
        self.assertEqual(200, read.status, f"GET a year\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.ACADEMIC_YEAR, "GET /academic-years/{id}")

        changed = self.w.admin.patch(f"/academic-years/{created['id']}", {"name": "2027-28 revised"})
        self.assertEqual(200, changed.status, f"PATCH a year\n{changed!r}")
        self.assertEqual("2027-28 revised", changed.body["name"])

    def test_only_one_year_is_current_at_a_time(self):
        # The rule the rest of the product leans on: "the current year" has to
        # mean exactly one row, or every screen that resolves it silently picks
        # whichever came back first.
        created = self.created(
            self.w.admin.post(
                "/academic-years",
                {
                    "school_id": self.w.school_id,
                    "name": "2028-29",
                    "start_date": "2028-04-01",
                    "end_date": "2029-03-31",
                },
            ),
            "POST a year to promote",
        )

        promoted = self.w.admin.patch(f"/academic-years/{created['id']}/set-current")
        self.assertEqual(200, promoted.status, f"PATCH set-current\n{promoted!r}")
        self.assertTrue(promoted.body["is_current"])

        current = [y for y in self.w.admin.get("/academic-years").data if y["is_current"]]
        self.assertEqual(1, len(current), f"exactly one year may be current, found {len(current)}")

    def test_a_year_can_be_deleted(self):
        created = self.created(
            self.w.admin.post(
                "/academic-years",
                {
                    "school_id": self.w.school_id,
                    "name": "2029-30",
                    "start_date": "2029-04-01",
                    "end_date": "2030-03-31",
                },
            ),
            "POST a year to delete",
        )

        removed = self.w.admin.delete(f"/academic-years/{created['id']}")
        self.assertIn(removed.status, (200, 204), f"DELETE a year\n{removed!r}")
        shapes.assert_error(self, self.w.admin.get(f"/academic-years/{created['id']}"), 404, "the deleted year")

    def test_another_school_cannot_read_this_years(self):
        mine = self.w.admin.get("/academic-years").data
        self.assertGreaterEqual(len(mine), 1)

        response = self.w.other_admin.get(f"/academic-years/{mine[0]['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Departments(AcademicTest):
    def test_the_list_is_paginated_and_shaped(self):
        shapes.assert_paginated(self, self.w.admin.get("/departments"), "GET /departments")

    def test_a_department_can_be_created_read_changed_and_deleted(self):
        created = self.created(
            self.w.admin.post("/departments", {"school_id": self.w.school_id, "name": "Science"}),
            "POST /departments",
        )
        shapes.assert_shape(self, created, shapes.DEPARTMENT, "POST /departments")

        read = self.w.admin.get(f"/departments/{created['id']}")
        self.assertEqual(200, read.status, f"GET a department\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.DEPARTMENT, "GET /departments/{id}")

        changed = self.w.admin.patch(f"/departments/{created['id']}", {"name": "Natural Science"})
        self.assertEqual(200, changed.status, f"PATCH a department\n{changed!r}")
        self.assertEqual("Natural Science", changed.body["name"])

        removed = self.w.admin.delete(f"/departments/{created['id']}")
        self.assertIn(removed.status, (200, 204), f"DELETE a department\n{removed!r}")

    def test_a_duplicate_name_is_refused(self):
        payload = {"school_id": self.w.school_id, "name": "Humanities"}
        self.assertEqual(201, self.w.admin.post("/departments", payload).status)

        shapes.assert_validation_error(self, self.w.admin.post("/departments", payload), "name", "a duplicate department")

    def test_another_school_cannot_read_this_departments(self):
        created = self.created(
            self.w.admin.post("/departments", {"school_id": self.w.school_id, "name": "Isolated"}),
            "POST a department",
        )

        response = self.w.other_admin.get(f"/departments/{created['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Subjects(AcademicTest):
    def test_the_list_is_paginated_and_shaped(self):
        shapes.assert_paginated(self, self.w.admin.get("/subjects"), "GET /subjects")

    def test_a_subject_can_be_created_read_changed_and_deleted(self):
        created = self.created(
            self.w.admin.post(
                "/subjects",
                {
                    "school_id": self.w.school_id,
                    "department_id": self.w.department_id,
                    "code": "MATH",
                    "name": "Mathematics",
                    "min_class_level": 1,
                    "max_class_level": 12,
                },
            ),
            "POST /subjects",
        )
        shapes.assert_shape(self, created, shapes.SUBJECT, "POST /subjects")

        read = self.w.admin.get(f"/subjects/{created['id']}")
        self.assertEqual(200, read.status, f"GET a subject\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.SUBJECT, "GET /subjects/{id}")

        changed = self.w.admin.patch(f"/subjects/{created['id']}", {"name": "Further Mathematics"})
        self.assertEqual(200, changed.status, f"PATCH a subject\n{changed!r}")
        self.assertEqual("Further Mathematics", changed.body["name"])

        removed = self.w.admin.delete(f"/subjects/{created['id']}")
        self.assertIn(removed.status, (200, 204), f"DELETE a subject\n{removed!r}")

    def test_another_school_cannot_read_this_subjects(self):
        created = self.created(
            self.w.admin.post(
                "/subjects",
                {
                    "school_id": self.w.school_id,
                    "department_id": self.w.department_id,
                    "code": "ISO",
                    "name": "Isolation",
                    "min_class_level": 1,
                    "max_class_level": 12,
                },
            ),
            "POST a subject",
        )

        response = self.w.other_admin.get(f"/subjects/{created['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class ClassesAndSections(AcademicTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/classes")

        shapes.assert_paginated(self, response, "GET /classes")
        for school_class in response.data:
            shapes.assert_shape(self, school_class, shapes.SCHOOL_CLASS, "a class in the list")

    def test_a_class_carries_its_sections(self):
        # The client renders class and section together; a class that forgets
        # its sections renders as an empty year group.
        response = self.w.admin.get(f"/classes/{self.w.school_class_id}")

        self.assertEqual(200, response.status, f"GET a class\n{response!r}")
        shapes.assert_shape(self, response.body, shapes.SCHOOL_CLASS, "GET /classes/{id}")
        self.assertGreaterEqual(len(response.body["sections"]), 1, "the world gave this class a section")

        for section in response.body["sections"]:
            shapes.assert_shape(self, section, shapes.CLASS_SECTION, "a section on a class")

    def test_a_class_can_be_created_changed_and_deleted_with_its_sections(self):
        created = self.created(
            self.w.admin.post(
                "/classes",
                {
                    "school_id": self.w.school_id,
                    "academic_year_id": self.w.academic_year_id,
                    "name": "Grade 9",
                    "level": 9,
                },
            ),
            "POST /classes",
        )
        shapes.assert_shape(self, created, shapes.SCHOOL_CLASS, "POST /classes")

        section = self.created(
            self.w.admin.post(f"/classes/{created['id']}/sections", {"name": "B", "room_number": "12"}),
            "POST a section",
        )
        shapes.assert_shape(self, section, shapes.CLASS_SECTION, "POST /classes/{id}/sections")

        changed = self.w.admin.patch(f"/sections/{section['id']}", {"room_number": "14"})
        self.assertEqual(200, changed.status, f"PATCH a section\n{changed!r}")
        self.assertEqual("14", changed.body["room_number"])

        self.assertIn(self.w.admin.delete(f"/sections/{section['id']}").status, (200, 204))

        changed_class = self.w.admin.patch(f"/classes/{created['id']}", {"name": "Grade 9 (upper)"})
        self.assertEqual(200, changed_class.status, f"PATCH a class\n{changed_class!r}")

        self.assertIn(self.w.admin.delete(f"/classes/{created['id']}").status, (200, 204))

    def test_another_school_cannot_read_this_classes(self):
        response = self.w.other_admin.get(f"/classes/{self.w.school_class_id}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Periods(AcademicTest):
    def test_the_list_is_shaped(self):
        response = self.w.admin.get("/periods")

        self.assertEqual(200, response.status, f"GET /periods\n{response!r}")
        for period in response.data:
            shapes.assert_shape(self, period, shapes.PERIOD, "a period in the list")

    def test_a_period_can_be_created_changed_and_deleted(self):
        created = self.created(
            self.w.admin.post(
                "/periods",
                {
                    "school_id": self.w.school_id,
                    "period_number": 7,
                    "start_time": "14:00",
                    "end_time": "14:45",
                },
            ),
            "POST /periods",
        )
        shapes.assert_shape(self, created, shapes.PERIOD, "POST /periods")

        changed = self.w.admin.patch(f"/periods/{created['id']}", {"end_time": "14:50"})
        self.assertEqual(200, changed.status, f"PATCH a period\n{changed!r}")

        self.assertIn(self.w.admin.delete(f"/periods/{created['id']}").status, (200, 204))


class Holidays(AcademicTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/holidays")

        shapes.assert_paginated(self, response, "GET /holidays")
        for holiday in response.data:
            shapes.assert_shape(self, holiday, shapes.HOLIDAY, "a holiday in the list")

    def test_a_holiday_can_be_created_read_changed_and_deleted(self):
        created = self.created(
            self.w.admin.post(
                "/holidays",
                {
                    "school_id": self.w.school_id,
                    "name": "Founders Day",
                    "type": "school_event",
                    "start_date": "2026-11-02",
                    "end_date": "2026-11-02",
                },
            ),
            "POST /holidays",
        )
        shapes.assert_shape(self, created, shapes.HOLIDAY, "POST /holidays")
        self.assertEqual(1, created["days"], "a one-day holiday is one day")

        read = self.w.admin.get(f"/holidays/{created['id']}")
        self.assertEqual(200, read.status, f"GET a holiday\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.HOLIDAY, "GET /holidays/{id}")

        changed = self.w.admin.patch(f"/holidays/{created['id']}", {"end_date": "2026-11-03"})
        self.assertEqual(200, changed.status, f"PATCH a holiday\n{changed!r}")
        self.assertEqual(2, changed.body["days"], "extending by a day makes it two days")

        self.assertIn(self.w.admin.delete(f"/holidays/{created['id']}").status, (200, 204))

    def test_another_school_cannot_read_this_holidays(self):
        created = self.created(
            self.w.admin.post(
                "/holidays",
                {
                    "school_id": self.w.school_id,
                    "name": "Isolated Day",
                    "type": "school_event",
                    "start_date": "2026-12-01",
                    "end_date": "2026-12-01",
                },
            ),
            "POST a holiday",
        )

        response = self.w.other_admin.get(f"/holidays/{created['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Timezones(AcademicTest):
    def test_the_timezone_list_is_offered(self):
        # Every school picks one of these at onboarding, and the client renders
        # the list verbatim - so it has to be a list of strings, not of objects
        # the picker cannot read.
        response = self.w.super_admin.get("/timezones")

        self.assertEqual(200, response.status, f"GET /timezones\n{response!r}")
        zones = response.data
        self.assertIsInstance(zones, list)
        self.assertGreater(len(zones), 0, "a school has to be able to choose one")


if __name__ == "__main__":
    unittest.main(verbosity=2)
