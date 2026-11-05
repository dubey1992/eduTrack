"""Class tests for one academic year (decided 2026-11-05) - the top bar's
year switch: the tests set in any term of that year, and nothing else."""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole


class AssessmentsByYear(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.last = factories.AcademicYearFactory(school=self.school, name="2025-26", is_current=False,
                                                  start_date=dt.date(2025, 4, 1), end_date=dt.date(2026, 3, 31))
        self.this = factories.AcademicYearFactory(school=self.school, name="2026-27", is_current=True,
                                                  start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31))
        self.old = self.set_test(self.last, "Annual Examination", dt.date(2026, 3, 10))
        self.new = self.set_test(self.this, "Term 1 Examination", dt.date(2026, 7, 21))

    def set_test(self, year, title, day):
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=self.school, academic_year=year)
        )
        term = factories.AcademicTermFactory(academic_year=year, start_date=year.start_date, end_date=year.end_date)
        return factories.AssessmentFactory(class_section=section, academic_term=term, title=title, assessment_date=day)

    def titles(self, **params):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))
        response = client.get("/api/v1/assessments", params)
        self.assertEqual(200, response.status_code, response.data)
        return [row["title"] for row in response.data["data"]]

    def test_a_year_lists_only_its_own_tests(self):
        self.assertEqual(["Annual Examination"], self.titles(academic_year_id=self.last.id))
        self.assertEqual(["Term 1 Examination"], self.titles(academic_year_id=self.this.id))

    def test_without_a_year_every_test_is_listed_as_before(self):
        self.assertEqual({"Annual Examination", "Term 1 Examination"}, set(self.titles()))

    def test_another_schools_year_is_refused(self):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))
        theirs = factories.AcademicYearFactory(school=factories.SchoolFactory())

        response = client.get("/api/v1/assessments", {"academic_year_id": theirs.id})

        self.assertEqual(422, response.status_code)
