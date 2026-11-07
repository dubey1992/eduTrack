"""The parent's view of a child's learning (docs/parent-student-app.md, F2).

What this file guards that a quick read would not:

- **Nothing unpublished.** A draft test - its marks, its grades - is the
  teacher's until they publish; a reopened one disappears again.
- **The class average is the school's choice**, off until it says so, and
  even then a number, never another child's mark.
- **Absent is not zero:** an absent child's test says absent, and the
  average leaves them out.
- **A progress report is ready when its term is over**, and only ever for
  the caller's own child and a term of the child's own year.
- **The week and the syllabus are the child's class's**, this year's.
"""

import datetime as dt

from school import factories
from school.models import ModuleSetting, SyllabusTopicProgress
from school.tests.test_family_f1_api import FAMILY, FamilyAppTest


class LearningTest(FamilyAppTest):
    def setUp(self):
        super().setUp()
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Class 6",
                                                    level=6)
        self.class_section = factories.ClassSectionFactory(school_class=school_class, name="A")
        self.child.class_section = self.class_section
        self.child.save(update_fields=["class_section"])
        self.classmate = factories.StudentFactory(class_section=self.class_section, school=self.school)
        today = self.today()
        self.term = factories.AcademicTermFactory(
            academic_year=self.year, school=self.school, name="Term 1", sequence_number=1,
            start_date=today - dt.timedelta(days=50), end_date=today + dt.timedelta(days=30),
        )
        self.maths = factories.SubjectFactory(department__school=self.school, name="Mathematics")

    def assessment(self, status="published", title="Fractions", maximum=20):
        return factories.AssessmentFactory(
            class_section=self.class_section, academic_year=self.year, academic_term=self.term,
            subject=self.maths, title=title, max_marks=maximum, status=status,
            assessment_date=self.today() - dt.timedelta(days=5),
        )

    def mark(self, assessment, student, marks=None, absent=False, grade=None):
        return factories.AssessmentMarkFactory(assessment=assessment, student=student, marks_obtained=marks,
                                               is_absent=absent, grade=grade)

    def results(self, **params):
        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/results", params)
        self.assertEqual(200, response.status_code, response.data)
        return response.data

    def show_averages(self):
        ModuleSetting.objects.filter(school=self.school, module="family_app").update(
            settings={"show_class_average": True}
        )


class AParentSeesPublishedResults(LearningTest):
    def test_a_published_test_shows_the_mark_and_the_frozen_grade(self):
        fractions = self.assessment()
        self.mark(fractions, self.child, marks=18, grade="A")

        data = self.results()

        self.assertEqual("Term 1", data["term"]["name"])
        [subject] = data["subjects"]
        [test] = subject["tests"]
        self.assertEqual(("Mathematics", "Fractions", "18.00", "20.00", "A"), (
            subject["subject"], test["title"], test["marks_obtained"], test["max_marks"], test["grade"]))
        self.assertEqual("90", test["percentage"].split(".")[0])

    def test_a_draft_test_is_not_shown(self):
        draft = self.assessment(status="draft")
        self.mark(draft, self.child, marks=5)

        self.assertEqual([], self.results()["subjects"])

    def test_absent_is_absent_not_zero(self):
        fractions = self.assessment()
        self.mark(fractions, self.child, absent=True)

        [test] = self.results()["subjects"][0]["tests"]

        self.assertTrue(test["is_absent"])
        self.assertIsNone(test["marks_obtained"])
        self.assertIsNone(test["percentage"])

    def test_the_class_average_is_hidden_until_the_school_shows_it(self):
        fractions = self.assessment()
        self.mark(fractions, self.child, marks=18)
        self.mark(fractions, self.classmate, marks=10)

        data = self.results()
        self.assertFalse(data["shows_class_average"])
        self.assertIsNone(data["subjects"][0]["tests"][0]["class_average_percentage"])

        self.show_averages()
        data = self.results()
        self.assertTrue(data["shows_class_average"])
        # (18 + 10) / 2 of 20 = 70%.
        self.assertEqual("70", data["subjects"][0]["tests"][0]["class_average_percentage"].split(".")[0])

    def test_the_average_leaves_out_who_was_absent(self):
        self.show_averages()
        fractions = self.assessment()
        self.mark(fractions, self.child, marks=16)
        self.mark(fractions, self.classmate, absent=True)

        test = self.results()["subjects"][0]["tests"][0]

        self.assertEqual("80", test["class_average_percentage"].split(".")[0])

    def test_no_other_childs_marks_are_in_the_answer(self):
        self.show_averages()
        fractions = self.assessment()
        self.mark(fractions, self.child, marks=18)
        self.mark(fractions, self.classmate, marks=3)

        text = str(self.results())

        self.assertNotIn(self.classmate.first_name, text)
        self.assertNotIn("'3'", text)

    def test_a_term_of_another_school_is_no_term(self):
        elsewhere = factories.AcademicTermFactory()

        self.assertIsNone(self.results(term_id=elsewhere.id)["term"])

    def test_a_term_that_is_not_a_number_is_refused(self):
        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/results", {"term_id": "first"})

        self.assertEqual(422, response.status_code)

    def test_another_familys_child_is_not_found(self):
        response = self.parent.get(f"{FAMILY}/children/{self.classmate.id}/results")

        self.assertEqual(404, response.status_code)


class AParentDownloadsTheProgressReport(LearningTest):
    def url(self, term=None):
        return f"{FAMILY}/children/{self.child.id}/progress-report" + (f"?term_id={term.id}" if term else "")

    def test_not_before_the_term_is_over(self):
        response = self.parent.get(self.url(self.term))

        self.assertEqual(404, response.status_code)
        self.assertEqual("PROGRESS_REPORT_NOT_READY", response.data["code"])
        self.assertFalse(self.results()["progress_report"]["available"])

    def test_a_finished_term_gives_the_pdf(self):
        self.term.start_date = self.today() - dt.timedelta(days=80)
        self.term.end_date = self.today() - dt.timedelta(days=1)
        self.term.save(update_fields=["start_date", "end_date"])
        self.mark(self.assessment(), self.child, marks=18, grade="A")

        response = self.parent.get(self.url(self.term))

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertTrue(response.content.startswith(b"%PDF"))

    def test_not_for_another_familys_child(self):
        response = self.parent.get(f"{FAMILY}/children/{self.classmate.id}/progress-report")

        self.assertEqual(404, response.status_code)


class AParentSeesTheWeekAndTheSyllabus(LearningTest):
    def test_the_week_has_the_classs_periods_in_bell_order(self):
        early = factories.PeriodFactory(school=self.school, period_number=1, start_time=dt.time(8, 0),
                                        end_time=dt.time(8, 40), day_shape="full")
        late = factories.PeriodFactory(school=self.school, period_number=2, start_time=dt.time(8, 45),
                                       end_time=dt.time(9, 25), day_shape="full")
        science = factories.SubjectFactory(department__school=self.school, name="Science")
        factories.TimetableEntryFactory(class_section=self.class_section, period=late, day_of_week="monday",
                                        subject=science)
        factories.TimetableEntryFactory(class_section=self.class_section, period=early, day_of_week="monday",
                                        subject=self.maths)
        other_class = factories.ClassSectionFactory(school_class=self.class_section.school_class, name="B")
        factories.TimetableEntryFactory(class_section=other_class, period=early, day_of_week="tuesday",
                                        subject=self.maths)

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/timetable")

        self.assertEqual(200, response.status_code, response.data)
        days = {day["day"]: day for day in response.data["days"]}
        self.assertEqual(["Mathematics", "Science"], [p["subject"] for p in days["monday"]["periods"]])
        self.assertEqual([], days["tuesday"]["periods"])

    def test_the_syllabus_says_how_far_each_subject_has_got(self):
        factories.TimetableEntryFactory(class_section=self.class_section, subject=self.maths,
                                        period=factories.PeriodFactory(school=self.school))
        topics = [factories.SyllabusTopicFactory(subject=self.maths, school=self.school, class_level=level,
                                                 title=f"Topic {i}")
                  for i, level in enumerate((6, 6, 6, None, 9))]
        SyllabusTopicProgress.objects.create(school=self.school, syllabus_topic=topics[0], class_section=self.class_section,
                                             completed_by=self.admin, completed_at=dt.datetime.now(dt.timezone.utc),
                                             created_at=dt.datetime.now(dt.timezone.utc),
                                             updated_at=dt.datetime.now(dt.timezone.utc))

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/syllabus")

        self.assertEqual(200, response.status_code, response.data)
        [maths] = response.data["subjects"]
        # Class 9's topic is not Class 6's; the every-class topic is.
        self.assertEqual((4, 1, 25), (maths["total_topics"], maths["covered_topics"], maths["percent"]))
        self.assertEqual(["Topic 1", "Topic 2", "Topic 3"], maths["next_topics"])

    def test_another_familys_child_is_not_found(self):
        for path in ("timetable", "syllabus"):
            with self.subTest(path=path):
                self.assertEqual(404, self.parent.get(f"{FAMILY}/children/{self.classmate.id}/{path}").status_code)
