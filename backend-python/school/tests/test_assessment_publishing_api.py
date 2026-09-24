"""Publishing a result, and taking it back (docs/assessments.md).

Publishing is the moment a test stops being the school's own business, so
the tests here are about the three things that happen together:

- **Every grade is frozen.** A school that later moves a band boundary must
  not change a result somebody has already been told about.
- **The sheet locks.** No editing, no deleting, no re-scaling.
- **It can be taken back, visibly.** An administrator or the subject's HOD
  reopens it, the grades go, and the act is recorded.

And the rule that decides when publishing is allowed at all: a class with
anybody unmarked is not publishable. A blank is not a zero, and a guardian
who hears nothing while the rest of the class hears something is the worst
version of this feature.
"""

import datetime as dt
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import AssessmentStatus, StudentStatus, UserRole
from school.models import AssessmentMark, AuditLog, GradeBand, ModuleSetting
from school.services import AssessmentMarkService

ASSESSMENTS = "/api/v1/assessments"


class PublishingTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.term = factories.AcademicTermFactory(
            academic_year=self.year,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=1, max_class_level=12
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            subject=self.subject,
            teacher=self.teacher,
            period=factories.PeriodFactory(school=self.school),
        )

        self.scale = factories.GradeScaleFactory(school=self.school, name="Secondary")
        # 91-100 A1, 81-90 A2, the rest a pass or a fail. A mark falls in the
        # highest band whose minimum it reaches.
        for label, low, high, failing in (
            ("A1", 91, 100, False),
            ("A2", 81, 90, False),
            ("Pass", 33, 80, False),
            ("Fail", 0, 32, True),
        ):
            factories.GradeBandFactory(
                grade_scale=self.scale, label=label, min_percentage=low, max_percentage=high, is_failing=failing
            )

        self.students = [
            factories.StudentFactory(
                school=self.school, class_section=self.section, first_name=name, admission_number=f"ADM-{index}"
            )
            for index, name in enumerate(("Aarav", "Bina"), start=1)
        ]

        self.assessment = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=self.term,
            class_section=self.section,
            subject=self.subject,
            max_marks=20,
            grade_scale=self.scale,
            created_by=self.teacher,
        )
        self.client = self.as_user(self.teacher)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def url(self, action: str, assessment_id: int | None = None) -> str:
        return f"{ASSESSMENTS}/{assessment_id or self.assessment.id}/{action}"

    def mark_everybody(self, first="19", second="8"):
        """A sheet with nobody left blank: 19/20 is 95%, 8/20 is 40%."""
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": first},
                    {"student_id": self.students[1].id, "marks_obtained": second},
                ]
            },
            format="json",
        )

    def grade_of(self, student):
        return AssessmentMark.objects.get(assessment_id=self.assessment.id, student_id=student.id).grade


class Publishing(PublishingTestCase):
    def test_publishing_freezes_the_grade_of_every_mark(self):
        self.mark_everybody()

        response = self.client.post(self.url("publish"))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(AssessmentStatus.PUBLISHED, response.data["status"])
        self.assertIsNotNone(response.data["published_at"])
        self.assertEqual("A1", self.grade_of(self.students[0]), "19 of 20 is 95%")
        self.assertEqual("Pass", self.grade_of(self.students[1]), "8 of 20 is 40%")

    def test_a_frozen_grade_survives_the_band_moving_underneath_it(self):
        self.mark_everybody()
        self.client.post(self.url("publish"))

        # The school re-bands afterwards: 95% would now be an A2.
        GradeBand.objects.filter(grade_scale=self.scale, label="A1").update(min_percentage=96)

        self.assertEqual("A1", self.grade_of(self.students[0]), "the grade was frozen, not recomputed")

    def test_a_mark_on_a_band_boundary_takes_the_higher_band(self):
        # 18.2 of 20 is exactly 91%.
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": "18.2"},
                    {"student_id": self.students[1].id, "is_absent": True},
                ]
            },
            format="json",
        )

        self.client.post(self.url("publish"))

        self.assertEqual("A1", self.grade_of(self.students[0]))

    def test_full_marks_and_no_marks_both_have_a_grade(self):
        self.mark_everybody(first="20", second="0")

        self.client.post(self.url("publish"))

        self.assertEqual("A1", self.grade_of(self.students[0]))
        self.assertEqual("Fail", self.grade_of(self.students[1]))

    def test_an_absent_student_gets_no_grade(self):
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": "19"},
                    {"student_id": self.students[1].id, "is_absent": True},
                ]
            },
            format="json",
        )

        self.client.post(self.url("publish"))

        self.assertIsNone(self.grade_of(self.students[1]), "there is no percentage to band")

    def test_a_test_with_no_scale_publishes_marks_and_no_grades(self):
        self.assessment.grade_scale = None
        self.assessment.save(update_fields=["grade_scale"])
        self.mark_everybody()

        response = self.client.post(self.url("publish"))

        self.assertEqual(200, response.status_code, response.data)
        self.assertIsNone(self.grade_of(self.students[0]))

    def test_the_result_is_recorded_with_who_published_it(self):
        self.mark_everybody()

        self.client.post(self.url("publish"))

        entry = AuditLog.objects.get(action="assessment.published")
        self.assertEqual("assessments", entry.module)
        self.assertEqual(self.teacher.id, entry.user_id)
        self.assertEqual("published", entry.new_values["status"])


class WhatPublishingRefuses(PublishingTestCase):
    def test_a_class_with_anybody_unmarked_is_refused(self):
        self.client.put(
            self.url("marks"),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "19"}]},
            format="json",
        )

        response = self.client.post(self.url("publish"))

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("MARKS_INCOMPLETE", response.data["code"])
        self.assertIn("1 of the class has no mark yet", response.data["message"])
        self.assertEqual(AssessmentStatus.DRAFT, self.assessment.status)

    def test_an_unmarked_class_says_how_many_are_left(self):
        response = self.client.post(self.url("publish"))

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("2 of the class have no mark yet", response.data["message"])

    def test_marking_everybody_absent_is_enough_to_publish(self):
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.students[0].id, "is_absent": True},
                    {"student_id": self.students[1].id, "is_absent": True},
                ]
            },
            format="json",
        )

        self.assertEqual(200, self.client.post(self.url("publish")).status_code)

    def test_a_class_with_nobody_in_it_is_refused(self):
        for student in self.students:
            student.status = StudentStatus.INACTIVE
            student.save(update_fields=["status"])

        response = self.client.post(self.url("publish"))

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("nobody in this class", response.data["message"])

    def test_publishing_twice_is_refused(self):
        self.mark_everybody()
        self.client.post(self.url("publish"))

        response = self.client.post(self.url("publish"))

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ASSESSMENT_PUBLISHED", response.data["code"])

    def test_a_student_admitted_after_the_sheet_was_filled_in_blocks_publishing(self):
        self.mark_everybody()
        factories.StudentFactory(school=self.school, class_section=self.section, admission_number="ADM-LATE")

        response = self.client.post(self.url("publish"))

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("MARKS_INCOMPLETE", response.data["code"])


class APublishedSheetIsClosed(PublishingTestCase):
    def setUp(self):
        super().setUp()
        self.mark_everybody()
        self.client.post(self.url("publish"))

    def test_the_marks_cannot_be_changed(self):
        response = self.client.put(
            self.url("marks"),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "5"}]},
            format="json",
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual(Decimal("19.00"), AssessmentMark.objects.get(
            assessment_id=self.assessment.id, student_id=self.students[0].id
        ).marks_obtained)

    def test_the_test_cannot_be_edited_or_deleted(self):
        self.assertEqual(409, self.client.patch(f"{ASSESSMENTS}/{self.assessment.id}", {"title": "X"}, format="json").status_code)
        self.assertEqual(409, self.client.delete(f"{ASSESSMENTS}/{self.assessment.id}").status_code)

    def test_the_grade_scale_it_used_cannot_be_deleted(self):
        response = self.as_user(self.admin).delete(f"/api/v1/grade-scales/{self.scale.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertIn("used by class tests", response.data["message"])


class Reopening(PublishingTestCase):
    def setUp(self):
        super().setUp()
        self.mark_everybody()
        self.client.post(self.url("publish"))
        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.department.hod_user = self.hod
        self.department.save(update_fields=["hod_user"])

    def test_an_administrator_reopens_it_and_the_grades_go(self):
        response = self.as_user(self.admin).post(self.url("reopen"))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(AssessmentStatus.DRAFT, response.data["status"])
        self.assertIsNone(response.data["published_at"])
        self.assertIsNone(self.grade_of(self.students[0]), "a draft carries marks, never grades")

    def test_the_marks_themselves_are_kept(self):
        self.as_user(self.admin).post(self.url("reopen"))

        self.assertEqual(
            Decimal("19.00"),
            AssessmentMark.objects.get(assessment_id=self.assessment.id, student_id=self.students[0].id).marks_obtained,
        )

    def test_the_sheet_can_be_corrected_and_published_again(self):
        self.as_user(self.admin).post(self.url("reopen"))

        self.client.put(
            self.url("marks"),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "17"}]},
            format="json",
        )
        response = self.client.post(self.url("publish"))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("A2", self.grade_of(self.students[0]), "17 of 20 is 85%")

    def test_the_hod_of_the_subject_may_reopen_it(self):
        self.assertEqual(200, self.as_user(self.hod).post(self.url("reopen")).status_code)

    def test_the_teacher_who_published_it_may_not(self):
        response = self.client.post(self.url("reopen"))

        self.assertEqual(403, response.status_code, response.data)

    def test_an_hod_of_another_department_may_not(self):
        science = factories.DepartmentFactory(school=self.school, name="Science")
        stranger = factories.UserFactory(school=self.school, role=UserRole.HOD)
        science.hod_user = stranger
        science.save(update_fields=["hod_user"])

        self.assertEqual(403, self.as_user(stranger).post(self.url("reopen")).status_code)

    def test_a_super_admin_may_not(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(403, root.post(self.url("reopen")).status_code)

    def test_another_school_may_not(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(403, outsider.post(self.url("reopen")).status_code)

    def test_reopening_a_draft_is_refused(self):
        self.as_user(self.admin).post(self.url("reopen"))

        response = self.as_user(self.admin).post(self.url("reopen"))

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ASSESSMENT_NOT_PUBLISHED", response.data["code"])

    def test_the_reopening_is_recorded(self):
        self.as_user(self.admin).post(self.url("reopen"))

        entry = AuditLog.objects.get(action="assessment.reopened")
        self.assertEqual(self.admin.id, entry.user_id)
        self.assertEqual("draft", entry.new_values["status"])


class AbsenceBeatsAnyMarkOnTheRow(PublishingTestCase):
    """The form refuses absent-with-a-mark, so the row below cannot be made
    through the API. It can be made by a direct write - an importer, a
    correction in the shell - and what an absentee is worth must not depend
    on that: no percentage, no grade, no pass."""

    def test_an_absent_row_is_worth_nothing_however_it_was_written(self):
        factories.AssessmentMarkFactory(
            assessment=self.assessment,
            school=self.school,
            student=self.students[0],
            marks_obtained=Decimal("19.00"),
            is_absent=True,
        )
        row = AssessmentMark.objects.get(assessment_id=self.assessment.id, student_id=self.students[0].id)

        self.assertIsNone(AssessmentMarkService.percentage_of(self.assessment, row))
        self.assertIsNone(AssessmentMarkService.passed(self.assessment, row))

        factories.AssessmentMarkFactory(
            assessment=self.assessment, school=self.school, student=self.students[1], marks_obtained=Decimal("10.00")
        )
        self.client.post(self.url("publish"))

        self.assertIsNone(self.grade_of(self.students[0]), "an absentee is not banded")


class WhoMayPublish(PublishingTestCase):
    def setUp(self):
        super().setUp()
        self.mark_everybody()

    def test_the_teacher_of_the_class_may(self):
        self.assertEqual(200, self.client.post(self.url("publish")).status_code)

    def test_an_administrator_may(self):
        self.assertEqual(200, self.as_user(self.admin).post(self.url("publish")).status_code)

    def test_a_teacher_of_another_class_may_not(self):
        stranger = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.as_user(stranger).post(self.url("publish")).status_code)

    def test_a_super_admin_may_not(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(403, root.post(self.url("publish")).status_code)

    def test_another_school_may_not(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(403, outsider.post(self.url("publish")).status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().post(self.url("publish")).status_code)


class WhatCountsAsAPass(PublishingTestCase):
    def test_the_schools_pass_percentage_is_used_when_a_test_sets_none(self):
        # The default is 33%, so 8 of 20 (40%) passes and 6 (30%) does not.
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": "8"},
                    {"student_id": self.students[1].id, "marks_obtained": "6"},
                ]
            },
            format="json",
        )

        entries = self.client.get(self.url("marks")).data["entries"]

        self.assertIs(True, entries[0]["passed"])
        self.assertIs(False, entries[1]["passed"])

    def test_a_school_can_set_its_own_pass_percentage(self):
        ModuleSetting.objects.create(
            school_id=self.school.id,
            module="assessments",
            platform_enabled=True,
            school_enabled=True,
            settings={"pass_percentage": 50},
        )
        cache.clear()
        self.client.put(
            self.url("marks"),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "8"}]},
            format="json",
        )

        entries = self.client.get(self.url("marks")).data["entries"]

        self.assertIs(False, entries[0]["passed"], "40% no longer passes at this school")

    def test_the_tests_own_pass_mark_wins_over_the_setting(self):
        self.assessment.pass_marks = Decimal("15.00")
        self.assessment.save(update_fields=["pass_marks"])
        self.client.put(
            self.url("marks"),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "14"}]},
            format="json",
        )

        entries = self.client.get(self.url("marks")).data["entries"]

        self.assertIs(False, entries[0]["passed"])
        self.assertEqual(Decimal("15.00"), AssessmentMarkService.pass_mark_for(self.assessment))

    def test_an_absent_student_neither_passes_nor_fails(self):
        self.client.put(
            self.url("marks"), {"marks": [{"student_id": self.students[0].id, "is_absent": True}]}, format="json"
        )

        entries = self.client.get(self.url("marks")).data["entries"]

        self.assertIsNone(entries[0]["passed"])
        self.assertIsNone(entries[0]["percentage"])

    def test_the_sheet_says_what_each_mark_comes_to(self):
        self.client.put(
            self.url("marks"),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "17"}]},
            format="json",
        )

        entries = self.client.get(self.url("marks")).data["entries"]

        self.assertEqual("85.00", entries[0]["percentage"])
