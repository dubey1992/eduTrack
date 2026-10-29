"""Academic analytics, A4 (docs/analytics.md): subjects and classes, term by
term, over HTTP.

Monday 14 September 2026, as in the report tests. The year runs April to
March in three terms: the first is over, the second has begun, and the third
has not - so it is left out rather than shown empty. Each term's figures are
the Class Performance report's for that term, and the two roll-ups weigh
each class and subject by the marks it counted.
"""

import datetime as dt

from rest_framework.test import APIClient

from school import factories
from school.enums import UserRole

from .test_reports_api import ReportTestCase, client_for

URL = "/api/v1/analytics/academic"


class AcademicTestCase(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.year.name = "2026-27"
        self.year.start_date = dt.date(2026, 4, 1)
        self.year.end_date = dt.date(2027, 3, 31)
        self.year.is_current = True
        self.year.save()

        self.term1 = self.term("Term 1", 1, "2026-04-01", "2026-07-31")
        self.term2 = self.term("Term 2", 2, "2026-08-01", "2026-11-30")
        self.term3 = self.term("Term 3", 3, "2026-12-01", "2027-03-31")

        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.maths_department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.physics = factories.SubjectFactory(department=self.science, name="Physics")
        self.maths = factories.SubjectFactory(department=self.maths_department, name="Maths")
        self.section_b = factories.ClassSectionFactory(school_class=self.section.school_class, name="B")
        self.student_b = factories.StudentFactory(class_section=self.section_b, first_name="Neha")

    def term(self, name, sequence, start, end):
        return factories.AcademicTermFactory(
            academic_year=self.year, school=self.school, name=name, sequence_number=sequence,
            start_date=dt.date.fromisoformat(start), end_date=dt.date.fromisoformat(end),
        )

    def result(self, on: str, scored: int, subject, student=None, section=None, term=None, out_of: int = 20):
        assessment = factories.AssessmentFactory(
            class_section=section or self.section, academic_term=term or self.term1, subject=subject,
            assessment_date=dt.date.fromisoformat(on), max_marks=out_of, status="published",
            created_by=self.teacher,
        )
        factories.AssessmentMarkFactory(assessment=assessment, student=student or self.student, marks_obtained=scored)

    def look(self, user=None, **params):
        response = client_for(user or self.admin).get(URL, params)
        self.assertEqual(200, response.status_code, getattr(response, "data", response))

        return response.data


class TermByTerm(AcademicTestCase):
    def setUp(self):
        super().setUp()
        self.result("2026-05-10", 15, self.physics)  # 8 A Physics, term 1: 75%
        self.result("2026-06-10", 18, self.maths)  # 8 A Maths, term 1: 90%
        self.result("2026-09-01", 10, self.physics, term=self.term2)  # 8 A Physics, term 2: 50%
        self.result("2026-09-02", 20, self.physics, student=self.student_b, section=self.section_b,
                    term=self.term2)  # 8 B Physics, term 2: 100%

    def test_only_the_terms_that_have_begun(self):
        data = self.look()

        self.assertEqual({"id": self.year.id, "name": "2026-27"}, data["year"])
        # Three set up, two of them begun.
        self.assertEqual(3, data["terms_set_up"])
        self.assertEqual(
            [
                {"id": self.term1.id, "name": "Term 1", "from": "2026-04-01", "to": "2026-07-31",
                 "in_progress": False},
                # Up to today, and said to be still going.
                {"id": self.term2.id, "name": "Term 2", "from": "2026-08-01", "to": "2026-09-14",
                 "in_progress": True},
            ],
            data["terms"],
        )

    def test_each_class_and_subject_term_by_term_with_gaps_left_empty(self):
        cells = {(c["class_section"], c["subject"]): c["terms"] for c in self.look()["cells"]}

        self.assertEqual(75, cells[("Grade 8 A", "Physics")][0]["average_percentage"])
        self.assertEqual(50, cells[("Grade 8 A", "Physics")][1]["average_percentage"])
        # Maths had no test in term 2: nothing, not nought.
        self.assertIsNone(cells[("Grade 8 A", "Maths")][1])
        self.assertIsNone(cells[("Grade 8 B", "Physics")][0])

    def test_a_subject_across_its_classes(self):
        subjects = {s["subject"]: s["terms"] for s in self.look()["subjects"]}

        # Term 2 Physics: 50% in 8 A and 100% in 8 B, one mark each.
        self.assertEqual({"average_percentage": 75, "marks_counted": 2}, subjects["Physics"][1])
        self.assertEqual("Science", self.look()["subjects"][1]["department"])

    def test_a_class_across_its_subjects(self):
        classes = {c["class_section"]: c["terms"] for c in self.look()["classes"]}

        # Term 1, 8 A: Physics 75 and Maths 90, one mark each.
        self.assertEqual(82.5, classes["Grade 8 A"][0]["average_percentage"])
        self.assertIsNone(classes["Grade 8 B"][0])

    def test_the_school_s_lines_come_with_it(self):
        data = self.look()

        self.assertEqual((33, 40), (data["pass_mark"], data["weak_below"]))

    def test_unpublished_results_do_not_count(self):
        assessment = factories.AssessmentFactory(
            class_section=self.section, academic_term=self.term1, subject=self.maths,
            assessment_date=dt.date(2026, 6, 20), status="draft", created_by=self.teacher,
        )
        factories.AssessmentMarkFactory(assessment=assessment, student=self.student, marks_obtained=0)

        cells = {(c["class_section"], c["subject"]): c["terms"] for c in self.look()["cells"]}
        self.assertEqual(90, cells[("Grade 8 A", "Maths")][0]["average_percentage"])


class Years(AcademicTestCase):
    def test_another_year_is_asked_for_by_id(self):
        last = factories.AcademicYearFactory(
            school=self.school, name="2025-26", start_date=dt.date(2025, 4, 1), end_date=dt.date(2026, 3, 31),
            is_current=False,
        )

        data = self.look(academic_year_id=last.id)

        self.assertEqual({"id": last.id, "name": "2025-26"}, data["year"])
        self.assertEqual(([], 0), (data["terms"], data["terms_set_up"]))
        self.assertEqual(["2026-27", "2025-26"], [year["name"] for year in data["years"]])

    def test_another_school_s_year_is_not_this_school_s(self):
        other = factories.AcademicYearFactory(school=factories.SchoolFactory(timezone="UTC"))

        data = self.look(academic_year_id=other.id)

        self.assertEqual(self.year.id, data["year"]["id"], "falls back to this school's current year")

    def test_a_school_with_no_year_has_nothing_to_show(self):
        empty = factories.SchoolFactory(timezone="UTC")
        admin = factories.UserFactory(school=empty, role=UserRole.SCHOOL_ADMIN)

        data = self.look(admin)

        self.assertEqual((None, [], [], []), (data["year"], data["terms"], data["subjects"], data["cells"]))

    def test_a_year_that_is_not_a_number_is_refused(self):
        response = client_for(self.admin).get(URL, {"academic_year_id": "this one"})

        self.assertEqual(422, response.status_code)


class WhoSees(AcademicTestCase):
    def setUp(self):
        super().setUp()
        self.result("2026-05-10", 15, self.physics)
        self.result("2026-06-10", 18, self.maths)

    def test_a_head_of_department_sees_only_their_subjects(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.science.hod_user = hod
        self.science.save()

        data = self.look(hod)

        self.assertEqual(["Physics"], [subject["subject"] for subject in data["subjects"]])
        self.assertEqual({"Physics"}, {cell["subject"] for cell in data["cells"]})

    def test_others_are_refused(self):
        for role in (UserRole.TEACHER, UserRole.STAFF, UserRole.ACCOUNTANT, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                user = factories.UserFactory(school=self.school, role=role)
                self.assertEqual(403, client_for(user).get(URL).status_code)

    def test_a_school_admin_naming_another_school_sees_their_own(self):
        other = factories.SchoolFactory(timezone="UTC")

        data = self.look(school_id=other.id)

        self.assertEqual(self.year.id, data["year"]["id"])

    def test_a_super_admin_names_a_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        refused = client_for(root).get(URL)
        named = self.look(root, school_id=self.school.id)

        self.assertEqual(422, refused.status_code)
        self.assertEqual({"Physics", "Maths"}, {subject["subject"] for subject in named["subjects"]})

    def test_a_school_without_class_tests_has_none(self):
        factories.ModuleSettingFactory(school=self.school, module="assessments", school_enabled=False)

        response = client_for(self.admin).get(URL)

        self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))

    def test_an_unauthenticated_caller_gets_nothing(self):
        self.assertEqual(401, APIClient().get(URL).status_code)
