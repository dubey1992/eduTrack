"""What a student's marks add up to (docs/assessments.md, slice 11).

Every figure here is computed on the way out, so the tests are about the
arithmetic and - more often - about refusing to do arithmetic on nothing:

- a draft counts for nothing, because a draft is nobody's business;
- absent is not zero, so a subject the student missed entirely has no
  average rather than a nought;
- the class average covers exactly the tests the student sat, or comparing
  the two numbers means nothing;
- a term with no previous term, a subject with one test, a range with no
  working day and a school that grades nothing each read as *nothing*,
  because a zero on this page is a sentence about a child.
"""

import datetime as dt
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import AssessmentStatus, AttendanceStatus, UserRole
from school.models import Assessment, AssessmentMark, Attendance, ModuleSetting


class PerformanceTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="UTC")
        self.year = factories.AcademicYearFactory(
            school=self.school,
            name="2026-27",
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2027, 3, 31),
            is_current=True,
        )
        self.term_1 = self.term("Term 1", 1, dt.date(2026, 4, 1), dt.date(2026, 8, 31))
        # The term being lived: today is inside it.
        self.term_2 = self.term("Term 2", 2, dt.date(2026, 9, 1), dt.date(2027, 3, 31))

        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")

        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.maths = factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=1, max_class_level=12
        )
        self.science = factories.SubjectFactory(
            department=self.department, school=self.school, name="Science", min_class_level=1, max_class_level=12
        )

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        self.student = factories.StudentFactory(
            school=self.school, class_section=self.section, first_name="Aarav", admission_number="ADM-1"
        )
        self.classmate = factories.StudentFactory(
            school=self.school, class_section=self.section, first_name="Bina", admission_number="ADM-2"
        )

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def term(self, name: str, sequence: int, start: dt.date, end: dt.date):
        return factories.AcademicTermFactory(
            academic_year=self.year,
            school=self.school,
            name=name,
            sequence_number=sequence,
            start_date=start,
            end_date=end,
        )

    def published(self, subject=None, term=None, max_marks="20", weightage=None, grade_scale=None) -> Assessment:
        return factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=term or self.term_2,
            class_section=self.section,
            subject=subject or self.maths,
            max_marks=Decimal(max_marks),
            weightage=None if weightage is None else Decimal(weightage),
            grade_scale=grade_scale,
            status=AssessmentStatus.PUBLISHED,
            published_at=timezone.now(),
            created_by=self.admin,
        )

    def draft(self, subject=None, term=None) -> Assessment:
        return factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=term or self.term_2,
            class_section=self.section,
            subject=subject or self.maths,
            max_marks=Decimal("20"),
            created_by=self.admin,
        )

    def mark(self, assessment, student=None, marks=None, is_absent=False):
        return AssessmentMark.objects.create(
            assessment=assessment,
            student=student or self.student,
            school=self.school,
            marks_obtained=None if marks is None else Decimal(marks),
            is_absent=is_absent,
            entered_by=self.admin,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

    def ask(self, client=None, student=None, **params):
        return (client or self.client).get(
            f"/api/v1/students/{(student or self.student).id}/performance", params
        )

    def subjects(self, response) -> dict:
        return {row["subject_name"]: row for row in response.data["subjects"]}


class WhereTheyStand(PerformanceTestCase):
    def test_a_subject_averages_the_tests_that_were_sat(self):
        self.mark(self.published(), marks="18")
        self.mark(self.published(), marks="12")

        response = self.ask()

        self.assertEqual(200, response.status_code, response.data)
        maths = self.subjects(response)["Mathematics"]
        self.assertEqual("75.00", maths["average_percentage"], "90% and 60%")
        self.assertEqual(2, maths["assessments"])
        self.assertEqual(0, maths["absent"])

    def test_the_class_average_covers_the_same_tests(self):
        test = self.published()
        self.mark(test, marks="18")
        self.mark(test, student=self.classmate, marks="12")

        maths = self.subjects(self.ask())["Mathematics"]

        self.assertEqual("90.00", maths["average_percentage"])
        self.assertEqual("75.00", maths["class_average_percentage"], "(18 + 12) / 2 of 20")

    def test_a_draft_counts_for_nothing(self):
        self.mark(self.published(), marks="18")
        self.mark(self.draft(), marks="2")

        maths = self.subjects(self.ask())["Mathematics"]

        self.assertEqual("90.00", maths["average_percentage"])
        self.assertEqual(1, maths["assessments"], "a draft is nobody's business yet")

    def test_an_absence_leaves_the_denominator_rather_than_scoring_nought(self):
        self.mark(self.published(), marks="18")
        self.mark(self.published(), is_absent=True)

        maths = self.subjects(self.ask())["Mathematics"]

        self.assertEqual("90.00", maths["average_percentage"], "not 45%")
        self.assertEqual(2, maths["assessments"])
        self.assertEqual(1, maths["absent"])

    def test_a_subject_missed_entirely_has_no_average_at_all(self):
        self.mark(self.published(), is_absent=True)

        maths = self.subjects(self.ask())["Mathematics"]

        self.assertIsNone(maths["average_percentage"], "nothing, rather than zero")
        self.assertEqual(1, maths["absent"])

    def test_one_test_is_still_a_figure(self):
        self.mark(self.published(), marks="15")

        self.assertEqual("75.00", self.subjects(self.ask())["Mathematics"]["average_percentage"])

    def test_the_overall_figure_weighs_each_subject_evenly(self):
        # Two maths tests and one science, so mark-by-mark would let maths
        # drown science. The page reads subject by subject, and so does this.
        self.mark(self.published(subject=self.maths), marks="20")
        self.mark(self.published(subject=self.maths), marks="20")
        self.mark(self.published(subject=self.science), marks="10")

        overall = self.ask().data["overall"]

        self.assertEqual("75.00", overall["average_percentage"], "100% and 50%, evenly")
        self.assertEqual(2, overall["subjects"])
        self.assertEqual(3, overall["assessments"])

    def test_a_school_with_a_grade_scale_reads_a_grade_beside_the_average(self):
        scale = factories.GradeScaleFactory(school=self.school, name="Secondary", is_default=True)
        for label, low, high in (("A1", 91, 100), ("A2", 81, 90), ("Pass", 33, 80), ("Fail", 0, 32)):
            factories.GradeBandFactory(
                grade_scale=scale, label=label, min_percentage=low, max_percentage=high, is_failing=label == "Fail"
            )
        self.mark(self.published(grade_scale=scale), marks="18")

        self.assertEqual("A2", self.subjects(self.ask())["Mathematics"]["grade"], "90%")

    def test_a_school_that_grades_nothing_reads_marks_and_no_grades(self):
        self.mark(self.published(), marks="18")

        self.assertIsNone(self.subjects(self.ask())["Mathematics"]["grade"])


class WeightedSubjects(PerformanceTestCase):
    def test_weightages_are_used_where_every_test_carries_one(self):
        self.mark(self.published(weightage="30"), marks="10")
        self.mark(self.published(weightage="70"), marks="20")

        maths = self.subjects(self.ask())["Mathematics"]

        self.assertEqual("85.00", maths["average_percentage"], "50% at 30 and 100% at 70")

    def test_weightages_that_do_not_add_to_a_hundred_are_normalised(self):
        # A school part-way through setting them up. 25 and 25 means half
        # each, not a quarter each with the rest unaccounted for.
        self.mark(self.published(weightage="25"), marks="10")
        self.mark(self.published(weightage="25"), marks="20")

        self.assertEqual("75.00", self.subjects(self.ask())["Mathematics"]["average_percentage"])

    def test_half_a_weighting_is_not_a_weighting(self):
        self.mark(self.published(weightage="90"), marks="10")
        self.mark(self.published(), marks="20")

        self.assertEqual(
            "75.00",
            self.subjects(self.ask())["Mathematics"]["average_percentage"],
            "a plain mean, rather than pretending the blank one weighs nothing",
        )


class AreTheyImproving(PerformanceTestCase):
    def test_the_previous_term_sits_beside_this_one(self):
        self.mark(self.published(term=self.term_1), marks="12")
        self.mark(self.published(term=self.term_2), marks="18")

        response = self.ask()
        maths = self.subjects(response)["Mathematics"]

        self.assertEqual("Term 2", response.data["term"]["name"])
        self.assertEqual("Term 1", response.data["previous_term"]["name"])
        self.assertEqual("90.00", maths["average_percentage"])
        self.assertEqual("60.00", maths["previous_average_percentage"])
        self.assertEqual("30.00", maths["change"])

    def test_a_fall_reads_as_a_fall(self):
        self.mark(self.published(term=self.term_1), marks="18")
        self.mark(self.published(term=self.term_2), marks="10")

        self.assertEqual("-40.00", self.subjects(self.ask())["Mathematics"]["change"])

    def test_the_first_term_of_a_year_has_nothing_to_be_measured_against(self):
        self.mark(self.published(term=self.term_1), marks="18")

        response = self.ask(academic_term_id=self.term_1.id)

        self.assertIsNone(response.data["previous_term"])
        self.assertIsNone(self.subjects(response)["Mathematics"]["previous_average_percentage"])
        self.assertIsNone(self.subjects(response)["Mathematics"]["change"])

    def test_a_subject_new_this_term_has_no_change(self):
        self.mark(self.published(subject=self.maths, term=self.term_1), marks="18")
        self.mark(self.published(subject=self.science, term=self.term_2), marks="18")

        science = self.subjects(self.ask())["Science"]

        self.assertEqual("90.00", science["average_percentage"])
        self.assertIsNone(science["change"])

    def test_a_student_promoted_between_the_terms_keeps_both(self):
        """Where the enrollment history earns its place (docs/promotion.md).

        The marks are read by student, not by section, so moving class does
        not lose the term that was already sat.
        """
        self.mark(self.published(term=self.term_1), marks="12")
        self.mark(self.published(term=self.term_2), marks="18")

        moved = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        self.student.class_section = moved
        self.student.save(update_fields=["class_section"])

        maths = self.subjects(self.ask())["Mathematics"]

        self.assertEqual("90.00", maths["average_percentage"])
        self.assertEqual("60.00", maths["previous_average_percentage"])


class TheRegisterBeside(PerformanceTestCase):
    def present_on(self, day: dt.date):
        Attendance.objects.create(
            school=self.school,
            academic_year=self.year,
            class_section=self.section,
            student=self.student,
            attendance_date=day,
            status=AttendanceStatus.PRESENT,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

    def test_attendance_covers_the_same_period(self):
        self.present_on(dt.date(2026, 9, 16))

        attendance = self.ask().data["attendance"]

        self.assertEqual(1, attendance["present"])
        self.assertGreater(attendance["working_days"], 0)
        self.assertIsNotNone(attendance["attendance_rate"])

    def test_a_term_that_has_not_started_has_no_rate_at_all(self):
        future = self.term("Term 9", 9, dt.date(2030, 4, 1), dt.date(2031, 3, 31))

        attendance = self.ask(academic_term_id=future.id).data["attendance"]

        self.assertEqual(0, attendance["working_days"])
        self.assertIsNone(attendance["attendance_rate"], "a percentage out of nothing is nothing")

    def test_days_nobody_marked_are_not_absences(self):
        self.present_on(dt.date(2026, 9, 16))

        attendance = self.ask().data["attendance"]

        self.assertEqual(0, attendance["absent"])
        self.assertEqual(attendance["working_days"] - 1, attendance["not_marked"])


class WhenThereIsNothingToSay(PerformanceTestCase):
    def test_a_student_with_no_published_result_reads_as_empty_rather_than_zero(self):
        response = self.ask()

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], response.data["subjects"])
        self.assertIsNone(response.data["overall"]["average_percentage"])
        self.assertEqual(0, response.data["overall"]["subjects"])

    def test_a_school_with_no_terms_still_answers(self):
        other = factories.SchoolFactory()
        year = factories.AcademicYearFactory(school=other, is_current=True)
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=year, school=other, name="Grade 1", level=1),
            name="A",
        )
        student = factories.StudentFactory(school=other, class_section=section)
        admin = self.as_user(factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN))

        response = self.ask(client=admin, student=student)

        self.assertEqual(200, response.status_code, response.data)
        self.assertIsNone(response.data["term"])
        self.assertEqual([], response.data["subjects"])
        self.assertIsNone(response.data["attendance"]["attendance_rate"])

    def test_the_page_says_what_the_school_calls_weak(self):
        response = self.ask()

        self.assertEqual(40, response.data["weak_below_percentage"], "the default in the settings screen")

    def test_a_school_that_moved_the_weak_mark_is_read_back(self):
        ModuleSetting.objects.create(
            school=self.school,
            module="assessments",
            settings={"weak_below_percentage": 50},
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

        self.assertEqual(50, self.ask().data["weak_below_percentage"])

    def test_every_term_of_the_year_is_offered(self):
        names = [row["name"] for row in self.ask().data["terms"]]

        self.assertEqual(["Term 2", "Term 1"], names, "newest first, which is what a picker opens on")


class TheSentencesOnThePage(PerformanceTestCase):
    """The rules themselves are unit-tested in test_insights.py; these are
    about the figures reaching them at all."""

    def test_a_weak_subject_is_said_in_words_with_the_school_s_own_mark(self):
        self.mark(self.published(), marks="6")
        self.mark(self.published(), marks="8")

        insights = self.ask().data["insights"]

        self.assertEqual(
            ["weak_subject"],
            [row["code"] for row in insights],
            "no register was taken, so nothing is said about attendance",
        )
        self.assertEqual("Mathematics is at 35%, below the school's 40% mark.", insights[0]["message"])
        self.assertEqual(self.maths.id, insights[0]["subject_id"])

    def test_a_slipping_subject_names_the_term_it_fell_from(self):
        self.mark(self.published(term=self.term_1), marks="18")
        self.mark(self.published(term=self.term_1), marks="18")
        self.mark(self.published(term=self.term_2), marks="10")
        self.mark(self.published(term=self.term_2), marks="10")

        codes = {row["code"]: row for row in self.ask().data["insights"]}

        self.assertIn("slipping", codes)
        self.assertEqual("Mathematics has fallen 40 points since Term 1.", codes["slipping"]["message"])

    def test_a_student_too_new_to_say_anything_about_hears_nothing(self):
        self.mark(self.published(), marks="2")

        self.assertEqual([], self.ask().data["insights"], "one test is not a trend")

    def test_the_rules_read_the_same_figures_the_page_shows(self):
        self.mark(self.published(), marks="6")
        self.mark(self.published(), marks="8")

        response = self.ask()
        average = self.subjects(response)["Mathematics"]["average_percentage"]

        self.assertIn(average.rstrip("0").rstrip("."), response.data["insights"][0]["message"])


class WhoMayRead(PerformanceTestCase):
    def test_a_term_from_another_school_is_a_field_error(self):
        elsewhere = factories.SchoolFactory()
        year = factories.AcademicYearFactory(school=elsewhere, is_current=False)
        theirs = factories.AcademicTermFactory(
            academic_year=year,
            school=elsewhere,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )

        response = self.ask(academic_term_id=theirs.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("academic_term_id", response.data["details"]["errors"])

    def test_another_school_reaches_none_of_it(self):
        outsider = self.as_user(factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN))

        self.assertEqual(403, self.ask(client=outsider).status_code)

    def test_the_class_teacher_reads_their_own_student(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section.class_teacher = teacher
        self.section.save(update_fields=["class_teacher"])

        self.assertEqual(200, self.ask(client=self.as_user(teacher)).status_code)

    def test_a_teacher_of_another_class_does_not(self):
        stranger = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.ask(client=self.as_user(stranger)).status_code)

    def test_a_school_with_class_tests_switched_off_has_no_performance_to_read(self):
        ModuleSetting.objects.create(
            school=self.school,
            module="assessments",
            school_enabled=False,
            settings=None,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

        response = self.ask()

        self.assertEqual(403, response.status_code, response.data)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_a_student_who_does_not_exist_is_a_404(self):
        self.assertEqual(404, self.client.get("/api/v1/students/99999999/performance").status_code)
