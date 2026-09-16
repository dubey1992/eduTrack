"""Classes, sections, periods and holidays, over HTTP.

Four modules that finish M9's academic configuration. The awkward ones:

- A **section** has no school of its own and reaches one through its class, so
  its policy cannot use the shared school-owned shape. A policy that silently
  read a missing `school_id` as None would allow everything for a scope that
  permits None, which is the worst failure available here.
- A **holiday** reports what it broke. Declaring one after the fact is a
  legitimate correction; doing it silently is not.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import ClassSection, Holiday, Period, SchoolClass


class AcademicTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(school=self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client


class Classes(AcademicTest):
    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "academic_year_id": self.year.id,
            "name": "Grade 8",
            "level": 8,
        }
        body.update(overrides)

        return body

    def test_a_class_is_created_with_an_empty_section_list(self):
        response = self.client.post("/api/v1/classes", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Grade 8", response.data["name"])
        self.assertEqual(self.year.name, response.data["academic_year_name"])
        self.assertEqual([], response.data["sections"])

    def test_the_name_is_unique_within_the_year_not_the_school(self):
        # "Grade 8" exists again next year and is a different class.
        self.client.post("/api/v1/classes", self.payload(), format="json")

        same_year = self.client.post("/api/v1/classes", self.payload(), format="json")
        self.assertEqual(422, same_year.status_code, same_year.data)
        self.assertEqual(
            "The name has already been taken.", same_year.data["details"]["errors"]["name"][0]
        )

        next_year = factories.AcademicYearFactory(school=self.school, name="The Year After")
        other = self.client.post(
            "/api/v1/classes", self.payload(academic_year_id=next_year.id), format="json"
        )
        self.assertEqual(201, other.status_code, other.data)

    def test_a_year_from_another_school_is_refused(self):
        elsewhere = factories.AcademicYearFactory(school=factories.SchoolFactory())

        response = self.client.post(
            "/api/v1/classes", self.payload(academic_year_id=elsewhere.id), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("academic_year_id", response.data["details"]["errors"])

    def test_a_level_outside_the_school_years_is_refused(self):
        response = self.client.post("/api/v1/classes", self.payload(level=13), format="json")

        self.assertEqual(
            "The level field must not be greater than 12.",
            response.data["details"]["errors"]["level"][0],
        )

    def test_the_list_filters_by_academic_year(self):
        mine = self.client.post("/api/v1/classes", self.payload(), format="json")
        next_year = factories.AcademicYearFactory(school=self.school, name="The Year After")
        self.client.post(
            "/api/v1/classes", self.payload(academic_year_id=next_year.id), format="json"
        )

        response = self.client.get(f"/api/v1/classes?academic_year_id={self.year.id}")

        self.assertEqual([mine.data["id"]], [row["id"] for row in response.data["data"]])

    def test_a_class_with_sections_cannot_be_deleted(self):
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school)
        factories.ClassSectionFactory(school_class=school_class)

        response = self.client.delete(f"/api/v1/classes/{school_class.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("HAS_DEPENDENT_RECORDS", response.data["code"])
        self.assertTrue(SchoolClass.objects.filter(pk=school_class.id).exists())

    def test_an_empty_class_can_be_deleted(self):
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school)

        self.assertEqual(204, self.client.delete(f"/api/v1/classes/{school_class.id}").status_code)
        self.assertFalse(SchoolClass.objects.filter(pk=school_class.id).exists())


class Sections(AcademicTest):
    def setUp(self):
        super().setUp()
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school
        )

    def test_a_section_is_added_to_a_class(self):
        response = self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections",
            {"name": "A", "room_number": "12"},
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("A", response.data["name"])
        self.assertEqual("12", response.data["room_number"])
        self.assertEqual(self.school_class.id, response.data["school_class_id"])

    def test_a_class_carries_its_sections(self):
        self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections", {"name": "A"}, format="json"
        )
        self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections", {"name": "B"}, format="json"
        )

        response = self.client.get(f"/api/v1/classes/{self.school_class.id}")

        self.assertEqual(["A", "B"], [s["name"] for s in response.data["sections"]])

    def test_a_teacher_can_be_given_the_class(self):
        response = self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections",
            {"name": "A", "class_teacher_id": self.teacher.id},
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.teacher.name, response.data["class_teacher_name"])

    def test_a_teacher_from_another_school_cannot(self):
        outsider = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.TEACHER)

        response = self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections",
            {"name": "A", "class_teacher_id": outsider.id},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("class_teacher_id", response.data["details"]["errors"])

    def test_the_name_is_unique_within_the_class(self):
        self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections", {"name": "A"}, format="json"
        )

        response = self.client.post(
            f"/api/v1/classes/{self.school_class.id}/sections", {"name": "A"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The name has already been taken.", response.data["details"]["errors"]["name"][0]
        )

    def test_a_section_with_students_cannot_be_deleted(self):
        section = factories.ClassSectionFactory(school_class=self.school_class)
        factories.StudentFactory(school=self.school, class_section=section)

        response = self.client.delete(f"/api/v1/sections/{section.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("HAS_DEPENDENT_RECORDS", response.data["code"])
        self.assertTrue(ClassSection.objects.filter(pk=section.id).exists())

    def test_an_empty_section_can_be_deleted(self):
        section = factories.ClassSectionFactory(school_class=self.school_class)

        self.assertEqual(204, self.client.delete(f"/api/v1/sections/{section.id}").status_code)

    def test_an_admin_from_another_school_reaches_neither(self):
        # The section has no school_id of its own, so this is the check that
        # its policy resolves one through the class rather than reading a
        # missing attribute as None.
        section = factories.ClassSectionFactory(school_class=self.school_class)
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(
            403,
            outsider.patch(f"/api/v1/sections/{section.id}", {"name": "Z"}, format="json").status_code,
        )
        self.assertEqual(403, outsider.delete(f"/api/v1/sections/{section.id}").status_code)
        self.assertTrue(ClassSection.objects.filter(pk=section.id).exists())

    def test_a_teacher_may_not_add_a_section(self):
        response = self.as_user(self.teacher).post(
            f"/api/v1/classes/{self.school_class.id}/sections", {"name": "Z"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)


class Periods(AcademicTest):
    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "period_number": 1,
            "start_time": "09:00",
            "end_time": "09:45",
        }
        body.update(overrides)

        return body

    def test_a_period_is_created(self):
        response = self.client.post("/api/v1/periods", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("09:00", response.data["start_time"])
        self.assertEqual("09:45", response.data["end_time"])

    def test_the_list_is_a_bare_array_not_an_envelope(self):
        # A school has eight or nine periods, so this list is not paginated -
        # and Laravel calls JsonResource::withoutWrapping(), which means a
        # non-paginated collection is flat. The Flutter client depends on it:
        # period_api.dart does `response.data as List` and would throw on an
        # object.
        #
        # This assertion exists because the first version of this endpoint
        # returned {"data": [...]} and every test here passed, having been
        # written against the wrapper. Diffing the two backends found it.
        self.client.post("/api/v1/periods", self.payload(), format="json")

        response = self.client.get("/api/v1/periods")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIsInstance(response.data, list)
        self.assertEqual(1, len(response.data))
        self.assertEqual(1, response.data[0]["period_number"])

    def test_the_period_number_is_unique_within_the_school(self):
        self.client.post("/api/v1/periods", self.payload(), format="json")

        response = self.client.post(
            "/api/v1/periods", self.payload(start_time="10:00", end_time="10:45"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("period_number", response.data["details"]["errors"])

    def test_a_period_must_end_after_it_starts(self):
        response = self.client.post(
            "/api/v1/periods", self.payload(start_time="10:00", end_time="09:00"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("end_time", response.data["details"]["errors"])

    def test_a_time_in_the_wrong_format_is_refused(self):
        response = self.client.post(
            "/api/v1/periods", self.payload(start_time="9am"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("start_time", response.data["details"]["errors"])

    def test_moving_one_end_is_checked_against_the_stored_other(self):
        created = self.client.post("/api/v1/periods", self.payload(), format="json")

        response = self.client.patch(
            f"/api/v1/periods/{created.data['id']}", {"start_time": "11:00"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_a_period_can_be_deleted(self):
        created = self.client.post("/api/v1/periods", self.payload(), format="json")

        self.assertEqual(204, self.client.delete(f"/api/v1/periods/{created.data['id']}").status_code)
        self.assertFalse(Period.objects.filter(pk=created.data["id"]).exists())

    def test_a_teacher_may_read_but_not_write(self):
        teacher = self.as_user(self.teacher)

        self.assertEqual(200, teacher.get("/api/v1/periods").status_code)
        self.assertEqual(
            403, teacher.post("/api/v1/periods", self.payload(), format="json").status_code
        )


class Holidays(AcademicTest):
    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "name": "Diwali",
            "type": "religious",
            "start_date": "2026-11-08",
            "end_date": "2026-11-12",
        }
        body.update(overrides)

        return body

    def test_a_holiday_is_created_and_counts_its_days_inclusively(self):
        response = self.client.post("/api/v1/holidays", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(5, response.data["days"], "the 8th to the 12th is five days")

    def test_a_one_day_holiday_is_one_day(self):
        response = self.client.post(
            "/api/v1/holidays",
            self.payload(start_date="2026-11-08", end_date="2026-11-08"),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(1, response.data["days"])

    def test_overlapping_dates_are_refused_and_name_what_they_clash_with(self):
        # Which holiday a date belongs to decides what the calendar says it
        # is, so guessing would put the wrong reason next to a closed day.
        self.client.post("/api/v1/holidays", self.payload(), format="json")

        response = self.client.post(
            "/api/v1/holidays",
            self.payload(name="Something Else", start_date="2026-11-10", end_date="2026-11-15"),
            format="json",
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("HOLIDAY_OVERLAP", response.data["code"])
        self.assertEqual(
            'These dates overlap the existing holiday "Diwali".', response.data["message"]
        )

    def test_another_schools_holiday_is_not_an_overlap(self):
        elsewhere = factories.SchoolFactory()
        other_admin = self.as_user(
            factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)
        )
        other_admin.post(
            "/api/v1/holidays", self.payload(school_id=elsewhere.id), format="json"
        )

        response = self.client.post("/api/v1/holidays", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)

    def test_editing_a_holiday_does_not_clash_with_itself(self):
        created = self.client.post("/api/v1/holidays", self.payload(), format="json")

        response = self.client.patch(
            f"/api/v1/holidays/{created.data['id']}", {"name": "Deepavali"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_a_write_reports_the_records_it_affects(self):
        # Declaring a holiday after the fact is a legitimate correction; doing
        # it silently is not, because those records stop counting towards
        # every working-day figure in the product.
        response = self.client.post("/api/v1/holidays", self.payload(), format="json")

        self.assertEqual(
            {"attendance": 0, "staff_attendance": 0, "teaching_reports": 0},
            response.data["affected_records"],
        )

    def test_reading_the_calendar_does_not_count_them(self):
        # It would cost three counts per holiday on the page, for a figure
        # only the person declaring one needs.
        self.client.post("/api/v1/holidays", self.payload(), format="json")

        listed = self.client.get("/api/v1/holidays")

        self.assertNotIn("affected_records", listed.data["data"][0])

    def test_the_end_date_may_equal_the_start_but_not_precede_it(self):
        response = self.client.post(
            "/api/v1/holidays",
            self.payload(start_date="2026-11-12", end_date="2026-11-08"),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("end_date", response.data["details"]["errors"])

    def test_a_type_that_does_not_exist_is_refused(self):
        response = self.client.post(
            "/api/v1/holidays", self.payload(type="long_weekend"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected type is invalid.", response.data["details"]["errors"]["type"][0]
        )

    def test_the_list_filters_by_an_overlapping_range(self):
        # A holiday running across the boundary of the window is still in the
        # window.
        self.client.post("/api/v1/holidays", self.payload(), format="json")

        inside = self.client.get("/api/v1/holidays?date_from=2026-11-10&date_to=2026-11-20")
        outside = self.client.get("/api/v1/holidays?date_from=2026-12-01&date_to=2026-12-31")

        self.assertEqual(1, inside.data["meta"]["total"])
        self.assertEqual(0, outside.data["meta"]["total"])

    def test_a_holiday_can_be_deleted(self):
        created = self.client.post("/api/v1/holidays", self.payload(), format="json")

        self.assertEqual(204, self.client.delete(f"/api/v1/holidays/{created.data['id']}").status_code)
        self.assertFalse(Holiday.objects.filter(pk=created.data["id"]).exists())

    def test_a_teacher_may_read_but_not_write(self):
        teacher = self.as_user(self.teacher)

        self.assertEqual(200, teacher.get("/api/v1/holidays").status_code)
        self.assertEqual(
            403, teacher.post("/api/v1/holidays", self.payload(), format="json").status_code
        )


class SchoolIsolation(AcademicTest):
    def setUp(self):
        super().setUp()
        self.outside_school = factories.SchoolFactory()
        self.outsider = self.as_user(
            factories.UserFactory(school=self.outside_school, role=UserRole.SCHOOL_ADMIN)
        )
        self.my_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school)

    def test_an_admin_cannot_reach_another_schools_class(self):
        self.assertEqual(403, self.outsider.get(f"/api/v1/classes/{self.my_class.id}").status_code)
        self.assertEqual(
            403,
            self.outsider.patch(
                f"/api/v1/classes/{self.my_class.id}", {"name": "Stolen"}, format="json"
            ).status_code,
        )
        self.assertEqual(403, self.outsider.delete(f"/api/v1/classes/{self.my_class.id}").status_code)

    def test_an_admin_cannot_add_a_section_to_another_schools_class(self):
        response = self.outsider.post(
            f"/api/v1/classes/{self.my_class.id}/sections", {"name": "Z"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_the_lists_never_include_another_schools_records(self):
        self.client.post(
            "/api/v1/periods",
            {"school_id": self.school.id, "period_number": 1, "start_time": "09:00", "end_time": "09:45"},
            format="json",
        )
        self.client.post(
            "/api/v1/holidays",
            {
                "school_id": self.school.id,
                "name": "Diwali",
                "type": "religious",
                "start_date": "2026-11-08",
                "end_date": "2026-11-12",
            },
            format="json",
        )

        for path in ("/api/v1/classes", "/api/v1/periods", "/api/v1/holidays"):
            with self.subTest(path=path):
                response = self.outsider.get(path + "?per_page=100")
                # Periods come back as a bare array; the other two are
                # paginated. See test_the_list_is_a_bare_array_not_an_envelope.
                rows = response.data if isinstance(response.data, list) else response.data["data"]

                self.assertEqual(
                    [], [row for row in rows if row["school_id"] == self.school.id], path
                )

    def test_a_signed_out_caller_gets_401(self):
        for path in ("/api/v1/classes", "/api/v1/periods", "/api/v1/holidays"):
            with self.subTest(path=path):
                self.assertEqual(401, APIClient().get(path).status_code)
