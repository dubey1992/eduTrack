"""The week's grid, over HTTP.

Three rules do the work here:

**One slice at a time.** The grid is read by class section or by teacher, and
asking for both at once is refused rather than silently resolved - they are
two different questions.

**Somebody else's grid is a 404.** The id comes from a query string, so an
actor outside that school learns nothing, not even that it is real. That is
the one place this module answers 404 where the rest of the product answers
403, and it is deliberate.

**Nobody teaches two classes at once.** The table's unique key guards one
class section's grid; a teacher standing in two rooms at the same time is a
collision between two of them, and only the service can see it.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import TimetableEntry


class TimetableTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(school=self.school)
        self.school_class = factories.SchoolClassFactory(
            school=self.school, academic_year=self.year, name="Grade 8"
        )
        self.section = factories.ClassSectionFactory(
            school_class=self.school_class, name="A"
        )
        self.other_section = factories.ClassSectionFactory(
            school_class=self.school_class, name="B"
        )

        self.department = factories.DepartmentFactory(school=self.school, name="Science")
        self.maths = factories.SubjectFactory(
            school=self.school, department=self.department, name="Mathematics"
        )
        self.first = factories.PeriodFactory(school=self.school, period_number=1)
        self.second = factories.PeriodFactory(school=self.school, period_number=2)

        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def cell(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "class_section_id": self.section.id,
            "period_id": self.first.id,
            "day_of_week": "monday",
            "subject_id": self.maths.id,
            "teacher_id": self.teacher.id,
        }
        body.update(overrides)

        return body

    # -- writing a cell -----------------------------------------------------

    def test_a_cell_is_created_with_the_names_the_grid_draws(self):
        response = self.client.post("/api/v1/timetable", self.cell(), format="json")

        self.assertEqual(201, response.status_code)
        self.assertEqual("Grade 8 A", response.data["class_section_name"])
        self.assertEqual(1, response.data["period_number"])
        self.assertEqual("Mathematics", response.data["subject_name"])
        self.assertEqual(self.teacher.name, response.data["teacher_name"])
        self.assertEqual("monday", response.data["day_of_week"])

    def test_writing_the_same_cell_twice_replaces_it(self):
        physics = factories.SubjectFactory(
            school=self.school, department=self.department, name="Physics"
        )

        first = self.client.post("/api/v1/timetable", self.cell(), format="json")
        second = self.client.post(
            "/api/v1/timetable", self.cell(subject_id=physics.id), format="json"
        )

        self.assertEqual(first.data["id"], second.data["id"])
        self.assertEqual("Physics", second.data["subject_name"])
        self.assertEqual(1, TimetableEntry.objects.count())

    def test_a_teacher_cannot_be_in_two_rooms_at_once(self):
        self.client.post("/api/v1/timetable", self.cell(), format="json")

        response = self.client.post(
            "/api/v1/timetable",
            self.cell(class_section_id=self.other_section.id),
            format="json",
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("TEACHER_SCHEDULE_CONFLICT", response.data["code"])

    def test_the_same_teacher_may_take_the_next_period(self):
        self.client.post("/api/v1/timetable", self.cell(), format="json")

        response = self.client.post(
            "/api/v1/timetable",
            self.cell(class_section_id=self.other_section.id, period_id=self.second.id),
            format="json",
        )

        self.assertEqual(201, response.status_code)

    def test_an_empty_cell_names_every_missing_field(self):
        response = self.client.post("/api/v1/timetable", {}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["class_section_id", "period_id", "day_of_week", "subject_id", "teacher_id"],
            list(response.data["details"]["errors"]),
        )

    def test_a_weekend_is_not_a_day_of_the_school_week(self):
        response = self.client.post(
            "/api/v1/timetable", self.cell(day_of_week="sunday"), format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("day_of_week", response.data["details"]["errors"])

    def test_another_schools_period_subject_and_teacher_are_all_invalid(self):
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.TEACHER)

        response = self.client.post(
            "/api/v1/timetable",
            self.cell(
                period_id=factories.PeriodFactory(school=elsewhere).id,
                subject_id=factories.SubjectFactory(
                    school=elsewhere,
                    department=factories.DepartmentFactory(school=elsewhere),
                ).id,
                teacher_id=stranger.id,
            ),
            format="json",
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["period_id", "subject_id", "teacher_id"],
            list(response.data["details"]["errors"]),
        )

    def test_an_admin_account_is_not_a_name_for_a_timetable_cell(self):
        response = self.client.post(
            "/api/v1/timetable", self.cell(teacher_id=self.admin.id), format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("teacher_id", response.data["details"]["errors"])

    def test_a_teacher_cannot_edit_the_grid(self):
        response = self.as_user(self.teacher).post(
            "/api/v1/timetable", self.cell(), format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_an_admin_cannot_write_into_another_school(self):
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(
            school=elsewhere, role=UserRole.SCHOOL_ADMIN
        )

        response = self.as_user(stranger).post(
            "/api/v1/timetable", self.cell(), format="json"
        )

        # The school_id they sent is ignored in favour of their own, so every
        # other id in the payload then belongs to a school they cannot reach.
        self.assertEqual(422, response.status_code)

    # -- reading the grid ---------------------------------------------------

    def test_the_grid_is_a_bare_list(self):
        self.client.post("/api/v1/timetable", self.cell(), format="json")

        response = self.client.get(
            f"/api/v1/timetable?class_section_id={self.section.id}"
        )

        self.assertEqual(200, response.status_code)
        self.assertIsInstance(response.data, list)
        self.assertEqual(1, len(response.data))

    def test_the_grid_can_be_sliced_by_teacher_instead(self):
        self.client.post("/api/v1/timetable", self.cell(), format="json")
        self.client.post(
            "/api/v1/timetable",
            self.cell(class_section_id=self.other_section.id, period_id=self.second.id),
            format="json",
        )

        response = self.as_user(self.teacher).get(
            f"/api/v1/timetable?teacher_id={self.teacher.id}"
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(2, len(response.data))

    def test_one_slice_or_the_other_but_not_neither(self):
        response = self.client.get("/api/v1/timetable")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["class_section_id", "teacher_id"], list(response.data["details"]["errors"])
        )

    def test_one_slice_or_the_other_but_not_both(self):
        response = self.client.get(
            f"/api/v1/timetable?class_section_id={self.section.id}"
            f"&teacher_id={self.teacher.id}"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn(
            "prohibits", response.data["details"]["errors"]["class_section_id"][0]
        )

    def test_an_id_that_is_not_there_is_refused(self):
        response = self.client.get("/api/v1/timetable?class_section_id=999999")

        self.assertEqual(422, response.status_code)

    def test_another_schools_grid_is_not_found_rather_than_forbidden(self):
        # 404 and not 403: the id was named in a query string, and a stranger
        # should not learn that it is real.
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)

        response = self.as_user(stranger).get(
            f"/api/v1/timetable?class_section_id={self.section.id}"
        )

        self.assertEqual(404, response.status_code)

    def test_another_schools_teacher_is_not_found_either(self):
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)

        response = self.as_user(stranger).get(
            f"/api/v1/timetable?teacher_id={self.teacher.id}"
        )

        self.assertEqual(404, response.status_code)

    def test_a_teacher_reads_the_grid_of_their_own_school(self):
        self.client.post("/api/v1/timetable", self.cell(), format="json")

        response = self.as_user(self.teacher).get(
            f"/api/v1/timetable?class_section_id={self.section.id}"
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(1, len(response.data))

    # -- removing a cell ----------------------------------------------------

    def test_a_cell_can_be_cleared(self):
        created = self.client.post("/api/v1/timetable", self.cell(), format="json")

        response = self.client.delete(f"/api/v1/timetable/{created.data['id']}")

        self.assertEqual(204, response.status_code)
        self.assertEqual(0, TimetableEntry.objects.count())

    def test_a_teacher_cannot_clear_a_cell(self):
        created = self.client.post("/api/v1/timetable", self.cell(), format="json")

        response = self.as_user(self.teacher).delete(
            f"/api/v1/timetable/{created.data['id']}"
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual(1, TimetableEntry.objects.count())

    def test_an_admin_cannot_clear_another_schools_cell(self):
        created = self.client.post("/api/v1/timetable", self.cell(), format="json")
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)

        response = self.as_user(stranger).delete(
            f"/api/v1/timetable/{created.data['id']}"
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual(1, TimetableEntry.objects.count())

    def test_a_super_admin_reaches_any_school(self):
        super_admin = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        entry = factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            period=self.first,
            subject=self.maths,
            teacher=self.teacher,
        )

        read = self.as_user(super_admin).get(
            f"/api/v1/timetable?class_section_id={self.section.id}"
        )
        removed = self.as_user(super_admin).delete(f"/api/v1/timetable/{entry.id}")

        self.assertEqual(1, len(read.data))
        self.assertEqual(204, removed.status_code)

    def test_a_cell_that_is_not_there_is_a_404(self):
        response = self.client.delete("/api/v1/timetable/999999")

        self.assertEqual(404, response.status_code)

    def test_a_cell_carries_nothing_extra(self):
        created = self.client.post("/api/v1/timetable", self.cell(), format="json")

        self.assertEqual(
            {
                "id", "school_id", "class_section_id", "class_section_name",
                "period_id", "period_number", "day_of_week", "subject_id",
                "subject_name", "teacher_id", "teacher_name",
            },
            set(created.data),
        )
