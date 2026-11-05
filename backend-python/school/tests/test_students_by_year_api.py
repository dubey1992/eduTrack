"""The student list for one academic year (decided 2026-11-05).

The top bar's year switch: a past or next year lists who was enrolled that
year, in the class and with the roll number they had then - a child now in
Class 6 was in Class 5 last year. The current year is the list as it always
was. A year of another school is refused, never quietly ignored.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole

URL = "/api/v1/students"


class StudentsByYear(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.last = factories.AcademicYearFactory(
            school=self.school, name="2025-26", start_date=dt.date(2025, 4, 1), end_date=dt.date(2026, 3, 31),
            is_current=False,
        )
        self.this = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31),
            is_current=True,
        )
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.five_then = self.section(self.last, "Class 5", 5, class_teacher=self.teacher)
        self.six_then = self.section(self.last, "Class 6", 6)
        self.six_now = self.section(self.this, "Class 6", 6)

        # Riya: Class 5 last year, Class 6 now. Kabir: joined this year.
        self.riya = factories.StudentFactory(class_section=self.six_now, first_name="Riya", roll_number="4")
        self.enrol(self.riya, self.five_then, roll="12")
        self.enrol(self.riya, self.six_now, roll="4")
        self.kabir = factories.StudentFactory(class_section=self.six_now, first_name="Kabir")
        self.enrol(self.kabir, self.six_now)
        # Dev: Class 6 last year, gone now.
        self.dev = factories.StudentFactory(class_section=self.six_then, first_name="Dev", status="inactive")
        self.enrol(self.dev, self.six_then, roll="7")

    def section(self, year, name, level, class_teacher=None):
        return factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=self.school, academic_year=year, name=name, level=level),
            name="A",
            class_teacher=class_teacher,
        )

    def enrol(self, student, section, roll=None):
        return factories.StudentEnrollmentFactory(
            student=student, academic_year=section.school_class.academic_year, school_class=section.school_class,
            class_section=section, roll_number=roll,
        )

    def list(self, user=None, **params):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user or self.admin))
        return client.get(URL, params)

    def names(self, response):
        self.assertEqual(200, response.status_code, response.data)
        return sorted(row["first_name"] for row in response.data["data"])

    def test_a_past_year_lists_who_was_enrolled_then(self):
        self.assertEqual(["Dev", "Riya"], self.names(self.list(academic_year_id=self.last.id)))

    def test_each_shows_the_class_and_roll_number_of_that_year(self):
        rows = {row["first_name"]: row for row in self.list(academic_year_id=self.last.id).data["data"]}

        self.assertEqual(("Class 5 A", "12", self.five_then.id),
                         (rows["Riya"]["class_section_name"], rows["Riya"]["roll_number"], rows["Riya"]["class_section_id"]))
        self.assertEqual("Class 6 A", rows["Dev"]["class_section_name"])

    def test_the_class_filter_is_that_years_class(self):
        self.assertEqual(["Riya"], self.names(self.list(academic_year_id=self.last.id, class_section_id=self.five_then.id)))

    def test_the_current_year_is_the_list_as_it_always_was(self):
        self.assertEqual(self.names(self.list()), self.names(self.list(academic_year_id=self.this.id)))
        row = next(r for r in self.list(academic_year_id=self.this.id).data["data"] if r["first_name"] == "Riya")
        self.assertEqual("Class 6 A", row["class_section_name"])

    def test_a_teacher_sees_the_class_they_taught_that_year(self):
        self.assertEqual(["Riya"], self.names(self.list(self.teacher, academic_year_id=self.last.id)))

    def test_a_teacher_does_not_see_another_class_of_that_year(self):
        self.assertEqual([], self.names(self.list(self.teacher, academic_year_id=self.last.id,
                                                  class_section_id=self.six_then.id)))

    def test_another_schools_year_is_refused(self):
        theirs = factories.AcademicYearFactory(school=factories.SchoolFactory())

        response = self.list(academic_year_id=theirs.id)

        self.assertEqual(422, response.status_code)
        self.assertIn("academic_year_id", response.data["details"]["errors"])

    def test_a_year_that_does_not_exist_is_refused(self):
        self.assertEqual(422, self.list(academic_year_id=999999).status_code)

    def classes(self, **params):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))
        response = client.get(f"{URL}/classes", params)
        self.assertEqual(200, response.status_code, response.data)
        return {row["name"]: row["sections"][0]["students"] for row in response.data["data"]}

    def test_the_class_list_beside_it_is_that_years_with_who_was_in_each(self):
        self.assertEqual({"Class 5": 1, "Class 6": 1}, self.classes(academic_year_id=self.last.id))

    def test_without_a_year_the_class_list_is_this_years(self):
        self.assertEqual({"Class 6": 2}, self.classes())
