"""The marks sheet, over HTTP (docs/assessments.md).

The sheet is saved as a whole, so the risks are the ones that come with
writing forty rows in one request: a mark in the wrong child's name, a mark
the test cannot hold, two teachers saving at once, and a half-saved sheet.

Three rules the tests hold on to:

- **Absent is not zero.** An absentee has no mark at all.
- **A blank is not a zero either.** Clearing the box removes the mark; the
  student has simply not been marked yet.
- **A mark for somebody who has left stays.** The sheet writes the students
  it was sent and never deletes a row it was not asked about.
"""

import datetime as dt
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import AssessmentStatus, StudentStatus, UserRole
from school.models import AssessmentMark

ASSESSMENTS = "/api/v1/assessments"


class MarksTestCase(TestCase):
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
        self.other_section = factories.ClassSectionFactory(school_class=self.school_class, name="B")
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

        self.students = [
            factories.StudentFactory(
                school=self.school, class_section=self.section, first_name=name, admission_number=f"ADM-{index}"
            )
            for index, name in enumerate(("Aarav", "Bina", "Chetan"), start=1)
        ]

        self.assessment = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=self.term,
            class_section=self.section,
            subject=self.subject,
            max_marks=20,
            created_by=self.teacher,
        )

        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def url(self, assessment_id: int | None = None) -> str:
        return f"{ASSESSMENTS}/{assessment_id or self.assessment.id}/marks"

    def sheet(self, **overrides) -> dict:
        body = {
            "marks": [
                {"student_id": self.students[0].id, "marks_obtained": "17.5"},
                {"student_id": self.students[1].id, "is_absent": True},
                {"student_id": self.students[2].id, "marks_obtained": "12"},
            ]
        }
        body.update(overrides)

        return body

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def stored(self, student):
        return AssessmentMark.objects.filter(assessment_id=self.assessment.id, student_id=student.id).first()


class ReadingTheSheet(MarksTestCase):
    def test_the_whole_class_reads_back_even_before_anybody_is_marked(self):
        response = self.client.get(self.url())

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(["Aarav", "Bina", "Chetan"], [row["student_name"].split()[0] for row in response.data["entries"]])
        self.assertTrue(all(row["marks_obtained"] is None for row in response.data["entries"]))
        self.assertTrue(all(row["is_absent"] is False for row in response.data["entries"]))
        self.assertEqual("20.00", response.data["assessment"]["max_marks"])

    def test_a_marked_sheet_reads_back_with_its_marks(self):
        factories.AssessmentMarkFactory(
            assessment=self.assessment, school=self.school, student=self.students[0], marks_obtained=Decimal("17.50")
        )

        response = self.client.get(self.url())

        first = response.data["entries"][0]
        self.assertEqual("17.50", first["marks_obtained"])
        self.assertIsNone(response.data["entries"][1]["marks_obtained"])

    def test_a_student_who_left_the_class_is_not_on_the_sheet(self):
        self.students[2].status = StudentStatus.INACTIVE
        self.students[2].save(update_fields=["status"])

        response = self.client.get(self.url())

        self.assertEqual(2, len(response.data["entries"]))

    def test_a_class_of_one_reads_back(self):
        lonely_section = factories.ClassSectionFactory(school_class=self.school_class, name="C")
        factories.StudentFactory(school=self.school, class_section=lonely_section, admission_number="ADM-9")
        alone = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=self.term,
            class_section=lonely_section,
            subject=self.subject,
            created_by=self.admin,
        )

        response = self.client.get(self.url(alone.id))

        self.assertEqual(1, len(response.data["entries"]))

    def test_a_class_with_nobody_in_it_reads_back_empty(self):
        empty_section = factories.ClassSectionFactory(school_class=self.school_class, name="D")
        empty = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=self.term,
            class_section=empty_section,
            subject=self.subject,
            created_by=self.admin,
        )

        response = self.client.get(self.url(empty.id))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], response.data["entries"])


class SavingTheSheet(MarksTestCase):
    def test_the_whole_sheet_is_saved_in_one_write(self):
        response = self.client.put(self.url(), self.sheet(), format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("17.50", response.data["entries"][0]["marks_obtained"])
        self.assertIs(True, response.data["entries"][1]["is_absent"])
        self.assertEqual("12.00", response.data["entries"][2]["marks_obtained"])
        self.assertEqual(3, AssessmentMark.objects.filter(assessment_id=self.assessment.id).count())

    def test_an_absent_student_has_no_marks_at_all(self):
        self.client.put(self.url(), self.sheet(), format="json")

        row = self.stored(self.students[1])
        self.assertIsNone(row.marks_obtained)
        self.assertIs(True, row.is_absent)

    def test_saving_again_updates_the_same_rows(self):
        self.client.put(self.url(), self.sheet(), format="json")
        self.client.put(
            self.url(),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "19"}]},
            format="json",
        )

        self.assertEqual(3, AssessmentMark.objects.filter(assessment_id=self.assessment.id).count())
        self.assertEqual(Decimal("19.00"), self.stored(self.students[0]).marks_obtained)

    def test_clearing_a_mark_removes_it_rather_than_storing_a_zero(self):
        self.client.put(self.url(), self.sheet(), format="json")

        self.client.put(
            self.url(),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "", "is_absent": False}]},
            format="json",
        )

        self.assertIsNone(self.stored(self.students[0]), "not marked yet is not the same as zero")
        self.assertIsNotNone(self.stored(self.students[1]), "the rest of the sheet is untouched")

    def test_a_sheet_that_names_only_some_students_leaves_the_others_alone(self):
        self.client.put(self.url(), self.sheet(), format="json")

        self.client.put(
            self.url(), {"marks": [{"student_id": self.students[2].id, "marks_obtained": "5"}]}, format="json"
        )

        self.assertEqual(Decimal("17.50"), self.stored(self.students[0]).marks_obtained)
        self.assertEqual(Decimal("5.00"), self.stored(self.students[2]).marks_obtained)

    def test_marks_of_a_student_who_has_since_left_are_kept(self):
        self.client.put(self.url(), self.sheet(), format="json")
        self.students[2].status = StudentStatus.INACTIVE
        self.students[2].save(update_fields=["status"])

        response = self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "18"}]}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertIsNotNone(self.stored(self.students[2]), "their mark is history, not rubbish")

    def test_a_remark_can_be_left_beside_a_mark(self):
        self.client.put(
            self.url(),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "17.5", "remarks": "Careless slips"}]},
            format="json",
        )

        self.assertEqual("Careless slips", self.stored(self.students[0]).remarks)

    def test_the_save_is_recorded_once_with_what_the_sheet_says(self):
        from school.models import AuditLog

        self.client.put(self.url(), self.sheet(), format="json")

        entry = AuditLog.objects.get(action="marks.saved")
        self.assertEqual("assessments", entry.module)
        self.assertEqual(self.assessment.id, entry.entity_id)
        self.assertEqual("absent", entry.new_values["marks"][str(self.students[1].id)])


class TheServiceKeepsItsOwnRules(MarksTestCase):
    """The form refuses an absent student with a mark, so the service's own
    guard is never reached through the API. It is still the service that
    writes the row, and it is called directly by tests, by the shell and -
    later - by an importer, so the invariant is pinned here rather than left
    to whoever calls it next."""

    def test_an_absent_student_is_stored_without_marks_however_they_were_sent(self):
        from school.services import AssessmentMarkService

        AssessmentMarkService.save(
            self.assessment,
            [{"student_id": self.students[0].id, "is_absent": True, "marks_obtained": Decimal("10.00"), "remarks": None}],
            self.admin,
        )

        row = self.stored(self.students[0])
        self.assertIsNone(row.marks_obtained, "absent is not a mark of any size")
        self.assertIs(True, row.is_absent)


class WhatTheSheetRefuses(MarksTestCase):
    def test_a_mark_above_the_maximum_is_refused_by_row(self):
        response = self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "21"}]}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The marks must be between 0 and 20.00.", self.errors(response)["marks.0.marks_obtained"][0]
        )

    def test_a_mark_of_exactly_the_maximum_is_allowed(self):
        response = self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "20"}]}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_a_mark_of_zero_is_allowed_and_is_not_an_absence(self):
        self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "0"}]}, format="json"
        )

        row = self.stored(self.students[0])
        self.assertEqual(Decimal("0.00"), row.marks_obtained)
        self.assertIs(False, row.is_absent)

    def test_a_negative_mark_is_refused(self):
        response = self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "-1"}]}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_a_mark_that_is_not_a_number_is_refused(self):
        response = self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "seventeen"}]}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The marks obtained field must be a number.", self.errors(response)["marks.0.marks_obtained"][0]
        )

    def test_a_third_decimal_is_rounded_to_what_the_column_holds(self):
        self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "17.555"}]}, format="json"
        )

        self.assertEqual(Decimal("17.56"), self.stored(self.students[0]).marks_obtained)

    def test_absent_with_a_mark_attached_is_refused(self):
        response = self.client.put(
            self.url(),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "10", "is_absent": True}]},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("An absent student has no marks.", self.errors(response)["marks.0.marks_obtained"][0])

    def test_marking_somebody_absent_clears_the_mark_they_had(self):
        self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "17"}]}, format="json"
        )

        self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "is_absent": True}]}, format="json"
        )

        row = self.stored(self.students[0])
        self.assertIsNone(row.marks_obtained)
        self.assertIs(True, row.is_absent)

    def test_a_student_from_another_class_is_refused(self):
        stranger = factories.StudentFactory(
            school=self.school, class_section=self.other_section, admission_number="ADM-OTHER"
        )

        response = self.client.put(
            self.url(), {"marks": [{"student_id": stranger.id, "marks_obtained": "10"}]}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("The selected student id is invalid.", self.errors(response)["marks.0.student_id"][0])

    def test_a_student_from_another_school_is_refused(self):
        elsewhere = factories.StudentFactory(admission_number="ADM-ELSEWHERE")

        response = self.client.put(
            self.url(), {"marks": [{"student_id": elsewhere.id, "marks_obtained": "10"}]}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_the_same_student_twice_on_one_sheet_is_refused(self):
        response = self.client.put(
            self.url(),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": "10"},
                    {"student_id": self.students[0].id, "marks_obtained": "18"},
                ]
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "This student appears twice on the sheet.", self.errors(response)["marks.1.student_id"][0]
        )

    def test_an_empty_sheet_is_refused(self):
        for body in ({"marks": []}, {}):
            with self.subTest(body=body):
                response = self.client.put(self.url(), body, format="json")

                self.assertEqual(422, response.status_code, response.data)
                self.assertEqual("A sheet needs at least one student.", self.errors(response)["marks"][0])

    def test_marks_that_are_not_a_list_are_refused(self):
        response = self.client.put(self.url(), {"marks": "17"}, format="json")

        self.assertEqual(422, response.status_code, response.data)

    def test_every_bad_row_is_reported_at_once(self):
        response = self.client.put(
            self.url(),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": "99"},
                    {"student_id": self.students[1].id, "marks_obtained": "x"},
                    {"student_id": self.students[2].id, "marks_obtained": "10"},
                ]
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("marks.0.marks_obtained", self.errors(response))
        self.assertIn("marks.1.marks_obtained", self.errors(response))

    def test_a_refused_sheet_writes_nothing_at_all(self):
        self.client.put(
            self.url(), {"marks": [{"student_id": self.students[0].id, "marks_obtained": "10"}]}, format="json"
        )

        self.client.put(
            self.url(),
            {
                "marks": [
                    {"student_id": self.students[0].id, "marks_obtained": "18"},
                    {"student_id": self.students[1].id, "marks_obtained": "99"},
                ]
            },
            format="json",
        )

        self.assertEqual(Decimal("10.00"), self.stored(self.students[0]).marks_obtained, "the old mark stands")
        self.assertIsNone(self.stored(self.students[1]))

    def test_a_remark_longer_than_the_column_is_refused(self):
        response = self.client.put(
            self.url(),
            {"marks": [{"student_id": self.students[0].id, "marks_obtained": "10", "remarks": "x" * 256}]},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("marks.0.remarks", self.errors(response))


class APublishedSheetIsClosed(MarksTestCase):
    def setUp(self):
        super().setUp()
        self.assessment.status = AssessmentStatus.PUBLISHED
        self.assessment.save(update_fields=["status"])

    def test_a_published_sheet_can_still_be_read(self):
        self.assertEqual(200, self.client.get(self.url()).status_code)

    def test_a_published_sheet_cannot_be_written(self):
        response = self.client.put(self.url(), self.sheet(), format="json")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ASSESSMENT_PUBLISHED", response.data["code"])
        self.assertEqual(0, AssessmentMark.objects.filter(assessment_id=self.assessment.id).count())


class TheTestCannotBeRescaledUnderTheMarks(MarksTestCase):
    def test_the_maximum_is_locked_once_anybody_is_marked(self):
        self.client.put(self.url(), self.sheet(), format="json")

        response = self.client.patch(
            f"{ASSESSMENTS}/{self.assessment.id}", {"max_marks": "50"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("MAX_MARKS_LOCKED", response.data["code"])

    def test_the_maximum_can_be_changed_while_the_sheet_is_empty(self):
        response = self.client.patch(
            f"{ASSESSMENTS}/{self.assessment.id}", {"max_marks": "50"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("50.00", response.data["max_marks"])

    def test_saving_the_same_maximum_again_is_not_a_change(self):
        self.client.put(self.url(), self.sheet(), format="json")

        response = self.client.patch(
            f"{ASSESSMENTS}/{self.assessment.id}", {"max_marks": "20", "title": "Renamed"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)

    def test_deleting_the_test_takes_its_marks_with_it(self):
        self.client.put(self.url(), self.sheet(), format="json")

        self.assertEqual(204, self.client.delete(f"{ASSESSMENTS}/{self.assessment.id}").status_code)
        self.assertEqual(0, AssessmentMark.objects.filter(assessment_id=self.assessment.id).count())


class WhoMayMarkASheet(MarksTestCase):
    def test_the_teacher_of_that_class_and_subject_may_mark_it(self):
        response = self.as_user(self.teacher).put(self.url(), self.sheet(), format="json")

        self.assertEqual(200, response.status_code, response.data)

    def test_a_teacher_of_another_class_may_neither_read_nor_mark_it(self):
        stranger = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.other_section.class_teacher = stranger
        self.other_section.save(update_fields=["class_teacher"])
        client = self.as_user(stranger)

        self.assertEqual(403, client.get(self.url()).status_code)
        self.assertEqual(403, client.put(self.url(), self.sheet(), format="json").status_code)

    def test_an_hod_of_the_subjects_department_may_mark_it(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.department.hod_user = hod
        self.department.save(update_fields=["hod_user"])

        self.assertEqual(200, self.as_user(hod).put(self.url(), self.sheet(), format="json").status_code)

    def test_an_hod_of_another_department_is_refused(self):
        science = factories.DepartmentFactory(school=self.school, name="Science")
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        science.hod_user = hod
        science.save(update_fields=["hod_user"])

        self.assertEqual(403, self.as_user(hod).put(self.url(), self.sheet(), format="json").status_code)

    def test_a_super_admin_reads_the_sheet_and_marks_nothing(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(200, root.get(self.url()).status_code)
        self.assertEqual(403, root.put(self.url(), self.sheet(), format="json").status_code)

    def test_another_school_reaches_neither(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(403, outsider.get(self.url()).status_code)
        self.assertEqual(403, outsider.put(self.url(), self.sheet(), format="json").status_code)

    def test_the_roles_with_no_business_here_are_refused(self):
        for role in (UserRole.STAFF, UserRole.ACCOUNTANT, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, client.get(self.url()).status_code)
                self.assertEqual(403, client.put(self.url(), self.sheet(), format="json").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(self.url()).status_code)
