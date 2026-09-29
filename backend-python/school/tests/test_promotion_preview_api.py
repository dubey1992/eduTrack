"""The promotion preview (docs/promotion.md), which writes nothing.

A promotion moves a whole class at once, and the thing that makes that safe
is seeing the list first. So the tests here are about what the list says
before anybody presses anything:

- everybody active defaults to promoted, and nobody is ever defaulted to
  retained - holding a child back is a decision a person makes;
- a class with nothing above it graduates, which is not an error;
- a student already enrolled in the target year is listed and blocked, never
  quietly dropped;
- the target year and section belong to this school or the answer is a
  refusal with its own code;
- and a preview reads: no enrollment row, no batch, nothing.
"""

import datetime as dt
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import AssessmentStatus, AttendanceStatus, StudentStatus, UserRole
from school.models import Attendance, AssessmentMark, ClassSection, ModuleSetting, StudentEnrollment

URL = "/api/v1/promotions/preview"


class PreviewTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.this_year = factories.AcademicYearFactory(
            school=self.school,
            name="2026-27",
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2027, 3, 31),
            is_current=True,
        )
        # Not current: the year being promoted into has not started, and the
        # factory would otherwise make every year the current one.
        self.next_year = factories.AcademicYearFactory(
            school=self.school,
            name="2027-28",
            start_date=dt.date(2027, 4, 1),
            end_date=dt.date(2028, 3, 31),
            is_current=False,
        )

        self.grade_8 = factories.SchoolClassFactory(
            academic_year=self.this_year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.grade_8, name="A")

        # Next year's Grade 9 A, which is where these students should land.
        self.grade_9 = factories.SchoolClassFactory(
            academic_year=self.next_year, school=self.school, name="Grade 9", level=9
        )
        self.grade_9_a = factories.ClassSectionFactory(school_class=self.grade_9, name="A")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        self.aarav = self.student("Aarav", "ADM-1", roll_number="1")
        self.bina = self.student("Bina", "ADM-2", roll_number="2")

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def student(self, first_name: str, admission_number: str, **fields):
        return factories.StudentFactory(
            school=self.school,
            class_section=self.section,
            first_name=first_name,
            admission_number=admission_number,
            **fields,
        )

    def ask(self, client=None, **params):
        query = {"class_section_id": self.section.id, "to_academic_year_id": self.next_year.id}
        query.update(params)

        return (client or self.client).get(URL, query)

    def row_for(self, response, student) -> dict:
        return [row for row in response.data["students"] if row["student_id"] == student.id][0]


class WhatThePreviewSays(PreviewTestCase):
    def test_the_roster_comes_back_with_both_sides_named(self):
        response = self.ask()

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Grade 8 A", response.data["from"]["class_section_name"])
        self.assertEqual("2026-27", response.data["from"]["academic_year_name"])
        self.assertEqual("Grade 9 A", response.data["to"]["class_section_name"])
        self.assertEqual("2027-28", response.data["to"]["academic_year_name"])
        self.assertIs(True, response.data["to"]["is_suggested"], "nobody named a section, so this is the guess")
        self.assertEqual(2, len(response.data["students"]))

    def test_everybody_active_defaults_to_promoted_and_nobody_to_retained(self):
        response = self.ask()

        self.assertEqual(["promote", "promote"], [row["default_outcome"] for row in response.data["students"]])
        self.assertEqual({"promote": 2, "retain": 0, "graduate": 0, "leave": 0}, response.data["counts"])

    def test_an_inactive_student_defaults_to_left_out(self):
        self.bina.status = StudentStatus.INACTIVE
        self.bina.save(update_fields=["status"])

        response = self.ask()

        left_out = self.row_for(response, self.bina)
        self.assertEqual("leave", left_out["default_outcome"])
        self.assertEqual(1, response.data["counts"]["leave"])

    def test_a_graduated_student_is_not_offered_a_fifth_year(self):
        self.bina.status = StudentStatus.GRADUATED
        self.bina.save(update_fields=["status"])

        response = self.ask()

        self.assertEqual([self.aarav.id], [row["student_id"] for row in response.data["students"]])

    def test_a_class_with_nothing_above_it_graduates(self):
        # Grade 8 is the top of this school next year: no Grade 9 exists.
        # Its sections go first - the test database is built from unmanaged
        # models, so nothing cascades here the way production does.
        ClassSection.objects.filter(school_class=self.grade_9).delete()
        self.grade_9.delete()

        response = self.ask()

        self.assertIs(True, response.data["is_graduating"])
        self.assertIsNone(response.data["to"]["class_section_id"])
        self.assertEqual(["graduate", "graduate"], [row["default_outcome"] for row in response.data["students"]])
        self.assertEqual(2, response.data["counts"]["graduate"])

    def test_the_roll_number_and_admission_number_travel_with_the_row(self):
        row = self.row_for(self.ask(), self.aarav)

        self.assertEqual("ADM-1", row["admission_number"])
        self.assertEqual("1", row["roll_number"])
        self.assertEqual("Aarav", row["name"].split()[0])

    def test_an_empty_section_says_there_is_nothing_to_promote(self):
        empty = factories.ClassSectionFactory(school_class=self.grade_8, name="B")

        response = self.ask(class_section_id=empty.id)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], response.data["students"])
        self.assertIs(False, response.data["can_run"])
        self.assertEqual("NOTHING_TO_PROMOTE", response.data["cannot_run_reason"])

    def test_the_preview_writes_nothing(self):
        before = StudentEnrollment.objects.count()

        self.ask()

        self.assertEqual(before, StudentEnrollment.objects.count())


class TheStudentWhoCannotMove(PreviewTestCase):
    def test_a_student_already_in_the_target_year_is_listed_and_blocked(self):
        factories.StudentEnrollmentFactory(
            student=self.bina,
            school=self.school,
            academic_year=self.next_year,
            school_class=self.grade_9,
            class_section=self.grade_9_a,
        )

        response = self.ask()
        blocked = self.row_for(response, self.bina)

        self.assertIs(True, blocked["is_blocked"], "a roster that drops a child is how a child is left behind")
        self.assertIn("already has a place", blocked["blocked_reason"])
        self.assertEqual(1, response.data["counts"]["promote"], "and they are not counted as moving")

    def test_a_class_where_everybody_is_blocked_cannot_be_run(self):
        for student in (self.aarav, self.bina):
            factories.StudentEnrollmentFactory(
                student=student,
                school=self.school,
                academic_year=self.next_year,
                school_class=self.grade_9,
                class_section=self.grade_9_a,
            )

        response = self.ask()

        self.assertIs(False, response.data["can_run"])


class ChoosingTheTarget(PreviewTestCase):
    def test_a_named_section_is_used_and_not_called_a_suggestion(self):
        chosen = factories.ClassSectionFactory(school_class=self.grade_9, name="B")

        response = self.ask(to_class_section_id=chosen.id)

        self.assertEqual("Grade 9 B", response.data["to"]["class_section_name"])
        self.assertIs(False, response.data["to"]["is_suggested"])

    def test_the_suggestion_keeps_the_section_letter_where_it_can(self):
        factories.ClassSectionFactory(school_class=self.grade_9, name="B")

        response = self.ask()

        self.assertEqual("Grade 9 A", response.data["to"]["class_section_name"], "A goes to A, not to whatever is first")

    def test_a_section_in_another_year_is_refused_by_code(self):
        # Next year's students cannot land in this year's Grade 9.
        this_year_9 = factories.SchoolClassFactory(
            academic_year=self.this_year, school=self.school, name="Grade 9 (old)", level=9
        )
        wrong_year = factories.ClassSectionFactory(school_class=this_year_9, name="A")

        response = self.ask(to_class_section_id=wrong_year.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("TARGET_SECTION_MISMATCH", response.data["code"])

    def test_a_section_in_another_school_is_refused_the_same_way(self):
        other = factories.SchoolFactory()
        other_year = factories.AcademicYearFactory(school=other, name="2027-28", is_current=False)
        other_class = factories.SchoolClassFactory(academic_year=other_year, school=other, name="Grade 9", level=9)
        stranger = factories.ClassSectionFactory(school_class=other_class, name="A")

        response = self.ask(to_class_section_id=stranger.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("TARGET_SECTION_MISMATCH", response.data["code"])

    def test_promoting_into_the_same_year_is_refused(self):
        response = self.ask(to_academic_year_id=self.this_year.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("SAME_ACADEMIC_YEAR", response.data["code"])

    def test_another_school_s_year_is_not_found_rather_than_forbidden(self):
        other = factories.SchoolFactory()
        elsewhere = factories.AcademicYearFactory(school=other, name="2027-28", is_current=False)

        response = self.ask(to_academic_year_id=elsewhere.id)

        self.assertEqual(404, response.status_code, response.data)
        self.assertEqual("TARGET_YEAR_NOT_FOUND", response.data["code"])

    def test_a_section_that_does_not_exist_is_a_field_error(self):
        response = self.ask(class_section_id=999999)

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("class_section_id", response.data["details"]["errors"])


class TheSuggestionToRetain(PreviewTestCase):
    """Marks are shown beside the decision, and never make it."""

    def setUp(self):
        super().setUp()
        self.term = factories.AcademicTermFactory(
            academic_year=self.this_year,
            school=self.school,
            name="Term 3",
            sequence_number=3,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2027, 3, 31),
        )
        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, min_class_level=1, max_class_level=12
        )

    def published_test(self, max_marks="20"):
        return factories.AssessmentFactory(
            school=self.school,
            academic_year=self.this_year,
            academic_term=self.term,
            class_section=self.section,
            subject=self.subject,
            max_marks=Decimal(max_marks),
            status=AssessmentStatus.PUBLISHED,
            published_at=timezone.now(),
            created_by=self.admin,
        )

    def mark(self, assessment, student, marks=None, is_absent=False):
        return AssessmentMark.objects.create(
            assessment=assessment,
            student=student,
            school=self.school,
            marks_obtained=None if marks is None else Decimal(marks),
            is_absent=is_absent,
            entered_by=self.admin,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

    def test_a_weak_average_is_suggested_for_retention_without_changing_the_default(self):
        test = self.published_test()
        self.mark(test, self.aarav, "18")
        self.mark(test, self.bina, "4")

        response = self.ask()
        rows = {row["student_id"]: row for row in response.data["students"]}

        self.assertEqual("retain", rows[self.bina.id]["suggested_outcome"], "4 of 20 is 20%, under the 33% pass mark")
        self.assertIn("below the school", rows[self.bina.id]["suggestion_reason"])
        self.assertEqual("promote", rows[self.bina.id]["default_outcome"], "a suggestion is not a decision")
        self.assertIsNone(rows[self.aarav.id]["suggested_outcome"])
        self.assertEqual("90.00", rows[self.aarav.id]["average_percentage"])

    def test_the_average_names_the_term_it_came_from(self):
        self.mark(self.published_test(), self.aarav, "18")

        response = self.ask()

        self.assertIs(True, response.data["suggestions"]["available"])
        self.assertEqual("Term 3", response.data["suggestions"]["term_name"])

    def test_an_absence_is_left_out_of_the_average(self):
        first = self.published_test()
        second = self.published_test()
        self.mark(first, self.aarav, "18")
        self.mark(second, self.aarav, is_absent=True)

        row = self.row_for(self.ask(), self.aarav)

        self.assertEqual("90.00", row["average_percentage"], "a missed test is not a zero")

    def test_a_draft_result_counts_for_nothing(self):
        draft = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.this_year,
            academic_term=self.term,
            class_section=self.section,
            subject=self.subject,
            max_marks=Decimal("20"),
            created_by=self.admin,
        )
        self.mark(draft, self.bina, "2")

        response = self.ask()

        self.assertIs(False, response.data["suggestions"]["available"])
        self.assertIsNone(self.row_for(response, self.bina)["average_percentage"])

    def test_a_school_with_assessments_switched_off_sees_no_marks_at_all(self):
        self.mark(self.published_test(), self.bina, "2")
        ModuleSetting.objects.create(
            school=self.school,
            module="assessments",
            school_enabled=False,
            settings=None,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

        response = self.ask()

        self.assertIs(False, response.data["suggestions"]["available"])
        self.assertIsNone(self.row_for(response, self.bina)["suggested_outcome"])

    def test_attendance_comes_back_out_of_the_school_s_working_days(self):
        # One present day in a year full of working days is a very small
        # percentage, but it is a percentage - and it is out of the days the
        # school ran, like every other attendance figure in the product.
        Attendance.objects.create(
            school=self.school,
            academic_year=self.this_year,
            class_section=self.section,
            student=self.aarav,
            attendance_date=dt.date(2026, 9, 24),
            status=AttendanceStatus.PRESENT,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

        row = self.row_for(self.ask(), self.aarav)

        self.assertIsNotNone(row["attendance_percentage"])
        self.assertGreater(row["attendance_percentage"], 0)


class AttendanceOnTheRow(PreviewTestCase):
    def test_a_student_nobody_ever_marked_reads_as_nought_rather_than_blank(self):
        # The attendance report's rule: the denominator is the days the school
        # ran, so a register nobody took is 0%, which is the truth - not "no
        # data", which invites the reader to assume the best.
        row = self.row_for(self.ask(), self.aarav)

        self.assertEqual(0, row["attendance_percentage"])

    def test_a_year_that_has_not_started_has_no_rate_at_all(self):
        # A year entirely in the future holds no working day yet, and a
        # percentage out of nothing is nothing rather than zero.
        future = factories.AcademicYearFactory(
            school=self.school,
            name="2030-31",
            start_date=dt.date(2030, 4, 1),
            end_date=dt.date(2031, 3, 31),
            is_current=False,
        )
        class_in_future = factories.SchoolClassFactory(
            academic_year=future, school=self.school, name="Grade 8", level=8
        )
        section = factories.ClassSectionFactory(school_class=class_in_future, name="A")
        student = factories.StudentFactory(
            school=self.school, class_section=section, first_name="Later", admission_number="ADM-9"
        )

        response = self.ask(class_section_id=section.id)

        self.assertEqual(200, response.status_code, response.data)
        self.assertIsNone(self.row_for(response, student)["attendance_percentage"])


class WhoMayLook(PreviewTestCase):
    def test_a_teacher_may_not_preview_even_though_academics_is_readable(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, self.ask(client=teacher).status_code)

    def test_an_hod_may_not_either(self):
        hod = self.as_user(factories.UserFactory(school=self.school, role=UserRole.HOD))

        self.assertEqual(403, self.ask(client=hod).status_code)

    def test_an_accountant_may_not(self):
        accountant = self.as_user(factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT))

        self.assertEqual(403, self.ask(client=accountant).status_code)

    def test_a_super_admin_reads_the_school_and_promotes_nothing(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(403, self.ask(client=root).status_code, "the platform's owner is not a member of staff")

    def test_another_school_s_admin_is_refused(self):
        outsider = self.as_user(factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN))

        self.assertEqual(403, self.ask(client=outsider).status_code)

    def test_a_group_admin_previews_a_branch(self):
        branch_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)

        self.assertEqual(200, self.ask(client=self.as_user(branch_admin)).status_code)
